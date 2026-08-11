"""벡터 타일용 좌표 변환/레이어 구성 단위 테스트."""

import mapbox_vector_tile
import pytest

from app.geo.georeference import GeoTransform
from app.geo.tiling import TileBounds, build_floor_tile_layers, tile_bounds
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


def _store_with_category(
    store_id: str,
    category: str | None,
    subcategory: str | None,
) -> Store:
    return Store(
        id=store_id,
        floor_id="f1",
        name=f"매장 {store_id}",
        category=category,
        subcategory=subcategory,
        centroid_x_m=0.1,
        centroid_y_m=0.1,
        polygon=[
            {"x": 0.1, "y": 0.1},
            {"x": 0.2, "y": 0.1},
            {"x": 0.2, "y": 0.2},
        ],
    )


def _store_properties_by_id(stores: list[Store]) -> dict[str, dict]:
    layers = build_floor_tile_layers(
        _building(),
        stores=stores,
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    store_layer = next(layer for layer in layers if layer["name"] == "stores")
    return {feature["properties"]["id"]: feature["properties"] for feature in store_layer["features"]}


# 클라이언트가 MapLibre setFilter로 카테고리 필터를 걸려면 두 값이 타일에 실려야 한다.
def test_매장_feature에_category와_subcategory가_실린다():
    properties = _store_properties_by_id([_store_with_category("s1", "패션", "여성복")])["s1"]

    assert properties["category"] == "패션"
    assert properties["subcategory"] == "여성복"


# category/subcategory는 nullable이다. None이면 null을 싣는 게 아니라 키 자체를
# 빼는 것이 계약이다 — MapLibre 필터에서 ['has', 'category']로 판정할 수 있다.
@pytest.mark.parametrize(
    ("category", "subcategory", "expected_keys"),
    [
        (None, None, set()),
        ("패션", None, {"category"}),
        (None, "여성복", {"subcategory"}),
    ],
)
def test_category가_없으면_해당_키를_아예_넣지_않는다(category, subcategory, expected_keys):
    properties = _store_properties_by_id([_store_with_category("s1", category, subcategory)])["s1"]

    assert {"category", "subcategory"} & set(properties) == expected_keys
    # 값이 없어도 나머지 property는 그대로 있어야 한다.
    assert properties["kind"] == "store"


# 위 계약이 실제 MVT 바이트까지 살아남는지 확인한다. 인코더에 None을 넘겨도 지금은
# 조용히 키가 빠지지만, 그 동작에 기대지 않는다는 것이 이 테스트의 요지다.
def test_category가_없는_매장도_예외없이_MVT로_인코딩된다():
    bounds = tile_bounds(0, 0, 0)
    layers = build_floor_tile_layers(
        _building(),
        stores=[
            _store_with_category("s1", None, None),
            _store_with_category("s2", "패션", "여성복"),
        ],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=bounds,
    )

    encoded = mapbox_vector_tile.encode(
        layers,
        default_options={"quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north)},
    )
    decoded = mapbox_vector_tile.decode(encoded)

    properties = {feature["properties"]["id"]: feature["properties"] for feature in decoded["stores"]["features"]}
    assert "category" not in properties["s1"]
    assert "subcategory" not in properties["s1"]
    assert properties["s2"]["category"] == "패션"
    assert properties["s2"]["subcategory"] == "여성복"


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


# 라벨(아이콘+이름)은 매장 폴리곤이 아니라 전용 점 레이어에 실린다. MapLibre가
# 폴리곤 심볼을 면적 무게중심에 찍는데, ㄱ자 매장에서는 그 점이 매장 밖이다
# ([label_point.py] 주석). 클라이언트 라벨 레이어가 이 레이어를 본다.
def test_매장_라벨은_전용_점_레이어로_나간다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[_store_with_category("s1", "패션", "여성복")],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    label_layer = next(layer for layer in layers if layer["name"] == "store_labels")
    feature = label_layer["features"][0]

    assert feature["geometry"]["type"] == "Point"
    # 필터 표현식이 폴리곤 레이어와 같은 키를 보므로 properties도 같아야 한다.
    assert feature["properties"]["id"] == "s1"
    assert feature["properties"]["category"] == "패션"
    assert feature["properties"]["subcategory"] == "여성복"


# ㄱ자 매장에서 라벨 점이 폴리곤 안에 들어와야 한다. 무게중심을 그대로 쓰면
# 두 팔 사이 빈 곳(=복도)에 아이콘이 뜬다.
def test_ㄱ자_매장_라벨_점이_폴리곤_안에_있다():
    l_shaped = Store(
        id="l1",
        floor_id="f1",
        name="ㄱ자 매장",
        centroid_x_m=0.0,
        centroid_y_m=0.0,
        polygon=[
            {"x": 0.0, "y": 0.0},
            {"x": 0.30, "y": 0.0},
            {"x": 0.30, "y": 0.06},
            {"x": 0.06, "y": 0.06},
            {"x": 0.06, "y": 0.30},
            {"x": 0.0, "y": 0.30},
        ],
    )

    layers = build_floor_tile_layers(
        _building(),
        stores=[l_shaped],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    ring = next(layer for layer in layers if layer["name"] == "stores")["features"][0]
    polygon = [(point[0], point[1]) for point in ring["geometry"]["coordinates"][0]]
    label = next(layer for layer in layers if layer["name"] == "store_labels")["features"][0]
    x, y = label["geometry"]["coordinates"]

    inside = False
    for index in range(len(polygon)):
        x0, y0 = polygon[index]
        x1, y1 = polygon[(index + 1) % len(polygon)]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            inside = not inside

    assert inside


# 라벨 좌표는 타일(z/x/y)과 무관하게 매장 폴리곤 + 건물 변환만으로 정해지므로,
# 호출자가 memo를 넘기면 계산 결과가 채워져 다음 타일에서 재사용할 수 있어야 한다.
def test_라벨_memo에_계산된_좌표가_채워진다():
    memo: dict[str, tuple[float, float]] = {}

    layers = build_floor_tile_layers(
        _building(),
        stores=[_store_with_category("s1", "패션", "여성복")],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
        store_label_memo=memo,
    )

    label = next(layer for layer in layers if layer["name"] == "store_labels")["features"][0]
    assert memo["s1"] == tuple(label["geometry"]["coordinates"])


# memo에 이미 있는 매장은 다시 계산하지 않고 그 좌표를 그대로 쓴다. 재계산이
# 일어나면 memo 값과 다른(진짜 계산된) 좌표가 실리므로, 일부러 다른 좌표를
# 심어 재사용 여부를 판별한다.
def test_라벨_memo의_좌표를_재계산_없이_그대로_쓴다():
    planted = (126.15, 37.15)
    memo = {"s1": planted}

    layers = build_floor_tile_layers(
        _building(),
        stores=[_store_with_category("s1", "패션", "여성복")],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
        store_label_memo=memo,
    )

    label = next(layer for layer in layers if layer["name"] == "store_labels")["features"][0]
    assert tuple(label["geometry"]["coordinates"]) == planted


# 타일 경계에 걸친 매장은 폴리곤이 양쪽 타일에 실리지만 **라벨은 한 번만**
# 실려야 한다. 둘 다 실으면 두 타일이 함께 떠 있을 때 같은 이름이 두 번 찍힌다.
def test_라벨_점이_없는_타일에는_라벨을_싣지_않는다():
    store = _store_with_category("s1", "패션", "여성복")
    # 매장 폴리곤(lng 126.1~126.2)과 겹치지만 라벨 점(lng≈126.171)은 담지 못하는
    # 좁은 띠. 화면 가장자리에서 매장의 오른쪽 끝만 걸친 타일이 이 모양이다.
    sliver = TileBounds(west=126.18, south=37.0, east=126.5, north=37.5)

    layers = build_floor_tile_layers(
        _building(),
        stores=[store],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=sliver,
    )

    assert next(layer for layer in layers if layer["name"] == "stores")["features"]
    assert next(layer for layer in layers if layer["name"] == "store_labels")["features"] == []
