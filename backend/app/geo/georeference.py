# 2D 점 대응 쌍으로 affine 변환(축별 스케일+기울임+회전+평행이동)을
# 피팅하고 적용/합성하는 순수 유틸리티.
#
# 본래는 local_m(건물 로컬 평면 좌표)을 WGS84로 옮기는 데만 썼지만, 같은 수학이
# "SVG px 좌표 -> WGS84"처럼 다른 2D 평면 쌍에도 그대로 적용된다. 실내 지도는
# 서로 다른 좌표계를 가진 여러 소스(예: local_m 기반 그래프/POI 데이터셋과
# 사람이 손으로 정리한 SVG 도면)를 조합해야 할 때가 많은데, 두 affine
# 변환을 이어붙이면(compose_transforms) 다시 하나의 affine 변환이
# 나온다는 성질을 이용해 "local_m -> SVG px -> WGS84"처럼 여러 단계를
# 거치는 지점도 별도 런타임 계산 없이 미리 합성한 변환 하나로 처리할 수 있다.
#
# 4-DOF similarity가 아니라 6-DOF affine을 쓰는 이유(실측으로 확인됨):
# 처음에는 균일 스케일+회전만 표현하는 4-DOF similarity 변환으로 충분하다고
# 가정했다. 하지만 실제 데이터(navigation_1f.json의 "provisional" wgs84)로
# 피팅해보니 중앙값 27m, 최대 80m라는 큰 오차가 났고, 건물 면적이 절반 이하로
# 쪼그라드는 왜곡까지 있었다. 원인은 "노이즈"가 아니라 애초에 이 데이터의
# local_m<->wgs84 관계가 순수 similarity가 아니라 축별로 스케일이 다른 affine
# 관계였기 때문이다(추정: 원본 이미지 정합 과정이 진짜 similarity가 아니었을
# 가능성). 같은 대응점에 6-DOF affine을 피팅하자 오차가 중앙값 0.29m로
# 줄었다 — 그래서 이 모듈은 4-DOF가 아니라 항상 6-DOF affine을 피팅한다.
#
# WGS84로 피팅할 때 주의할 점: 위도 1도와 경도 1도는 실제 거리가 다르다
# (경도 1도 ≈ 위도 1도 * cos(위도)). (lng, lat)을 그냥 평면 좌표처럼 취급해서
# 피팅하면 이 비등방성 때문에 결과가 왜곡된다. 그래서 wgs84로 피팅할 때는
# fit_affine_transform을 직접 쓰지 말고 fit_wgs84_transform을 써야 한다.

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass
from typing import Iterable

import numpy as np


# 변환 피팅에 쓰는 2D 대응점 하나. (x, y)는 입력 평면, (u, v)는 출력 평면 좌표.
@dataclass(frozen=True)
class PointPair:
    x: float
    y: float
    u: float
    v: float


# (x, y) -> (u, v) 2D affine 변환(축별로 다른 스케일/기울임 허용, 6-DOF).
#   u = a*x + b*y + tx
#   v = c*x + d*y + ty
# local_m -> WGS84로 쓸 때는 (u, v)가 (lng, lat)이 아니라 "등방(isotropic)
# 공간의 (경도류, 위도)"다 — 피팅 시 경도에 lng_scale(=cos(기준 위도))을
# 곱해서 위도와 같은 물리적 스케일로 맞췄기 때문이다. apply()가 이 값으로
# 다시 나눠 진짜 경도로 되돌린다. wgs84가 아닌 용도(예: local_m -> SVG px)로
# 쓸 때는 lng_scale=1.0(기본값)이라 이 보정이 그냥 항등 연산이 된다.
@dataclass(frozen=True)
class GeoTransform:
    a: float
    b: float
    c: float
    d: float
    tx: float
    ty: float
    lng_scale: float = 1.0

    # 입력 평면 좌표 하나를 (u, v)로 변환한다(lng_scale 보정 없이 그대로).
    def apply_uv(self, x: float, y: float) -> tuple[float, float]:
        u = self.a * x + self.b * y + self.tx
        v = self.c * x + self.d * y + self.ty
        return u, v

    # local_m 좌표 하나를 (lat, lng)로 변환한다. apply_uv가 등방 공간의 (u, v)를
    # 돌려주면, u를 lng_scale로 나눠 진짜 경도로 되돌린다(fit_wgs84_transform 참고).
    def apply(self, x_m: float, y_m: float) -> tuple[float, float]:
        u, v = self.apply_uv(x_m, y_m)
        lng = u / self.lng_scale
        lat = v
        return lat, lng


