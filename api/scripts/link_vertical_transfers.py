"""층 간 수직 이동(엘리베이터·에스컬레이터) 노드를 이어 transfer edge를 생성한다.

설계 근거: docs/floorgraph-studio-integration.md (§ 수직 전이, 결정 D7)

Studio 데이터에는 각 층에 elevator/escalator 노드는 있으나 **층을 잇는 엣지가 없다.**
연결 단서는 노드 '이름 규칙'뿐이다.
  - 엘리베이터: ``EV1``·``EV2`` … 같은 번호 = 같은 수직 통로 → 층 간 노드끼리 연결.
  - 에스컬레이터: ``ES{group}-{UP|DN}(TO{n}F|FR{n}F)`` — 그룹·방향이 같고
    두 노드의 (자기 층, 상대 층)이 서로 맞물리면 같은 물리 세그먼트 → 연결.

상대 층이 데이터셋에 없으면(예: 1F의 TO2F/FRB1) 연결 불가로 리포트한다.

실행 (api/ 디렉토리에서):
  python -m scripts.link_vertical_transfers            # 페어링 결과 출력 + JSON 저장
"""

from __future__ import annotations

import json
import re
from itertools import combinations
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
STUDIO_DIR = API_ROOT / "app" / "data" / "studio" / "thehyundai-seoul"
DEFAULT_FLOORS = ["1f", "3f", "4f"]

# 수직 이동 비용(m 환산): dijkstra 가중치용. 층 간격이 클수록 비싸게.
ELEVATOR_COST = lambda gap: 8.0 + 6.0 * gap  # noqa: E731
ESCALATOR_COST = lambda gap: 6.0 + 10.0 * gap  # noqa: E731

_EV_RE = re.compile(r"^EV(\d+)$")
_ES_RE = re.compile(r"^ES(?P<group>[0-9A-Za-z\-]+?)-(?P<dir>UP|DN)\((?P<rel>TO|FR)(?P<floor>B?\d+)F?\)$")


def _scoped(floor_id: str, raw_id: str) -> str:
    """studio_adapter와 동일한 층 스코프 네임스페이싱(D6)."""
    return f"{floor_id}:{raw_id}"


def _floor_num(label: str) -> int | None:
    """'1F'→1, '4F'→4, 'B1'→-1. 파싱 실패 시 None."""
    label = label.upper().strip()
    if label.startswith("B") and label[1:].isdigit():
        return -int(label[1:])
    digits = "".join(ch for ch in label if ch.isdigit())
    return int(digits) if digits else None


def _norm_other_floor(token: str) -> str:
    """에스컬레이터 주석의 상대 층 토큰을 층 라벨로 정규화. '2'→'2F', 'B1'→'B1'."""
    token = token.upper()
    if token.startswith("B"):
        return token
    return f"{token}F"


def _collect_vertical_nodes(floor_codes: list[str]) -> list[dict]:
    """모든 층의 elevator/escalator 노드를 스코프 ID·층 라벨과 함께 수집."""
    collected: list[dict] = []
    for code in floor_codes:
        studio = json.loads((STUDIO_DIR / f"{code}.json").read_text(encoding="utf-8"))
        floor_id = studio["floor"]["id"]
        floor_label = studio["floor"]["name"]
        for node in studio["nodes"]:
            if node.get("type") not in ("elevator", "escalator"):
                continue
            collected.append(
                {
                    "scoped_id": _scoped(floor_id, node["id"]),
                    "raw_id": node["id"],
                    "type": node["type"],
                    "name": (node.get("name") or "").strip(),
                    "floor_label": floor_label,
                    "floor_num": _floor_num(floor_label),
                }
            )
    return collected


