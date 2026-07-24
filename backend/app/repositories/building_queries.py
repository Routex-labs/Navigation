# 건물/층/매장/지도/그래프 단순 조회 Query 함수.
# - Session을 첫 인자로 받고 기존 API 응답과 동일한 dict를 조립한다.
# - None은 존재하지 않는 Building/Floor, 빈 list는 검색 결과 없음을 뜻한다.
# - HTTP 상태 코드 변환은 Router가 담당한다.

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.geo.georeference import GeoTransform
from app.geo.tiling import local_points_to_lnglat
from app.models import Building, Edge, Floor, Node, Poi, Store
from app.repositories.geo_transform import fit_building_geo_transform


# 전체 건물 요약 목록. selectinload로 층 목록 N+1을 제거한다.
def list_buildings(session: Session) -> list[dict[str, Any]]:
    buildings = session.scalars(
        select(Building).options(selectinload(Building.floors))
    ).all()
    return [_to_building_summary(building) for building in buildings]


# 건물 상세(footprint 포함). 없으면 None.
def get_building(session: Session, building_id: str) -> dict[str, Any] | None:
    building = session.scalars(
        select(Building)
        .where(Building.id == building_id)
        .options(selectinload(Building.floors))
    ).one_or_none()
    if building is None:
        return None

    # 목록용 요약에 상세 전용 필드를 얹는다.
    summary = _to_building_summary(building)
    summary["area_m2"] = building.area_m2
    summary["perimeter_m"] = building.perimeter_m
    summary["footprint_local_m"] = building.footprint_local_m or []
    return summary


# 건물 내 매장 이름 검색. 건물이 없으면 None, 결과 없으면 빈 리스트.
def search_stores(
    session: Session,
    building_id: str,
    query: str,
) -> list[dict[str, Any]] | None:
    if session.get(Building, building_id) is None:
        return None

    stores = session.scalars(
        select(Store)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id, Store.name.like(f"%{query}%"))
    ).all()

    transform = fit_building_geo_transform(session, building_id)
    return [_to_store_dict(store, transform) for store in stores]


