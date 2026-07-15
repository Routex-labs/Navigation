"""건물/층/매장/지도/그래프 단순 조회 Query 함수.

- Session을 첫 인자로 받고 기존 API 응답과 동일한 dict를 조립한다.
- None은 존재하지 않는 Building/Floor, 빈 list는 검색 결과 없음을 뜻한다.
- HTTP 상태 코드 변환은 Router가 담당한다.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models import Building, Edge, Floor, FloorVectorMap, MapFeature, Node, Poi, Store


def list_buildings(session: Session) -> list[dict[str, Any]]:
    """전체 건물 요약 목록. selectinload로 층 목록 N+1을 제거한다."""
    buildings = session.scalars(
        select(Building).options(selectinload(Building.floors))
    ).all()
    return [_to_building_summary(building) for building in buildings]


def get_building(session: Session, building_id: str) -> dict[str, Any] | None:
    """건물 상세(footprint 포함). 없으면 None."""
    building = session.scalars(
        select(Building)
        .where(Building.id == building_id)
        .options(selectinload(Building.floors))
    ).one_or_none()
    if building is None:
        return None
    summary = _to_building_summary(building)
    summary["area_m2"] = building.area_m2
    summary["perimeter_m"] = building.perimeter_m
    summary["footprint_local_m"] = building.footprint_local_m or []
    return summary


def search_stores(
    session: Session,
    building_id: str,
    query: str,
) -> list[dict[str, Any]] | None:
    """건물 내 매장 이름 검색. 건물이 없으면 None, 결과 없으면 빈 리스트."""
    if session.get(Building, building_id) is None:
        return None
    stores = session.scalars(
        select(Store)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id, Store.name.like(f"%{query}%"))
    ).all()
    return [_to_store_dict(store) for store in stores]


def get_floor_map(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    """층 지도 데이터(footprint + 벡터 지도 + 매장 폴리곤 + POI). 없으면 None."""
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None
    building = session.get(Building, building_id)
    vector_map = session.get(FloorVectorMap, floor.id)
    stores = session.scalars(
        select(Store).where(Store.floor_id == floor.id)
    ).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()
    return {
        "floor": {"id": floor.id, "name": floor.name, "level": floor.level},
        "navigation_coordinate_system": "local_m",
        "footprint_local_m": (building.footprint_local_m or []) if building else [],
        "vector_map": _to_vector_map_dict(session, vector_map) if vector_map else None,
        "navigation_graph": _to_floor_graph_dict(session, floor),
        "stores": [_to_store_dict(store) for store in stores],
        "pois": [_to_poi_dict(poi) for poi in pois],
    }


def get_floor_graph(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    """층 길찾기 그래프(nodes + edges). 없으면 None."""
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None
    return _to_floor_graph_dict(session, floor)


def _to_floor_graph_dict(session: Session, floor: Floor) -> dict[str, Any]:
    """층 지도와 독립 그래프 API가 공유하는 길찾기 레이어 응답을 조립한다."""
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
    floors = sorted(building.floors, key=lambda floor: floor.level)
    return {
        "id": building.id,
        "name": building.name,
        "floors": [floor.name for floor in floors],
    }


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


def _to_edge_dict(edge: Edge) -> dict[str, Any]:
    # 내부 from_node_id/to_node_id를 API에서는 짧은 from/to 키로 노출한다.
    return {
        "id": edge.id,
        "from": edge.from_node_id,
        "to": edge.to_node_id,
        "length_m": edge.length_m,
        "bidirectional": edge.bidirectional,
        "geometry_local_m": edge.geometry or [],
    }


def _to_store_dict(store: Store) -> dict[str, Any]:
    return {
        "id": store.id,
        "floor_id": store.floor_id,
        "name": store.name,
        "centroid_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
        "entrance_local_m": _optional_point(
            store.entrance_x_m,
            store.entrance_y_m,
            label=f"매장 {store.id} 입구",
        ),
        "entrance_node_id": store.entrance_node_id,
        "polygon_local_m": store.polygon,
    }


def _to_poi_dict(poi: Poi) -> dict[str, Any]:
    return {
        "id": poi.id,
        "type": poi.type,
        "name": poi.name,
        "position_local_m": {"x": poi.x_m, "y": poi.y_m},
        "linked_node_id": poi.linked_node_id,
    }


def _to_vector_map_dict(
    session: Session,
    vector_map: FloorVectorMap,
) -> dict[str, Any]:
    features = session.scalars(
        select(MapFeature).where(MapFeature.floor_id == vector_map.floor_id)
    ).all()
    return {
        "coordinate_system": vector_map.coordinate_system,
        "source": vector_map.source,
        "features": [_to_map_feature_dict(feature) for feature in features],
    }


def _to_map_feature_dict(feature: MapFeature) -> dict[str, Any]:
    return {
        "id": feature.id,
        "kind": feature.kind,
        "name": feature.name,
        "category": feature.category,
        "geometry": {
            "type": feature.geometry_type,
            "coordinates": feature.coordinates,
        },
        "centroid": {"x": feature.centroid_x, "y": feature.centroid_y}
        if feature.centroid_x is not None and feature.centroid_y is not None
        else None,
    }


def _optional_point(
    x: float | None,
    y: float | None,
    *,
    label: str,
) -> dict[str, float] | None:
    """선택 좌표는 x/y 모두 NULL일 때만 없음으로 처리하고, 한쪽만 있으면 오류다."""
    if x is None and y is None:
        return None
    if x is None or y is None:
        raise ValueError(f"{label} 좌표 값이 불완전합니다.")
    return {"x": x, "y": y}
