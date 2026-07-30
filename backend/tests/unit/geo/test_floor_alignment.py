"""좌표 아핀 유틸 검증.

예전에는 층 정렬 아핀 피팅(엘리베이터 대응점, shear/잔차 게이트)까지 여기서
검증했다. 다베오 데이터가 전 층에 한 프레임을 물려주면서 정렬 단계 자체가
사라졌고, 남은 것은 좌표를 찍는 함수뿐이다.
"""

from scripts.transform import floor_alignment as fa


def test_identity_preserves_coordinates():
    assert fa.apply(fa.IDENTITY, 12.5, -3.25) == (12.5, -3.25)


def test_apply_transforms_scale_and_offset():
    # x' = 2x + 5, y' = 3y - 1
    affine = ((2.0, 0.0, 5.0), (0.0, 3.0, -1.0))

    assert fa.apply(affine, 10.0, 10.0) == (25.0, 29.0)


def test_apply_point_returns_rounded_dict():
    affine = ((1.0, 0.0, 0.1234567), (0.0, 1.0, 0.0))

    assert fa.apply_point(affine, {"x": 0.0, "y": 2.0}) == {"x": 0.123457, "y": 2.0}