# (x,y)<->(u,v) 대응점들로 6-DOF affine 변환을 최소자승 피팅한다.
# (u, v)가 진짜 등방(isotropic) 평면 좌표일 때만 쓴다(예: local_m -> SVG px처럼
# 둘 다 같은 물리적 스케일 단위). (u, v)가 (lng, lat)이면 fit_wgs84_transform을
# 대신 써야 한다 — 위도/경도 1도의 실제 거리가 다르기 때문이다.
# u = a*x + b*y + tx, v = c*x + d*y + ty를 각각 독립적으로 최소자승 피팅한다
# (두 식이 계수를 공유하지 않으므로 따로 풀어도 similarity 특수해를 포함하는
# 일반해가 나온다).
def fit_affine_transform(pairs: Iterable[PointPair]) -> GeoTransform:
    pairs = list(pairs)
    if len(pairs) < 3:
        raise ValueError("affine 변환을 피팅하려면 대응점이 3개 이상 필요합니다.")

    design = np.array([[pair.x, pair.y, 1.0] for pair in pairs])
    u_values = np.array([pair.u for pair in pairs])
    v_values = np.array([pair.v for pair in pairs])

    (a, b, tx), *_ = np.linalg.lstsq(design, u_values, rcond=None)
    (c, d, ty), *_ = np.linalg.lstsq(design, v_values, rcond=None)

    return GeoTransform(a=float(a), b=float(b), c=float(c), d=float(d), tx=float(tx), ty=float(ty))


# (x,y) -> (lng, lat) 대응점들로 6-DOF affine 변환을 피팅한다.
# (u, v)에 원본 그대로의 (lng, lat)(도 단위)를 넣어서 호출한다. 위도/경도
# 1도의 실제 거리가 다른 문제를 내부에서 자동으로 보정한다: 대응점들의
# 평균 위도로 lng_scale = cos(평균위도)를 구해 경도에 곱한 뒤(등방 공간으로
# 만든 뒤) 피팅하고, 그 lng_scale을 결과 GeoTransform에 담아 돌려준다.
# apply()가 이 값을 이용해 최종 결과를 다시 진짜 (lat, lng)로 되돌린다.
def fit_wgs84_transform(pairs: Iterable[PointPair]) -> GeoTransform:
    pairs = list(pairs)
    if len(pairs) < 3:
        raise ValueError("affine 변환을 피팅하려면 대응점이 3개 이상 필요합니다.")

    # 경도를 위도와 같은 물리 스케일로 눌러 등방 공간을 만든다.
    mean_lat = sum(pair.v for pair in pairs) / len(pairs)
    lng_scale = math.cos(math.radians(mean_lat))

    isotropic_pairs = [PointPair(x=p.x, y=p.y, u=p.u * lng_scale, v=p.v) for p in pairs]
    transform = fit_affine_transform(isotropic_pairs)

    # apply()가 되돌릴 수 있도록 보정값을 결과에 실어 보낸다.
    return dataclasses.replace(transform, lng_scale=lng_scale)


# outer ∘ inner: 먼저 inner를, 그 결과에 outer를 적용하는 것과 동일한 단일 변환.
# 두 affine 변환의 합성은 2x2 행렬 곱셈 + 평행이동 결합과 동치라서, 합성해도
# 다시 하나의 affine 변환이 된다. 예: local_m -> SVG px 변환과 SVG px ->
# WGS84 변환을 합성하면, 요청마다 두 단계를 거치지 않고도 local_m -> WGS84
# 변환 하나로 같은 결과를 낼 수 있다.
# 합성 결과의 lng_scale은 outer의 것을 그대로 물려받는다 — 최종 출력 좌표계가
# wgs84(등방 보정이 필요)인지는 outer가 결정하고, inner의 출력(중간 좌표계)은
# 보통 wgs84가 아니라 lng_scale 보정이 의미가 없기 때문이다.
def compose_transforms(inner: GeoTransform, outer: GeoTransform) -> GeoTransform:
    a1, b1, c1, d1, tx1, ty1 = inner.a, inner.b, inner.c, inner.d, inner.tx, inner.ty
    a2, b2, c2, d2, tx2, ty2 = outer.a, outer.b, outer.c, outer.d, outer.tx, outer.ty

    # M_composed = M2 @ M1, t_composed = M2 @ t1 + t2
    a = a2 * a1 + b2 * c1
    b = a2 * b1 + b2 * d1
    c = c2 * a1 + d2 * c1
    d = c2 * b1 + d2 * d1
    tx = a2 * tx1 + b2 * ty1 + tx2
    ty = c2 * tx1 + d2 * ty1 + ty2

    return GeoTransform(a=a, b=b, c=c, d=d, tx=tx, ty=ty, lng_scale=outer.lng_scale)
