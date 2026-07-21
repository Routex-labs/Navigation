# 층 JSON(다층)을 ORM 적재용 표준 dict로 변환한다.
# 입력은 scripts/transform/build_studio_from_dabeeo.py가 만든 층별 파일이다.
# 변환 규칙:
#   - floor(상단) → building 블록 합성. 건물명은 Studio 건물 ID의 정적 메타데이터로 보완한다.
#   - nodes  → local_m을 그대로 쓰고 wgs84만 다시 계산한다(아래 좌표계 항목 참고).
#   - edges  → 그대로 사용(seed_navigation.edge_geometry_and_length가 geometry.local_m 처리).
#   - stores → 폴리곤이 포함된 stores_{층}.json을 seed 스키마로 reshape.
#   - pois   → elevator/escalator 노드에서 자동 생성(지도 마커용).
#   - 층 간   → 엘리베이터/에스컬레이터를 이어 수직 전이 간선 생성(vertical_transfers).
# 좌표계(중요):
#   전 층이 하나의 local_m 프레임을 공유한다는 것이 이 어댑터의 전제다. 백엔드는
#   건물당 local_m->wgs84 변환을 하나만 피팅하므로(repositories/geo_transform.py),
#   층 프레임이 제각각이면 그 피팅이 무의미해진다. 다베오 변환기가 원본 좌표계를
#   전 층에 그대로 물려주므로(build_studio_from_dabeeo.py) 이 전제가 성립한다.
#   wgs84만 기준층의 local_m_to_wgs84 아핀으로 다시 계산한다 — 개별 층 익스포트에는
#   wgs84가 아예 없는 경우가 있기 때문이다.
# 실행 (backend/ 디렉토리에서):
#   python -m scripts.seed.studio_adapter

from __future__ import annotations

import json
from math import hypot
from pathlib import Path

from app.core.database import SessionLocal
from scripts.seed import seed_navigation
from scripts.transform import floor_alignment, vertical_transfers

API_ROOT = Path(__file__).resolve().parents[2]
# 다베오 공식 payload에서 만든 12개 층(scripts/transform/build_studio_from_dabeeo.py).
STUDIO_DIR = API_ROOT / "resources" / "studio" / "thehyundai-seoul-dabeeo"
BUILDING_NAMES = {"thehyundai-seoul": "더현대 서울"}

# 매장 id -> {category, subcategory} 오버라이드. Studio 원본은 리테일을 전부
# category="매장"으로 뭉개므로(build_studio가 dabeeo categoryCode를 버림), 실제
# 카테고리를 별도 매핑으로 주입한다. 현재는 category_code가 repo에 남아 있는
# 매장만 채워져 있고(navigation_map_parts/stores.json 기반), 나머지는 매핑에
# 없으므로 원본 category를 그대로 둔다. 파일이 없으면 오버라이드 없이 동작한다.
STORE_CATEGORIES_PATH = API_ROOT / "resources" / "store_categories.json"
# 매장명 -> {category, subcategory}. category_code가 없는 매장(대부분)을 브랜드명
# 기준으로 분류한 폴백 매핑. id 기반(STORE_CATEGORIES_PATH)이 우선한다.
STORE_CATEGORIES_BY_NAME_PATH = API_ROOT / "resources" / "store_category_by_name.json"


def _load_store_categories(path: Path = STORE_CATEGORIES_PATH) -> dict[str, dict]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))

# 기준층: 건물 공통 프레임의 wgs84 앵커를 가진 층. 좌표 자체는 전 층이 공유하므로
# 여기서 가져오는 것은 local_m -> wgs84 아핀뿐이다.
REFERENCE_FLOOR = "1f"

# 지도에 마커로 노출할 편의시설 노드 타입 → POI 로 승격(노드에서 자동 생성)
POI_NODE_TYPES = {"elevator", "escalator"}


# {층}.json이 있는 층 코드를 찾아 기준층을 맨 앞에 둔 순서로 돌려준다.
def discover_floor_codes(directory: Path = STUDIO_DIR) -> list[str]:
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


# Studio 데이터에 없는 표시용 건물명을 ID 기반 메타데이터로 보완한다.
def _building_name(building_id: str) -> str:
    return BUILDING_NAMES.get(building_id, building_id)


