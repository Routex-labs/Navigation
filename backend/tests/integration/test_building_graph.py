"""건물 전체 그래프 API 통합 테스트 (GET /buildings/{id}/graph).

층별 /graph와 달리 전 층 노드 + 수직 전이 간선을 한 그래프에 담는다.
합성 픽스처(test-tower)는 엘리베이터 4개가 1F↔2F를 잇는다(에스컬레이터는 없음).

검증 기준:
    V4  건물 그래프가 전이 간선+transfer_mode를 포함하고, vertical 정책 필터가 동작한다.
        층별 /graph에는 여전히 전이 간선이 없다(test_floor_graph.py가 별도 단언).
"""

from sqlalchemy import select

from app.models import Floor, Node
from tests.conftest import BUILDING_ID, REAL_BUILDING_ID


def _transfer_edges(body):
    return [edge for edge in body["edges"] if edge.get("transfer_mode")]


# 건물 그래프가 전 층 노드와 수직 전이 간선을 함께 반환한다.
def test_건물_그래프가_전층_노드와_전이간선을_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/graph")

    assert response.status_code == 200
    body = response.json()
    assert body["building"]["id"] == BUILDING_ID
    assert body["vertical"] == "auto"

    # 1F/2F 노드가 모두 실려야 한다(층별 그래프는 한 층만).
    floor_ids = {node["floor_id"] for node in body["nodes"]}
    assert len(floor_ids) == 2, f"두 층 노드가 모두 있어야 한다: {floor_ids}"

    transfers = _transfer_edges(body)
    assert transfers, "수직 전이 간선이 포함돼야 한다"
    assert {edge["transfer_mode"] for edge in transfers} == {"elevator"}
    assert len(transfers) == 4  # 엘리베이터 4개


# 전이 간선의 from/to가 그래프 안에 실존하는 노드를 가리킨다(참조 무결성).
def test_전이간선은_그래프_노드를_가리킨다(api_client):
    body = api_client.get(f"/buildings/{BUILDING_ID}/graph").json()
    node_ids = {node["id"] for node in body["nodes"]}

    for edge in body["edges"]:
        assert edge["from"] in node_ids
        assert edge["to"] in node_ids


# vertical=escalator 정책은 에스컬레이터 전이만 남긴다 — 픽스처엔 없으므로 전이 0.
def test_정책_escalator는_엘리베이터_전이를_제외한다(api_client):
    body = api_client.get(f"/buildings/{BUILDING_ID}/graph", params={"vertical": "escalator"}).json()

    assert body["vertical"] == "escalator"
    assert _transfer_edges(body) == []  # 픽스처엔 에스컬레이터가 없다
    # 층 내부 간선은 정책과 무관하게 남는다.
    assert [edge for edge in body["edges"] if not edge.get("transfer_mode")]


# vertical=elevator 정책은 엘리베이터 전이만 남긴다.
def test_정책_elevator는_엘리베이터_전이만_남긴다(api_client):
    body = api_client.get(f"/buildings/{BUILDING_ID}/graph", params={"vertical": "elevator"}).json()

    transfers = _transfer_edges(body)
    assert transfers
    assert {edge["transfer_mode"] for edge in transfers} == {"elevator"}


# 잘못된 정책 값은 422.
def test_잘못된_vertical_값은_422다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/graph", params={"vertical": "stairs"})
    assert response.status_code == 422


# 없는 건물은 404.
def test_없는_건물_그래프는_404다(api_client):
    response = api_client.get("/buildings/no-such-building/graph")
    assert response.status_code == 404


# 실데이터: 에스컬레이터 전이는 단방향이고 방향이 층 level과 일치한다(불가능 경로 제거).
def test_실데이터_에스컬레이터_전이는_방향을_지킨다(real_api_client, real_db_session):
    body = real_api_client.get(f"/buildings/{REAL_BUILDING_ID}/graph").json()

    # 노드 id -> 층 level. 전이 간선의 from/to가 실제로 위·아래 층을 잇는지 본다.
    level_by_node = dict(
        real_db_session.execute(select(Node.id, Floor.level).join(Floor, Node.floor_id == Floor.id)).all()
    )

    escalators = [e for e in body["edges"] if e.get("transfer_mode") == "escalator"]
    assert escalators, "실데이터에 에스컬레이터 전이가 있어야 한다"
    for edge in escalators:
        assert edge["bidirectional"] is False  # 단방향
        # 같은 층을 잇지 않는다(방향이 층과 일치, 불가능 경로 아님).
        assert level_by_node[edge["from"]] != level_by_node[edge["to"]]


