"""건물/층/그래프/매장 HTTP 엔드포인트.

URL 파라미터, Depends(get_db), response_model, 400/404 변환만 담당한다.
조회는 building_queries가 담당한다. 최단 경로 계산은 클라이언트가 층 지도 응답의
navigation_graph로 온디바이스 다익스트라를 돌리므로 서버에는 두지 않는다.
sqlite3/SQLAlchemy 동기 IO이므로 모든 핸들러는 def(동기)로 선언한다.

경로 목록 (prefix=/buildings):
  GET /buildings                                → 건물 목록
  GET /buildings/{id}                           → 건물 상세 (footprint 포함)
  GET /buildings/{id}/stores?q=검색어           → 매장 검색
  GET /buildings/{id}/store-index               → 자동완성용 경량 매장 목록(좌표 없음)
  GET /buildings/{id}/places/{place_id}         → 매장/시설 상세
  GET /buildings/{id}/floors/{floor}            → 층 지도 데이터 (매장+POI+그래프)
  GET /buildings/{id}/floors/{floor}/graph      → 층 길찾기 그래프 (nodes+edges)
  GET /buildings/{id}/graph?vertical=auto       → 건물 전체 그래프 (전 층+수직 전이)
  GET /buildings/{id}/floors/{floor}/tiles/{z}/{x}/{y}.mvt → 벡터 타일(MVT)
"""

import hashlib

from fastapi import APIRouter, Depends, Header, HTTPException, Response
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.http_cache import cache_headers, etag_matches
from app.dto.building import (
    BuildingDetailResponse,
    BuildingSummaryResponse,
    CategoryCountResponse,
    StoreIndexResponse,
)
from app.dto.floor_map import FloorMapResponse, StoreResponse
from app.dto.place_detail import PlaceDetailResponse
from app.dto.route import BuildingGraphResponse, FloorGraphResponse
from app.repositories import building_queries, place_detail_queries, tile_queries

router = APIRouter(prefix="/buildings", tags=["buildings"])


# 전체 건물 목록. footprint 같은 무거운 데이터는 제외한 요약.
@router.get("", response_model=list[BuildingSummaryResponse])
def list_buildings(session: Session = Depends(get_db)):
    return building_queries.list_buildings(session)


