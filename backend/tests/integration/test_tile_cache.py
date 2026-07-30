"""MVT 타일 캐시 무효화 테스트.

캐시가 잘못되는 방향은 하나뿐이지만 증상이 고약하다 — 재시드했는데 서버가
시드 이전 타일을 계속 내보내면, 데이터를 고친 사람은 "고쳐지지 않았다"고
판단하고 엉뚱한 곳을 파게 된다. AGENTS.md의 개발 절차는 reset_and_seed를
별도 프로세스로 돌리고 uvicorn은 app/ 코드만 감시하므로, 재시드로는 프로세스가
재시작되지 않는다는 점이 이 테스트의 전제다.
"""

import os

import mapbox_vector_tile
import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app.models import Store
from app.models.base import Base
from app.repositories import tile_queries
from app.repositories.geo_transform import fit_building_geo_transform
from scripts.seed.studio_adapter import seed_studio
from tests.conftest import BUILDING_ID, FIXTURE_DIR, FLOOR_NAME

# 클라이언트가 실제로 쓰는 줌대. z=0 같은 낮은 줌은 전 세계를 4096유닛으로
# 양자화하느라 건물이 통째로 뭉개져 매장 feature가 0개가 된다 — 그러면 이
# 테스트가 "캐시가 갱신됐는지"를 볼 수 없다.
ZOOM = 17


@pytest.fixture
def seeded_sessions(tmp_path):
    """테스트마다 독립된 임시 DB와 세션 팩토리."""
    db_path = tmp_path / "navigation.db"
    engine = create_engine(
        f"sqlite:///{db_path.as_posix()}",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine)

    with factory() as session:
        seed_studio(session=session, directory=FIXTURE_DIR)
        session.commit()

    yield factory, db_path
    engine.dispose()


def _store_names(tile_bytes: bytes) -> set[str]:
    decoded = mapbox_vector_tile.decode(tile_bytes)
    layer = decoded.get("stores", {})
    return {f["properties"]["name"] for f in layer.get("features", [])}


# 매장이 실제로 들어 있는 타일 좌표를 시드 데이터에서 구한다. 좌표를 상수로
# 박아 두면 픽스처 위치가 바뀔 때 조용히 빈 타일을 검사하게 된다.
def _content_tile(factory) -> tuple[int, int, int]:
    with factory() as session:
        transform = fit_building_geo_transform(session, BUILDING_ID)
        store = session.scalars(select(Store)).first()
        assert store is not None and store.polygon, "픽스처에 매장 폴리곤이 있어야 한다"
        point = store.polygon[0]
        lat, lng = transform.apply(point["x"], point["y"])

    x, y = tile_queries._lnglat_to_tile(lng, lat, ZOOM)
    return ZOOM, x, y


def _render(factory, tile: tuple[int, int, int]) -> bytes:
    with factory() as session:
        rendered = tile_queries.render_floor_tile(session, BUILDING_ID, FLOOR_NAME, *tile)
    assert rendered is not None
    return rendered


# 캐시가 실제로 먹는지 먼저 확인한다 — 안 먹으면 아래 무효화 테스트가 의미 없다.
def test_같은_타일을_다시_요청하면_캐시에서_같은_바이트가_나온다(seeded_sessions):
    factory, _ = seeded_sessions
    tile = _content_tile(factory)

    assert _render(factory, tile) == _render(factory, tile)


def test_DB가_바뀌면_캐시가_무효화되어_새_데이터가_나온다(seeded_sessions):
    factory, _ = seeded_sessions
    tile = _content_tile(factory)

    before = _store_names(_render(factory, tile))
    assert before, "픽스처에 매장이 있어야 이 테스트가 의미가 있다"

    # 재시드와 같은 효과 — 데이터를 바꾸고 커밋하면 DB 파일이 갱신된다.
    with factory() as session:
        store = session.scalars(select(Store)).first()
        store.name = "재시드확인용매장"
        session.commit()

    after = _store_names(_render(factory, tile))

    assert "재시드확인용매장" in after
    assert after != before


# mtime 해상도가 낮은 파일 시스템에서도 무효화가 도는지 명시적으로 못 박는다.
def test_파일_mtime만_바뀌어도_캐시_세대가_갱신된다(seeded_sessions):
    factory, db_path = seeded_sessions

    _render(factory, _content_tile(factory))
    with factory() as session:
        generation_before = tile_queries._cache_generation(session)

    stat = db_path.stat()
    os.utime(db_path, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1_000_000_000))

    with factory() as session:
        generation_after = tile_queries._cache_generation(session)
        tile_queries._invalidate_if_reseeded(session)

    assert generation_before != generation_after
    assert tile_queries._TILE_BYTES_CACHE == {}


# 무효화 근거가 없는 백엔드에서는 세대 판정을 건너뛴다(캐시를 지어내지 않는다).
def test_메모리_DB는_세대를_만들지_않는다():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine)

    with factory() as session:
        assert tile_queries._cache_generation(session) is None