def build_transfers(floor_codes: list[str] = DEFAULT_FLOORS) -> dict:
    """수직 노드를 페어링해 transfer edge 목록과 미해결 리포트를 만든다."""
    nodes = _collect_vertical_nodes(floor_codes)
    present_floors = {n["floor_label"] for n in nodes}

    edges: list[dict] = []
    unresolved: list[dict] = []
    seen_pairs: set[frozenset[str]] = set()

    # --- 엘리베이터: EV 번호로 그룹핑 ---
    ev_groups: dict[str, list[dict]] = {}
    for node in nodes:
        if node["type"] != "elevator":
            continue
        match = _EV_RE.match(node["name"])
        if not match:
            unresolved.append({**_slim(node), "reason": "elevator_name_no_number"})
            continue
        ev_groups.setdefault(f"EV{match.group(1)}", []).append(node)

    for group, members in ev_groups.items():
        # 같은 EV 번호 노드들을 층 간 쌍으로 모두 연결(clique).
        for a, b in combinations(members, 2):
            if a["floor_label"] == b["floor_label"]:
                continue
            _add_edge(edges, seen_pairs, a, b, "elevator", group)

    # --- 에스컬레이터: (그룹, 방향, {자기층, 상대층})로 세그먼트 매칭 ---
    seg_index: dict[tuple, list[dict]] = {}
    for node in nodes:
        if node["type"] != "escalator":
            continue
        match = _ES_RE.match(node["name"])
        if not match:
            unresolved.append({**_slim(node), "reason": "escalator_name_unparsed"})
            continue
        other = _norm_other_floor(match.group("floor"))
        if other not in present_floors:
            unresolved.append(
                {**_slim(node), "reason": f"other_floor_absent:{other}"}
            )
            continue
        key = (
            match.group("group"),
            match.group("dir"),
            frozenset({node["floor_label"], other}),
        )
        seg_index.setdefault(key, []).append(node)

    for key, members in seg_index.items():
        floors = {m["floor_label"] for m in members}
        if len(floors) < 2:
            # 상대 층은 존재하지만 그 짝 노드를 못 찾음 → 리포트
            for m in members:
                unresolved.append(
                    {**_slim(m), "reason": f"escalator_pair_missing:{key[0]}-{key[1]}"}
                )
            continue
        for a, b in combinations(members, 2):
            if a["floor_label"] == b["floor_label"]:
                continue
            _add_edge(edges, seen_pairs, a, b, "escalator", key[0])

    return {
        "building_id": "thehyundai-seoul",
        "floors": floor_codes,
        "transfers": edges,
        "unresolved": unresolved,
        "summary": {
            "transfers": len(edges),
            "elevator": sum(1 for e in edges if e["mode"] == "elevator"),
            "escalator": sum(1 for e in edges if e["mode"] == "escalator"),
            "unresolved": len(unresolved),
        },
    }


def _slim(node: dict) -> dict:
    return {"scoped_id": node["scoped_id"], "name": node["name"], "floor": node["floor_label"]}


def _add_edge(edges, seen_pairs, a, b, mode, group) -> None:
    pair = frozenset({a["scoped_id"], b["scoped_id"]})
    if pair in seen_pairs:
        return
    seen_pairs.add(pair)
    gap = abs((a["floor_num"] or 0) - (b["floor_num"] or 0)) or 1
    cost = ELEVATOR_COST(gap) if mode == "elevator" else ESCALATOR_COST(gap)
    lo, hi = sorted([a["scoped_id"], b["scoped_id"]])
    edges.append(
        {
            "id": f"xfer:{mode[:2]}:{lo}__{hi}",
            "from": a["scoped_id"],
            "to": b["scoped_id"],
            "mode": mode,
            "group": group,
            "floors": [a["floor_label"], b["floor_label"]],
            "length_m": round(cost, 3),
            "bidirectional": True,
        }
    )


def main() -> None:
    result = build_transfers()
    out = STUDIO_DIR / "transfers_thehyundai-seoul.json"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    s = result["summary"]
    print(f"transfers={s['transfers']} (EV {s['elevator']} / ES {s['escalator']}) "
          f"unresolved={s['unresolved']} → {out.name}")
    print("--- transfer edges ---")
    for e in result["transfers"]:
        print(f"  [{e['mode'][:2].upper()}] {e['group']:5} {e['floors'][0]}<->{e['floors'][1]}"
              f"  cost={e['length_m']:5}  {e['from']}  <->  {e['to']}")
    print("--- unresolved (연결 못 함) ---")
    for u in result["unresolved"]:
        print(f"  {u['floor']:3} {u['name']:18} {u['reason']}")


if __name__ == "__main__":
    main()
