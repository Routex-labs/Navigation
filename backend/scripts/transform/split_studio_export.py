# FloorGraph Studio의 통합 export를 그래프/매장 2개 JSON으로 분리한다.
# Studio(HTML)의 '현재 층 내보내기'는 그래프와 매장 폴리곤을 한 파일에 담아 준다.
# 이 스크립트는 그것을 파이프라인이 먹는 2개 파일로 나눈다:
#   {floor}.json        - 노드/엣지 그래프 (+ 건물 테두리 building_footprint_local_m)
#   stores_{floor}.json - 매장 폴리곤 (front 파이프라인 포맷)
# 좌표계 주의: 편집기는 과거 호환성 때문에 store_polygons_local_m과
# building_footprint_local_m을 source 좌표로 저장한다. 여기서
# coordinate_system.affine_transforms.source_to_local_m으로 실제 local_m으로 변환한다.
# 실행 (backend/ 디렉토리에서):
#   python -m scripts.transform.split_studio_export <통합export.json>
#   python -m scripts.transform.split_studio_export <통합export.json> --floor 1f --out-dir resources/studio/thehyundai-seoul

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = API_ROOT / "resources" / "studio" / "thehyundai-seoul"

# 편집기 전용 키. 그래프 JSON에서는 빼고 stores JSON으로 옮긴다.
STORE_KEYS = (
    "store_polygons_local_m",
    "store_polygons_imported",
    "store_polygon_metadata",
)
# 폴리곤으로 인정할 최소 꼭짓점 수(그리는 중이던 빈 초안 제외용).
MIN_POLYGON_POINTS = 3
# 폴리곤 안에 있으면 그 매장의 입구로 볼 노드 타입.
ENTRANCE_NODE_TYPES = ("store_entrance", "poi", "elevator", "escalator", "stairs", "restroom", "entrance")


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _dump(path: Path, obj: dict) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


# source_to_local_m 아핀 변환을 적용하는 함수를 만든다.
def _source_to_local(combined: dict):
    matrix = combined["coordinate_system"]["affine_transforms"]["source_to_local_m"]["matrix"]
    (a, b, tx), (c, d, ty) = matrix[0], matrix[1]

    def convert(point: dict) -> dict:
        return {
            "x": round(a * point["x"] + b * point["y"] + tx, 6),
            "y": round(c * point["x"] + d * point["y"] + ty, 6),
        }

    return convert


def _point_in_polygon(polygon: list[dict], point: dict) -> bool:
    x, y, inside, j = point["x"], point["y"], False, len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = polygon[i]["x"], polygon[i]["y"]
        xj, yj = polygon[j]["x"], polygon[j]["y"]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


# 면적 가중 폴리곤 중심. 퇴화(선형) 도형이면 꼭짓점 평균으로 대체.
def _centroid(polygon: list[dict]) -> dict:
    area = cx = cy = 0.0
    n = len(polygon)
    for i in range(n):
        a, b = polygon[i], polygon[(i + 1) % n]
        cross = a["x"] * b["y"] - b["x"] * a["y"]
        area += cross
        cx += (a["x"] + b["x"]) * cross
        cy += (a["y"] + b["y"]) * cross
    if abs(area) < 1e-9:
        return {
            "x": round(sum(p["x"] for p in polygon) / n, 6),
            "y": round(sum(p["y"] for p in polygon) / n, 6),
        }
    area *= 0.5
    return {"x": round(cx / (6 * area), 6), "y": round(cy / (6 * area), 6)}


