"""그래프 리비전(내용 기반 체크섬).

같은 그래프 → 같은 리비전, 데이터가 바뀌면 → 다른 리비전. 클라이언트·타일 캐시(06번)가
"이 그래프가 그대로인가"를 값 하나로 판단하는 무효화 키로 쓴다.

성질:
  - **순서 무관**: DB 조회 순서가 달라져도(정렬 미지정) 같은 그래프면 같은 값이 나오도록,
    노드·간선을 id로 정렬한 뒤 해싱한다. 안 그러면 재시드마다 캐시가 무의미하게 깨진다.
  - **내용 기반**: 응답에 실리는 필드(좌표·거리·비용·전이 수단·층 등)를 그대로 해싱하므로,
    좌표 한 점만 바뀌어도 리비전이 바뀐다.
  - **정책 반영**: 넘긴 간선 목록 그대로를 해싱한다. vertical 정책으로 간선이 필터된
    건물 그래프는 정책마다 다른 리비전을 갖는다(반환 payload가 실제로 다르므로 옳다).
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from typing import Any


def graph_revision(nodes: Sequence[Mapping[str, Any]], edges: Sequence[Mapping[str, Any]]) -> str:
    """노드·간선 dict 목록에서 16바이트 hex 리비전을 만든다(순서 무관, 내용 기반)."""
    payload = {
        "nodes": sorted(nodes, key=lambda node: node["id"]),
        "edges": sorted(edges, key=lambda edge: edge["id"]),
    }
    # sort_keys로 키 순서까지 고정해, 같은 내용이면 바이트열이 항상 같게 만든다.
    blob = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.blake2b(blob.encode("utf-8"), digest_size=16).hexdigest()
