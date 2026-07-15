"""JSON 지도 데이터를 ORM 객체로 변환해 개발 DB에 적재하는 시드 스크립트.

DDL을 갖지 않는다. 스키마 생성은 scripts.reset_database가 담당하고,
이 모듈은 한 건물/층 데이터를 하나의 트랜잭션으로 저장한다.
여러 건물을 담으려면 JSON별로 반복 호출한다(테이블을 지우지 않으므로 append 동작).

실행 방법 (api/ 디렉토리에서):
  python -m scripts.seed_navigation
  python -m scripts.seed_navigation --json app/data/navigation_test_center_1f.json
"""

from __future__ import annotations

import argparse
import json
from math import hypot
from pathlib import Path

from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.models import (
    Building,
    Edge,
    Floor,
    FloorVectorMap,
    MapFeature,
    Node,
    Poi,
    Store,
)

API_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON = API_ROOT / "app" / "data" / "navigation_1f.json"
DEFAULT_VECTOR_DIR = API_ROOT / "app" / "data" / "vector_maps"


def find_vector_dataset(
    vector_path: Path,
    *,
    building_id: str,
    floor_id: str,
) -> dict:
    """파일 또는 디렉터리에서 현재 건물/층에 해당하는 벡터 JSON 하나를 찾는다."""
    vector_path = Path(vector_path)
    if vector_path.is_file():
        candidates = [vector_path]
    elif vector_path.is_dir():
        candidates = sorted(vector_path.rglob("*.json"))
    else:
        raise FileNotFoundError(f"벡터 데이터 경로가 없습니다: {vector_path}")

    matches: list[dict] = []
    for candidate in candidates:
        with candidate.open(encoding="utf-8") as vector_file:
            vector_data = json.load(vector_file)
        if (
            vector_data.get("building_id") == building_id
            and vector_data.get("floor_id") == floor_id
        ):
            matches.append(vector_data)

    if not matches:
        raise FileNotFoundError(
            f"{building_id}/{floor_id} 벡터 JSON을 {vector_path}에서 찾지 못했습니다."
        )
    if len(matches) > 1:
        raise ValueError(f"동일한 건물/층 벡터 JSON이 여러 개입니다: {building_id}/{floor_id}")
    return matches[0]


def edge_geometry_and_length(
    edge: dict,
    node_points: dict[str, dict[str, float]],
) -> tuple[list[dict], float]:
    """geometry 또는 length가 누락된 입력을 양 끝 노드 좌표로 보완한다.

    입력 포맷 두 가지를 모두 지원한다.
      - 기존:   edge["geometry_local_m"] = [{x,y}, ...]
      - Studio: edge["geometry"] = {"source": [...], "local_m": [{x,y}, ...]}
    """
    geometry = edge.get("geometry_local_m")
    if geometry is None:
        raw = edge.get("geometry")
        if isinstance(raw, dict):
            geometry = raw.get("local_m")
        elif isinstance(raw, list):
            geometry = raw
    if not geometry:
        geometry = [
            dict(node_points[edge["from"]]),
            dict(node_points[edge["to"]]),
        ]
    length_m = edge.get("length_m")
    if length_m is None:
        length_m = sum(
            hypot(current["x"] - previous["x"], current["y"] - previous["y"])
            for previous, current in zip(geometry, geometry[1:])
        )
    return geometry, length_m


