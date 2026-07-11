"""자연어 질의 HTTP API 계약 테스트."""

from tests.conftest import BUILDING_ID


# 목적지 질의 API가 현재 임시 응답 계약을 유지하는지 검증한다.
def test_목적지_질의의_임시응답을_확인한다(api_client):
    payload = {"text": "구찌 어디야", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None


# 장소 정보 질의 API가 현재 임시 응답 계약을 유지하는지 검증한다.
def test_정보_질의의_임시응답을_확인한다(api_client):
    payload = {"text": "화장실 위치", "building_id": BUILDING_ID}

    response = api_client.post("/query/info", json=payload)

    body = response.json()
    assert response.status_code == 200
    assert body["status"] == "stub"
    assert body["query"] == payload["text"]
    assert body["result"] is None
