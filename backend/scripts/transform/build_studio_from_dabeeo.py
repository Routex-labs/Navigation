"""다베오 공식 payload를 Studio 층 JSON으로 변환한다(12개 층).

기존 파이프라인의 문제:
  - 1F만 다베오에서 받고 B2는 스크린샷을 40px 격자로 근사했다.
  - 층마다 좌표 변환을 따로 피팅해 층별 비등방 배율(1.39~2.77)이 생겼고,
    이를 6-DOF 아핀으로 이어붙이며 shear가 발생했다.
  - 기존 노드 wgs84는 그 비등방 변환의 산물이라 건물이 북향으로 눕는다
    (실측 회전 52.578°, 기존 데이터 0.04°).

이 변환기는 다베오 원본 좌표계를 **모든 층이 그대로 공유**하게 한다. 층 정렬이
필요 없으므로 shear도 이방성도 구조적으로 발생할 수 없다.

미해결:
  절대 배율. payload의 scaleCm=10/scalePx=1은 0.1m/unit을 뜻하지만, 그러면 1F
  LEVEL section이 167x98m(16182m²)로 VWorld 실측 7062m²와 맞지 않는다. 형상과
  층간 정합은 배율과 무관하므로 우선 0.1을 쓰고 SCALE_M_PER_UNIT 한 곳만 고치면
  전체가 따라오도록 둔다.
"""

from __future__ import annotations

import json
from math import hypot
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "backend/resources/studio/thehyundai-seoul-dabeeo"

# payload.scaleCm=10.0, scalePx=1 → 1 unit = 10cm. 등방.
SCALE_M_PER_UNIT = 0.1

# 다베오 층 이름 -> 우리 층 코드. level은 위층일수록 커지는 단조 정수로 둔다
# (vertical_transfers가 level 정렬로 인접 층을 잇는다).
FLOOR_LEVELS = {
    "6F": 6, "5F": 5, "4F": 4, "3F": 3, "2F": 2, "1F": 1,
    "B1": -1, "B2": -2, "B3": -3, "B4": -4, "B5": -5, "B6": -6,
}

# node.transCode -> 우리 노드 타입. 나머지는 통로 교차점이다.
TRANS_CODE_TYPES = {
    "OB-ELEVATOR": "elevator",
    "OB-ESCALATOR_UP": "escalator",
    "OB-ESCALATOR_DOWN": "escalator",
    "OB-STAIRS": "stairs",
}

FACILITY_ATTRIBUTES = {
    "OB-ELEVATOR": "elevator",
    "OB-ESCALATOR_UP": "escalator",
    "OB-ESCALATOR_DOWN": "escalator",
    "OB-TOILET": "restroom",
    "OB-CAFE": "cafe",
    "OB-RESTAURANT": "restaurant",
    "OB-OTHER_FACILITIES": "facility",
}


METERS_PER_DEGREE_LAT = 111320.0
VWORLD_BUILDING = REPO / "thehyundai_indoor_navigation_dataset/navigation_map_parts/building.json"


def floor_code(name: str) -> str:
    return name.lower()


# local_m -> wgs84 아핀을 만든다.
#
# 회전은 payload의 georeferencingRotate(52.578°)를 쓴다. 기존 데이터는 이 값을
# 반영하지 않아 건물이 북향으로 누워 있었다. 위치는 VWorld 실측 건물 중심에
# 맞춘다 — georeferencing 4개 코너로 풀면 배율이 0.1024로 나와 공식 scaleCm과
# 2.4% 어긋나므로, 검증된 회전·배율은 쓰고 평행이동만 실측으로 정한다.
#
# status는 unverified로 남긴다. 절대 배율이 확정되기 전까지 이 변환은 표시용이다.
def georeference(payload: dict, reference_floor: dict) -> dict:
    import math

    rotate = math.radians(float(payload.get("georeferencingRotate") or 0.0))
    building = json.loads(VWORLD_BUILDING.read_text(encoding="utf-8"))["building"]
    ring = building["exterior_geojson"]["coordinates"][0]
    target_lng = sum(p[0] for p in ring) / len(ring)
    target_lat = sum(p[1] for p in ring) / len(ring)

    footprint = floor_footprint(reference_floor)
    source = centroid(footprint)

    cos_lat = math.cos(math.radians(target_lat))
    cos_r, sin_r = math.cos(rotate), math.sin(rotate)

    # local_m을 회전시켜 동/북 미터로, 다시 경위도로. y축은 화면 아래가 +이므로 북쪽은 -y다.
    a = cos_r / (METERS_PER_DEGREE_LAT * cos_lat)
    b = sin_r / (METERS_PER_DEGREE_LAT * cos_lat)
    c = sin_r / METERS_PER_DEGREE_LAT
    d = -cos_r / METERS_PER_DEGREE_LAT
    return {
        "type": "affine_2d",
        "matrix": [
            [a, b, target_lng - (a * source["x"] + b * source["y"])],
            [c, d, target_lat - (c * source["x"] + d * source["y"])],
            [0, 0, 1],
        ],
        "input_axes": ["x", "y"],
        "output_axes": ["lng", "lat"],
        "rotate_deg": payload.get("georeferencingRotate"),
        "anchor": "vworld_building_centroid",
        "status": "unverified",
    }