# 층 지도 데이터(footprint + 벡터 지도 + 매장 폴리곤 + POI). 없으면 None.
def get_floor_map(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None

    # 한 층을 그리는 데 필요한 재료를 모은다.
    building = session.get(Building, building_id)
    stores = session.scalars(
        select(Store).where(Store.floor_id == floor.id)
    ).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()
    transform = fit_building_geo_transform(session, building_id)

    return {
        "floor": {"id": floor.id, "name": floor.name, "level": floor.level},
        "navigation_coordinate_system": "local_m",
        "map_calibration_version": floor.map_calibration_version,
        # 층 외곽선이 있으면 그것을 쓴다. 건물 footprint는 기준층(1F) 것이라
        # 전 층에 돌려쓰면 지하 주차장에도 1F 윤곽이 그려진다.
        "footprint_local_m": _floor_footprint(floor, building),
        "footprint_wgs84": _footprint_wgs84(_floor_footprint(floor, building), transform),
        # Flutter는 최초 층 지도 응답에서 이 그래프를 캐시해 클라이언트 다익스트라를 실행한다.
        "navigation_graph": _to_floor_graph_dict(session, floor),
        "stores": [_to_store_dict(store, transform) for store in stores],
        "pois": [_to_poi_dict(poi, transform) for poi in pois],
    }


# 층 길찾기 그래프(nodes + edges). 없으면 None.
def get_floor_graph(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None
    return _to_floor_graph_dict(session, floor)


# 수직 이동 정책. 층 간 전이 간선 중 무엇을 그래프에 실을지 고른다.
#   auto      — 엘리베이터·에스컬레이터 모두(비용 모델이 층수에 따라 자동으로 고름)
#   elevator  — 엘리베이터만 (에스컬레이터 회피)
#   escalator — 에스컬레이터만
VERTICAL_POLICIES = ("auto", "elevator", "escalator")


def _vertical_allows(policy: str, transfer_mode: str | None) -> bool:
    # 층 내부 간선(transfer_mode=None)은 정책과 무관하게 항상 포함한다.
    if transfer_mode is None:
        return True
    if policy == "elevator":
        return transfer_mode == "elevator"
    if policy == "escalator":
        return transfer_mode == "escalator"
    return True  # auto


# 건물 전체 길찾기 그래프(전 층 nodes + 층 내부 간선 + 수직 전이 간선). 없으면 None.
# 층별 /graph와 달리 수직 전이 간선을 포함해 클라이언트가 층 간 경로를 계산할 수 있다.
# 전이 간선은 floor_id가 None이라 층별 조회에서는 빠지므로 여기서만 합류한다.
def get_building_graph(
    session: Session,
    building_id: str,
    vertical: str = "auto",
) -> dict[str, Any] | None:
    building = session.get(Building, building_id)
    if building is None:
        return None

    floor_ids = session.scalars(
        select(Floor.id).where(Floor.building_id == building_id)
    ).all()
    nodes = session.scalars(select(Node).where(Node.floor_id.in_(floor_ids))).all()
    node_ids = {node.id for node in nodes}

    # 층 내부 간선 + 이 건물 노드를 잇는 전이 간선(floor_id=None). 전이 간선은
    # 건물 스코프가 없으므로 from 노드가 이 건물 소속인 것만 고른다.
    intra_edges = session.scalars(select(Edge).where(Edge.floor_id.in_(floor_ids))).all()
    transfer_edges = session.scalars(
        select(Edge).where(
            Edge.floor_id.is_(None),
            Edge.from_node_id.in_(node_ids),
        )
    ).all()
    edges = list(intra_edges) + [
        edge for edge in transfer_edges if _vertical_allows(vertical, edge.transfer_mode)
    ]

    return {
        "building": {"id": building.id, "name": building.name},
        "vertical": vertical,
        "nodes": [_to_graph_node_dict(node) for node in nodes],
        "edges": [_to_edge_dict(edge) for edge in edges],
    }


# 층 지도와 독립 그래프 API가 공유하는 길찾기 레이어 응답을 조립한다.
def _to_floor_graph_dict(session: Session, floor: Floor) -> dict[str, Any]:
    nodes = session.scalars(select(Node).where(Node.floor_id == floor.id)).all()
    edges = session.scalars(select(Edge).where(Edge.floor_id == floor.id)).all()

    return {
        "floor": {"id": floor.id, "name": floor.name},
        "nodes": [_to_node_dict(node) for node in nodes],
        "edges": [_to_edge_dict(edge) for edge in edges],
    }


def _find_floor(
    session: Session,
    building_id: str,
    floor_name: str,
) -> Floor | None:
    return session.scalars(
        select(Floor).where(
            Floor.building_id == building_id,
            Floor.name == floor_name,
        )
    ).one_or_none()


# --- ORM 객체 → API 응답 dict 변환 ---


def _to_building_summary(building: Building) -> dict[str, Any]:
    # level은 실제 층 높이다 — 위로 갈수록 크고 지하는 음수다(6F=6 … 1F=1 … B6=-6).
    # 내림차순 정렬은 엘리베이터 버튼판과 같은 순서(6F→B6)를 만든다.
    #
    # 기본 층은 정렬 순서와 분리해 default_floor로 따로 내려준다. 예전에는
    # 클라이언트가 floors.first를 초기 층으로 썼는데, 지하층이 생기자 목록 첫
    # 항목이 최상층(6F)이 되어 앱이 6F로 열렸다.
    floors = sorted(building.floors, key=lambda floor: floor.level, reverse=True)

    return {
        "id": building.id,
        "name": building.name,
        "floors": [floor.name for floor in floors],
        "default_floor": _default_floor(floors),
    }


# 앱이 처음 열 층. 출입구가 있는 지상 1층이 기준이고, 지상층이 없으면 가장 위층으로
# 폴백한다(지하 전용 건물도 빈 값 없이 열리도록).
def _default_floor(floors: list[Floor]) -> str | None:
    if not floors:
        return None

    # 지상층이 있으면 그중 가장 낮은 층(=1F), 없으면 최상층으로 폴백.
    above_ground = [floor for floor in floors if floor.level >= 1]
    if above_ground:
        return min(above_ground, key=lambda floor: floor.level).name
    return max(floors, key=lambda floor: floor.level).name


def _to_node_dict(node: Node) -> dict[str, Any]:
    return {
        "id": node.id,
        "type": node.type,
        "name": node.name,
        "x_m": node.x_m,
        "y_m": node.y_m,
        "lat": node.lat,
        "lng": node.lng,
    }


# 건물 전체 그래프용 노드 dict. 층별 그래프와 달리 어느 층 노드인지 floor_id를 함께 준다
# (전 층 노드가 한 그래프에 섞이므로 클라이언트가 층별로 다시 나눌 수 있어야 한다).
def _to_graph_node_dict(node: Node) -> dict[str, Any]:
    return {**_to_node_dict(node), "floor_id": node.floor_id}


def _to_edge_dict(edge: Edge) -> dict[str, Any]:
    # 내부 from_node_id/to_node_id를 API에서는 짧은 from/to 키로 노출한다.
    return {
        "id": edge.id,
        "from": edge.from_node_id,
        "to": edge.to_node_id,
        "length_m": edge.length_m,
        "bidirectional": edge.bidirectional,
        "geometry_local_m": edge.geometry or [],
        # 층 내부 간선은 None, 수직 전이 간선은 elevator/escalator. 클라이언트가
        # 경로 안내에서 "엘리베이터 이용" 같은 문구·아이콘을 고르는 근거.
        "transfer_mode": edge.transfer_mode,
    }


def _to_store_dict(store: Store, transform: GeoTransform | None) -> dict[str, Any]:
    # 실좌표 앵커가 없는 건물이면 transform이 없어 wgs84 필드는 null로 나간다.
    centroid_wgs84 = None
    polygon_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(store.centroid_x_m, store.centroid_y_m)
        centroid_wgs84 = {"lat": lat, "lng": lng}
        if store.polygon:
            polygon_wgs84 = [
                {"lng": lng, "lat": lat}
                for lng, lat in local_points_to_lnglat(store.polygon, transform)
            ]

    return {
        "id": store.id,
        "floor_id": store.floor_id,
        "name": store.name,
        "category": store.category,
        "subcategory": store.subcategory,
        "centroid_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
        "centroid_wgs84": centroid_wgs84,
        "polygon_wgs84": polygon_wgs84,
        "entrance_local_m": _optional_point(
            store.entrance_x_m,
            store.entrance_y_m,
            label=f"매장 {store.id} 입구",
        ),
        "entrance_node_id": store.entrance_node_id,
        "polygon_local_m": store.polygon,
    }


def _to_poi_dict(poi: Poi, transform: GeoTransform | None) -> dict[str, Any]:
    position_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(poi.x_m, poi.y_m)
        position_wgs84 = {"lat": lat, "lng": lng}

    return {
        "id": poi.id,
        "type": poi.type,
        "name": poi.name,
        "position_local_m": {"x": poi.x_m, "y": poi.y_m},
        "position_wgs84": position_wgs84,
        "linked_node_id": poi.linked_node_id,
    }


# 층 자체 외곽선 우선, 없으면 건물 대표 외곽으로 폴백한다.
def _floor_footprint(floor: Floor, building: Building | None) -> list[dict]:
    if floor.footprint_local_m:
        return floor.footprint_local_m
    return (building.footprint_local_m or []) if building else []


def _footprint_wgs84(
    footprint: list[dict],
    transform: GeoTransform | None,
) -> list[dict[str, float]] | None:
    if transform is None or not footprint:
        return None

    points = local_points_to_lnglat(footprint, transform)
    return [{"lng": lng, "lat": lat} for lng, lat in points]


# 선택 좌표는 x/y 모두 NULL일 때만 없음으로 처리하고, 한쪽만 있으면 오류다.
def _optional_point(
    x: float | None,
    y: float | None,
    *,
    label: str,
) -> dict[str, float] | None:
    if x is None and y is None:
        return None
    if x is None or y is None:
        raise ValueError(f"{label} 좌표 값이 불완전합니다.")
    return {"x": x, "y": y}
