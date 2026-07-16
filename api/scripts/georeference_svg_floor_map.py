"""사람이 정리한 SVG 도면을 실좌표(WGS84)에 앵커링해서 DB를 보강하는 ETL.

배경: load_dataset.py가 적재하는 매장 폴리곤은 navigation_1f.json의 CV
자동 추출 결과(confidence 0.52 수준)라 모양이 정돈돼 있지 않고, 매장
centroid만 실측 wgs84로 스냅 보정하다 보니 "보정된 매장"과 "보정 안 된
외곽선/POI"가 서로 다른 정확도로 그려져 어긋나 보인다(매장 61개 중 16개가
건물 외곽선 밖으로 나가는 문제로 실제 확인됨).

해결: hyundai_floor_map_corrected_v6.svg(사람이 손으로 정리한 도면)의 매장
폴리곤/외곽선을 실좌표에 앵커링한다. SVG와 navigation_1f.json 양쪽에 같은
이름으로 존재하는 매장(대응점)을 다리 삼아 두 단계 affine 변환을
피팅한다:

    T1 = local_m -> SVG px   (매장 centroid 쌍으로 피팅)
    T2 = SVG px -> WGS84     (매장 centroid 쌍으로 피팅)

(참고: 처음엔 4-DOF similarity로 피팅했는데 건물 면적이 절반 이하로
쪼그라드는 오류가 있었다. 확인해보니 navigation_1f.json의 wgs84 값은 축별로
스케일이 다른 6-DOF affine 관계였다 — 6-DOF affine으로 다시 피팅하니 오차가
중앙값 27m에서 0.29m로 줄었다.)

두 변환 다 affine이라 합성(T_final = T2 ∘ T1)하면 다시 하나의 affine
변환이 된다. 이 T_final로 건물의 geo_a/b/c/d/tx/ty(local_m -> wgs84
직행 변환)를 덮어쓰면, POI처럼 SVG에 대응 도형이 없는 local_m 데이터도
런타임 계산 없이 더 일관된 위치를 받는다. 건물 외곽선/매장 폴리곤은 SVG
도형에 T2를 바로 적용해서 만든다(그래서 SVG만큼 깔끔한 모양이 나온다).

실행 방법 (api/ 디렉토리에서):
    python scripts/georeference_svg_floor_map.py \\
        "C:/Users/user/OneDrive/Documents/카카오톡 받은 파일/hyundai_floor_map_corrected_v6.svg" \\
        --building-id thehyundai-seoul --floor-id FL-soem999bnha10599
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.domain.georeference import (  # noqa: E402
    GeoTransform,
    PointPair,
    compose_transforms,
    fit_affine_transform,
    fit_wgs84_transform,
)
from convert_svg_floor_map import convert_svg_floor_map  # noqa: E402

DEFAULT_JSON = API_ROOT / "app" / "data" / "navigation_1f.json"
DEFAULT_DB = API_ROOT / "data" / "navigation.db"

# 이름 비교용 정규화: 공백 차이("바이 레도" vs "바이레도")만 흡수한다.
# 철자 자체가 다른 경우("톰포드 뷰티" vs "톰 포드 뷰티"는 공백만 다름이라 흡수됨,
# "레페토"처럼 아예 없는 경우는 정규화해도 매칭되지 않는다 — 의도된 동작).
_WHITESPACE = re.compile(r"\s+")


def _normalize_name(name: str) -> str:
    return _WHITESPACE.sub("", name).strip()


def _real_store_lookup(json_path: Path) -> dict[str, dict]:
    """navigation_1f.json 매장을 정규화한 이름 -> {local_m centroid, wgs84 centroid} 매핑."""
    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)

    lookup: dict[str, dict] = {}
    for store in data["stores"]:
        wgs84 = store["centroid"].get("wgs84")
        if not wgs84 or wgs84.get("lat") is None or wgs84.get("lng") is None:
            continue
        key = _normalize_name(store["name"])
        lookup[key] = {
            "id": store["id"],
            "name": store["name"],
            "local_m": store["centroid"]["local_m"],
            "wgs84": wgs84,
        }
    return lookup


def _match_svg_stores(
    svg_features: list[dict],
    real_lookup: dict[str, dict],
) -> list[dict]:
    """SVG 매장 feature마다 이름이 일치하는 실데이터 매장을 찾아 대응점을 만든다."""
    matches = []
    for feature in svg_features:
        if feature["kind"] != "store" or not feature.get("name"):
            continue
        key = _normalize_name(feature["name"])
        real = real_lookup.get(key)
        if real is None:
            continue
        matches.append({"svg_feature": feature, "real": real})
    return matches


def build_georeference(
    svg_path: Path,
    json_path: Path,
    *,
    building_id: str,
    floor_id: str,
) -> dict:
    """SVG px -> WGS84(T2), local_m -> WGS84(T_final), 매칭된 매장/외곽선을 계산한다."""
    svg_data = convert_svg_floor_map(svg_path, building_id=building_id, floor_id=floor_id)
    real_lookup = _real_store_lookup(json_path)
    matches = _match_svg_stores(svg_data["features"], real_lookup)

    if len(matches) < 3:
        raise ValueError(
            f"SVG와 실데이터 사이 이름이 일치하는 매장이 {len(matches)}개뿐입니다"
            " (affine 변환 피팅에 3개 이상 필요)."
        )

    local_to_svg_pairs = [
        PointPair(
            x=match["real"]["local_m"]["x"],
            y=match["real"]["local_m"]["y"],
            u=match["svg_feature"]["centroid"]["x"],
            v=match["svg_feature"]["centroid"]["y"],
        )
        for match in matches
    ]
    svg_to_wgs84_pairs = [
        PointPair(
            x=match["svg_feature"]["centroid"]["x"],
            y=match["svg_feature"]["centroid"]["y"],
            u=match["real"]["wgs84"]["lng"],
            v=match["real"]["wgs84"]["lat"],
        )
        for match in matches
    ]

    # T1은 두 축 다 등방(px) 공간이라 fit_affine_transform을 그대로 쓴다.
    # T2는 출력이 (lng, lat)이라 위도/경도 스케일 차이를 보정하는
    # fit_wgs84_transform을 써야 한다 — 아니면 건물이 실제보다 훨씬 작게(또는
    # 크게) 피팅된다(실측: 이 보정 없이 피팅했을 때 건물 면적이 절반 이하로
    # 쪼그라드는 오류가 있었다).
    t1_local_to_svg = fit_affine_transform(local_to_svg_pairs)
    t2_svg_to_wgs84 = fit_wgs84_transform(svg_to_wgs84_pairs)
    t_final_local_to_wgs84 = compose_transforms(inner=t1_local_to_svg, outer=t2_svg_to_wgs84)

    footprint_feature = next(f for f in svg_data["features"] if f["kind"] == "footprint")
    footprint_wgs84 = _polygon_to_wgs84(footprint_feature["geometry"]["coordinates"], t2_svg_to_wgs84)

    store_polygons_wgs84: dict[str, list[dict]] = {}
    for match in matches:
        svg_feature = match["svg_feature"]
        real_id = match["real"]["id"]
        ring = _polygon_to_wgs84(svg_feature["geometry"]["coordinates"], t2_svg_to_wgs84)
        ring = _snap_ring(ring, svg_feature["centroid"], t2_svg_to_wgs84, match["real"]["wgs84"])
        store_polygons_wgs84[real_id] = ring

    return {
        "geo_transform": t_final_local_to_wgs84,
        "footprint_wgs84": footprint_wgs84,
        "store_polygons_wgs84": store_polygons_wgs84,
        "matched_count": len(matches),
        "svg_store_count": sum(1 for f in svg_data["features"] if f["kind"] == "store"),
        "real_store_count": len(real_lookup),
    }


def _polygon_to_wgs84(points: list[dict], transform: GeoTransform) -> list[dict]:
    result = []
    for point in points:
        # apply()(apply_uv 아님)를 써야 lng_scale 보정이 적용돼 진짜 경도가 나온다.
        lat, lng = transform.apply(point["x"], point["y"])
        result.append({"lat": lat, "lng": lng})
    return result


def _snap_ring(
    ring: list[dict],
    svg_centroid: dict,
    transform: GeoTransform,
    known_wgs84: dict,
) -> list[dict]:
    """매장 폴리곤 전체를, 예측한 centroid와 실측 centroid의 차이만큼 평행이동한다.

    매장 폭은 수 미터 수준이라 이 안에서 T2의 잔여 오차(회전/스케일)는
    무시할 만큼 작고, 평행이동만으로도 centroid 오차를 사실상 0으로 없앨 수 있다.
    """
    predicted_lat, predicted_lng = transform.apply(svg_centroid["x"], svg_centroid["y"])
    offset_lat = known_wgs84["lat"] - predicted_lat
    offset_lng = known_wgs84["lng"] - predicted_lng
    return [
        {"lat": point["lat"] + offset_lat, "lng": point["lng"] + offset_lng} for point in ring
    ]


def apply_to_db(
    result: dict,
    *,
    db_path: Path,
    building_id: str,
) -> dict[str, int]:
    """계산한 geo_transform/외곽선/매장 폴리곤을 DB에 반영한다."""
    conn = sqlite3.connect(db_path)
    try:
        transform: GeoTransform = result["geo_transform"]
        conn.execute(
            "UPDATE buildings SET geo_a = ?, geo_b = ?, geo_c = ?, geo_d = ?,"
            " geo_tx = ?, geo_ty = ?, geo_lng_scale = ?, footprint_wgs84_svg = ? WHERE id = ?",
            (
                transform.a,
                transform.b,
                transform.c,
                transform.d,
                transform.tx,
                transform.ty,
                transform.lng_scale,
                json.dumps(result["footprint_wgs84"], ensure_ascii=False),
                building_id,
            ),
        )
        updated_stores = 0
        for store_id, ring in result["store_polygons_wgs84"].items():
            cursor = conn.execute(
                "UPDATE stores SET svg_polygon_wgs84 = ? WHERE id = ?",
                (json.dumps(ring, ensure_ascii=False), store_id),
            )
            updated_stores += cursor.rowcount
        conn.commit()
        return {"stores_updated": updated_stores}
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("svg", type=Path)
    parser.add_argument("--building-id", required=True)
    parser.add_argument("--floor-id", required=True)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()

    result = build_georeference(
        args.svg, args.json, building_id=args.building_id, floor_id=args.floor_id
    )
    print(
        f"매장 매칭: {result['matched_count']}/{result['real_store_count']}"
        f"(실데이터) , SVG 매장 {result['svg_store_count']}개 중 매칭"
    )
    db_result = apply_to_db(result, db_path=args.db, building_id=args.building_id)
    print(f"DB 반영 완료: {args.db}")
    print(f" stores.svg_polygon_wgs84 갱신: {db_result['stores_updated']}건")
    print(f" buildings.geo_a/b/c/d/tx/ty, footprint_wgs84_svg 갱신: {args.building_id}")


if __name__ == "__main__":
    main()
