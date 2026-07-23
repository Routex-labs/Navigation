"""자연어 질의 HTTP API 통합 테스트 (합성 픽스처 test-tower).

1F/2F에 각각 가게A(입구 노드 있음)·가게B가 있다.
"""

from tests.conftest import BUILDING_ID, FLOOR_ID, FLOOR_NAME


# 목적지 질의가 매장 1건과 입구 노드를 반환한다.
def test_목적지_질의가_매장과_입구노드를_반환한다(api_client):
    payload = {"text": "가게A", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["match"]["name"] == "가게A"
    assert body["match"]["entrance_node_id"]  # 경로용 노드가 채워져 있어야 한다
    assert body["match"]["floor_name"] in ("1F", "2F")
    # 지도 표시용 wgs84 좌표가 함께 온다(클라이언트가 지도에 찍을 수 있어야 한다).
    assert body["match"]["centroid_wgs84"]["lat"] is not None
    assert body["match"]["centroid_wgs84"]["lng"] is not None


# 매칭 결과가 없으면 예외가 아니라 200 + no_match다.
def test_매칭_없으면_no_match를_반환한다(api_client):
    payload = {"text": "존재하지않는가게", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "no_match"
    assert body["match"] is None


# 없는 건물은 404.
def test_없는_건물은_404를_반환한다(api_client):
    payload = {"text": "가게A", "building_id": "no-such-building"}

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 404


# 빈 질의는 요청 검증 단계에서 422.
def test_빈_질의는_422를_반환한다(api_client):
    payload = {"text": "", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 422


# 정보 질의는 대표 1건과 대상이 존재하는 층 목록(level 오름차순)을 반환한다.
def test_정보_질의가_존재하는_층_목록을_반환한다(api_client):
    payload = {"text": "가게A", "building_id": BUILDING_ID}

    response = api_client.post("/query/info", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["match"]["name"] == "가게A"
    assert body["floors"] == ["1F", "2F"]  # 가게A는 두 층 모두에 있다


def test_현재_층을_지정하면_그_층의_대상만_반환한다(api_client):
    payload = {
        "text": "가게A",
        "building_id": BUILDING_ID,
        "current_floor_id": FLOOR_ID,
    }

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["match"]["floor_id"] == FLOOR_ID
    assert body["match"]["name"] == "가게A"


def test_현재_층을_지정한_정보_질의는_그_층만_반환한다(api_client):
    payload = {
        "text": "가게A",
        "building_id": BUILDING_ID,
        "current_floor_id": FLOOR_ID,
    }

    response = api_client.post("/query/info", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["match"]["floor_id"] == FLOOR_ID
    assert body["floors"] == ["1F"]


# 정보 질의도 매칭 없으면 no_match.
def test_정보_질의_매칭_없으면_no_match(api_client):
    payload = {"text": "존재하지않는가게", "building_id": BUILDING_ID}

    response = api_client.post("/query/info", json=payload)

    assert response.status_code == 200
    assert response.json()["status"] == "no_match"


# AI 질의도 정확한 이름은 1차 경량 경로로 확정된다(임베딩·torch 없이 동작).
def test_ai_질의가_정확한_이름을_경량으로_확정한다(api_client):
    payload = {"text": "가게A", "building_id": BUILDING_ID}

    response = api_client.post("/query/ai", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["match"]["name"] == "가게A"
    assert body["match"]["entrance_node_id"]  # 경로용 노드가 채워져 있어야 한다


# AI 질의도 응답 계약(status/query/match)은 destination과 같다 — 빈 질의는 422.
def test_ai_질의_빈_텍스트는_422를_반환한다(api_client):
    payload = {"text": "", "building_id": BUILDING_ID}

    response = api_client.post("/query/ai", json=payload)

    assert response.status_code == 422


# 없는 건물은 AI 질의도 404.
def test_ai_질의_없는_건물은_404를_반환한다(api_client):
    payload = {"text": "가게A", "building_id": "no-such-building"}

    response = api_client.post("/query/ai", json=payload)

    assert response.status_code == 404


# 클라이언트는 내부 id가 아니라 사용자가 보는 층 라벨("1F")을 보낸다.
def test_현재_층을_층라벨로_지정해도_그_층의_대상만_반환한다(api_client):
    payload = {
        "text": "가게A",
        "building_id": BUILDING_ID,
        "current_floor_id": FLOOR_NAME,  # "1F" — 내부 id가 아니라 사람이 보는 라벨
    }

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["match"]["floor_id"] == FLOOR_ID
    assert body["match"]["name"] == "가게A"


# 라벨/id 어느 쪽을 보내도 같은 결과여야 한다 — 이 동치가 깨져서 층 검색이 죽었었다.
def test_층라벨과_내부id는_같은_결과를_준다(api_client):
    base = {"text": "가게A", "building_id": BUILDING_ID}

    by_name = api_client.post(
        "/query/destination", json={**base, "current_floor_id": FLOOR_NAME}
    ).json()
    by_id = api_client.post(
        "/query/destination", json={**base, "current_floor_id": FLOOR_ID}
    ).json()

    assert by_name == by_id


# 정보 질의도 층 라벨을 받는다. 다른 층의 동명 매장은 섞이지 않는다.
def test_현재_층을_층라벨로_지정한_정보_질의는_그_층만_반환한다(api_client):
    payload = {
        "text": "가게A",
        "building_id": BUILDING_ID,
        "current_floor_id": FLOOR_NAME,
    }

    response = api_client.post("/query/info", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["floors"] == [FLOOR_NAME]  # 다른 층의 동명 매장은 섞이지 않는다


# 없는 층 라벨은 404가 아니라 no_match다(층 필터는 매칭 범위일 뿐).
def test_없는_층_라벨은_no_match다(api_client):
    payload = {
        "text": "가게A",
        "building_id": BUILDING_ID,
        "current_floor_id": "B99",
    }

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 200
    assert response.json()["status"] == "no_match"
