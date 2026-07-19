"""FloorGraph Studio 익스포트(다층)를 ORM 적재용 표준 dict로 변환한다.

설계 근거: docs/floorgraph-studio-integration.md (§3 목표 구조, §6 결정 D1~D5)

변환 규칙:
  - floor(상단) → building 블록 합성. 건물명은 Studio 건물 ID의 정적 메타데이터로 보완한다.
  - nodes  → 좌표를 건물 공통 프레임으로 정규화한 뒤 사용(아래 좌표계 항목 참고).
  - edges  → 그대로 사용(seed_navigation.edge_geometry_and_length가 geometry.local_m 처리).
  - stores → 폴리곤이 포함된 stores_{층}.json을 seed 스키마로 reshape(D1/D4).
  - pois   → elevator/escalator 노드에서 자동 생성(지도 마커용).
  - 층 간   → 엘리베이터/에스컬레이터를 이어 수직 전이 간선 생성(vertical_transfers).

좌표계(중요):
  Studio는 층마다 좌표 변환을 따로 피팅해 내보내므로 층별 local_m 스케일이 다르다.
  백엔드는 건물당 local_m->wgs84 변환을 하나만 피팅하므로(queries/geo_transform.py),
  적재 전에 모든 층을 기준층(1F) 프레임으로 정규화한다(floor_alignment).
  wgs84는 정규화 후 기준층의 local_m_to_wgs84 아핀으로 다시 계산한다 — 3F/4F 익스포트에는
  wgs84가 아예 없기 때문이다.

실행 (api/ 디렉토리에서):
  python -m scripts.studio_adapter
"""

from __future__ import annotations

import json
from pathlib import Path

from app.core.database import SessionLocal
from scripts import floor_alignment, seed_navigation, vertical_transfers

API_ROOT = Path(__file__).resolve().parents[1]
STUDIO_DIR = API_ROOT / "app" / "data" / "studio" / "thehyundai-seoul"
BUILDING_NAMES = {"thehyundai-seoul": "더현대 서울"}

# 기준층: 건물 공통 프레임을 정의하고, 실측 wgs84 앵커를 가진 유일한 층이다.
REFERENCE_FLOOR = "1f"

# 지도에 마커로 노출할 편의시설 노드 타입 → POI 로 승격(D-POI: 노드에서 자동 생성)
POI_NODE_TYPES = {"elevator", "escalator"}


def discover_floor_codes(directory: Path = STUDIO_DIR) -> list[str]:
    """{층}.json이 있는 층 코드를 찾아 기준층을 맨 앞에 둔 순서로 돌려준다."""
    codes = sorted(
        path.stem
        for path in directory.glob("*.json")
        if not path.stem.startswith(("stores_", "transfers_"))
    )
    if REFERENCE_FLOOR in codes:
        codes.remove(REFERENCE_FLOOR)
        codes.insert(0, REFERENCE_FLOOR)
    return codes


def _load(floor_code: str, directory: Path = STUDIO_DIR) -> dict:
    return json.loads((directory / f"{floor_code}.json").read_text(encoding="utf-8"))


def _building_name(building_id: str) -> str:
    """Studio 데이터에 없는 표시용 건물명을 ID 기반 메타데이터로 보완한다."""
    return BUILDING_NAMES.get(building_id, building_id)


def _scoped(floor_id: str, raw_id: str | None) -> str | None:
    """D6: 노드/엣지 ID를 층 스코프로 네임스페이싱한다(층 간 ID 재사용 충돌 방지)."""
    if raw_id is None:
        return None
    return f"{floor_id}:{raw_id}"


def _wgs84_transform(reference: dict) -> floor_alignment.Affine | None:
    """기준층의 local_m -> wgs84 아핀. 출력은 (lng, lat) 순서다."""
    matrix = (
        reference["coordinate_system"]
        .get("affine_transforms", {})
        .get("local_m_to_wgs84", {})
        .get("matrix")
    )
    if not matrix:
        return None
    return (
        (matrix[0][0], matrix[0][1], matrix[0][2]),
        (matrix[1][0], matrix[1][1], matrix[1][2]),
    )