# 노드/엣지 ID를 층 스코프로 네임스페이싱한다(층 간 ID 재사용 충돌 방지).
def _scoped(floor_id: str, raw_id: str | None) -> str | None:
    if raw_id is None:
        return None
    return f"{floor_id}:{raw_id}"


# 기준층의 local_m -> wgs84 아핀. 출력은 (lng, lat) 순서다.
def _wgs84_transform(reference: dict) -> floor_alignment.Affine | None:
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


# 노드의 wgs84를 건물 아핀으로 다시 계산한다(ID도 층 스코프).
def _normalized_nodes(
    floor_id: str,
    nodes: list[dict],
    to_wgs84: floor_alignment.Affine | None,
) -> list[dict]:
    out: list[dict] = []
    for node in nodes:
        local = node["position"]["local_m"]
        position = {**node["position"], "local_m": local}
        if to_wgs84 is not None:
            lng, lat = floor_alignment.apply(to_wgs84, local["x"], local["y"])
            position["wgs84"] = {"lat": round(lat, 9), "lng": round(lng, 9)}
        out.append({**node, "id": _scoped(floor_id, node["id"]), "position": position})
    return out


# 간선 ID를 층 스코프로 바꾼다. geometry는 양 끝점만 남기면 향후 곡선/꺾인 복도의
# 실제 경로와 길이가 유실되므로 모든 점을 보존한다.
def _scope_edges(floor_id: str, edges: list[dict]) -> list[dict]:
    scoped = []
    for edge in edges:
        geometry = edge.get("geometry_local_m")
        if geometry is None and isinstance(edge.get("geometry"), dict):
            geometry = edge["geometry"].get("local_m")
        item = {k: v for k, v in edge.items() if k not in ("geometry", "geometry_local_m", "length_m")}
        item.update(
            {
                "id": _scoped(floor_id, edge["id"]),
                "from": _scoped(floor_id, edge["from"]),
                "to": _scoped(floor_id, edge["to"]),
            }
        )
        if geometry:
            item["geometry_local_m"] = geometry
            item["length_m"] = sum(
                hypot(current["x"] - previous["x"], current["y"] - previous["y"])
                for previous, current in zip(geometry, geometry[1:])
            )
        scoped.append(item)
    return scoped


# 입구 좌표(local_m)에서 가장 가까운 통행 노드 ID를 찾는다. Studio 원본은 매장에
# entrance_local_m(좌표)만 주고 entrance_node_id(그래프 연결)는 비워두므로, 이걸
# 채워주지 않으면 클라이언트가 도착 노드를 못 찾아 다익스트라가 아예 돌지 않는다.
# 교차점(junction) 우선으로 스냅해 엘리베이터/에스컬레이터 노드에 잘못 붙는 걸 막고,
# junction이 하나도 없으면 아무 노드로나 폴백한다.
def _nearest_node_id(
    nodes: list[dict],
    x: float,
    y: float,
) -> str | None:
    candidates = [n for n in nodes if n.get("type") == "junction"] or nodes
    best_id: str | None = None
    best_distance = float("inf")
    for node in candidates:
        local = node["position"]["local_m"]
        distance = hypot(local["x"] - x, local["y"] - y)
        if distance < best_distance:
            best_distance = distance
            best_id = node["id"]
    return best_id


