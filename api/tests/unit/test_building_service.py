"""SQLite 없이 Fake Repository로 검증하는 BuildingService 단위 테스트."""

from unittest.mock import Mock

import pytest

from app.domain.building import (
    Building,
    Edge,
    Floor,
    FloorVectorMap,
    LocalPoint,
    MapFeature,
    Node,
    Poi,
    Store,
)
from app.repository.BuildingRepository import BuildingRepository
from app.service.buildingService import BuildingService

BUILDING_ID = "test-building"
FLOOR_ID = "test-building-1f"
FLOOR_NAME = "1F"


@pytest.fixture
def repository():
    building = Building(
        id=BUILDING_ID,
        name="테스트 건물",
        area_m2=100.0,
        perimeter_m=40.0,
        footprint_local_m=[{"x": 0.0, "y": 0.0}],
    )
    floor = Floor(id=FLOOR_ID, building_id=BUILDING_ID, name=FLOOR_NAME, level=1)
    nodes = [
        Node("A", FLOOR_ID, "corridor", None, LocalPoint(0.0, 0.0), None, None),
        Node("B", FLOOR_ID, "junction", None, LocalPoint(1.0, 0.0), None, None),
        Node("C", FLOOR_ID, "corridor", None, LocalPoint(2.0, 0.0), None, None),
        Node("D", FLOOR_ID, "dead_end", None, LocalPoint(9.0, 9.0), None, None),
    ]
    edges = [
        Edge(
            "AB",
            FLOOR_ID,
            "A",
            "B",
            1.0,
            True,
            [
                {"x": 0.0, "y": 0.0},
                {"x": 0.5, "y": 0.2},
                {"x": 1.0, "y": 0.0},
            ],
        ),
        Edge("BC", FLOOR_ID, "B", "C", 1.0, True, []),
    ]
    stores = [
        Store(
            "store-1",
            FLOOR_ID,
            "테스트 매장",
            LocalPoint(2.0, 1.0),
            LocalPoint(2.0, 0.0),
            "C",
        )
    ]
    pois = [
        Poi("poi-1", FLOOR_ID, "toilet", "화장실", LocalPoint(1.0, 1.0), "B")
    ]

    # spec으로 Repository 계약에 없는 메서드 호출이 통과하는 것을 막는다.
    fake = Mock(spec=BuildingRepository)
    fake.find_all_buildings.return_value = [building]
    fake.find_building_by_id.side_effect = (
        lambda building_id: building if building_id == BUILDING_ID else None
    )
    fake.find_floors_by_building.side_effect = (
        lambda building_id: [floor] if building_id == BUILDING_ID else []
    )
    fake.find_floor_by_name.side_effect = (
        lambda building_id, floor_name: floor
        if building_id == BUILDING_ID and floor_name == FLOOR_NAME
        else None
    )
    fake.find_nodes_by_floor.return_value = nodes
    fake.find_edges_by_floor.return_value = edges
    fake.find_vector_map_by_floor.return_value = FloorVectorMap(
        floor_id=FLOOR_ID,
        coordinate_system={
            "id": "svg_viewbox_px",
            "unit": "px",
            "origin": "top-left",
            "x_axis": "right",
            "y_axis": "down",
            "view_box": {
                "min_x": 0.0,
                "min_y": 0.0,
                "width": 100.0,
                "height": 50.0,
            },
        },
        source={"type": "svg", "file": "test.svg"},
        features=[
            MapFeature(
                id="store-vector-1",
                floor_id=FLOOR_ID,
                kind="store",
                name="테스트 매장",
                category="fashion",
                geometry_type="Polygon",
                coordinates=[
                    {"x": 0.0, "y": 0.0},
                    {"x": 10.0, "y": 0.0},
                    {"x": 10.0, "y": 10.0},
                ],
                centroid={"x": 6.666667, "y": 3.333333},
            )
        ],
    )
    fake.find_stores_by_floor.return_value = stores
    fake.find_pois_by_floor.return_value = pois
    fake.search_stores.side_effect = (
        lambda _building_id, query: [
            store for store in stores if query in store.name
        ]
    )
    return fake


@pytest.fixture
def service(repository) -> BuildingService:
    return BuildingService(repository)


