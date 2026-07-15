"""FloorGraph Studio 익스포트를 기존 seed 파이프라인이 먹는 표준 dict로 변환한다.

설계 근거: docs/floorgraph-studio-integration.md (§3 목표 구조, §6 결정 D1~D5)

변환 규칙:
  - floor(상단) → building 블록 합성. 건물명은 legacy navigation_1f.json에서 계승,
    footprint/area는 좌표계 재투영 전이므로 None(D2).
  - nodes  → 그대로 사용(position.local_m/wgs84/source 구조가 이미 호환).
  - edges  → 그대로 사용(seed_navigation.edge_geometry_and_length가 geometry.local_m 처리).
  - stores → map_studio_stores가 만든 stores_{층}.json을 seed 스키마로 reshape(D1/D4).
  - pois   → elevator/escalator 노드에서 자동 생성(지도 마커용).

실행 (api/ 디렉토리에서):
  python -m scripts.studio_adapter                # 1F/3F/4F를 개발 DB에 시드(reset 안 함)
  python -m scripts.studio_adapter --floor 3f
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from app.core.database import SessionLocal
from app.models import Edge
from scripts import seed_navigation
from scripts.link_vertical_transfers import build_transfers

API_ROOT = Path(__file__).resolve().parents[1]
STUDIO_DIR = API_ROOT / "app" / "data" / "studio" / "thehyundai-seoul"
LEGACY_NAV_1F = API_ROOT / "app" / "data" / "navigation_1f.json"

# 지도에 마커로 노출할 편의시설 노드 타입 → POI 로 승격(D-POI: 노드에서 자동 생성)
POI_NODE_TYPES = {"elevator", "escalator"}


def _building_name(building_id: str) -> str:
    """건물명은 legacy navigation_1f.json에서 계승(없으면 building_id로 대체)."""
    if LEGACY_NAV_1F.exists():
        legacy = json.loads(LEGACY_NAV_1F.read_text(encoding="utf-8"))
        building = legacy.get("building", {})
        if building.get("id") == building_id and building.get("name"):
            return building["name"]
    return building_id


def _scoped(floor_id: str, raw_id: str | None) -> str | None:
    """D6: 노드/엣지 ID를 층 스코프로 네임스페이싱한다(층 간 ID 재사용 충돌 방지)."""
    if raw_id is None:
        return None
    return f"{floor_id}:{raw_id}"


def _scope_nodes(floor_id: str, nodes: list[dict]) -> list[dict]:
    return [{**node, "id": _scoped(floor_id, node["id"])} for node in nodes]


def _scope_edges(floor_id: str, edges: list[dict]) -> list[dict]:
    return [
        {
            **edge,
            "id": _scoped(floor_id, edge["id"]),
            "from": _scoped(floor_id, edge["from"]),
            "to": _scoped(floor_id, edge["to"]),
        }
        for edge in edges
    ]


def _reshape_stores(floor_code: str, floor_id: str) -> list[dict]:
    """stores_{층}.json(map_studio_stores 산출물)을 seed용 store dict로 변환."""
    stores_path = STUDIO_DIR / f"stores_{floor_code}.json"
    if not stores_path.exists():
        return []
    payload = json.loads(stores_path.read_text(encoding="utf-8"))
    reshaped: list[dict] = []
    for store in payload.get("stores", []):
        entrance = store.get("entrance_local_m")
        centroid = store.get("centroid_local_m") or entrance
        reshaped.append(
            {
                "id": store["id"],  # store id는 층별로 이미 유일(네임스페이싱 불필요)
                "name": store["name"],
                # seed_navigation는 store["centroid"]["local_m"] 구조를 기대한다.
                "centroid": {"local_m": centroid},
                "entrance_local_m": entrance,
                # entrance_node_id는 Node FK → 네임스페이싱한 노드 ID와 일치시켜야 한다.
                "entrance_node_id": _scoped(floor_id, store.get("entrance_node_id")),
                "polygon_local_m": store.get("polygon_local_m"),
            }
        )
    return reshaped


def _generate_pois(floor_id: str, nodes: list[dict]) -> list[dict]:
    """elevator/escalator 노드를 POI(지도 마커)로 승격한다(ID도 층 스코프)."""
    pois: list[dict] = []
    for node in nodes:
        if node.get("type") not in POI_NODE_TYPES:
            continue
        pois.append(
            {
                "id": _scoped(floor_id, f"poi_{node['id']}"),
                "type": node["type"],
                "name": node.get("name"),
                "position": {"local_m": node["position"]["local_m"]},
                "linked_node_id": _scoped(floor_id, node["id"]),
            }
        )
    return pois


def build_seed_dict(floor_code: str) -> dict:
    """Studio JSON + stores 매핑을 표준 seed dict로 조립한다."""
    studio = json.loads((STUDIO_DIR / f"{floor_code}.json").read_text(encoding="utf-8"))
    building_id = studio["building_id"]
    floor = studio["floor"]
    floor_id = floor["id"]

    return {
        "building": {
            "id": building_id,
            "name": _building_name(building_id),
            "area_m2": None,  # D2: 좌표계 재투영 전까지 보류
            "perimeter_m": None,
            "footprint_local_m": None,
            "floor": {
                "id": floor_id,
                "name": floor["name"],
                "level": floor["level"],
            },
        },
        "nodes": _scope_nodes(floor_id, studio["nodes"]),  # D6
        "edges": _scope_edges(floor_id, studio["edges"]),  # D6
        "stores": _reshape_stores(floor_code, floor_id),
        "pois": _generate_pois(floor_id, studio["nodes"]),
    }


def _seed_transfers(session, floors: list[str]) -> None:
    """층 간 수직 전이(엘리베이터·에스컬레이터) 간선을 Edge(floor_id=None)로 적재한다.

    모든 층의 노드가 먼저 추가된 뒤 호출해야 FK가 성립한다.
    """
    result = build_transfers(floors)
    session.flush()  # 앞서 add한 노드를 DB에 반영해 FK 참조가 성립하도록.
    session.add_all(
        Edge(
            id=transfer["id"],
            floor_id=None,  # 특정 층에 속하지 않는 수직 간선
            from_node_id=transfer["from"],
            to_node_id=transfer["to"],
            length_m=transfer["length_m"],
            bidirectional=transfer["bidirectional"],
            geometry=None,
            transfer_mode=transfer["mode"],
        )
        for transfer in result["transfers"]
    )


def seed_studio(floors: list[str], *, session=None) -> None:
    """여러 층을 하나의 트랜잭션으로 개발 DB에 적재한다(Building은 1회만 생성)."""
    own_session = session or SessionLocal()
    try:
        for floor_code in floors:
            data = build_seed_dict(floor_code)
            seed_navigation._add_dataset(own_session, data, vector_path=None)
        _seed_transfers(own_session, floors)
        if session is None:
            own_session.commit()
    except Exception:
        if session is None:
            own_session.rollback()
        raise
    finally:
        if session is None:
            own_session.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--floor", nargs="*", default=["1f", "3f", "4f"])
    args = parser.parse_args()
    seed_studio(args.floor)
    for floor_code in args.floor:
        data = build_seed_dict(floor_code)
        print(
            f"[{floor_code.upper()}] nodes={len(data['nodes'])} "
            f"edges={len(data['edges'])} stores={len(data['stores'])} "
            f"pois={len(data['pois'])}"
        )
    print("Studio 데이터 적재 완료")


if __name__ == "__main__":
    main()