# 폴리곤을 포함한 stores_{층}.json을 seed용 store dict로 변환한다.
def _reshape_stores(
    floor_code: str,
    floor_id: str,
    nodes: list[dict],
    directory: Path = STUDIO_DIR,
) -> list[dict]:
    stores_path = directory / f"stores_{floor_code}.json"
    if not stores_path.exists():
        return []
    payload = json.loads(stores_path.read_text(encoding="utf-8"))
    category_overrides = _load_store_categories()
    category_by_name = _load_store_categories(STORE_CATEGORIES_BY_NAME_PATH)
    reshaped: list[dict] = []
    for store in payload.get("stores", []):
        entrance = store.get("entrance_local_m")
        centroid = store.get("centroid_local_m") or entrance
        if centroid is None:
            continue  # 좌표가 없으면 지도에 놓을 자리가 없다
        polygon = store.get("polygon_local_m")
        # entrance_node_id는 Node FK → 네임스페이싱한 노드 ID와 일치시켜야 한다.
        # 원본이 이미 노드를 지정했으면 그대로 스코프하고, 비어 있으면(현 Studio
        # 데이터는 전부 null) 입구 좌표를 가장 가까운 통행 노드에 스냅해 채운다.
        entrance_node_id = _scoped(floor_id, store.get("entrance_node_id"))
        if entrance_node_id is None and entrance is not None:
            entrance_node_id = _nearest_node_id(nodes, entrance["x"], entrance["y"])
        # 실제 카테고리 오버라이드. id 기반(category_code 근거)이 최우선, 없으면
        # 매장명 기반 폴백, 둘 다 없으면 원본 값을 유지한다.
        override = category_overrides.get(store["id"]) or category_by_name.get(
            (store.get("name") or "").strip()
        )
        category = (override or {}).get("category") or store.get("category")
        subcategory = (override or {}).get("subcategory") or store.get("subcategory")
        reshaped.append(
            {
                "id": store["id"],  # store id는 층별로 이미 유일(네임스페이싱 불필요)
                # 매칭 안 된 구조물 footprint는 name이 null → store id로 폴백(stores.name NOT NULL)
                "name": store.get("name") or store["id"],
                # 한글 대분류/소분류 카테고리(없으면 None). name-null footprint는 둘 다 null.
                "category": category,
                "subcategory": subcategory,
                # seed_navigation는 store["centroid"]["local_m"] 구조를 기대한다.
                "centroid": {"local_m": centroid},
                "entrance_local_m": entrance,
                "entrance_node_id": entrance_node_id,
                "polygon_local_m": polygon or None,
            }
        )
    return reshaped


# elevator/escalator 노드를 POI(지도 마커)로 승격한다. nodes는 정규화·스코프 후.
def _generate_pois(floor_id: str, nodes: list[dict]) -> list[dict]:
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


# 한 층의 Studio JSON + stores JSON을 표준 seed dict로 조립한다.
def build_seed_dict(
    floor_code: str,
    reference: dict | None = None,
    directory: Path = STUDIO_DIR,
) -> dict:
    studio = _load(floor_code, directory)
    reference = reference or _load(REFERENCE_FLOOR, directory)
    to_wgs84 = _wgs84_transform(reference)

    building_id = studio["building_id"]
    floor = studio["floor"]
    floor_id = floor["id"]
    nodes = _normalized_nodes(floor_id, studio["nodes"], to_wgs84)
    footprint = studio.get("building_footprint_local_m") or None

    return {
        "building": {
            "id": building_id,
            "name": _building_name(building_id),
            # 절대 배율이 미검증이라(build_studio_from_dabeeo.SCALE_M_PER_UNIT)
            # 면적·둘레는 신뢰할 수 없다. 배율이 확정되면 채운다.
            "area_m2": None,
            "perimeter_m": None,
            # 건물 대표 외곽(기준층). 층별 윤곽은 floor.footprint_local_m에 따로 넣는다.
            "footprint_local_m": footprint,
            "floor": {
                "id": floor_id,
                "name": floor["name"],
                "level": floor["level"],
                "footprint_local_m": footprint,
            },
            "map_calibration_version": studio.get("coordinate_system", {}).get(
                "calibration_version", "unversioned"
            ),
        },
        "nodes": nodes,
        "edges": _scope_edges(floor_id, studio["edges"]),
        "stores": _reshape_stores(floor_code, floor_id, nodes, directory),
        "pois": _generate_pois(floor_id, nodes),
    }


# Studio 전 층 + 층 간 전이 간선을 하나의 트랜잭션으로 적재한다.
def seed_studio(
    *,
    session=None,
    floor_codes: list[str] | None = None,
    directory: Path = STUDIO_DIR,
) -> list[dict]:
    codes = floor_codes or discover_floor_codes(directory)
    if REFERENCE_FLOOR not in codes:
        raise ValueError(f"기준층 {REFERENCE_FLOOR}.json이 있어야 wgs84를 계산할 수 있습니다.")
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
        print(
            f"[{row['name']}] nodes={row['nodes']} edges={row['edges']} "
            f"stores={row['stores']} pois={row['pois']}"
        )
    print("Studio 데이터 적재 완료")


if __name__ == "__main__":
    main()
