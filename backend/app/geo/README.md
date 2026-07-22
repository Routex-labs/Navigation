# `app/geo` — 좌표 변환·지도 타일 순수 로직

건물 로컬 좌표(`local_m`)와 실세계 좌표(WGS84), 지도 타일 사이의 **순수 수학**을 담는다.
FastAPI·SQLAlchemy를 몰라도 되는 계층이라, ORM 모델의 값 필드에만 의존하고 부작용이 없다.

> 이름의 유래: 순수 계산 계층을 `domain`이 아니라 `geo`로 둔 것은 이 모듈이 좌표/타일 수학만 담기 때문이다. 경로 탐색은 서버에 없다 — 클라이언트가 `navigation_graph`로 온디바이스 수행한다.

---

## 구성 파일

| 파일 | 역할 | 핵심 심볼 |
|---|---|---|
| `georeference.py` | 2D affine 변환 피팅·적용·합성 | `GeoTransform`, `PointPair`, `fit_wgs84_transform`, `fit_affine_transform`, `compose_transforms` |
| `tiling.py` | 슬리피맵 타일 계산 + MVT GeoJSON 레이어 | `TileBounds`, `tile_bounds`, `local_points_to_lnglat`, `build_floor_tile_layers` |
| `__init__.py` | 패키지 표식 | — |

---

## `georeference.py` — affine 변환

`local_m → WGS84`, `SVG px → WGS84` 같은 2D 평면 대 평면 변환을 최소자승으로 피팅한다.

```python
@dataclass(frozen=True)
class GeoTransform:
    a, b, c, d, tx, ty: float
    lng_scale: float = 1.0
    #   u = a*x + b*y + tx
    #   v = c*x + d*y + ty
    def apply(self, x_m, y_m) -> tuple[lat, lng]: ...
```

핵심 설계(코드 상단 주석에 근거 상세):

- **6-DOF affine을 쓴다(4-DOF similarity 아님).** 실데이터로 similarity를 피팅하면 오차 중앙값 27m·건물 왜곡이 났고, 축별 스케일이 다른 affine으로 바꾸자 0.29m로 줄었다.
- **WGS84 피팅은 반드시 `fit_wgs84_transform`을 쓴다.** 위도 1도와 경도 1도는 실제 거리가 달라서(경도 ≈ 위도·cos(위도)), 그냥 `fit_affine_transform`에 (lng, lat)을 넣으면 비등방성 때문에 왜곡된다. `fit_wgs84_transform`은 평균 위도로 `lng_scale = cos(위도)`를 구해 등방 공간에서 피팅하고, `apply()`가 이 값으로 되돌린다.
- **`compose_transforms(inner, outer)`**: 두 affine을 합성해도 다시 하나의 affine이 된다. `local_m → SVG px → WGS84`를 매 요청 두 단계로 돌리지 않고 미리 하나로 합칠 수 있다.

## `tiling.py` — 타일 계산

```python
def tile_bounds(z, x, y) -> TileBounds          # 슬리피맵 z/x/y → WGS84 경계 상자
def local_points_to_lnglat(points, transform)   # local_m 점 목록 → [lng, lat] 목록
def build_floor_tile_layers(building, stores, pois, transform, bounds) -> list[dict]
```

- `build_floor_tile_layers`는 footprint/stores/pois를 wgs84 GeoJSON feature로 만들되, **타일 bbox와 겹치는 것만** 담는다(정밀 클리핑 없이 bbox 교차만 — 실내 지도는 feature가 적어 충분).
- `transform`이 `None`이면 빈 레이어를 돌려준다 → 404 대신 "그릴 게 없음"으로 처리해 MapLibre가 조용히 넘어가게 한다.
- **MVT 바이트 인코딩은 여기서 하지 않는다.** 외부 라이브러리(`mapbox_vector_tile`) 의존이라 `repositories/tile_queries.py`가 담당한다. 이 모듈은 순수 계산까지만.

---

## 의존성 방향

```
geo/georeference.py  ──►  numpy (최소자승)만
geo/tiling.py        ──►  geo.georeference.GeoTransform (타입), app.models 필드

repositories/geo_transform.py  ──►  geo.georeference (변환 피팅)
repositories/building_queries.py, tile_queries.py ──►  geo.tiling, geo.georeference
```

- **geo는 app 상위 계층에 의존하지 않는다.** `models`의 값 필드(`x_m`, `polygon` 등)만 읽는다.
- DB에서 실제 대응점을 뽑아 변환을 **피팅하는** 책임은 `repositories/geo_transform.py`에 있다(Session이 필요하므로). geo는 "피팅 수학"만 제공한다.

---

## 자주 하는 작업

| 하고 싶은 것 | 어디를 보나 |
|---|---|
| 좌표가 어긋나 보인다 | 변환 피팅 입력(대응점)은 `repositories/geo_transform.py`, 수학은 `georeference.py` |
| 타일에 매장이 안 나온다 | `build_floor_tile_layers`의 bbox 교차 / `transform is None` 분기 |
| 새 좌표계 단계 추가 | `compose_transforms`로 기존 변환에 합성 |