def split_export(
    combined_path: Path,
    floor_code: str,
    out_dir: Path,
    prev_dir: Path | None = None,
    carry_over: bool = False,
) -> tuple[Path, Path]:
    combined = _load(combined_path)
    to_local = _source_to_local(combined)
    nodes = {n["id"]: n for n in combined["nodes"]}
    floor_id = combined["floor"]["id"]

    out_dir.mkdir(parents=True, exist_ok=True)
    graph_path = out_dir / f"{floor_code}.json"
    stores_path = out_dir / f"stores_{floor_code}.json"
    # 기존 stores 파일에서 id/entrance_wgs84/match 같은 정보를 이어받는다.
    # prev_dir을 따로 주면 다른 위치로 내보내면서도 리포지토리 값을 물려받을 수 있다.
    prev_path = (prev_dir / f"stores_{floor_code}.json") if prev_dir else stores_path
    previous = _load(prev_path) if prev_path.exists() else {"stores": [], "unmatched": []}
    prev_by_id = {s["id"]: s for s in previous.get("stores", [])}
    prev_by_entrance = {s.get("entrance_node_id"): s for s in previous.get("stores", [])}

    polygons = [
        [to_local(pt) for pt in poly] for poly in combined.get("store_polygons_local_m", [])
    ]
    metadata = combined.get("store_polygon_metadata", [])

    def entrance_of(node_id: str | None):
        node = nodes.get(node_id) if node_id else None
        if not node:
            return None, None
        return node["position"].get("local_m"), node["position"].get("wgs84")

    stores: list[dict] = []
    used: set[str] = set()

    # 1) 라벨(메타데이터)이 있는 폴리곤 — 인덱스가 서로 대응한다.
    for i, meta in enumerate(metadata):
        if i >= len(polygons) or len(polygons[i]) < MIN_POLYGON_POINTS:
            continue  # 그리는 중이던 빈 초안
        polygon = polygons[i]
        entrance_id = meta.get("entrance_node_id")
        # ID 안정성: 편집기 metadata에 id가 없으면 같은 입구 노드를 쓰던 기존 매장의
        # id를 물려받는다. 그래야 재-분리할 때 같은 매장이 새 id로 중복 생성되지 않는다
        # (예: ST-1F-001 컨시어지가 node_019로 바뀌어 둘 다 남는 문제).
        # 편집기는 id에 입구 노드 id를 넣어주기도 하므로(정규 매장 id가 아님)
        # 기존 파일에서 물려받은 id를 먼저 쓴다.
        inherited = prev_by_entrance.get(entrance_id, {}).get("id") if entrance_id else None
        store_id = inherited or meta.get("id") or entrance_id or f"footprint_{i + 1:03d}"
        # 입구 노드를 공유하는 폴리곤들(예: 남/여 화장실)은 물려받은 id가 겹친다.
        # store.id는 PK라 층 안에서 유일해야 하므로 접미사로 분리한다.
        if store_id in used:
            store_id = f"{store_id}_{i:03d}"
        local, wgs = entrance_of(entrance_id)
        base = prev_by_id.get(store_id, {})
        stores.append({
            "id": store_id,
            "name": meta.get("name"),
            "floor_id": floor_id,
            "entrance_node_id": meta.get("entrance_node_id"),
            "entrance_local_m": local or base.get("entrance_local_m"),
            "entrance_wgs84": wgs or base.get("entrance_wgs84"),
            # metadata의 centroid는 편집기가 source 좌표로 넣어둔 경우가 있어 신뢰하지 않는다.
            # 이미 local_m으로 바꾼 폴리곤에서 다시 계산해야 단위가 섞이지 않는다.
            "centroid_local_m": _centroid(polygon),
            "polygon_local_m": polygon,
            "match": base.get("match", {"method": "studio_export", "legacy_store_id": None}),
        })
        used.add(store_id)

    # 2) 메타데이터가 없는 폴리곤 — 안에 들어오는 노드로 입구를 추정한다.
    new_footprints = 0
    for i in range(len(metadata), len(polygons)):
        polygon = polygons[i]
        if len(polygon) < MIN_POLYGON_POINTS:
            continue
        hit = next(
            (n for n in combined["nodes"]
             if n["type"] in ENTRANCE_NODE_TYPES and _point_in_polygon(polygon, n["position"]["local_m"])),
            None,
        )
        source = prev_by_entrance.get(hit["id"]) if hit else None
        if source and source["id"] not in used:
            local, wgs = entrance_of(hit["id"])
            stores.append({
                "id": source["id"],
                "name": source.get("name") or hit.get("name"),
                "floor_id": floor_id,
                "entrance_node_id": hit["id"],
                "entrance_local_m": local or source.get("entrance_local_m"),
                "entrance_wgs84": wgs or source.get("entrance_wgs84"),
                "centroid_local_m": _centroid(polygon),
                "polygon_local_m": polygon,
                "match": source.get("match", {"method": "studio_footprint", "legacy_store_id": None}),
            })
            used.add(source["id"])
            continue
        local, wgs = entrance_of(hit["id"]) if hit else (None, None)
        name = hit.get("name") if hit else None
        new_id = f"footprint_{i - len(metadata) + 1:03d}"
        stores.append({
            "id": new_id,
            "name": name if name not in (None, "NODE") else None,
            "floor_id": floor_id,
            "entrance_node_id": hit["id"] if hit else None,
            "entrance_local_m": local,
            "entrance_wgs84": wgs,
            "centroid_local_m": _centroid(polygon),
            "polygon_local_m": polygon,
            "match": {"method": "studio_footprint", "legacy_store_id": None},
        })
        # 이 id를 소비 처리해야 3단계 carry-over가 이전 실행의 동명 footprint를
        # 중복으로 되살리지 않는다(재실행 시 매장 수가 계속 늘어나는 문제).
        used.add(new_id)
        new_footprints += 1

    # 3) 이번 export에 없는 기존 매장 살리기(기본 끔).
    #    Studio가 모든 폴리곤을 라벨과 함께 들고 있으면 export가 곧 source of truth라,
    #    살리면 같은 자리가 옛 id로 중복된다(예: EV3 ↔ 엘레베이터). 과거 데이터가
    #    Studio에 없어서 보존이 필요할 때만 carry_over=True로 켠다.
    carried = [s for s in previous.get("stores", []) if s["id"] not in used]
    if carry_over:
        for store in carried:
            stores.append(copy.deepcopy(store))
            used.add(store["id"])
    elif carried:
        print(f"[skip] export에 없는 기존 매장 {len(carried)}개 제외"
              f" (--carry-over 로 유지 가능): {', '.join(s['id'] for s in carried[:6])}"
              f"{' …' if len(carried) > 6 else ''}")

    stores_doc = {
        "building_id": combined.get("building_id"),
        "floor": combined["floor"],
        "coordinate_frame": previous.get("coordinate_frame", "local_m"),
        "stores": stores,
        "unmatched": previous.get("unmatched", []),
        "summary": {
            "stores": len(stores),
            "with_polygon": sum(1 for s in stores if s.get("polygon_local_m")),
            "new_footprints": new_footprints,
        },
    }

    graph = {k: v for k, v in combined.items() if k not in STORE_KEYS}
    # 건물 테두리도 source → local_m으로 변환해 그래프 JSON에 남긴다.
    # studio_adapter가 이 값을 building.footprint_local_m으로 적재한다.
    outline = combined.get("building_footprint_local_m") or []
    if outline:
        graph["building_footprint_local_m"] = [to_local(pt) for pt in outline]

    _dump(graph_path, graph)
    _dump(stores_path, stores_doc)
    print(f"그래프 : {graph_path} (노드 {len(graph['nodes'])} · 엣지 {len(graph['edges'])}"
          f" · 테두리 {len(outline)}모서리)")
    print(f"매장   : {stores_path} (매장 {len(stores)} · 신규 footprint {new_footprints})")
    return graph_path, stores_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Studio 통합 export를 그래프/매장 2개 JSON으로 분리한다."
    )
    parser.add_argument("combined", type=Path, help="Studio가 내보낸 통합 JSON")
    parser.add_argument("--floor", default="1f", help="층 코드 (기본: 1f)")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument(
        "--prev-dir",
        type=Path,
        default=None,
        help="id/wgs84/match를 물려받을 기존 stores JSON 위치 (기본: --out-dir과 동일)",
    )
    parser.add_argument(
        "--carry-over",
        action="store_true",
        help="이번 export에 없는 기존 매장도 결과에 유지한다(기본: 제외)",
    )
    args = parser.parse_args()
    split_export(args.combined, args.floor, args.out_dir, args.prev_dir, args.carry_over)


if __name__ == "__main__":
    main()
