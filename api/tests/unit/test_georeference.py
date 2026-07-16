"""2D affine 변환 피팅/적용/합성 단위 테스트."""

import math

import pytest

from app.domain.georeference import (
    GeoTransform,
    PointPair,
    compose_transforms,
    fit_affine_transform,
    fit_wgs84_transform,
)


def _polygon_area_m2(points: list[tuple[float, float]]) -> float:
    """(lat, lng) 폴리곤의 실제 넓이(m^2)를 신발끈 공식으로 근사한다."""
    mean_lat = sum(lat for lat, _ in points) / len(points)
    m_per_deg_lat = 111_320.0
    m_per_deg_lng = 111_320.0 * math.cos(math.radians(mean_lat))
    xy = [(lng * m_per_deg_lng, lat * m_per_deg_lat) for lat, lng in points]
    area = 0.0
    for (x1, y1), (x2, y2) in zip(xy, xy[1:] + xy[:1]):
        area += x1 * y2 - x2 * y1
    return abs(area) / 2


# 알려진 affine 변환(축별로 다른 스케일 + 기울임 + 평행이동)으로 점을 만들어
# 역으로 피팅했을 때 원래 파라미터를 복원하는지 검증한다. 4-DOF similarity로는
# 표현할 수 없는 "축별로 다른 스케일"까지 포함해서, 6-DOF가 실제로 필요한
# 관계도 정확히 잡아내는지 확인한다.
def test_알려진_affine_변환을_정확히_복원한다():
    true_transform = GeoTransform(a=0.9, b=0.15, c=-0.05, d=1.3, tx=126.9283, ty=37.5265)

    local_points = [(0.0, 0.0), (30.0, 0.0), (0.0, 40.0), (15.0, 25.0), (50.0, 10.0)]
    pairs = [
        PointPair(x=x, y=y, u=u, v=v)
        for x, y in local_points
        for u, v in [true_transform.apply_uv(x, y)]
    ]

    fitted = fit_affine_transform(pairs)

    assert fitted.a == pytest.approx(true_transform.a, abs=1e-9)
    assert fitted.b == pytest.approx(true_transform.b, abs=1e-9)
    assert fitted.c == pytest.approx(true_transform.c, abs=1e-9)
    assert fitted.d == pytest.approx(true_transform.d, abs=1e-9)
    assert fitted.tx == pytest.approx(true_transform.tx, abs=1e-9)
    assert fitted.ty == pytest.approx(true_transform.ty, abs=1e-9)


# apply()가 lat/lng 순서를 뒤집지 않고 그대로 돌려주는지 확인한다.
def test_apply는_lat_lng_순서를_지킨다():
    transform = GeoTransform(a=1.0, b=0.0, c=0.0, d=1.0, tx=126.0, ty=37.0)

    lat, lng = transform.apply(x_m=1.0, y_m=1.0)

    assert lat == pytest.approx(38.0)
    assert lng == pytest.approx(127.0)


# 대응점이 2개뿐이면(축별 스케일이 다를 수 있는 6개 미지수를 결정하기엔
# 부족함) 명시적으로 거부한다.
def test_대응점이_3개_미만이면_에러를_낸다():
    with pytest.raises(ValueError):
        fit_affine_transform(
            [PointPair(x=0, y=0, u=127.0, v=37.0), PointPair(x=1, y=0, u=128.0, v=37.0)]
        )


# fit_wgs84_transform으로 피팅한 변환이, 원래 변환(lng_scale 포함)과 같은
# 결과를 내는지 확인한다(왕복 정확도).
def test_fit_wgs84_transform은_원래_변환을_복원한다():
    true_lng_scale = math.cos(math.radians(37.5))
    true_transform = GeoTransform(
        a=1e-5, b=2e-6, c=-1e-6, d=1.1e-5, tx=127.0, ty=37.5, lng_scale=true_lng_scale
    )

    local_points = [
        (0.0, 0.0),
        (100.0, 0.0),
        (0.0, 80.0),
        (60.0, 40.0),
        (-30.0, 90.0),
        (20.0, -15.0),
    ]
    pairs = [
        PointPair(x=x, y=y, u=lng, v=lat)
        for x, y in local_points
        for lat, lng in [true_transform.apply(x, y)]
    ]

    fitted = fit_wgs84_transform(pairs)

    for x, y in local_points:
        expected = true_transform.apply(x, y)
        actual = fitted.apply(x, y)
        # lstsq 수치오차 감안: 절대오차 1e-7 이내(도 단위 1e-7 ≈ 1cm 미만)면 충분하다.
        assert actual == pytest.approx(expected, abs=1e-7)


