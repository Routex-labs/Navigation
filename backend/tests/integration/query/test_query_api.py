"""자연어 질의 HTTP API 통합 테스트 (합성 픽스처 test-tower).

1F/2F에 각각 가게A(입구 노드 있음)·가게B가 있다.
"""

import pytest

from app.repositories import query_search
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


# 한 곳을 지목할 수 없는 질의는 임의의 1건으로 확정하지 않는다.
#
# 회귀 대상: 실데이터에서 "명품"(서로 다른 이름 42건)·"레스토랑"(57건)이 몽클레르·
# 데이릿 한 건으로 고정됐다. 클라이언트는 /query/destination이 성공하면 /query/ai를
# 부르지 않으므로(search_panel.dart), 카테고리성 질의는 목록을 볼 기회가 없었다.
# 여기서는 픽스처의 가게A·가게B가 같은 이유로 걸린다(이름 부분 일치 2건).
def test_여러_이름이_걸리면_임의로_확정하지_않고_ambiguous다(api_client):
    payload = {"text": "가게", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ambiguous"
    # match=null이라야 클라이언트가 빈 결과로 파싱해 /query/ai로 이어 간다.
    assert body["match"] is None


# 위 ambiguous가 실제로 목록으로 이어지는지 — 클라이언트가 타는 경로 그대로.
def test_ambiguous로_비운_질의는_탐색에서_여러_후보가_된다(api_client):
    payload = {"text": "가게", "building_id": BUILDING_ID}

    direct = api_client.post("/query/destination", json=payload).json()
    discovery = api_client.post("/query/ai", json=payload).json()

    assert direct["match"] is None
    assert discovery["mode"] == "results"
    assert {match["name"] for match in discovery["matches"]} == {"가게A", "가게B"}


# 이름이 하나뿐이면 예전처럼 바로 1건이다 — 같은 이름이 여러 층에 있어도 한 대상이다.
def test_이름이_하나면_여러_층에_있어도_direct_1건이다(api_client):
    payload = {"text": "가게A", "building_id": BUILDING_ID}

    response = api_client.post("/query/destination", json=payload)

    body = response.json()
    assert body["status"] in ("ok", "ok_no_route")
    assert body["match"]["name"] == "가게A"


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


@pytest.mark.parametrize("path", ["/query/destination", "/query/info", "/query/ai"])
@pytest.mark.parametrize("text", ["   ", "\t", "\n  "])
def test_공백뿐인_질의는_모든_엔드포인트에서_422다(api_client, path, text):
    response = api_client.post(path, json={"text": text, "building_id": BUILDING_ID})

    assert response.status_code == 422


@pytest.mark.parametrize("path", ["/query/destination", "/query/info", "/query/ai"])
def test_질의가_200자를_넘으면_모든_엔드포인트에서_422다(api_client, path):
    response = api_client.post(
        path,
        json={"text": "가" * 201, "building_id": BUILDING_ID},
    )

    assert response.status_code == 422


_PUNCTUATED = ["가게A?", "가게A 어디야?", "가게A 어디야!", "가게A 어디야.", "가게A 어디야,"]


@pytest.mark.parametrize("path", ["/query/destination", "/query/info"])
@pytest.mark.parametrize("text", _PUNCTUATED)
def test_문장끝_구두점이_붙어도_단일목적지_계약에서_매칭된다(api_client, path, text):
    response = api_client.post(path, json={"text": text, "building_id": BUILDING_ID})

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["match"]["name"] == "가게A"


# /query/ai는 탐색 계약(mode/matches)이라 status/match가 아니다. 구두점 처리는 같은
# 경량 정규화를 쓰므로 여기서도 동일하게 direct 1건이 나와야 한다.
@pytest.mark.parametrize("text", _PUNCTUATED)
def test_문장끝_구두점이_붙어도_탐색은_direct_1건이다(api_client, text):
    response = api_client.post("/query/ai", json={"text": text, "building_id": BUILDING_ID})

    assert response.status_code == 200
    body = response.json()
    assert body["mode"] == "direct"
    assert [match["name"] for match in body["matches"]] == ["가게A"]


def test_공백_검증은_통과한_질의의_원문을_보존한다(api_client):
    text = "  가게A  "
    response = api_client.post(
        "/query/destination",
        json={"text": text, "building_id": BUILDING_ID},
    )

    assert response.status_code == 200
    assert response.json()["query"] == text


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


# --- /query/ai 탐색 계약 (conversational-discovery.md 8-3절) ---
# 응답은 {mode, query, question, options, matches}다. destination의 status/match가 아니다.


# 정확한 이름은 되묻지 않고 바로 1건(direct) — 임베딩·torch 없이 경량 1차로 확정된다.
def test_ai_질의가_정확한_이름을_direct_1건으로_확정한다(api_client):
    payload = {"text": "가게A", "building_id": BUILDING_ID}

    response = api_client.post("/query/ai", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["mode"] == "direct"
    assert body["query"] == "가게A"
    assert body["question"] is None
    assert body["options"] == []
    assert len(body["matches"]) == 1
    match = body["matches"][0]
    assert match["name"] == "가게A"
    assert match["entrance_node_id"]  # 경로용 노드가 채워져 있어야 한다
    assert match["floor_name"] in ("1F", "2F")
    # 근거 태그가 없으면 이유를 만들지 않는다(추측 금지, 2절).
    assert match["matched_facets"] == {}
    assert match["reason"] is None


# 서로 다른 이름이 여럿 걸리는 부분 일치는 확정하지 않고 여러 후보를 준다.
def test_ai_질의가_여러_후보를_results로_반환한다(api_client):
    payload = {"text": "가게", "building_id": BUILDING_ID}

    response = api_client.post("/query/ai", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["mode"] == "results"
    names = [match["name"] for match in body["matches"]]
    assert set(names) == {"가게A", "가게B"}
    assert len(names) == len(set(names))  # 같은 이름이 층만 달리해 반복되지 않는다
    assert len(body["matches"]) <= 5


def test_ai_전체_보기_wire_필드를_서비스까지_전달한다(api_client, monkeypatch):
    captured = {}
    original_discover = query_search.discover

    def spy(*args, **kwargs):
        captured["show_all"] = kwargs["show_all"]
        return original_discover(*args, **kwargs)

    monkeypatch.setattr(query_search, "discover", spy)

    response = api_client.post(
        "/query/ai",
        json={
            "text": "가게",
            "building_id": BUILDING_ID,
            "selected_facets": {},
            "show_all": True,
        },
    )

    assert response.status_code == 200
    assert response.json()["mode"] == "results"
    assert captured == {"show_all": True}


# 태그가 붙지 않은 매장에 selected_facets를 걸면 좁혀지지 않는다 — 막다른 흐름 대신
# 선택을 해제하고 전체 후보를 보여준다(2절).
def test_ai_질의_선택이_후보를_0건으로_만들면_전체_결과로_되돌린다(api_client):
    payload = {
        "text": "가게",
        "building_id": BUILDING_ID,
        "selected_facets": {"styles": ["스포츠"]},
    }

    response = api_client.post("/query/ai", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["mode"] == "results"
    assert {match["name"] for match in body["matches"]} == {"가게A", "가게B"}


def test_ai_질의_매칭이_없으면_no_match다(api_client, monkeypatch):
    from app.repositories import query_semantic

    # 임베딩 2차는 "임계값 미달"로 흉내 낸다 — degraded가 아니라 no_match여야 한다.
    monkeypatch.setattr(
        query_semantic,
        "search_many",
        lambda *a, **k: query_semantic.SemanticResults(query_semantic.SemanticReason.BELOW_THRESHOLD),
    )

    response = api_client.post("/query/ai", json={"text": "존재하지않는가게", "building_id": BUILDING_ID})

    assert response.status_code == 200
    body = response.json()
    assert body["mode"] == "no_match"
    assert body["matches"] == []


# AI 질의도 요청 검증은 destination과 같다 — 빈 질의는 422.
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

    by_name = api_client.post("/query/destination", json={**base, "current_floor_id": FLOOR_NAME}).json()
    by_id = api_client.post("/query/destination", json={**base, "current_floor_id": FLOOR_ID}).json()

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