def _add_dataset(
    session: Session,
    data: dict,
    vector_path: Path | None,
) -> None:
    """파싱한 JSON 한 건물/층을 Session에 ORM 객체로 추가한다(commit은 호출자)."""
    building_data = data["building"]
    floor_data = building_data["floor"]
    building_id = building_data["id"]
    floor_id = floor_data["id"]
    node_points = {
        node["id"]: node["position"]["local_m"]
        for node in data["nodes"]
    }

    # 같은 건물의 여러 층을 이어서 시드할 때 Building은 한 번만 생성한다.
    # autoflush=False이므로 직후 flush로 identity map에 올려 다음 층 조회가 찾도록 한다.
    if session.get(Building, building_id) is None:
        session.add(
            Building(
                id=building_id,
                name=building_data["name"],
                area_m2=building_data.get("area_m2"),
                perimeter_m=building_data.get("perimeter_m"),
                footprint_local_m=building_data.get("footprint_local_m"),
            )
        )
        session.flush()
    session.add(
        Floor(
            id=floor_id,
            building_id=building_id,
            name=floor_data["name"],
            level=floor_data["level"],
        )
    )

    session.add_all(
        Node(
            id=node["id"],
            floor_id=floor_id,
            type=node["type"],
            name=node.get("name"),
            x_m=node["position"]["local_m"]["x"],
            y_m=node["position"]["local_m"]["y"],
            lat=(node["position"].get("wgs84") or {}).get("lat"),
            lng=(node["position"].get("wgs84") or {}).get("lng"),
            source_x=(node["position"].get("source") or {}).get("x"),
            source_y=(node["position"].get("source") or {}).get("y"),
        )
        for node in data["nodes"]
    )

    edges: list[Edge] = []
    for edge in data["edges"]:
        geometry, length_m = edge_geometry_and_length(edge, node_points)
        edges.append(
            Edge(
                id=edge["id"],
                floor_id=floor_id,
                from_node_id=edge["from"],
                to_node_id=edge["to"],
                length_m=length_m,
                bidirectional=edge.get("bidirectional", True),
                geometry=geometry,
            )
        )
    session.add_all(edges)

    session.add_all(
        Store(
            id=store["id"],
            floor_id=floor_id,
            name=store["name"],
            centroid_x_m=store["centroid"]["local_m"]["x"],
            centroid_y_m=store["centroid"]["local_m"]["y"],
            entrance_x_m=(store.get("entrance_local_m") or {}).get("x"),
            entrance_y_m=(store.get("entrance_local_m") or {}).get("y"),
            entrance_node_id=store.get("entrance_node_id"),
            polygon=store.get("polygon_local_m"),
        )
        for store in data.get("stores", [])
    )
    session.add_all(
        Poi(
            id=poi["id"],
            floor_id=floor_id,
            type=poi["type"],
            name=poi.get("name"),
            x_m=poi["position"]["local_m"]["x"],
            y_m=poi["position"]["local_m"]["y"],
            linked_node_id=poi.get("linked_node_id"),
        )
        for poi in data.get("pois", [])
    )

    if vector_path is not None:
        vector_data = find_vector_dataset(
            vector_path,
            building_id=building_id,
            floor_id=floor_id,
        )
        session.add(
            FloorVectorMap(
                floor_id=floor_id,
                coordinate_system=vector_data["coordinate_system"],
                source=vector_data["source"],
            )
        )
        session.add_all(
            MapFeature(
                id=feature["id"],
                floor_id=floor_id,
                kind=feature["kind"],
                name=feature.get("name"),
                category=feature.get("category"),
                geometry_type=feature["geometry"]["type"],
                coordinates=feature["geometry"]["coordinates"],
                centroid_x=(feature.get("centroid") or {}).get("x"),
                centroid_y=(feature.get("centroid") or {}).get("y"),
            )
            for feature in vector_data["features"]
        )


def seed_navigation(
    json_path: Path = DEFAULT_JSON,
    vector_path: Path | None = DEFAULT_VECTOR_DIR,
    *,
    session: Session | None = None,
) -> None:
    """JSON 지도 데이터 한 건물/층을 개발 DB에 적재한다.

    session을 주면 그 Session을 사용하고 commit/close는 호출자가 관리한다.
    (테스트가 임시 DB Session으로 시드할 때 사용)
    """
    with Path(json_path).open(encoding="utf-8") as file:
        data = json.load(file)

    if session is not None:
        _add_dataset(session, data, vector_path)
        return

    own_session = SessionLocal()
    try:
        _add_dataset(own_session, data, vector_path)
        own_session.commit()
    except Exception:
        own_session.rollback()
        raise
    finally:
        own_session.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    parser.add_argument(
        "--vector-dir",
        type=Path,
        default=DEFAULT_VECTOR_DIR,
        help="건물/층별 벡터 JSON 디렉터리 또는 단일 JSON 파일",
    )
    args = parser.parse_args()
    seed_navigation(args.json, args.vector_dir)
    print(f"지도 데이터 적재 완료: {args.json}")
