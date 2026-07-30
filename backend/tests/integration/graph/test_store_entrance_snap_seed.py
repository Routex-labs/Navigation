"""매장 입구 스냅 제한의 시드/회귀 통합 테스트.

검증 기준(05번 완료 기준):
    (1) 연결된 입구는 모두 최대 스냅 거리 안의 노드를 가리킨다(먼 오연결이 없다).
    (2) unresolved 목록의 각 항목은 실제로 임계값을 초과한다.
    (3) 그래프 무결성 검증에 에러가 없다(미연결 입구가 잘못된 경로/참조를 만들지 않는다).
"""

from __future__ import annotations

from math import hypot

from sqlalchemy import select

from app.core.config import settings
from app.graph.integrity import collect_graph_data, validate_graph
from app.models import Node, Store
from scripts.seed.studio_adapter import collect_unresolved_store_entrances


def test_연결된_입구는_모두_임계값_안의_노드를_가리킨다(real_db_session):
    max_m = settings.store_entrance_snap_max_m
    node_pos = {node.id: (node.x_m, node.y_m) for node in real_db_session.scalars(select(Node)).all()}

    stores = real_db_session.scalars(select(Store).where(Store.entrance_node_id.isnot(None))).all()
    assert stores, "연결된 입구가 있어야 비교가 성립한다"

    for store in stores:
        if store.entrance_x_m is None or store.entrance_y_m is None:
            continue  # 원본이 노드를 직접 지정한 경우(스냅 거리 개념 없음)
        nx, ny = node_pos[store.entrance_node_id]
        distance = hypot(nx - store.entrance_x_m, ny - store.entrance_y_m)
        assert distance <= max_m + 1e-6, f"매장 {store.id}의 입구가 {distance:.1f}m로 최대 {max_m}m 초과"


def test_unresolved_목록은_모두_임계값을_초과한다(real_db_session):
    max_m = settings.store_entrance_snap_max_m
    unresolved = collect_unresolved_store_entrances()

    # 실데이터엔 오연결 후보가 있다(0이면 이 테스트가 공허하다는 의미는 아니지만, 현재는 존재).
    for item in unresolved:
        assert item["distance_m"] is None or item["distance_m"] > max_m
        assert item["max_m"] == max_m
        # 매장 자체는 시드돼 있어야 한다(연결만 안 된 것이지 삭제된 게 아니다).
        assert real_db_session.get(Store, item["store_id"]) is not None


def test_미연결_입구가_그래프_무결성을_깨지_않는다(real_db_session):
    report = validate_graph(collect_graph_data(real_db_session))
    assert report.errors == [], [issue.to_dict() for issue in report.errors]
