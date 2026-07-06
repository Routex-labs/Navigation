"""
BuildingService 단위 테스트.

repository는 실데이터가 적재된 임시 SQLite 기반 SqliteBuildingRepository를
사용한다 (conftest 픽스처). HTTP 계층 없이 service 반환값을 직접 검증한다.
"""

import pytest

from app.service.buildingService import BuildingService
from tests.conftest import BUILDING_ID, FLOOR_NAME


@pytest.fixture
def service(building_repository) -> BuildingService:
    return BuildingService(building_repository)


def test_건물_목록_조회(service):
    # When
    buildings = service.get_all_buildings()

    # Then
    assert len(buildings) == 1
    assert buildings[0]["id"] == BUILDING_ID
    assert buildings[0]["floors"] == [FLOOR_NAME]
    assert "footprint_local_m" not in buildings[0]  # 목록은 요약만


def test_건물_상세_조회(service):
    # When
    building = service.get_building(BUILDING_ID)

    # Then
    assert building["id"] == BUILDING_ID
    assert building["area_m2"] == pytest.approx(16182.4, abs=1.0)
    assert len(building["footprint_local_m"]) >= 4


def test_없는_건물은_None(service):
    assert service.get_building("nonexistent") is None


def test_층_그래프_조회(service):
    # When
    graph = service.get_floor_graph(BUILDING_ID, FLOOR_NAME)

    # Then — 가공 결과 기준 (docs/dataset-analysis.md)
    assert len(graph["nodes"]) == 234
    assert len(graph["edges"]) == 282

    # 엣지가 참조하는 노드가 전부 존재해야 한다
    node_ids = {n["id"] for n in graph["nodes"]}
    for edge in graph["edges"]:
        assert edge["from"] in node_ids
        assert edge["to"] in node_ids
        assert edge["length_m"] >= 0


def test_층_지도_조회(service):
    # When
    floor_map = service.get_floor_map(BUILDING_ID, FLOOR_NAME)

    # Then
    assert floor_map["floor"]["name"] == FLOOR_NAME
    assert len(floor_map["footprint_local_m"]) >= 4
    assert len(floor_map["stores"]) == 61
    assert len(floor_map["pois"]) == 47


def test_없는_층은_None(service):
    assert service.get_floor_graph(BUILDING_ID, "99F") is None
    assert service.get_floor_map(BUILDING_ID, "99F") is None


def test_매장_검색(service):
    # When
    results = service.search_stores(BUILDING_ID, "베네타")

    # Then
    assert len(results) >= 1
    assert any("베네타" in s["name"] for s in results)
    assert all(s["entrance_node_id"] for s in results)


def test_매장_검색_빈_질의는_전체(service):
    assert len(service.search_stores(BUILDING_ID, "")) == 61


def test_없는_건물_매장_검색은_None(service):
    assert service.search_stores("nonexistent", "베네타") is None