def text_ko(values: list[dict] | None) -> str | None:
    for value in values or []:
        if value.get("lang") == "ko" and value.get("text"):
            return " ".join(value["text"].split())
    return None


def to_local(point: dict) -> dict[str, float]:
    return {
        "x": round(float(point.get("x", 0.0)) * SCALE_M_PER_UNIT, 6),
        "y": round(float(point.get("y", 0.0)) * SCALE_M_PER_UNIT, 6),
    }


def source_point(point: dict) -> dict[str, float]:
    return {"x": round(float(point.get("x", 0.0)), 6), "y": round(float(point.get("y", 0.0)), 6)}


def polygon(points: list[dict] | None) -> list[dict[str, float]]:
    return [to_local(p) for p in points or [] if "x" in p and "y" in p]


def polygon_area(points: list[dict]) -> float:
    n = len(points)
    if n < 3:
        return 0.0
    total = sum(
        points[i]["x"] * points[(i + 1) % n]["y"] - points[(i + 1) % n]["x"] * points[i]["y"]
        for i in range(n)
    )
    return abs(total) / 2


def centroid(points: list[dict]) -> dict[str, float]:
    if not points:
        return {"x": 0.0, "y": 0.0}
    return {
        "x": round(sum(p["x"] for p in points) / len(points), 6),
        "y": round(sum(p["y"] for p in points) / len(points), 6),
    }


# 층 외곽선: LEVEL section이 층 전체 윤곽이다. OB-OUTLINE은 1F에서 10~12m²짜리
# 장식 객체라 외곽선으로 쓸 수 없다.
def floor_footprint(floor: dict) -> list[dict[str, float]]:
    levels = [s for s in floor.get("sections") or [] if s.get("title") == "LEVEL"]
    pool = levels or (floor.get("sections") or [])
    if not pool:
        return []
    best = max(pool, key=lambda s: polygon_area(polygon(s.get("coordinates"))))
    return polygon(best.get("coordinates"))