# 응답이 실제 거리(length_m)와 라우팅 비용(cost_m)을 따로 싣는다.
#
# 층 내부 간선은 두 값이 같고, 수직 전이 간선만 갈라진다. 클라이언트는 탐색에 cost_m을,
# 사용자에게 보여 줄 거리에 length_m을 쓴다 — 한 값으로 겸하면 튜닝 비용이 표시 거리로
# 새어 나가 총 거리가 부풀려진다.
def test_그래프_응답이_거리와_비용을_분리해_싣는다(api_client):
    body = api_client.get(f"/buildings/{BUILDING_ID}/graph").json()

    intra = [edge for edge in body["edges"] if edge["transfer_mode"] is None]
    assert intra, "층 내부 간선이 있어야 비교가 성립한다"
    assert all(edge["cost_m"] == edge["length_m"] for edge in intra)

    transfers = _transfer_edges(body)
    assert transfers, "전이 간선이 있어야 분리를 확인할 수 있다"
    # 전이는 비용이 실제 거리보다 크다(층 이동을 함부로 고르지 않게 하는 튜닝값이라).
    assert all(edge["cost_m"] > edge["length_m"] for edge in transfers)


# 전이 간선이 어느 층에서 어느 층으로 가는지 응답에 명시된다.
#
# 이 값과 to 노드가 수직 전이 도착 지점의 단일 원천이다. 클라이언트가 이름·그룹으로
# 도착 노드를 다시 고르면 서버 그래프와 어긋나므로, 계약으로 못박아 둔다.
def test_전이_간선이_출발층과_도착층을_명시한다(api_client):
    body = api_client.get(f"/buildings/{BUILDING_ID}/graph").json()
    node_floor_ids = {node["id"]: node["floor_id"] for node in body["nodes"]}

    transfers = _transfer_edges(body)
    assert transfers

    for edge in transfers:
        # 층이 채워져 있고, 서로 다른 층을 잇는다(같은 층이면 전이가 아니다).
        assert edge["from_floor_id"] is not None
        assert edge["to_floor_id"] is not None
        assert edge["from_floor_id"] != edge["to_floor_id"]
        # 그리고 그 층은 실제 endpoint 노드의 소속 층과 일치한다.
        assert edge["from_floor_id"] == node_floor_ids[edge["from"]]
        assert edge["to_floor_id"] == node_floor_ids[edge["to"]]


# 층 내부 간선은 양 끝이 같은 층이다.
def test_층_내부_간선은_양끝_층이_같다(api_client):
    body = api_client.get(f"/buildings/{BUILDING_ID}/graph").json()

    intra = [edge for edge in body["edges"] if edge["transfer_mode"] is None]
    assert all(edge["from_floor_id"] == edge["to_floor_id"] for edge in intra)


# 응답에 그래프 리비전(체크섬)이 실리고, 같은 요청은 같은 값이다(캐시 무효화 키).
def test_그래프_응답에_안정적인_리비전이_실린다(api_client):
    first = api_client.get(f"/buildings/{BUILDING_ID}/graph").json()
    second = api_client.get(f"/buildings/{BUILDING_ID}/graph").json()

    assert isinstance(first["revision"], str) and first["revision"]
    # 데이터가 그대로면 재요청해도 같은 리비전이어야 캐시가 유효하다.
    assert first["revision"] == second["revision"]


# vertical 정책이 다르면 실리는 간선이 달라지므로 리비전도 달라진다.
def test_정책이_다르면_리비전이_다르다(api_client):
    auto = api_client.get(f"/buildings/{BUILDING_ID}/graph", params={"vertical": "auto"}).json()
    escalator = api_client.get(f"/buildings/{BUILDING_ID}/graph", params={"vertical": "escalator"}).json()

    # 픽스처는 엘리베이터만 있어 escalator 정책은 전이 간선을 뺀다 → 다른 payload, 다른 리비전.
    assert auto["revision"] != escalator["revision"]
