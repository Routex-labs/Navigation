"""FloorGraph Studio 익스포트의 store_entrance 노드를 매장(store) 레코드로 매핑한다.

설계 근거: docs/floorgraph-studio-integration.md (§4 매장 매핑, §6 결정 D1~D5)

1단계 범위(확정):
  - D1 매장명 = Studio `store_entrance` 노드명을 정답으로 사용.
  - D2 polygon = 미포함(null). centroid는 입구 노드 위치로 대체(마커).
  - D4 좌표 = Studio 프레임(신규 local_m / wgs84).
  - D5 매칭 순서 = ① ID 조인 → ② 이름 매칭 → ③ studio_only(구 매장 없음).
       (구 `stores[]`는 1F에만 있으며, 여기서는 legacy id 계승/리뷰용으로만 참조)

실행 (api/ 디렉토리에서):
  python -m scripts.map_studio_stores                 # 1F/3F/4F 전부
  python -m scripts.map_studio_stores --floor 3f      # 특정 층
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
STUDIO_DIR = API_ROOT / "app" / "data" / "studio" / "thehyundai-seoul"
LEGACY_NAV = {
    # Studio 이외에 구 stores[]가 존재하는 층만 매핑(1F뿐). 없으면 studio_only.
    "1f": API_ROOT / "app" / "data" / "navigation_1f.json",
}
OUTPUT_DIR = STUDIO_DIR  # stores_{floor}.json 을 같은 폴더에 생성

# 매장이 아닌 플레이스홀더 노드명(매장 레코드에서 제외하고 리뷰 대상으로 분류)
PLACEHOLDER_NAMES = {"", "NODE", "입구", "노드"}


def _norm(name: str | None) -> str:
    """이름 매칭용 정규화: 공백 제거."""
    return "".join((name or "").split())


def _load_legacy_stores(floor_code: str) -> dict:
    """구 navigation JSON에서 매장 정보를 인덱싱(있을 때만)."""
    path = LEGACY_NAV.get(floor_code)
    if path is None or not path.exists():
        return {"by_node": {}, "by_name": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    by_node: dict[str, dict] = {}
    by_name: dict[str, dict] = {}
    for store in data.get("stores", []):
        entrance_node_id = store.get("entrance_node_id")
        if entrance_node_id:
            by_node[entrance_node_id] = store
        by_name.setdefault(_norm(store.get("name")), store)
    return {"by_node": by_node, "by_name": by_name}


def map_floor(floor_code: str) -> dict:
    """한 층의 store_entrance 노드를 매장 레코드로 변환한다."""
    studio = json.loads((STUDIO_DIR / f"{floor_code}.json").read_text(encoding="utf-8"))
    floor = studio["floor"]
    floor_id = floor["id"]
    legacy = _load_legacy_stores(floor_code)

    stores: list[dict] = []
    unmatched: list[dict] = []
    seq = 0
    used_legacy_ids: set[str] = set()

    for node in studio["nodes"]:
        if node.get("type") != "store_entrance":
            continue
        name = (node.get("name") or "").strip()
        node_id = node["id"]
        local_m = node["position"]["local_m"]
        wgs84 = node["position"].get("wgs84")

        # 매장이 아닌 플레이스홀더는 리뷰 대상으로 분리
        if name in PLACEHOLDER_NAMES:
            unmatched.append(
                {"node_id": node_id, "name": name, "reason": "placeholder_name"}
            )
            continue

        # D5 매칭: ① ID 조인 → ② 이름 매칭 → ③ studio_only
        legacy_store = legacy["by_node"].get(node_id)
        method = "id_join"
        if legacy_store is None:
            legacy_store = legacy["by_name"].get(_norm(name))
            method = "name_match" if legacy_store is not None else "studio_only"

        # D1: 이름은 Studio 우선. legacy id는 있으면 계승(1F 하위호환)
        if legacy_store is not None and legacy_store["id"] not in used_legacy_ids:
            store_id = legacy_store["id"]
            used_legacy_ids.add(store_id)
        else:
            seq += 1
            store_id = f"ST-{floor_code.upper()}-{seq:03d}"
            if legacy_store is not None:
                method = "studio_only"  # legacy id가 이미 소진됨(중복명)

        stores.append(
            {
                "id": store_id,
                "name": name,  # D1
                "floor_id": floor_id,
                "entrance_node_id": node_id,
                "entrance_local_m": {"x": local_m["x"], "y": local_m["y"]},  # D4
                "entrance_wgs84": wgs84,
                # D2: polygon/정확한 centroid는 2단계. 지금은 입구 위치를 centroid로 대체.
                "centroid_local_m": {"x": local_m["x"], "y": local_m["y"]},
                "polygon_local_m": None,
                "match": {
                    "method": method,
                    "legacy_store_id": legacy_store["id"] if legacy_store else None,
                },
            }
        )

    return {
        "building_id": studio["building_id"],
        "floor": {"id": floor_id, "name": floor["name"], "level": floor["level"]},
        "coordinate_frame": "studio_local_m",
        "stores": stores,
        "unmatched": unmatched,
        "summary": _summary(stores, unmatched),
    }


def _summary(stores: list[dict], unmatched: list[dict]) -> dict:
    methods: dict[str, int] = {}
    for store in stores:
        method = store["match"]["method"]
        methods[method] = methods.get(method, 0) + 1
    return {
        "stores": len(stores),
        "unmatched": len(unmatched),
        "by_method": methods,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--floor",
        nargs="*",
        default=["1f", "3f", "4f"],
        help="처리할 층 코드(기본: 1f 3f 4f)",
    )
    args = parser.parse_args()

    for floor_code in args.floor:
        result = map_floor(floor_code)
        out_path = OUTPUT_DIR / f"stores_{floor_code}.json"
        out_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        summary = result["summary"]
        print(
            f"[{floor_code.upper()}] stores={summary['stores']} "
            f"unmatched={summary['unmatched']} "
            f"by_method={summary['by_method']} → {out_path.name}"
        )


if __name__ == "__main__":
    main()