# 핵심 회귀 테스트: 실제 데이터(navigation_1f.json)로 확인된 버그 두 가지를
# 함께 재현/검증한다.
# 1) (lng, lat)에 비등방 보정 없이 피팅하면 넓이가 왜곡된다.
# 2) 애초에 4-DOF similarity(균일 스케일)로 피팅하면, 데이터가 진짜 affine
#    관계(축별 스케일이 다름)일 때 큰 오차가 남는다 — 실측으로 중앙값 27m,
#    최대 80m였던 오차가 6-DOF affine으로는 중앙값 0.29m로 줄었다.
# fit_wgs84_transform(6-DOF affine + lng_scale 보정)은 두 문제를 모두
# 해결해서 원래 넓이를 보존해야 한다.
def test_fit_wgs84_transform은_비등방_affine_관계와_경위도_스케일을_모두_보정한다():
    # 서울(위도 37.5 부근)에서, x축과 y축의 실제 스케일이 서로 다른(진짜
    # affine, similarity 아님) 직사각형을 만든다: x 100m -> 위경도 100m 어치,
    # y 80m -> 위경도로는 120m 어치(축별 스케일이 다르다는 뜻).
    ref_lat = 37.5
    m_per_deg_lat = 111_320.0
    m_per_deg_lng = 111_320.0 * math.cos(math.radians(ref_lat))
    base_lat, base_lng = 37.5, 127.0
    rect_m = [(0.0, 0.0), (100.0, 0.0), (100.0, 80.0), (0.0, 80.0)]
    y_stretch = 1.5  # x와 y의 실제 물리적 스케일이 다르다는 것을 흉내낸다.
    wgs84_rect = [
        (base_lat + (y * y_stretch) / m_per_deg_lat, base_lng + x / m_per_deg_lng)
        for x, y in rect_m
    ]
    true_area = _polygon_area_m2(wgs84_rect)
    expected_area = 100.0 * (80.0 * y_stretch)
    assert true_area == pytest.approx(expected_area, rel=1e-3)

    pairs = [
        PointPair(x=x, y=y, u=lng, v=lat) for (x, y), (lat, lng) in zip(rect_m, wgs84_rect)
    ]

    correctly_fitted = fit_wgs84_transform(pairs)
    correct_rect = [correctly_fitted.apply(x, y) for x, y in rect_m]
    assert _polygon_area_m2(correct_rect) == pytest.approx(true_area, rel=1e-3)

    # 비교 대상: 4-DOF와 동치인 축별 동일 스케일을 강제하면(과거 similarity
    # 방식 재현) 이런 비등방 관계를 표현할 수 없어 왜곡이 남는다. affine은
    # 축별 스케일이 같은 경우로 축소될 수 없다는 점을 보이기 위해, 여기서는
    # a=d, b=-c(순수 회전+균일스케일)라는 제약을 강제로 걸고 최소자승을
    # 다시 풀어 그 결과가 정확할 수 없음을 확인한다.
    mean_lat = sum(p.v for p in pairs) / len(pairs)
    lng_scale = math.cos(math.radians(mean_lat))
    # a*x-b*y+tx = u*lng_scale, b*x+a*y+ty = v 형태(4-DOF)로 별도 피팅.
    import numpy as np

    rows, targets = [], []
    for p in pairs:
        rows.append([p.x, -p.y, 1.0, 0.0])
        targets.append(p.u * lng_scale)
        rows.append([p.y, p.x, 0.0, 1.0])
        targets.append(p.v)
    (a, b, tx, ty), *_ = np.linalg.lstsq(np.array(rows), np.array(targets), rcond=None)
    naive_fitted = GeoTransform(a=a, b=-b, c=b, d=a, tx=tx, ty=ty, lng_scale=lng_scale)
    naive_rect = [naive_fitted.apply(x, y) for x, y in rect_m]
    naive_area = _polygon_area_m2(naive_rect)
    # 왜곡 정도를 정확히 못박기보다, "무시 못 할 정도로 달라진다"만 확인한다.
    assert abs(naive_area - true_area) / true_area > 0.03


# T2∘T1을 합성한 결과가, 두 변환을 순서대로 직접 적용한 것과 같은 좌표를 내는지 확인한다.
def test_compose_transforms는_두_변환을_순서대로_적용한_것과_같다():
    # local_m -> svg_px
    t1 = GeoTransform(a=0.5, b=0.1, c=-0.2, d=0.6, tx=10.0, ty=-5.0)
    # svg_px -> wgs84
    t2 = GeoTransform(a=1e-5, b=-2e-6, c=3e-6, d=1.1e-5, tx=126.9, ty=37.5)

    composed = compose_transforms(inner=t1, outer=t2)

    for x, y in [(0.0, 0.0), (12.3, 45.6), (-7.0, 3.2)]:
        u1, v1 = t1.apply_uv(x, y)
        expected_u, expected_v = t2.apply_uv(u1, v1)

        actual_u, actual_v = composed.apply_uv(x, y)

        assert actual_u == pytest.approx(expected_u)
        assert actual_v == pytest.approx(expected_v)
