"""그래프 응답 DTO의 NaN·Infinity·음수 비용 거부 검증.

검증 기준:
    NaN, ±Infinity, 음수 거리/비용은 응답 모델 검증에서 거부된다 — 오염된 값이
    API 응답으로 새어 나가 클라이언트 파서를 깨거나 경로 탐색을 오염시키지 못한다.
"""

from __future__ import annotations

import math

import pytest
from pydantic import ValidationError

from app.dto.route import GraphEdgeResponse, GraphNodeResponse


def _edge(**overrides):
    payload = dict(
        id="e1",
        **{"from": "n1", "to": "n2"},
        length_m=1.0,
        cost_m=1.0,
        bidirectional=True,
        geometry_local_m=[],
    )
    payload.update(overrides)
    return GraphEdgeResponse.model_validate(payload)


def test_정상_간선은_통과한다():
    edge = _edge()
    assert edge.length_m == 1.0


@pytest.mark.parametrize("bad", [math.nan, math.inf, -math.inf])
def test_거리가_NaN이나_Infinity면_거부된다(bad):
    with pytest.raises(ValidationError):
        _edge(length_m=bad)


@pytest.mark.parametrize("bad", [math.nan, math.inf, -math.inf])
def test_비용이_NaN이나_Infinity면_거부된다(bad):
    with pytest.raises(ValidationError):
        _edge(cost_m=bad)


def test_음수_거리는_거부된다():
    with pytest.raises(ValidationError):
        _edge(length_m=-0.1)


def test_음수_비용은_거부된다():
    with pytest.raises(ValidationError):
        _edge(cost_m=-0.1)


def test_노드_좌표가_NaN이면_거부된다():
    with pytest.raises(ValidationError):
        GraphNodeResponse.model_validate(
            {"id": "n1", "type": "junction", "name": None, "x_m": math.nan, "y_m": 0.0, "lat": None, "lng": None}
        )
