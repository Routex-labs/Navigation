"""/query/ai 요청 DTO 계약 테스트."""

from app.routers.query import AiRequest


def test_ai_request_전체_보기는_기본적으로_꺼져_있다():
    request = AiRequest(text="패션", building_id="test-tower")

    assert request.show_all is False


def test_ai_request_전체_보기는_snake_case_필드를_받는다():
    request = AiRequest(
        text="패션",
        building_id="test-tower",
        selected_facets={},
        show_all=True,
    )

    assert request.show_all is True