# 건물 상세 정보 (면적, 둘레, footprint 폴리곤 포함).
@router.get("/{building_id}", response_model=BuildingDetailResponse)
def get_building(building_id: str, session: Session = Depends(get_db)):
    result = building_queries.get_building(session, building_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    # 타일 URL에 붙일 버전. 건물 응답은 지도보다 먼저 받으므로 클라이언트가
    # 첫 타일 요청부터 이 값을 쓸 수 있다. building_queries가 아니라 여기서
    # 채우는 이유는 tile_queries가 building_queries를 import하고 있어서다
    # (반대 방향으로 부르면 순환 import가 된다).
    result["tile_revision"] = tile_queries.tile_revision(session)
    return result


# 카테고리 필터용 (층·대분류·소분류)별 매장 수.
# 지도 위 pill 목록과 개수 안내가 이 응답 하나로 만들어진다.
@router.get("/{building_id}/categories", response_model=list[CategoryCountResponse])
def list_building_categories(building_id: str, session: Session = Depends(get_db)):
    result = building_queries.list_category_counts(session, building_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# 건물 전체 길찾기 그래프. 층별 /graph와 달리 수직 전이 간선까지 포함해
# 클라이언트가 층 간 경로를 온디바이스로 계산할 수 있다.
# vertical: 수직 이동 정책(auto/elevator/escalator). 잘못된 값은 422.
@router.get("/{building_id}/graph", response_model=BuildingGraphResponse)
def get_building_graph(
    building_id: str,
    vertical: str = "auto",
    session: Session = Depends(get_db),
):
    if vertical not in building_queries.VERTICAL_POLICIES:
        raise HTTPException(
            status_code=422,
            detail=f"vertical must be one of {building_queries.VERTICAL_POLICIES}",
        )
    result = building_queries.get_building_graph(session, building_id, vertical)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# 건물 내 매장 이름 검색. q 미지정 시 전체 매장 반환.
@router.get("/{building_id}/stores", response_model=list[StoreResponse])
def search_stores(
    building_id: str,
    q: str = "",  # ?q=검색어 쿼리 파라미터. 미지정 시 전체 매장
    session: Session = Depends(get_db),
):
    result = building_queries.search_stores(session, building_id, q)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# 온디바이스 자동완성의 원본이 되는 경량 매장 목록. 좌표·폴리곤은 싣지 않는다.
#
# 경로 이름: `/stores`의 쿼리 파라미터(`?light=1` 등)로 얹지 않고 별도 경로로 둔다.
# 같은 경로가 요청에 따라 다른 스키마를 돌려주면 response_model을 하나로 고정할 수
# 없고, 층 지도를 그리는 기존 소비자와 검색 인덱스 소비자가 같은 계약을 공유하게 된다.
# 건물 스코프의 파생 목록을 별도 경로로 두는 것은 `/categories`와 같은 방식이다.
# `store-index`라는 이름은 필터된 매장 목록이 아니라 **검색 인덱스 원본**이라는
# 용도를 드러낸다 — `?q=` 검색은 계속 `/stores`가 담당한다.
@router.get("/{building_id}/store-index", response_model=list[StoreIndexResponse])
def list_store_index(building_id: str, session: Session = Depends(get_db)):
    result = building_queries.list_store_index(session, building_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Building not found")
    return result


# 매장/시설 상세. 층 지도 응답에 끼워 넣지 않고 탭한 순간 1건만 가져오는 이유는,
# 한 층에 매장이 최대 240건이라 상세를 층 응답에 합치면 지도 첫 렌더가 그만큼
# 느려지기 때문이다. 층 응답은 지도를 그리는 최소 묶음으로 유지한다.
@router.get(
    "/{building_id}/places/{place_id}",
    response_model=PlaceDetailResponse,
)
def get_place_detail(
    building_id: str,
    place_id: str,
    session: Session = Depends(get_db),
    if_none_match: str | None = Header(default=None),
):
    result = place_detail_queries.get_place_detail(session, building_id, place_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Place not found")

    # 상세는 시트를 열 때마다 요청되고 내용은 재시드 전까지 바뀌지 않는다.
    # 직렬화된 본문에서 ETag를 뽑으므로 추가 쿼리가 없다.
    #
    # `exclude_none`이 있어야 계약 4-2 규칙 1이 HTTP 경계까지 지켜진다. 조립 단계는
    # 값이 없는 선택 키를 이미 빼고 있는데, DTO가 직렬화하면서 `"price": null`로
    # 도로 채워 넣는다. 그러면 클라이언트가 "없다"와 "있는데 비었다"를 구분하는
    # 분기를 갖게 되고, 그 분기가 카드마다 다른 높이로 새어 나온다.
    body = PlaceDetailResponse.model_validate(result).model_dump_json(exclude_none=True)
    etag = f'"{hashlib.blake2b(body.encode("utf-8"), digest_size=16).hexdigest()}"'
    headers = cache_headers(etag, settings.tile_cache_max_age)

    if etag_matches(if_none_match, etag):
        return Response(status_code=304, headers=headers)

    return Response(content=body, media_type="application/json", headers=headers)


# 층 지도 데이터. Flutter 지도 화면이 footprint/매장 폴리곤/POI를 그리는 데 사용.
@router.get(
    "/{building_id}/floors/{floor_name}",
    response_model=FloorMapResponse,
)
def get_floor_map(
    building_id: str,
    floor_name: str,
    session: Session = Depends(get_db),
    if_none_match: str | None = Header(default=None),
):
    result = building_queries.get_floor_map(session, building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")

    # 층 응답은 층을 전환할 때마다 요청되는데 내용은 재시드 전까지 바뀌지 않는다.
    # 같은 파일의 타일·상세 엔드포인트처럼 짧은 max-age + ETag 재검증을 붙여
    # 재방문을 304(본문 없음)로 끝낸다. ETag는 직렬화된 본문에서 뽑으므로 추가
    # 쿼리가 없다. 상세(get_place_detail)와 달리 exclude_none을 주지 않는 이유:
    # 이 응답은 지금까지 FastAPI 기본 직렬화(None 키 포함)로 나갔고, 클라이언트
    # 모델이 그 형태를 소비 중이라 본문 계약을 그대로 유지한다.
    body = FloorMapResponse.model_validate(result).model_dump_json()
    etag = f'"{hashlib.blake2b(body.encode("utf-8"), digest_size=16).hexdigest()}"'
    headers = cache_headers(etag, settings.tile_cache_max_age)

    if etag_matches(if_none_match, etag):
        return Response(status_code=304, headers=headers)

    return Response(content=body, media_type="application/json", headers=headers)


# 층 지도 벡터 타일(MVT). MapLibre GL의 벡터 타일 소스가 z/x/y로 호출한다.
@router.get("/{building_id}/floors/{floor_name}/tiles/{z}/{x}/{y}.mvt")
def get_floor_tile(
    building_id: str,
    floor_name: str,
    z: int,
    x: int,
    y: int,
    session: Session = Depends(get_db),
    if_none_match: str | None = Header(default=None),
    v: str | None = None,
):
    try:
        tile_bytes = tile_queries.render_floor_tile(session, building_id, floor_name, z, x, y)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    if tile_bytes is None:
        raise HTTPException(status_code=404, detail="Floor not found")

    # 같은 타일을 여러 번 요청하는 것은 MapLibre의 정상 동작이다(줌 전환·층
    # 재방문·부모 타일 프리페치). 캐시 헤더가 없으면 그 전부가 서버까지 온다.
    # ETag는 이미 만들어진 바이트에서 뽑으므로 추가 쿼리가 없다.
    etag = f'"{hashlib.blake2b(tile_bytes, digest_size=16).hexdigest()}"'

    # `?v=`가 붙어 있으면 URL이 곧 버전이다(값은 /buildings/{id}의 tile_revision).
    # 내용이 바뀌면 클라이언트가 새 주소로 오므로 길게 잡고 immutable을 준다 —
    # 재검증조차 안 나가 층을 오갈 때의 304 왕복이 사라진다. 값 자체는 검사하지
    # 않는다. 서버가 아는 것은 "이 주소로 온 바이트"뿐이고, 낡은 v로 온 요청은
    # 낡은 주소에 현재 내용이 담길 뿐 다음 실행에서 새 주소로 갈아탄다.
    if v:
        headers = cache_headers(etag, settings.tile_versioned_cache_max_age, immutable=True)
    else:
        headers = cache_headers(etag, settings.tile_cache_max_age)

    if etag_matches(if_none_match, etag):
        return Response(status_code=304, headers=headers)

    return Response(
        content=tile_bytes,
        media_type="application/vnd.mapbox-vector-tile",
        headers=headers,
    )


# 층 길찾기 그래프. 클라이언트/서버 경로 탐색의 입력.
@router.get(
    "/{building_id}/floors/{floor_name}/graph",
    response_model=FloorGraphResponse,
)
def get_floor_graph(
    building_id: str,
    floor_name: str,
    session: Session = Depends(get_db),
):
    result = building_queries.get_floor_graph(session, building_id, floor_name)
    if result is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    return result