def _normalized_nodes(
    floor_id: str,
    nodes: list[dict],
    align: floor_alignment.Affine,
    to_wgs84: floor_alignment.Affine | None,
) -> list[dict]:
    """노드 좌표를 건물 프레임으로 옮기고 wgs84를 다시 계산한다(ID도 층 스코프)."""
    out: list[dict] = []
    for node in nodes:
        local = floor_alignment.apply_point(align, node["position"]["local_m"])
        position = {**node["position"], "local_m": local}
        if to_wgs84 is not None:
            lng, lat = floor_alignment.apply(to_wgs84, local["x"], local["y"])
            position["wgs84"] = {"lat": round(lat, 9), "lng": round(lng, 9)}
        out.append({**node, "id": _scoped(floor_id, node["id"]), "position": position})
    return out


def _scope_edges(floor_id: str, edges: list[dict]) -> list[dict]:
    """간선 ID를 층 스코프로 바꾼다. geometry는 버리고 양 끝 노드로 재생성하게 둔다.

    (geometry는 정규화 전 층 좌표라 그대로 두면 노드와 어긋난다.)
    """
    scoped = []
    for edge in edges:
        item = {k: v for k, v in edge.items() if k not in ("geometry", "geometry_local_m", "length_m")}
        item.update(
            {
                "id": _scoped(floor_id, edge["id"]),
                "from": _scoped(floor_id, edge["from"]),
                "to": _scoped(floor_id, edge["to"]),
            }
        )
        scoped.append(item)
    return scoped


def _reshape_stores(
    floor_code: str,
    floor_id: str,
    align: floor_alignment.Affine,
    directory: Path = STUDIO_DIR,
) -> list[dict]:
    """폴리곤을 포함한 stores_{층}.json을 seed용 store dict로 변환한다."""
    stores_path = directory / f"stores_{floor_code}.json"
    if not stores_path.exists():
        return []
    payload = json.loads(stores_path.read_text(encoding="utf-8"))
    reshaped: list[dict] = []
    for store in payload.get("stores", []):
        entrance = store.get("entrance_local_m")
        centroid = store.get("centroid_local_m") or entrance
        if centroid is None:
            continue  # 좌표가 없으면 지도에 놓을 자리가 없다
        polygon = store.get("polygon_local_m")
        reshaped.append(
            {
                "id": store["id"],  # store id는 층별로 이미 유일(네임스페이싱 불필요)
                # 매칭 안 된 구조물 footprint는 name이 null → store id로 폴백(stores.name NOT NULL)
                "name": store.get("name") or store["id"],
                # 한글 대분류/소분류 카테고리(없으면 None). name-null footprint는 둘 다 null.
                "category": store.get("category"),
                "subcategory": store.get("subcategory"),
                # seed_navigation는 store["centroid"]["local_m"] 구조를 기대한다.
                "centroid": {"local_m": floor_alignment.apply_point(align, centroid)},
                "entrance_local_m": floor_alignment.apply_point(align, entrance) if entrance else None,
                # entrance_node_id는 Node FK → 네임스페이싱한 노드 ID와 일치시켜야 한다.
                "entrance_node_id": _scoped(floor_id, store.get("entrance_node_id")),
                "polygon_local_m": (
                    [floor_alignment.apply_point(align, p) for p in polygon] if polygon else None
                ),
            }
        )
    return reshaped


def _generate_pois(floor_id: str, nodes: list[dict]) -> list[dict]:
    """elevator/escalator 노드를 POI(지도 마커)로 승격한다. nodes는 정규화·스코프 후."""
    return [
        {
            "id": f"poi_{node['id']}",
            "type": node["type"],
            "name": node.get("name"),
            "position": {"local_m": node["position"]["local_m"]},
            "linked_node_id": node["id"],
        }
        for node in nodes
        if node.get("type") in POI_NODE_TYPES
    ]