# 건물 목록에 상세 외곽선 없이 요약 정보만 포함되는지 검증한다.
def test_건물_목록은_요약만_반환한다(service):
    result = service.get_all_buildings()

    assert result == [{"id": BUILDING_ID, "name": "테스트 건물", "floors": ["1F"]}]


# 저장소에 없는 건물을 조회하면 결과 없음으로 처리하는지 검증한다.
def test_없는_건물은_결과없음을_반환한다(service):
    assert service.get_building("missing") is None


# 층 지도 응답에 매장과 관심 지점 정보가 함께 조합되는지 검증한다.
def test_층_지도는_매장과_관심지점을_조합한다(service):
    result = service.get_floor_map(BUILDING_ID, FLOOR_NAME)

    assert result["stores"][0]["entrance_node_id"] == "C"
    assert result["pois"][0]["linked_node_id"] == "B"
    assert result["navigation_coordinate_system"] == "local_m"
    assert result["vector_map"]["coordinate_system"]["id"] == "svg_viewbox_px"
    assert result["vector_map"]["features"][0]["kind"] == "store"


# 저장소에 없는 층을 조회하면 결과 없음으로 처리하는지 검증한다.
def test_없는_층은_결과없음을_반환한다(service):
    assert service.get_floor_graph(BUILDING_ID, "99F") is None


# 정방향 최단 경로의 간선 좌표가 저장 순서대로 반환되는지 검증한다.
def test_최단경로의_경로선을_정방향으로_반환한다(service):
    result = service.get_shortest_path(BUILDING_ID, FLOOR_NAME, "A", "B")

    assert result["path_points"] == [
        {"x": 0.0, "y": 0.0},
        {"x": 0.5, "y": 0.2},
        {"x": 1.0, "y": 0.0},
    ]


# 양방향 간선을 역방향으로 이동할 때 좌표 순서가 반전되는지 검증한다.
def test_역방향_이동은_경로선_순서를_뒤집는다(service):
    result = service.get_shortest_path(BUILDING_ID, FLOOR_NAME, "B", "A")

    assert result["path_points"] == [
        {"x": 1.0, "y": 0.0},
        {"x": 0.5, "y": 0.2},
        {"x": 0.0, "y": 0.0},
    ]


# 간선 경로선이 없을 때 양 끝 노드 좌표로 보완하는지 검증한다.
def test_경로선이_없으면_노드_좌표를_사용한다(service):
    result = service.get_shortest_path(BUILDING_ID, FLOOR_NAME, "B", "C")

    assert result["path_points"] == [
        {"x": 1.0, "y": 0.0},
        {"x": 2.0, "y": 0.0},
    ]


# 여러 간선 연결 시 공통 접점 좌표가 중복되지 않는지 검증한다.
def test_여러_간선의_중복_접점은_한번만_포함한다(service):
    result = service.get_shortest_path(BUILDING_ID, FLOOR_NAME, "A", "C")

    assert result["path_points"] == [
        {"x": 0.0, "y": 0.0},
        {"x": 0.5, "y": 0.2},
        {"x": 1.0, "y": 0.0},
        {"x": 2.0, "y": 0.0},
    ]


# 출발지와 목적지가 같을 때 단일 좌표와 거리 0을 반환하는지 검증한다.
def test_출발지와_목적지가_같으면_좌표_하나를_반환한다(service):
    result = service.get_shortest_path(BUILDING_ID, FLOOR_NAME, "A", "A")

    assert result["path_points"] == [{"x": 0.0, "y": 0.0}]
    assert result["total_distance_m"] == 0.0


# 목적지까지 연결된 간선이 없을 때 경로 발견 값이 거짓인지 검증한다.
def test_연결되지_않은_목적지는_경로발견값이_거짓이다(service):
    result = service.get_shortest_path(BUILDING_ID, FLOOR_NAME, "A", "D")

    assert result["path_found"] is False


# 존재하지 않는 노드 식별자가 값 오류로 처리되는지 검증한다.
def test_존재하지_않는_노드는_값오류다(service):
    with pytest.raises(ValueError, match="존재하지 않습니다"):
        service.get_shortest_path(BUILDING_ID, FLOOR_NAME, "missing", "A")
