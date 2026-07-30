"""시드된 그래프가 무결성 검증을 통과하는지 확인하는 통합 테스트.

검증 기준:
    합성 픽스처와 실데이터 모두 검증기에서 에러가 0이어야 한다. 만약 실데이터에
    타 건물 연결·동일 층 전이·NaN 같은 에러가 잡히면 그건 검증기 버그가 아니라
    시드 데이터의 실제 결함이므로, 이 테스트가 그것을 드러낸다.
"""

from __future__ import annotations

from app.graph.integrity import collect_graph_data, validate_graph


def test_합성_픽스처_그래프는_검증을_통과한다(db_session):
    report = validate_graph(collect_graph_data(db_session))
    assert report.ok, report.to_dict()


def test_실데이터_그래프는_검증_에러가_없다(real_db_session):
    report = validate_graph(collect_graph_data(real_db_session))
    # 경고(고립 컴포넌트 등)는 허용하되, 에러는 실제 데이터 결함이므로 0이어야 한다.
    assert report.errors == [], [issue.to_dict() for issue in report.errors]


def test_실데이터_통계가_현실적이다(real_db_session):
    report = validate_graph(collect_graph_data(real_db_session))
    stats = report.stats
    # 여러 층·수백 개 노드·전이 간선이 있어야 한다(정확한 값은 편집으로 바뀌므로 하한만).
    assert stats["buildings"] >= 1
    assert stats["floors"] >= 2
    assert stats["nodes"] > 0
    assert stats["transfer_edges"] > 0
