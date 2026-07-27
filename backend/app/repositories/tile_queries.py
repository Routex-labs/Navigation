# 건물 층 지도를 MVT(Mapbox Vector Tile) 바이트로 렌더링하는 Query 함수.
# geo_transform은 DB 컬럼으로 저장하지 않고, 요청마다 해당 건물 Node들의
# (x_m, y_m, lat, lng) 실측 대응점으로 즉석 피팅한다. 실측 앵커가 3개
# 미만이면(예: test-center처럼 합성 데이터) 임의 앵커에 1m=1m로 배치하는
# 합성 대응점으로 대체한다 — None을 반환해 지도에 아무것도 못 그리게 두는
# 대신, 위치는 가짜지만 형태/크기는 정확한 지도를 보여준다.

from __future__ import annotations

import math
import threading
from pathlib import Path

import mapbox_vector_tile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.geo.tiling import build_floor_tile_layers, tile_bounds
from app.models import Building, Floor, Poi, Store
from app.repositories.building_queries import _find_floor
from app.repositories.geo_transform import fit_building_geo_transform


# (building_id, floor_name, z, x, y) → MVT 바이트 캐시.
#
# MVT 인코딩은 CPU-바운드(층 하나 9개 타일 인코딩에 ~1s 이상)라, 클라이언트가 층을
# 전환할 때 MapLibre가 격자 여러 개를 병렬 요청하면 uvicorn 단일 워커가 직렬로
# 처리하며 뒤쪽 타일이 3~4초 이상 걸린다. 그 사이 MapLibre 네이티브 OkHttp의
# keep-alive 소켓 재사용/취소 경쟁으로 "Socket closed"가 튀고, 실패한 타일은
# MapLibre가 잠시 재요청하지 않아 해당 층 오버레이가 빈 채로 남는 증상이 있었다.
# 타일 바이트는 (건물 데이터, 층, z, x, y) 조합에 대해 결정적이라 프로세스
# 메모리에 캐싱해도 안전하다 — 첫 요청 후 나머지는 마이크로초 반환이라 병렬
# 요청 폭풍이 사라진다.
#
# 단, "재시드하면 프로세스가 재시작되니 stale 걱정이 없다"는 전제는 이 저장소의
# 개발 절차에서 성립하지 않는다(AGENTS.md 참고). reset_and_seed는 별도 프로세스로
# 돌고 uvicorn은 --reload-dir app으로 app/ 코드만 감시하므로, 재시드는 DB 파일만
# 바꿀 뿐 리로드를 트리거하지 않는다. 그대로 두면 서버가 시드 이전 타일을 계속
# 내보낸다. 그래서 DB 파일의 mtime을 캐시 "세대"로 삼아 자동 무효화한다.
_TILE_BYTES_CACHE: dict[tuple[str, str, int, int, int], bytes] = {}

# 현재 캐시가 어느 DB 상태에서 만들어졌는지 — (파일 경로, mtime_ns).
# 경로까지 넣는 이유는 서로 다른 DB가 우연히 같은 mtime을 가질 수 있어서다
# (테스트가 임시 DB를 갈아끼울 때 실제로 일어날 수 있다).
_CACHE_GENERATION: tuple[str, int] | None = None

# 워밍업 데몬 스레드와 요청 처리 스레드가 같은 dict을 만지므로 교체는 락으로 묶는다.
_CACHE_LOCK = threading.Lock()


# 캐시 세대를 구한다. settings.database_url이 아니라 세션이 실제로 물고 있는
# 엔진에서 경로를 얻는다 — 테스트는 임시 DB 엔진을 get_db 오버라이드로 주입할 뿐
# settings는 건드리지 않으므로, 전역 설정을 보면 엉뚱한 파일을 보게 된다.
#
# sqlite 파일이 아니면(메모리 DB나 다른 백엔드) None을 돌려준다. 무효화 근거가
# 없는 상태에서 세대를 지어내면 조용히 낡은 타일을 내보내게 되므로, 그때는
# 세대 판정을 아예 건너뛴다.
def _cache_generation(session: Session) -> tuple[str, int] | None:
    url = session.get_bind().url
    if url.get_backend_name() != "sqlite" or not url.database:
        return None
    try:
        return url.database, Path(url.database).stat().st_mtime_ns
    except OSError:
        return None


# DB가 바뀌었으면(=재시드) 타일 캐시를 통째로 버린다.
def _invalidate_if_reseeded(session: Session) -> None:
    global _CACHE_GENERATION

    generation = _cache_generation(session)
    if generation is None:
        return

    with _CACHE_LOCK:
        if generation != _CACHE_GENERATION:
            _CACHE_GENERATION = generation
            _TILE_BYTES_CACHE.clear()


