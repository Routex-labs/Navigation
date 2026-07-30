"""매장 상세 HTTP API 통합 테스트.

합성 픽스처(test-tower) 기준. 1F/2F에 각각 가게A(패션·여성패션)·가게B(분류 없음)가 있다.

이 테스트가 지키려는 것은 "값이 잘 나온다"가 아니라 **표시할 데이터가 하나도 없는
상태에서도 계약이 성립한다**는 것이다. 오버레이가 아직 한 건도 없는 상태로 API가
먼저 서고, 클라이언트 작업이 데이터를 기다리지 않는 것이 이 Wave의 목적이다.
"""

from tests.conftest import BUILDING_ID, REAL_BUILDING_ID


# 오버레이가 없어도 200 + 코어 필드가 전부 채워져야 한다.
# 여기서 404나 빈 응답을 주면 클라이언트가 "정보 없음" 화면을 따로 만들어야 하고,
# 그것이 설계가 피하려는 빈 껍데기 상세다.
def test_오버레이가_없어도_코어를_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/places/shop-a-1f")

    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "store"
    assert body["id"] == "shop-a-1f"
    assert body["name"] == "가게A"
    assert body["subtitle"] == "1F · 여성패션"
    assert body["category"] == "패션"
    assert body["location"]["floor_label"] == "1F"
    assert body["location"]["building_id"] == BUILDING_ID
    assert body["provenance"]["source"] == "studio"


# 입구 노드가 있으면 길찾기 액션이 붙는다.
def test_입구_노드가_있으면_길찾기_액션이_붙는다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/places/shop-a-1f")

    actions = {action["type"] for action in response.json()["actions"]}
    assert "directions" in actions


# 폴리곤이 있으면 map 섹션이 붙고, 그 외 섹션은 오버레이가 없으므로 나오지 않는다.
# "빈 섹션을 만들지 않는다"는 규칙을 응답으로 고정한다.
def test_오버레이가_없으면_파생_섹션만_남는다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/places/shop-a-1f")

    types = [section["type"] for section in response.json()["sections"]]
    assert types == ["map"]


# 없는 매장은 404. 존재하지 않는 것과 상세가 없는 것을 구분한다.
def test_없는_매장은_404다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/places/no-such-store")

    assert response.status_code == 404


# 다른 건물의 매장 id로는 열리지 않는다. 열리면 층 라벨·길찾기가 전부 어긋난다.
def test_다른_건물의_매장은_404다(api_client):
    response = api_client.get(f"/buildings/no-such-building/places/shop-a-1f")

    assert response.status_code == 404


# 같은 요청 두 번이면 두 번째는 304. 시트를 여닫을 때마다 본문을 다시 보내지 않는다.
def test_같은_요청은_304로_재검증된다(api_client):
    first = api_client.get(f"/buildings/{BUILDING_ID}/places/shop-a-1f")
    etag = first.headers["etag"]

    second = api_client.get(
        f"/buildings/{BUILDING_ID}/places/shop-a-1f",
        headers={"If-None-Match": etag},
    )

    assert second.status_code == 304
    assert second.headers["etag"] == etag


# 층 지도 응답은 이번 변경으로 달라지면 안 된다. 상세를 층 응답에 합치면
# 한 층 최대 240건의 상세가 지도 첫 렌더를 막는다.
def test_층_지도_응답에_상세가_섞이지_않는다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/1F")

    assert response.status_code == 200
    store = response.json()["stores"][0]
    assert "sections" not in store
    assert "provenance" not in store


# --- 실데이터 스모크 -----------------------------------------------------
# 값은 편집으로 계속 바뀌므로 단언하지 않고, 분류 규칙이 실제 데이터에서
# 의도대로 갈리는지만 본다.


# 주차구역·에스컬레이터·엘리베이터(1,007건)는 상세를 열지 않는 kind로 내려간다.
# 404가 아니라 excluded인 이유: 클라이언트가 id 규칙을 몰라도 kind만 보고
# 시트를 열지 말지 정할 수 있어야 한다.
def test_실데이터_주차구역은_excluded로_내려간다(real_api_client, real_db_session):
    from sqlalchemy import select

    from app.models import Floor, Store

    parking = real_db_session.scalars(
        select(Store)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == REAL_BUILDING_ID, Store.subcategory == "주차")
        .limit(1)
    ).one_or_none()
    assert parking is not None, "실데이터에 주차구역이 있어야 한다"

    response = real_api_client.get(
        f"/buildings/{REAL_BUILDING_ID}/places/{parking.id}"
    )

    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "excluded"
    assert body["sections"] == []


# 화장실·락커 같은 위치 안내형 시설은 facility로 갈린다.
def test_실데이터_화장실은_facility로_내려간다(real_api_client, real_db_session):
    from sqlalchemy import select

    from app.models import Floor, Store

    restroom = real_db_session.scalars(
        select(Store)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == REAL_BUILDING_ID, Store.subcategory == "restroom")
        .limit(1)
    ).one_or_none()
    assert restroom is not None, "실데이터에 화장실이 있어야 한다"

    response = real_api_client.get(
        f"/buildings/{REAL_BUILDING_ID}/places/{restroom.id}"
    )

    assert response.status_code == 200
    assert response.json()["kind"] == "facility"
