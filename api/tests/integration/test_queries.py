"""시드 DB 기준 building_queries 조회 결과의 식별자와 핵심 JSON 구조 검증."""

from app.queries import building_queries
from tests.conftest import BUILDING_ID, FLOOR_NAME, FLOOR_NAMES


# 건물 목록이 요약(JSON 키: id, name, floors)만 반환하는지 검증한다.
def test_건물_목록은_요약만_반환한다(db_session):
    result = building_queries.list_buildings(db_session)

    assert [building["id"] for building in result] == [BUILDING_ID]
    assert result[0]["floors"] == FLOOR_NAMES
    assert set(result[0]) == {"id", "name", "floors"}


# 없는 건물 조회가 None으로 처리되는지 검증한다.
def test_없는_건물은_결과없음을_반환한다(db_session):
    assert building_queries.get_building(db_session, "missing") is None


# 매장 검색이 이름 부분 일치로 동작하는지 검증한다.
def test_검색어로_매장을_조회한다(db_session):
    result = building_queries.search_stores(db_session, BUILDING_ID, "가게B")

    assert sorted(store["id"] for store in result) == ["shop-b-1f", "shop-b-2f"]
    assert set(result[0]) >= {"id", "floor_id", "name", "centroid_local_m"}


# 층 지도 응답이 기존 JSON 키 구조를 유지하는지 검증한다.
def test_층_지도는_기존_JSON_구조를_유지한다(db_session):
    result = building_queries.get_floor_map(db_session, BUILDING_ID, FLOOR_NAME)

    assert result["floor"]["name"] == FLOOR_NAME
    assert result["navigation_coordinate_system"] == "local_m"
    assert result["stores"] and result["pois"]
    assert len(result["navigation_graph"]["nodes"]) == 8
    assert all(store["polygon_local_m"] for store in result["stores"])


# 층 그래프 간선이 from/to 짧은 키로 노출되는지 검증한다.
def test_층_그래프의_간선은_from_to_키를_사용한다(db_session):
    result = building_queries.get_floor_graph(db_session, BUILDING_ID, FLOOR_NAME)

    assert result["nodes"] and result["edges"]
    assert {"id", "from", "to", "length_m", "bidirectional"} <= set(result["edges"][0])