# 층 지도를 MVT 바이트로 렌더링한다. 건물/층이 없으면 None.
def render_floor_tile(
    session: Session,
    building_id: str,
    floor_name: str,
    z: int,
    x: int,
    y: int,
) -> bytes | None:
    _invalidate_if_reseeded(session)

    cache_key = (building_id, floor_name, z, x, y)
    cached = _TILE_BYTES_CACHE.get(cache_key)
    if cached is not None:
        return cached

    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None

    building = session.get(Building, building_id)
    if building is None:
        return None

    # 좌표 변환과 타일 경계 — 무엇을 그릴지 고르는 기준.
    transform = fit_building_geo_transform(session, building_id)
    bounds = tile_bounds(z, x, y)

    stores = session.scalars(select(Store).where(Store.floor_id == floor.id)).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()

    layers = build_floor_tile_layers(
        building,
        stores=stores,
        pois=pois,
        transform=transform,
        bounds=bounds,
        footprint_local_m=floor.footprint_local_m,
    )

    tile_bytes = mapbox_vector_tile.encode(
        layers,
        default_options={
            "quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north),
        },
    )
    _TILE_BYTES_CACHE[cache_key] = tile_bytes
    return tile_bytes


# 클라이언트가 층을 훑을 때 사용하는 실내 오버레이 줌 범위. floor_plan_view/outdoor
# overlay 모두 minzoom=16, maxzoom=18로 소스를 등록하므로 이 두 zoom만 채우면
# 실제 사용 범위를 다 덮는다. z=16은 페이드 시작 밖이라 굳이 안 채워도 되지만
# 안전하게 포함해 카메라가 살짝 축소된 순간에도 캐시 히트를 유지한다.
_WARM_ZOOMS: tuple[int, ...] = (16, 17, 18)
# 화면이 건물 중심을 벗어나 있어도 인접 타일까지 커버되도록 bbox 밖으로 몇 장
# 더 확장해 warmup한다. 1이면 8방향 인접, 2면 24방향. 실측 사용 패턴이 대체로
# 건물 중심 근처라 1로 충분하다.
_WARM_TILE_PADDING = 1


def _lnglat_to_tile(lng: float, lat: float, z: int) -> tuple[int, int]:
    n = 2 ** z
    x = int((lng + 180.0) / 360.0 * n)
    lat_rad = math.radians(max(min(lat, 85.05112878), -85.05112878))
    y = int((1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def _warm_tile_cache(session_factory) -> None:
    """모든 (건물, 층, z, x, y) 조합의 MVT 바이트를 미리 생성해 캐시에 채운다.

    클라이언트가 층을 전환하면 MapLibre가 격자 여러 개를 병렬 요청하는데,
    첫 방문 때는 각 인코딩이 CPU 바운드라 uvicorn 단일 워커에서 직렬 처리되며
    수 초씩 걸린다. 그 사이 클라이언트 쪽에서 소켓이 취소·재사용되며 "Socket
    closed"가 튀고 몇몇 타일이 로드되지 않는다. 기동 직후에 여기서 미리 인코딩
    해두면 사용자 첫 요청부터 캐시 히트라 즉시 반환된다.
    """
    session = session_factory()
    try:
        buildings = session.scalars(select(Building)).all()
        for building in buildings:
            transform = fit_building_geo_transform(session, building.id)
            footprint = building.footprint_local_m or []
            if not footprint:
                continue
            # local_m → WGS84 로 변환한 bbox를 구해, 이를 덮는 web mercator 타일 범위 계산.
            wgs = [transform.apply(p["x"], p["y"]) for p in footprint]
            lats = [lat for lat, _ in wgs]
            lngs = [lng for _, lng in wgs]
            min_lat, max_lat = min(lats), max(lats)
            min_lng, max_lng = min(lngs), max(lngs)
            floors = session.scalars(
                select(Floor).where(Floor.building_id == building.id)
            ).all()
            for z in _WARM_ZOOMS:
                x0, y_north = _lnglat_to_tile(min_lng, max_lat, z)
                x1, y_south = _lnglat_to_tile(max_lng, min_lat, z)
                for x in range(x0 - _WARM_TILE_PADDING, x1 + _WARM_TILE_PADDING + 1):
                    for y in range(y_north - _WARM_TILE_PADDING, y_south + _WARM_TILE_PADDING + 1):
                        if x < 0 or y < 0 or x >= 2 ** z or y >= 2 ** z:
                            continue
                        for floor in floors:
                            render_floor_tile(session, building.id, floor.name, z, x, y)
        print(f"[tile-warmup] MVT 캐시 준비 완료: {len(_TILE_BYTES_CACHE)}개 타일")
    except Exception as error:  # pragma: no cover — 워밍 실패는 조용히 degrade
        print(f"[tile-warmup] 실패(무시하고 lazy 캐시로 폴백): {error}")
    finally:
        session.close()


def warm_tile_cache_in_background(session_factory) -> threading.Thread:
    """MVT 캐시 워밍을 데몬 스레드로 미리 돌린다.

    daemon=True — 워밍이 남아 있어도 서버 종료를 막지 않는다. 워밍 중 사용자
    요청이 들어와도 그 요청은 정상 렌더링 후 캐시에 결과가 저장되므로 중복
    작업만 있을 뿐 결과에는 영향이 없다(캐시는 dict.setdefault가 아니라 최신
    값으로 덮어쓴다). 뮤텍스 없이 무해한 이유는 값이 결정적이기 때문이다 —
    같은 (building, floor, z, x, y)에 대해 어떤 스레드가 인코딩하든 같은 bytes.
    """
    thread = threading.Thread(
        target=_warm_tile_cache,
        args=(session_factory,),
        name="mvt-tile-warmup",
        daemon=True,
    )
    thread.start()
    return thread
