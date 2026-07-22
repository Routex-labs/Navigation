"""실제 Studio 데이터(resources/studio)를 시드했을 때의 불변식 스모크 테스트.

매장 수·노드 수 같은 값은 Studio에서 편집할 때마다 바뀌므로 단언하지 않는다.
대신 편집으로는 깨지면 안 되는 성질만 검증한다. 응답 값 자체의 정확성은
합성 픽스처 테스트(test-tower)가 담당한다.
"""

import json

from sqlalchemy import select

from app.core.config import API_ROOT
from app.models import Building, Edge, Floor, Node, Store
from app.repositories import query_search
from tests.conftest import REAL_BUILDING_ID, REAL_FLOOR_NAME


# 모든 층이 적재되고 기준층이 포함되는지 확인한다.
def test_모든_층이_적재된다(real_db_session):
    floors = real_db_session.scalars(
        select(Floor).where(Floor.building_id == REAL_BUILDING_ID)
    ).all()

    assert len(floors) >= 2, "다층 적재를 검증하려면 최소 2개 층이 필요하다"
    assert REAL_FLOOR_NAME in {floor.name for floor in floors}
    # 층 level은 층마다 유일해야 층 정렬이 안정적이다.
    levels = [floor.level for floor in floors]
    assert len(levels) == len(set(levels))


# 간선이 실존하는 노드만 참조하는지(참조 무결성) 확인한다.
def test_간선은_실존하는_노드만_참조한다(real_db_session):
    node_ids = set(real_db_session.scalars(select(Node.id)).all())
    edges = real_db_session.scalars(select(Edge)).all()

    assert edges
    dangling = [
        edge.id
        for edge in edges
        if edge.from_node_id not in node_ids or edge.to_node_id not in node_ids
    ]
    assert dangling == []


# 매장 입구가 실존 노드를 가리키는지 확인한다.
def test_매장_입구는_실존하는_노드를_가리킨다(real_db_session):
    node_ids = set(real_db_session.scalars(select(Node.id)).all())
    stores = real_db_session.scalars(select(Store)).all()

    assert stores
    dangling = [
        store.id
        for store in stores
        if store.entrance_node_id is not None and store.entrance_node_id not in node_ids
    ]
    assert dangling == []


# 층을 잇는 수직 전이 간선이 생성되고, 서로 다른 층을 잇는지 확인한다.
def test_수직_전이_간선이_층을_잇는다(real_db_session):
    node_floor = dict(real_db_session.execute(select(Node.id, Node.floor_id)).all())
    transfers = real_db_session.scalars(
        select(Edge).where(Edge.transfer_mode.is_not(None))
    ).all()

    assert transfers, "층 간 이동 경로를 만들려면 전이 간선이 있어야 한다"
    for edge in transfers:
        # 전이 간선은 특정 층에 속하지 않는다(단일 층 조회에서 제외되어야 하므로).
        assert edge.floor_id is None
        assert node_floor[edge.from_node_id] != node_floor[edge.to_node_id]


# 모든 층 노드가 건물 공통 프레임으로 정규화됐는지 확인한다.
def test_모든_층_노드가_같은_좌표_프레임에_있다(real_db_session):
    floors = real_db_session.scalars(
        select(Floor).where(Floor.building_id == REAL_BUILDING_ID)
    ).all()
    building = real_db_session.get(Building, REAL_BUILDING_ID)
    assert building.footprint_local_m, "건물 외곽이 있어야 정규화 범위를 검증할 수 있다"

    # 각 층의 노드는 그 층 외곽 bbox에 여유를 둔 범위 안에 들어와야 한다.
    # (층 프레임이 정규화되지 않으면 스케일이 달라 크게 벗어난다.)
    #
    # 층마다 자기 외곽선으로 재는 것이 핵심이다. 지하 주차장은 지상 타워보다
    # 훨씬 넓어(B3 295x148m 대 1F 167x98m) 기준층 외곽에 마진을 더하는 방식으로는
    # 검증이 성립하지 않는다.
    above_ground_margin = 15.0
    basement_margin = 30.0

    for floor in floors:
        footprint = floor.footprint_local_m or building.footprint_local_m
        assert footprint, f"{floor.name} 외곽선이 없다"
        margin = basement_margin if floor.level < 0 else above_ground_margin
        min_x = min(point["x"] for point in footprint) - margin
        max_x = max(point["x"] for point in footprint) + margin
        min_y = min(point["y"] for point in footprint) - margin
        max_y = max(point["y"] for point in footprint) + margin

        nodes = real_db_session.scalars(
            select(Node).where(Node.floor_id == floor.id)
        ).all()
        assert nodes
        outside = [
            node.id
            for node in nodes
            if not (min_x <= node.x_m <= max_x and min_y <= node.y_m <= max_y)
        ]
        assert outside == [], f"{floor.name} 노드가 건물 범위를 벗어남: {outside[:3]}"


# 모든 노드가 wgs84를 갖는지 확인한다(지오레퍼런스 피팅의 앵커가 된다).
def test_모든_노드가_wgs84를_갖는다(real_db_session):
    nodes = real_db_session.scalars(select(Node)).all()

    assert nodes
    assert [node.id for node in nodes if node.lat is None or node.lng is None] == []


# 선언된 동의어가 모두 실존 장소로 매칭되는지 확인한다(죽은 항목 방지).
# 브랜드가 데이터에서 사라지면 이 테스트가 그 동의어를 잡아낸다.
def test_동의어_사전은_실존_장소로_매칭된다(real_db_session):
    synonyms = json.loads(
        (API_ROOT / "resources" / "query_synonyms.json").read_text(encoding="utf-8")
    )

    assert synonyms, "동의어 사전이 비어 있다"
    dead = [
        alias
        for alias in synonyms
        if (query_search.match_destination(real_db_session, REAL_BUILDING_ID, alias) or {}).get("match")
        is None
    ]
    assert dead == [], f"매칭되지 않는 동의어(죽은 항목): {dead}"


# 실데이터로 층 지도 API가 그래프와 매장 폴리곤을 함께 응답하는지 확인한다.
def test_층지도는_그래프와_매장_폴리곤을_함께_응답한다(real_api_client):
    response = real_api_client.get(
        f"/buildings/{REAL_BUILDING_ID}/floors/{REAL_FLOOR_NAME}"
    )

    assert response.status_code == 200
    body = response.json()
    assert body["navigation_graph"]["nodes"] and body["navigation_graph"]["edges"]
    assert body["stores"]
    # 다베오 POI 중 연결된 도형 객체가 없는 것(호텔·설치 작품 같은 랜드마크)은
    # 점으로만 존재한다. 폴리곤이 있는 매장은 wgs84 폴리곤도 함께 와야 한다.
    with_polygon = [store for store in body["stores"] if store["polygon_local_m"]]
    assert with_polygon
    assert all(store["polygon_wgs84"] for store in with_polygon)
