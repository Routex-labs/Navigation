"""GCP 기반 건물 local_m → WGS84 아핀 재피팅.

지금 studio JSON들의 `local_m_to_wgs84`는 `status: "unverified"`고, 절대 배율이
실측 대비 ~1.33× 부풀려져 있다(1F LEVEL이 데이터상 167×98m인데 VWorld 실측은 126×68m).
이 스크립트는 사람이 뽑아 온 GCP(gcp_picker.html)를 이용해 그 아핀을 다시 피팅한다.

동작
  1. 대상 건물의 기준층(1f.json)에서 현재 아핀 + `building_footprint_local_m` 로드.
  2. footprint의 min/max 극점 4개를 "실측 건물 꼭지점 후보"로 뽑는다
     (더현대처럼 대체로 직사각형 건물 전제; 다른 모양이면 자동 매칭이 이상해질 수 있다).
  3. GCP와 극점을 각도로 정렬해 매칭 (아래 "왜 각도 매칭인가" 참고).
     `--map` 로 override 가능.
  4. `fit_wgs84_transform`으로 재피팅 → 잔차(각 GCP·중앙값·최대) + rotate_deg +
     축별 스케일(m per local_m) 리포트. 잔차가 커지는 짝이 있으면 매칭 오류 신호.
  5. `--write` 시 studio 폴더의 모든 층 JSON의 `local_m_to_wgs84`를 덮어쓴다
     (12개 층이 같은 아핀을 공유하므로 전부 갱신). 기본은 dry-run.

왜 각도 매칭인가
  현재(unverified) 아핀은 배율·이동 오차가 30~50m급이라 "GCP → 가장 가까운
  footprint vertex" 방식으로 매칭하면 인접 꼭지점이 뒤바뀔 수 있다(계산 확인).
  GCP 중심에서 각 GCP가 바라보는 각도와, footprint 중심에서 각 극점이 바라보는
  각도를 각각 정렬해 순서대로 짝지으면 회전·이동 오차에 무관하게 안정적으로 맞는다.

사용 예 (dry-run)
  cd backend
  python -m scripts.transform.refit_building_wgs84 \\
      --studio resources/studio/thehyundai-seoul-dabeeo \\
      --gcps resources/calibration/thehyundai-seoul-gcps.json

자동 매칭이 이상하면 명시적 매핑으로 override
  python -m scripts.transform.refit_building_wgs84 ... --map "N=1,W=2,S=3,E=4"
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

from app.geo.georeference import GeoTransform, PointPair, fit_wgs84_transform


# 콘솔이 cp949(기본 Windows)면 한글이나 특수문자에서 UnicodeEncodeError가 난다.
# UTF-8이 아니면 reconfigure로 UTF-8로 바꾼다(가능한 파이썬 3.7+).
def _force_utf8_stdout() -> None:
    for stream in (sys.stdout, sys.stderr):
        enc = (getattr(stream, "encoding", "") or "").lower()
        if enc != "utf-8":
            try:
                stream.reconfigure(encoding="utf-8")
            except (AttributeError, Exception):
                pass


_force_utf8_stdout()


REFERENCE_FLOOR = "1f.json"
# 다베오는 모든 층이 같은 아핀을 공유하므로 층 파일들만 골라 전부 갱신한다
# (stores_*.json 같은 부산물은 아핀을 안 담고 있으므로 제외).
FLOOR_FILE_GLOB = "[0-9bB]*.json"

# 도 단위 좌표를 사람이 이해할 수 있는 미터 오차로 환산할 때 쓰는 근사 상수.
# haversine에 넣을 지구 반경(WGS84 GRS80 장반경).
EARTH_RADIUS_M = 6_378_137.0
# 위도 1도의 실측 거리(경도는 위도에 따라 다르므로 별도 처리).
METERS_PER_DEGREE_LAT = 111_320.0


@dataclass
class Corner:
    """footprint 극점 후보 — 사용자가 클릭했을 것으로 가정하는 4개 지점."""

    name: str  # min_xy / max_x_min_y / max_xy / min_x_max_y
    x: float
    y: float


@dataclass
class Match:
    label: str
    gcp_lat: float
    gcp_lng: float
    corner: Corner
    dist_before_m: float  # 현재 아핀 기준 예측 vs 실측 거리
    residual_after_m: float = 0.0  # 재피팅 후 잔차


def load_studio_reference(studio_dir: Path) -> dict:
    ref = studio_dir / REFERENCE_FLOOR
    if not ref.exists():
        raise SystemExit(f"기준층 {ref} 을(를) 찾을 수 없습니다.")
    return json.loads(ref.read_text(encoding="utf-8"))


def load_gcps(gcps_path: Path) -> list[dict]:
    payload = json.loads(gcps_path.read_text(encoding="utf-8"))
    all_gcps = payload.get("gcps", [])
    complete = [g for g in all_gcps if g.get("outdoor") and g["outdoor"].get("lat") is not None]
    if len(complete) < len(all_gcps):
        skipped = len(all_gcps) - len(complete)
        print(f"[알림] outdoor 좌표가 없는 GCP {skipped}개는 건너뜁니다.")
    return complete


# 현재 studio 아핀은 (x,y) -> (lng, lat)를 도 단위 그대로 계산한다.
# GeoTransform.apply는 lng_scale로 나눠 등방 보정을 원래대로 되돌리지만, 여기서는
# 저장된 매트릭스가 이미 도 단위로 lng를 뱉으므로 lng_scale=1.0으로 취급한다.
def current_transform_from_studio(reference: dict) -> GeoTransform:
    matrix = reference["coordinate_system"]["affine_transforms"]["local_m_to_wgs84"]["matrix"]
    a, b, tx = matrix[0]
    c, d, ty = matrix[1]
    return GeoTransform(a=a, b=b, c=c, d=d, tx=tx, ty=ty, lng_scale=1.0)


def project_current(t: GeoTransform, x: float, y: float) -> tuple[float, float]:
    """현재(도 단위) 아핀으로 (x,y) → (lat, lng)."""
    lng = t.a * x + t.b * y + t.tx
    lat = t.c * x + t.d * y + t.ty
    return lat, lng


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


# footprint에서 실제 vertex 4개를 뽑는다. 각 bounding-box 꼭지점에 가장 가까운
# 진짜 vertex를 골라, 대체로 직사각형인 건물의 4 모서리와 대응시킨다.
def extreme_corners(footprint: list[dict]) -> list[Corner]:
    xs = [v["x"] for v in footprint]
    ys = [v["y"] for v in footprint]
    targets = [
        ("min_xy", min(xs), min(ys)),
        ("max_x_min_y", max(xs), min(ys)),
        ("max_xy", max(xs), max(ys)),
        ("min_x_max_y", min(xs), max(ys)),
    ]
    corners = []
    for name, tx, ty in targets:
        v = min(footprint, key=lambda p: (p["x"] - tx) ** 2 + (p["y"] - ty) ** 2)
        corners.append(Corner(name=name, x=v["x"], y=v["y"]))
    return corners


# GCP·극점을 각도(중심에서 바라본)로 정렬해 순환 순서 4가지 중 가장 물리적으로
# 합당한 매칭을 고른다.
#
# 왜 각도 정렬만으로는 부족한가:
#   현재 unverified 아핀의 회전각을 신뢰해 corner를 세계 방위로 돌린 뒤 짝짓는데,
#   그 회전각 자체가 90° 정도 틀려있으면 매칭이 축 하나만큼 밀린 잘못된 순열로
#   들어간다. 그러면 fit은 여전히 수학적으로 수렴하지만 스케일이 심하게 이방적
#   (예: x=0.6 vs y=1.7)이 되어, 실제 건물이 정사각형에 가까운데도 축별로
#   물리 단위가 다른 것처럼 취급된다 — 이 상태로 재시드하면 실내 지도 카메라
#   정렬·매장 폴리곤이 눈에 띄게 어긋난다.
#
# 어떻게 바로잡는가:
#   각도 정렬로 얻은 base 매칭에 대해 순환 shift 0/1/2/3(= 0/90/180/270°)를
#   모두 시도하고, 각각 아핀을 fit해 스케일 이방성이 가장 낮은 순열을 채택한다.
#   물리적으로 국소 좌표계는 대체로 등방(같은 m/local_m)이므로 균일 스케일 fit
#   이 "옳은" 매칭이라는 근거가 된다.
def _angular_distance(a: float, b: float) -> float:
    d = abs(a - b) % (2 * math.pi)
    return min(d, 2 * math.pi - d)


def _fit_pairs(gcps, corners, perm) -> tuple[GeoTransform, list[float]]:
    """corner 순열 하나에 대해 fit + 각 GCP 잔차."""
    from app.geo.georeference import fit_wgs84_transform, PointPair
    pairs = [
        PointPair(x=corners[perm[i]].x, y=corners[perm[i]].y,
                  u=gcps[i]["outdoor"]["lng"], v=gcps[i]["outdoor"]["lat"])
        for i in range(len(gcps))
    ]
    t = fit_wgs84_transform(pairs)
    residuals = []
    for i in range(len(gcps)):
        pred_lat, pred_lng = t.apply(corners[perm[i]].x, corners[perm[i]].y)
        residuals.append(haversine_m(
            gcps[i]["outdoor"]["lat"], gcps[i]["outdoor"]["lng"],
            pred_lat, pred_lng,
        ))
    return t, residuals


def _scale_anisotropy(t: GeoTransform) -> float:
    """축별 스케일 비율(1.0이 완전 균일, 값이 클수록 이방적)."""
    sx = math.hypot(t.a, t.c) * METERS_PER_DEGREE_LAT
    sy = math.hypot(t.b, t.d) * METERS_PER_DEGREE_LAT
    return max(sx, sy) / max(1e-9, min(sx, sy))


def angle_nearest_match(gcps: list[dict], corners: list[Corner], current: GeoTransform) -> list[Match]:
    lats = [g["outdoor"]["lat"] for g in gcps]
    lngs = [g["outdoor"]["lng"] for g in gcps]
    lat0 = sum(lats) / len(lats)
    lng0 = sum(lngs) / len(lngs)
    cos_lat = math.cos(math.radians(lat0))

    gcp_angles = []
    for g in gcps:
        dy = (g["outdoor"]["lat"] - lat0) * METERS_PER_DEGREE_LAT
        dx = (g["outdoor"]["lng"] - lng0) * METERS_PER_DEGREE_LAT * cos_lat
        gcp_angles.append(math.atan2(dy, dx))

    x0 = sum(c.x for c in corners) / len(corners)
    y0 = sum(c.y for c in corners) / len(corners)
    corner_angles = []
    for c in corners:
        dx = c.x - x0
        dy = c.y - y0
        # 현재 아핀의 회전만 적용(평행이동·전체 스케일은 각도에 영향 없음).
        proj_lng = current.a * dx + current.b * dy
        proj_lat = current.c * dx + current.d * dy
        # 도 좌표를 등방으로 눌러 각도가 실제 방위와 일치하게 한다.
        corner_angles.append(math.atan2(proj_lat, proj_lng * cos_lat))

    n = len(gcps)
    if n != len(corners):
        raise SystemExit(
            f"GCP {n}개 vs footprint 극점 {len(corners)}개. 지금은 4점 GCP → 4극점만 지원."
        )

    # base: 각도만으로 최적 순열
    base_perm = None
    best_total = float("inf")
    for perm in itertools.permutations(range(n)):
        total = sum(_angular_distance(gcp_angles[i], corner_angles[perm[i]]) for i in range(n))
        if total < best_total:
            best_total = total
            base_perm = perm
    assert base_perm is not None

    # corner 목록은 CCW 순환(bbox 극점을 min_xy→max_x_min_y→max_xy→min_x_max_y로
    # 뽑았음)이라, base_perm에 shift 1/2/3을 얹으면 90/180/270° 돈 매칭이 된다.
    # 네 후보 중 스케일 이방성이 가장 낮은 것을 택한다 — 실제 로컬 좌표계는 등방
    # (dabeeo scale 0.1 m/unit for both axes)이라는 사전 정보를 활용한다.
    print("\n== 순환 shift 후보별 fit 비교 ==")
    print(f"{'shift':<6} {'x-scale':>10} {'y-scale':>10} {'anisotropy':>12} {'max_resid(m)':>14}")
    candidates = []
    for shift in range(n):
        perm = tuple(base_perm[(i + shift) % n] for i in range(n))
        t, residuals = _fit_pairs(gcps, corners, perm)
        aniso = _scale_anisotropy(t)
        sx = math.hypot(t.a, t.c) * METERS_PER_DEGREE_LAT
        sy = math.hypot(t.b, t.d) * METERS_PER_DEGREE_LAT
        candidates.append((aniso, shift, perm, t, residuals))
        marker = " <-" if shift == 0 else ""
        print(f"{shift:<6} {sx:>10.4f} {sy:>10.4f} {aniso:>12.3f} {max(residuals):>14.3f}{marker}")

    # 정렬 우선순위: (1) 이방성 낮음(0.001 단위로 반올림) (2) 잔차 낮음.
    # 대칭 회전(0°/180° 또는 90°/270°)은 스케일이 같이 나오는데, 그중 잔차가
    # 더 작은 쪽이 실제 매칭 방향과 일치한다 — 사각형이 완벽 대칭이 아니라
    # GCP 오차가 한 쪽에서 더 잘 상쇄되기 때문. 반올림 없이 float으로 비교하면
    # 부동소수 미세 차이 때문에 tiebreaker가 작동하지 않아 잘못된 방향을 고른다.
    candidates.sort(key=lambda x: (round(x[0], 3), max(x[4])))
    best = candidates[0]
    _, chosen_shift, chosen_perm, _, _ = best
    if chosen_shift != 0:
        print(f"** base 각도 매칭이 축 {chosen_shift}칸 shift됨 — 스케일 이방성·잔차 최소값을 채택.")
        print(f"   (원인: 현재 unverified 아핀의 회전각이 실제와 90°*{chosen_shift} 어긋나 있음)")

    matches = []
    for i, corner_idx in enumerate(chosen_perm):
        g = gcps[i]
        c = corners[corner_idx]
        lat, lng = g["outdoor"]["lat"], g["outdoor"]["lng"]
        pred_lat, pred_lng = project_current(current, c.x, c.y)
        matches.append(Match(
            label=g["label"], gcp_lat=lat, gcp_lng=lng, corner=c,
            dist_before_m=haversine_m(lat, lng, pred_lat, pred_lng),
        ))
    return matches


# --map "N=1,W=2,S=3,E=4" 형식을 파싱해 명시적 매칭을 만든다. 방위 → 극점 이름 표.
_COMPASS_TO_CORNER = {
    "N": "max_x_min_y",
    "S": "min_x_max_y",
    "E": "max_xy",
    "W": "min_xy",
}


def explicit_match(gcps: list[dict], corners: list[Corner], mapping: str, current: GeoTransform) -> list[Match]:
    corner_by_name = {c.name: c for c in corners}
    gcp_by_label = {g["label"]: g for g in gcps}
    matches = []
    for part in mapping.split(","):
        compass, label = part.strip().split("=")
        compass = compass.strip().upper()
        label = label.strip()
        if compass not in _COMPASS_TO_CORNER:
            raise SystemExit(f"--map 방위 '{compass}' 를 모릅니다. N/S/E/W 중 하나.")
        if label not in gcp_by_label:
            raise SystemExit(f"--map 라벨 '{label}' 이 gcps에 없습니다.")
        c = corner_by_name[_COMPASS_TO_CORNER[compass]]
        g = gcp_by_label[label]
        lat, lng = g["outdoor"]["lat"], g["outdoor"]["lng"]
        pred_lat, pred_lng = project_current(current, c.x, c.y)
        matches.append(Match(
            label=f"{label}({compass})", gcp_lat=lat, gcp_lng=lng, corner=c,
            dist_before_m=haversine_m(lat, lng, pred_lat, pred_lng),
        ))
    return matches


def fit_and_compute_residuals(matches: list[Match]) -> GeoTransform:
    pairs = [PointPair(x=m.corner.x, y=m.corner.y, u=m.gcp_lng, v=m.gcp_lat) for m in matches]
    new_t = fit_wgs84_transform(pairs)
    for m in matches:
        pred_lat, pred_lng = new_t.apply(m.corner.x, m.corner.y)
        m.residual_after_m = haversine_m(m.gcp_lat, m.gcp_lng, pred_lat, pred_lng)
    return new_t


# fit_wgs84_transform이 돌려주는 아핀은 등방 공간에서 피팅됐다:
#   u_iso = a*x + b*y + tx, v = c*x + d*y + ty (u_iso = lng * lng_scale, v = lat)
# 즉 (a, c)는 local_m x축 1 이동 시 등방 (lng*cos_lat, lat) 변화량(도 단위).
# 미터 스케일: hypot(a, c) * m_per_deg = 실측 미터 / local_m.
# 회전각(정동에서 CCW): atan2(c, a). 다베오 원본의 rotate_deg와 같은 축 기준.
def rotate_and_scale(t: GeoTransform) -> tuple[float, float, float]:
    x_scale = math.hypot(t.a, t.c) * METERS_PER_DEGREE_LAT
    y_scale = math.hypot(t.b, t.d) * METERS_PER_DEGREE_LAT
    rotate_deg = math.degrees(math.atan2(t.c, t.a))
    return rotate_deg, x_scale, y_scale


# studio JSON의 matrix는 도 단위 (lng, lat)를 직접 뱉는 형태.
# fit_wgs84_transform 결과는 등방 공간이라 lng 관련 계수를 lng_scale로 나눠 되돌린다.
def studio_matrix_from(new_t: GeoTransform) -> list[list[float]]:
    s = new_t.lng_scale
    return [
        [new_t.a / s, new_t.b / s, new_t.tx / s],
        [new_t.c,     new_t.d,     new_t.ty     ],
        [0.0, 0.0, 1.0],
    ]


def write_studio_transforms(
    studio_dir: Path,
    new_t: GeoTransform,
    residuals_m: list[float],
    gcps_path: Path,
) -> list[Path]:
    matrix = studio_matrix_from(new_t)
    rotate_deg, _, _ = rotate_and_scale(new_t)
    residual_summary = {
        "n_gcps": len(residuals_m),
        "median_m": round(sorted(residuals_m)[len(residuals_m) // 2], 3),
        "max_m": round(max(residuals_m), 3),
    }
    written = []
    for path in sorted(studio_dir.glob(FLOOR_FILE_GLOB)):
        if path.name.startswith("stores_"):
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        entry = data["coordinate_system"]["affine_transforms"]["local_m_to_wgs84"]
        entry["matrix"] = matrix
        entry["rotate_deg"] = rotate_deg
        entry["anchor"] = "gcp_refit"
        entry["status"] = "verified_by_gcp"
        entry["refit"] = {
            "source": str(gcps_path.relative_to(gcps_path.parents[2])).replace("\\", "/"),
            "residuals_m": residual_summary,
        }
        # 예전 georeferencing bbox는 옛 아핀으로 뽑은 값이라 이제 신뢰할 수 없다 —
        # 명시적으로 stale 상태로 마킹해 뒤에서 오해하지 않도록 한다.
        if "georeferencing" in data["coordinate_system"]:
            data["coordinate_system"]["georeferencing"]["status"] = "stale_needs_recompute"
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        written.append(path)
    return written


# 새 아핀으로 변환된 폴리곤 + GCP 원본 클릭점 + 매칭된 극점 + 잔차 연결선을 함께
# GeoJSON으로 저장. 어긋남이 있으면 "GCP 클릭이 어디로 갔는가"를 눈으로 짚을 수 있다.
def _write_geojson_preview(
    out_path: Path,
    reference: dict,
    new_t: GeoTransform,
    matches: list["Match"],
) -> None:
    footprint = reference["building_footprint_local_m"]
    ring = []
    for v in footprint:
        lat, lng = new_t.apply(v["x"], v["y"])
        ring.append([lng, lat])
    if ring[0] != ring[-1]:
        ring.append(ring[0])

    features: list[dict] = [
        {
            "type": "Feature",
            "geometry": {"type": "Polygon", "coordinates": [ring]},
            "properties": {
                "name": f"{reference.get('building_id', 'building')}_footprint_refit",
                "stroke": "#3b82f6", "stroke-width": 2, "fill": "#3b82f6", "fill-opacity": 0.20,
            },
        }
    ]
    # GCP 원본 클릭점 (빨간 점) + 매칭된 극점의 새 아핀 예측 위치 (초록 점) +
    # 두 점을 잇는 얇은 선 (잔차 벡터, 이상적으로 겹쳐서 안 보임).
    for m in matches:
        pred_lat, pred_lng = new_t.apply(m.corner.x, m.corner.y)
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [m.gcp_lng, m.gcp_lat]},
            "properties": {
                "name": f"GCP {m.label}", "marker-color": "#ef4444", "marker-size": "small",
            },
        })
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [pred_lng, pred_lat]},
            "properties": {
                "name": f"{m.corner.name}", "marker-color": "#22c55e", "marker-size": "small",
            },
        })
        features.append({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": [[m.gcp_lng, m.gcp_lat], [pred_lng, pred_lat]]},
            "properties": {
                "name": f"residual {m.label} ({m.residual_after_m:.2f}m)",
                "stroke": "#f97316", "stroke-width": 2,
            },
        })
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def print_matches(matches: list[Match]) -> None:
    print(f"{'label':<10} {'corner':<14} {'gcp_lat':>13} {'gcp_lng':>13} {'local_x':>10} {'local_y':>10} {'before(m)':>10}")
    for m in matches:
        print(
            f"{m.label:<10} {m.corner.name:<14} "
            f"{m.gcp_lat:>13.7f} {m.gcp_lng:>13.7f} "
            f"{m.corner.x:>10.3f} {m.corner.y:>10.3f} "
            f"{m.dist_before_m:>10.2f}"
        )


def print_residuals(matches: list[Match]) -> tuple[float, float]:
    print(f"\n{'label':<10} {'residual(m)':>12}")
    for m in matches:
        print(f"{m.label:<10} {m.residual_after_m:>12.3f}")
    residuals = [m.residual_after_m for m in matches]
    median = sorted(residuals)[len(residuals) // 2]
    return median, max(residuals)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--studio", type=Path, required=True,
                        help="studio 폴더 경로 (예: resources/studio/thehyundai-seoul-dabeeo)")
    parser.add_argument("--gcps", type=Path, required=True,
                        help="gcp_picker.html에서 export한 JSON 경로")
    parser.add_argument("--map", dest="mapping", default=None,
                        help='명시적 매칭 (예: "N=1,W=2,S=3,E=4"). 미지정 시 각도 정렬 자동 매칭.')
    parser.add_argument("--write", action="store_true",
                        help="studio JSON들의 local_m_to_wgs84를 덮어쓴다 (기본: dry-run)")
    parser.add_argument("--geojson-out", type=Path, default=None,
                        help="새 아핀으로 변환한 건물 footprint 폴리곤을 GeoJSON으로 저장. "
                             "geojson.io에 VWorld 배경으로 얹어 시각 검증.")
    args = parser.parse_args()

    reference = load_studio_reference(args.studio)
    footprint = reference.get("building_footprint_local_m")
    if not footprint:
        raise SystemExit("기준층에 building_footprint_local_m이 없습니다.")

    gcps = load_gcps(args.gcps)
    if len(gcps) < 3:
        raise SystemExit(f"GCP가 {len(gcps)}개뿐입니다. affine 피팅에 최소 3개 필요.")

    print(f"studio: {args.studio}")
    print(f"gcps:   {args.gcps} ({len(gcps)}개)")
    print(f"footprint vertex: {len(footprint)}개")

    current = current_transform_from_studio(reference)
    corners = extreme_corners(footprint)

    print("\n== footprint 극점 4개 (bounding-box 극점에 최근접 vertex) ==")
    for c in corners:
        lat, lng = project_current(current, c.x, c.y)
        print(f"  {c.name:<14} local=({c.x:>8.3f}, {c.y:>8.3f}) → 현재 아핀 예측 ({lat:.7f}, {lng:.7f})")

    if args.mapping:
        print(f"\n== 명시적 매칭 (--map \"{args.mapping}\") ==")
        matches = explicit_match(gcps, corners, args.mapping, current)
    else:
        print("\n== 각도 최근접 자동 매칭 ==")
        matches = angle_nearest_match(gcps, corners, current)
    print_matches(matches)

    if len({m.corner.name for m in matches}) != len(matches):
        print("\n[경고] 같은 극점에 여러 GCP가 매칭됐습니다. --map 으로 명시하는 게 안전합니다.")

    new_t = fit_and_compute_residuals(matches)
    median, mx = print_residuals(matches)
    print(f"\n잔차: median={median:.3f} m, max={mx:.3f} m")

    rot, sx, sy = rotate_and_scale(new_t)
    old_rot = reference["coordinate_system"]["affine_transforms"]["local_m_to_wgs84"].get("rotate_deg")
    print(f"\n== 새 아핀 요약 ==")
    print(f"회전각: {rot:.3f} deg (기존: {old_rot})")
    print(f"축별 스케일 (실측 m per local_m 단위): x={sx:.4f}, y={sy:.4f}")
    if abs(sx - sy) / max(sx, sy) > 0.1:
        print(f"  * x, y 스케일 차이가 큼 -> local_m 좌표계가 이방적(anisotropic). 6-DOF affine 필요.")
    if args.geojson_out:
        _write_geojson_preview(args.geojson_out, reference, new_t, matches)
        print(f"\nGeoJSON 시각검증 파일: {args.geojson_out}")
        print(f"  geojson.io 또는 QGIS에 열어 VWorld 배경 위에 얹어 실제 건물과 정합 확인.")
        print(f"  빨간 점=GCP 클릭점, 초록 점=매칭된 극점 예측 위치, 주황 선=잔차 벡터.")

    if args.write:
        print("\n== studio JSON 덮어쓰기 ==")
        residuals = [m.residual_after_m for m in matches]
        written = write_studio_transforms(args.studio, new_t, residuals, args.gcps)
        for p in written:
            print(f"  wrote {p.name}")
        print(f"\n총 {len(written)}개 파일 갱신. `python -m scripts.seed.reset_and_seed`로 DB에 반영하세요.")
    else:
        print("\n[dry-run] --write 를 붙이면 studio JSON들을 덮어씁니다.")


if __name__ == "__main__":
    main()