def build_floor(payload: dict, floor: dict, geo: dict) -> tuple[dict, dict]:
    name = text_ko(floor.get("name")) or floor["id"]
    code = floor_code(name)
    floor_id = floor["id"]
    level = FLOOR_LEVELS.get(name, 0)

    objects = {o["id"]: o for o in floor.get("objects") or []}

    nodes: list[dict] = []
    for node in floor.get("nodes") or []:
        trans = node.get("transCode")
        node_type = TRANS_CODE_TYPES.get(trans or "", "junction")
        title = node.get("title")
        record = {
            "id": node["id"],
            "type": node_type,
            "position": {
                "source": source_point(node.get("position") or {}),
                "local_m": to_local(node.get("position") or {}),
            },
            "source": {"kind": "dabeeo_node", "trans_code": trans,
                       "object_ids": node.get("objectIds") or []},
        }
        if title and title != "NODE":
            record["name"] = title
        nodes.append(record)

    node_ids = {n["id"] for n in nodes}
    edges: list[dict] = []
    transfers: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for node in floor.get("nodes") or []:
        for edge in node.get("edges") or []:
            target = edge.get("nodeId")
            if not target:
                continue
            key = tuple(sorted((node["id"], target)))
            if key in seen:
                continue
            seen.add(key)
            linked = edge.get("linkedFloorId")
            # distance가 없는 간선이 있다. 두 노드 좌표로 직접 잰다.
            raw_distance = edge.get("distance")
            if raw_distance is None:
                other = next((n for n in floor.get("nodes") or [] if n["id"] == target), None)
                here = node.get("position") or {}
                there = (other or {}).get("position") or {}
                raw_distance = hypot(
                    float(there.get("x", here.get("x", 0.0))) - float(here.get("x", 0.0)),
                    float(there.get("y", here.get("y", 0.0))) - float(here.get("y", 0.0)),
                )
            length = round(float(raw_distance) * SCALE_M_PER_UNIT, 6)
            payload_edge = {
                "id": edge.get("id") or f"{node['id']}__{target}",
                "from": node["id"],
                "to": target,
                "bidirectional": True,
                "length_m": length,
                "passable": bool(edge.get("passable", True)),
                "source": {"kind": "dabeeo_edge"},
            }
            if linked and linked != floor_id:
                payload_edge["linked_floor_id"] = linked
                transfers.append(payload_edge)
            elif target in node_ids:
                edges.append(payload_edge)

    # POI를 매장/시설로, 연결된 object 폴리곤을 도형으로 쓴다.
    stores: list[dict] = []
    polygons: list[list[dict]] = []
    metadata: list[dict] = []
    for poi in floor.get("pois") or []:
        title = text_ko(poi.get("titleByLanguages")) or poi.get("title")
        if not title:
            continue
        obj = objects.get(poi.get("objectId") or "")
        shape = polygon((obj or {}).get("coordinates")) if obj else []
        attribute = (obj or {}).get("attributeCode")
        subcategory = FACILITY_ATTRIBUTES.get(attribute or "")
        store_id = poi["id"]
        record = {
            "id": store_id,
            "name": title,
            "category": "편의시설" if subcategory else "매장",
            "subcategory": subcategory or "매장",
            "floor_id": floor_id,
            "entrance_node_id": None,
            "entrance_local_m": to_local(poi.get("position") or {}),
            "entrance_wgs84": None,
            "centroid_local_m": centroid(shape) if shape else to_local(poi.get("position") or {}),
            "polygon_local_m": shape,
            "match": {"method": "dabeeo_official_poi", "object_id": poi.get("objectId"),
                      "review_required": False},
        }
        stores.append(record)
        if shape:
            polygons.append(shape)
            metadata.append({
                "id": store_id, "name": title,
                "category": record["category"], "subcategory": record["subcategory"],
                "entrance_node_id": None, "centroid_local_m": record["centroid_local_m"],
            })

    footprint = floor_footprint(floor)
    graph = {
        "schema_version": "0.1.0",
        "building_id": "thehyundai-seoul",
        "floor": {"id": floor_id, "name": name, "level": level, "order": floor.get("order", level)},
        "generated_from": {
            "provider": "dabeeo_official_map",
            "map_id": payload.get("id"),
            "map_version": payload.get("versionString"),
            "credentials_persisted": False,
        },
        "coordinate_system": {
            "type": "dabeeo_map_units_scaled",
            "calibration_version": f"dabeeo-official-v{payload.get('versionString')}",
            "source_map_size": payload.get("size"),
            "scale": {"x_m_per_source_unit": SCALE_M_PER_UNIT,
                      "y_m_per_source_unit": SCALE_M_PER_UNIT},
            "affine_transforms": {
                "source_to_local_m": {
                    "type": "affine_2d",
                    "matrix": [[SCALE_M_PER_UNIT, 0, 0], [0, SCALE_M_PER_UNIT, 0], [0, 0, 1]],
                    "input_axes": ["x", "y"], "output_axes": ["x", "y"],
                },
                "local_m_to_wgs84": geo,
            },
            "georeferencing": {
                "west": payload.get("georeferencingWest"),
                "south": payload.get("georeferencingSouth"),
                "east": payload.get("georeferencingEast"),
                "north": payload.get("georeferencingNorth"),
                "rotate_deg": payload.get("georeferencingRotate"),
                "status": "unverified",
            },
            "notes": [
                "모든 층이 다베오 원본 좌표계를 공유한다. 층 정렬이 필요 없으므로 shear/이방성이 생기지 않는다.",
                "절대 배율 미검증: scaleCm=10 기준 1F LEVEL이 167x98m인데 VWorld 실측은 126x68m다.",
            ],
        },
        "nodes": nodes,
        "edges": edges,
        "vertical_transfer_edges": transfers,
        "store_polygons_local_m": polygons,
        "store_polygons_imported": True,
        "store_polygon_metadata": metadata,
        "manual_review_candidates": [],
        "counts": {"nodes": len(nodes), "edges": len(edges), "transfers": len(transfers),
                   "stores": len(stores), "polygons": len(polygons)},
        "building_footprint_local_m": footprint,
    }
    store_payload = {
        "building_id": "thehyundai-seoul",
        "floor": graph["floor"],
        "coordinate_frame": "dabeeo_local_m",
        "stores": stores,
        "unmatched": [],
        "summary": {"source": "dabeeo official map", "store_count": len(stores),
                    "polygon_count": len(polygons), "review_required": False},
    }
    return code, {"graph": graph, "stores": store_payload}


def main(payload_path: Path) -> None:
    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    reference = next(f for f in payload["floors"] if text_ko(f.get("name")) == "1F")
    geo = georeference(payload, reference)
    print(f"{'층':5s}{'노드':>6s}{'간선':>7s}{'층간':>6s}{'매장':>6s}{'폴리곤':>7s}  외곽선")
    for floor in payload.get("floors") or []:
        code, built = build_floor(payload, floor, geo)
        (OUT / f"{code}.json").write_text(
            json.dumps(built["graph"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (OUT / f"stores_{code}.json").write_text(
            json.dumps(built["stores"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        c = built["graph"]["counts"]
        fp = built["graph"]["building_footprint_local_m"]
        xs = [p["x"] for p in fp] or [0]
        ys = [p["y"] for p in fp] or [0]
        print(f"{code:5s}{c['nodes']:6d}{c['edges']:7d}{c['transfers']:6d}"
              f"{c['stores']:6d}{c['polygons']:7d}  {len(fp)}각형 "
              f"{max(xs) - min(xs):.1f}x{max(ys) - min(ys):.1f}m")
    print(f"\n생성 위치: {OUT}")


if __name__ == "__main__":
    import sys

    main(Path(sys.argv[1]))