def build_seed_dict(
    floor_code: str,
    reference: dict | None = None,
    directory: Path = STUDIO_DIR,
) -> dict:
    """한 층의 Studio JSON + stores JSON을 표준 seed dict로 조립한다."""
    studio = _load(floor_code, directory)
    reference = reference or _load(REFERENCE_FLOOR, directory)
    align, stats = floor_alignment.alignment_to_reference(studio, reference)
    to_wgs84 = _wgs84_transform(reference)

    building_id = studio["building_id"]
    floor = studio["floor"]
    floor_id = floor["id"]
    nodes = _normalized_nodes(floor_id, studio["nodes"], align, to_wgs84)
    footprint = studio.get("building_footprint_local_m") or None

    return {
        "building": {
            "id": building_id,
            "name": _building_name(building_id),
            "area_m2": None,  # D2: 좌표계 재투영 전까지 보류
            "perimeter_m": None,
            # Studio '테두리' 도구로 찍은 건물 외곽. 건물 프레임으로 정규화해서 넣는다.
            "footprint_local_m": (
                [floor_alignment.apply_point(align, p) for p in footprint] if footprint else None
            ),
            "floor": {"id": floor_id, "name": floor["name"], "level": floor["level"]},
        },
        "nodes": nodes,
        "edges": _scope_edges(floor_id, studio["edges"]),
        "stores": _reshape_stores(floor_code, floor_id, align, directory),
        "pois": _generate_pois(floor_id, nodes),
        "_alignment": stats,
    }


def seed_studio(
    *,
    session=None,
    floor_codes: list[str] | None = None,
    directory: Path = STUDIO_DIR,
) -> list[dict]:
    """Studio 전 층 + 층 간 전이 간선을 하나의 트랜잭션으로 적재한다."""
    codes = floor_codes or discover_floor_codes(directory)
    if REFERENCE_FLOOR not in codes:
        raise ValueError(f"기준층 {REFERENCE_FLOOR}.json이 있어야 좌표계를 맞출 수 있습니다.")
    reference = _load(REFERENCE_FLOOR, directory)

    own_session = session or SessionLocal()
    try:
        summaries: list[dict] = []
        floors_for_transfer: list[dict] = []
        for code in codes:
            data = build_seed_dict(code, reference, directory)
            seed_navigation.add_dataset(own_session, data)
            floor = data["building"]["floor"]
            floors_for_transfer.append(
                {
                    "code": code,
                    "floor_id": floor["id"],
                    "name": floor["name"],
                    "level": floor["level"],
                    "nodes": data["nodes"],
                }
            )
            summaries.append(
                {
                    "code": code,
                    "name": floor["name"],
                    "nodes": len(data["nodes"]),
                    "edges": len(data["edges"]),
                    "stores": len(data["stores"]),
                    "pois": len(data["pois"]),
                    "alignment": data["_alignment"],
                }
            )

        transfers, unresolved = vertical_transfers.build_transfers(floors_for_transfer)
        seed_navigation.add_transfer_edges(own_session, transfers)
        summaries.append({"code": "-", "transfers": len(transfers), "unresolved": len(unresolved)})

        if session is None:
            own_session.commit()
        return summaries
    except Exception:
        if session is None:
            own_session.rollback()
        raise
    finally:
        if session is None:
            own_session.close()


def main() -> None:
    for row in seed_studio():
        if "transfers" in row:
            print(f"[전이] 간선={row['transfers']} 미해결={row['unresolved']}")
            continue
        a = row["alignment"]
        note = "기준층" if a["identity"] else f"앵커={a['anchors']} 잔차 평균={a['mean']:.2f}m 최대={a['max']:.2f}m"
        print(
            f"[{row['name']}] nodes={row['nodes']} edges={row['edges']} "
            f"stores={row['stores']} pois={row['pois']} · {note}"
        )
    print("Studio 데이터 적재 완료")


if __name__ == "__main__":
    main()
