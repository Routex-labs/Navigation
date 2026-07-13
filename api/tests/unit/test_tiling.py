"""벡터 타일용 좌표 변환/레이어 구성 단위 테스트."""

import pytest

from app.domain.georeference import GeoTransform
from app.domain.tiling import TileBounds, build_floor_tile_layers, tile_bounds
from app.models import Building, Poi, Store

IDENTITY_TRANSFORM = GeoTransform(a=1.0, b=0.0, c=0.0, d=1.0, tx=126.0, ty=37.0)


# z=0에서는 타일 하나가 지구 전체를 덮으므로 서경/남위 끝은 -180/-85.05...(Web
# Mercator 위도 한계) 근처가 나와야 한다.
def test_z0_타일은_지구_전체를_덮는다():
    bounds = tile_bounds(0, 0, 0)

    assert bounds.west == pytest.approx(-180.0)
    assert bounds.east == pytest.approx(180.0)
    assert bounds.north == pytest.approx(85.0511, abs=1e-3)
    assert bounds.south == pytest.approx(-85.0511, abs=1e-3)


def test_범위를_벗어난_타일_좌표는_거부한다():
    with pytest.raises(ValueError):
        tile_bounds(2, 4, 0)  # z=2는 x/y가 0..3까지만 유효


def _building() -> Building:
    return Building(
        id="b1",
        name="테스트빌딩",
        area_m2=100.0,
        perimeter_m=40.0,
        footprint_local_m=[
            {"x": 0.0, "y": 0.0},
            {"x": 10.0, "y": 0.0},
            {"x": 10.0, "y": 10.0},
            {"x": 0.0, "y": 10.0},
        ],
    )


# transform이 없는 건물(실측 앵커가 전혀 없어 피팅이 불가능한 경우)은 타일을
# 만들 실좌표 근거가 없으므로 빈 레이어를 반환해야 한다.
def test_transform이_없으면_빈_레이어를_반환한다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[],
        transform=None,
        bounds=tile_bounds(0, 0, 0),
    )

    assert layers == []


# 항등 변환(스케일 1, 회전 없음)일 때 footprint 좌표가 lng=x+126, lat=y+37로
# 그대로 옮겨지는지 확인한다.
def test_footprint이_geo_transform으로_wgs84로_변환된다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    footprint_layer = next(layer for layer in layers if layer["name"] == "footprint")
    ring = footprint_layer["features"][0]["geometry"]["coordinates"][0]

    assert ring[0] == [126.0, 37.0]
    assert ring[2] == [136.0, 47.0]
    # 폴리곤 링은 닫혀 있어야 한다(첫 점 == 마지막 점).
    assert ring[0] == ring[-1]


# 타일 경계와 겹치지 않는 매장은 걸러내는지 확인한다.
def test_타일_밖의_매장은_제외된다():
    far_store = Store(
        id="far",
        floor_id="f1",
        name="먼 매장",
        centroid_x_m=1000.0,
        centroid_y_m=1000.0,
        polygon=[
            {"x": 1000.0, "y": 1000.0},
            {"x": 1001.0, "y": 1000.0},
            {"x": 1001.0, "y": 1001.0},
        ],
    )
    near_store = Store(
        id="near",
        floor_id="f1",
        name="가까운 매장",
        centroid_x_m=0.1,
        centroid_y_m=0.1,
        polygon=[
            {"x": 0.1, "y": 0.1},
            {"x": 0.2, "y": 0.1},
            {"x": 0.2, "y": 0.2},
        ],
    )
    # 매장 전용 좁은 타일: IDENTITY_TRANSFORM 기준 lng/lat 126~126.5, 37~37.5
    # 범위만 덮도록 z=0 대신 직접 TileBounds를 만들어 검증한다.
    narrow_bounds = TileBounds(west=126.0, south=37.0, east=126.5, north=37.5)

    layers = build_floor_tile_layers(
        _building(),
        stores=[far_store, near_store],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=narrow_bounds,
    )

    store_layer = next(layer for layer in layers if layer["name"] == "stores")
    ids = {feature["properties"]["id"] for feature in store_layer["features"]}

    assert ids == {"near"}


# POI 좌표도 동일한 변환을 거치는지 확인한다.
def test_poi도_wgs84로_변환된다():
    poi = Poi(
        id="poi-1",
        floor_id="f1",
        type="elevator",
        name="EV1",
        x_m=5.0,
        y_m=5.0,
    )

    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[poi],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    poi_layer = next(layer for layer in layers if layer["name"] == "pois")
    coordinates = poi_layer["features"][0]["geometry"]["coordinates"]

    assert coordinates == [131.0, 42.0]
