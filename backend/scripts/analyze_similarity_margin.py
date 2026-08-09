"""의미 검색의 채택 규칙 후보를 같은 세트로 비교한다.

`backend/`에서 실행:
    python -m scripts.seed.reset_and_seed
    python -m scripts.analyze_similarity_margin --out margin.json

## 왜 필요한가

현재 채택 규칙은 **절대 임계값 하나**다(`query_semantic.SIMILARITY_THRESHOLD`). FAISS.md
11-1은 이 값을 더 내리지 못하는 이유로 "유효 질의 최하단과 무의미 질의의 간격이 0.006뿐"을
들었고, 대안으로 4번 항목에 "절대 임계값 대신 top1-top2 간격 등으로 무의미 질의를
거른다"를 남겨 두었다. 이 스크립트는 그 대안을 **실측으로 채점**한다.

## 무엇을 재는가

`search_many()`는 임계값 미달에서 잘라내므로 원점수를 볼 수 없다. 여기서는 인덱스를 직접
조회해 **임계값과 무관한 상위 K 원점수**를 받고, 그 위에서 규칙 후보를 적용한다.

- A. 절대: `top1 >= T`  (현행)
- B. 상대(2위 대비): `top1 - top2 >= d`
- C. 결합: `top1 >= T` 이면서 `top1 - top2 >= d`
- D. 꼬리 대비: `top1 - mean(top2..topK) >= g`
- E. 표준화: `(top1 - mean(topK)) / std(topK) >= z`

## 판정 기준

**부정 질의 통과 0건이 하드 제약이다.** 길찾기에서는 "틀린 매장 안내"가 "다시 말해
주세요"보다 나쁘다(FAISS.md 11-1). 이 제약을 지키는 규칙들 중에서 긍정 재현율이 가장
높은 것을 고른다. 제약을 어기면 재현율이 아무리 높아도 후보에서 제외한다.

여기서 재는 것은 **의미 검색 단계 단독**이다. 경량 1차가 확정하는 질의(정확 상호명 등)는
이 규칙의 영향을 받지 않으므로, 실제 사용자 체감 변화는 `routes_semantic` 부분집합에서만
일어난다. 그 수도 함께 출력한다.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path
from typing import Any

from app.core.database import SessionLocal
from app.repositories import query_search, query_semantic
from scripts.evaluate_query_hybrid import (
    BUILDING_ID,
    DEFAULT_SET_PATH,
    EvalQuery,
    load_queries,
)

# 규칙 비교에 쓸 상위 후보 수. 운영의 _TOP_K(10)와 같은 깊이를 본다.
TOP_K = 10


def _raw_scores(session: Any, queries: list[EvalQuery]) -> list[dict[str, Any]]:
    """질의별 상위 K 원점수를 임계값 없이 수집한다.

    `search_many()`를 쓰지 않는 이유는 모듈 docstring에 적었다 — 그 함수는 임계값
    미달에서 break하므로 "미달 후보가 얼마나 낮았는지"를 애초에 돌려주지 않는다.
    """
    model = query_semantic._get_model()
    if model is None:
        raise SystemExit("임베딩 모델을 로드하지 못했다. 이 분석은 모델 없이 돌 수 없다.")
    got = query_semantic._get_index(session, BUILDING_ID)
    if got is None:
        raise SystemExit(f"{BUILDING_ID} 인덱스를 만들지 못했다(시드 여부 확인).")
    index, store_ids = got
    rows = {store.id: (store, floor) for store, floor in query_search._load_stores(session, BUILDING_ID)}
    light_rows = query_search._load_stores(session, BUILDING_ID)

    collected: list[dict[str, Any]] = []
    for item in queries:
        vector = query_semantic._encode(model, [item.query])
        scores, positions = index.search(vector, min(TOP_K, index.ntotal))
        candidates: list[dict[str, Any]] = []
        for score, position in zip(scores[0], positions[0]):
            if position < 0:
                continue
            pair = rows.get(store_ids[position])
            if pair is None:
                continue
            store, _floor = pair
            candidates.append(
                {
                    "score": float(score),
                    "name": store.name,
                    "document": query_semantic._document_text(store),
                    "subcategory": store.subcategory,
                }
            )
        light = query_search._rank_with_candidate(light_rows, item.query)
        collected.append(
            {
                "id": item.id,
                "class": item.cls,
                "origin": item.origin,
                "query": item.query,
                "expect": item.expect,
                "is_negative": item.is_negative,
                # 경량 1차가 확정하는 질의는 채택 규칙을 바꿔도 답이 그대로다.
                "light_confident": query_search._is_confident_light_match(light),
                "candidates": candidates,
            }
        )
    return collected


def _top1_is_correct(row: dict[str, Any]) -> bool:
    """상위 1건이 기대 패턴을 만족하는가. 규칙이 채택했을 때 정답인지의 판단이다."""
    if row["is_negative"] or not row["candidates"]:
        return False
    return re.search(row["expect"], row["candidates"][0]["document"], re.IGNORECASE) is not None


def _features(row: dict[str, Any]) -> dict[str, float] | None:
    """규칙들이 공통으로 쓰는 파생값. 후보가 2건 미만이면 상대 규칙을 못 쓴다."""
    scores = [candidate["score"] for candidate in row["candidates"]]
    if not scores:
        return None
    top1 = scores[0]
    tail = scores[1:]
    if not tail:
        return {"top1": top1, "gap2": top1, "gap_tail": top1, "z": 0.0}
    spread = statistics.pstdev(scores)
    return {
        "top1": top1,
        "gap2": top1 - scores[1],
        "gap_tail": top1 - statistics.fmean(tail),
        "z": (top1 - statistics.fmean(scores)) / spread if spread > 1e-9 else 0.0,
    }


def _score_rule(rows: list[dict[str, Any]], accepts) -> dict[str, Any]:
    """규칙 하나를 세트 전체에 적용해 채점한다.

    - `false_positives`: 부정 질의를 채택한 건수. 0이 아니면 그 규칙은 탈락이다.
    - `recall`: 긍정 질의 중 "채택했고 상위 1건이 정답"인 건수.
    - `wrong_accepts`: 채택했지만 상위 1건이 오답인 긍정 건수(자신 있게 틀리는 행).
    """
    false_positives: list[str] = []
    recall = 0
    wrong_accepts: list[str] = []
    positives = 0
    semantic_recall = 0
    semantic_positives = 0
    for row in rows:
        features = _features(row)
        accepted = features is not None and accepts(features)
        if row["is_negative"]:
            if accepted:
                false_positives.append(f"{row['query']}→{row['candidates'][0]['name']}")
            continue
        positives += 1
        correct = _top1_is_correct(row)
        if not row["light_confident"]:
            semantic_positives += 1
        if accepted and correct:
            recall += 1
            if not row["light_confident"]:
                semantic_recall += 1
        elif accepted:
            wrong_accepts.append(f"{row['query']}→{row['candidates'][0]['name']}")
    return {
        "false_positives": len(false_positives),
        "false_positive_examples": false_positives[:6],
        "recall": recall,
        "positives": positives,
        "wrong_accepts": len(wrong_accepts),
        "wrong_accept_examples": wrong_accepts[:6],
        "semantic_recall": semantic_recall,
        "semantic_positives": semantic_positives,
    }


def _rules() -> list[tuple[str, Any]]:
    """비교할 규칙 후보. 이름에 파라미터를 박아 표에서 바로 읽히게 한다."""
    rules: list[tuple[str, Any]] = []
    for threshold in (0.44, 0.46, 0.48, 0.50, 0.52, 0.54):
        rules.append((f"A 절대 top1>={threshold:.2f}", lambda f, t=threshold: f["top1"] >= t))
    for gap in (0.01, 0.02, 0.03, 0.05, 0.08):
        rules.append((f"B 상대 gap2>={gap:.2f}", lambda f, g=gap: f["gap2"] >= g))
    for threshold in (0.42, 0.44, 0.46):
        for gap in (0.01, 0.02, 0.03):
            rules.append(
                (
                    f"C 결합 top1>={threshold:.2f}&gap2>={gap:.2f}",
                    lambda f, t=threshold, g=gap: f["top1"] >= t and f["gap2"] >= g,
                )
            )
    for threshold in (0.42, 0.44, 0.46):
        for gap in (0.04, 0.06, 0.08):
            rules.append(
                (
                    f"D 꼬리 top1>={threshold:.2f}&tail>={gap:.2f}",
                    lambda f, t=threshold, g=gap: f["top1"] >= t and f["gap_tail"] >= g,
                )
            )
    for threshold in (0.42, 0.44, 0.46):
        for z in (1.5, 2.0, 2.5):
            rules.append(
                (
                    f"E 표준화 top1>={threshold:.2f}&z>={z:.1f}",
                    lambda f, t=threshold, zz=z: f["top1"] >= t and f["z"] >= zz,
                )
            )
    return rules


def _parking_share(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """상위 후보에 주차 구역이 얼마나 끼는지.

    이 건물의 인덱스 1640건 중 787건(48%)이 주차 구역이고 문서 텍스트가 서로 거의 같다.
    거의 같은 문서가 절반이면 무의미 질의의 상위 점수가 그 덩어리에서 결정될 수 있어,
    임계값 마진을 논하기 전에 실제로 끼어드는지를 먼저 본다.
    """
    occupied = 0
    top1 = 0
    total_slots = 0
    for row in rows:
        for rank, candidate in enumerate(row["candidates"]):
            total_slots += 1
            if candidate["subcategory"] == "주차":
                occupied += 1
                if rank == 0:
                    top1 += 1
    return {
        "top_k_slots": total_slots,
        "parking_slots": occupied,
        "parking_top1": top1,
    }


def analyze(set_path: Path) -> dict[str, Any]:
    queries, meta = load_queries(set_path)
    session = SessionLocal()
    try:
        query_semantic.reset_indexes()
        rows = _raw_scores(session, queries)
    finally:
        session.close()

    scored = [{"rule": name, **_score_rule(rows, accepts)} for name, accepts in _rules()]
    return {
        "building_id": BUILDING_ID,
        "set": {"path": str(set_path), "version": meta.get("version"), "count": len(queries)},
        "current_threshold": query_semantic.SIMILARITY_THRESHOLD,
        "top_k": TOP_K,
        "parking": _parking_share(rows),
        "rules": scored,
        "rows": [
            {
                "id": row["id"],
                "class": row["class"],
                "query": row["query"],
                "is_negative": row["is_negative"],
                "light_confident": row["light_confident"],
                "top1_correct": _top1_is_correct(row),
                "top1_name": row["candidates"][0]["name"] if row["candidates"] else None,
                **{key: round(value, 4) for key, value in (_features(row) or {}).items()},
            }
            for row in rows
        ],
    }


def _rule_table(report: dict[str, Any]) -> str:
    """부정 통과 0건인 규칙을 먼저, 재현율 높은 순으로 읽히게 정렬한다."""
    rules = sorted(
        report["rules"],
        key=lambda r: (r["false_positives"] > 0, -r["recall"], r["wrong_accepts"]),
    )
    lines = [
        "규칙 후보 비교 (부정 통과 0건이 하드 제약 — 어기면 탈락)",
        "| 규칙 | 부정통과 | 긍정정답 | 오채택 | 의미경로 정답 |",
        "|---|---|---|---|---|",
    ]
    for rule in rules:
        verdict = "" if rule["false_positives"] == 0 else " ← 탈락"
        lines.append(
            "| {rule}{verdict} | {fp} | {recall}/{positives} | {wrong} | {sr}/{sp} |".format(
                rule=rule["rule"],
                verdict=verdict,
                fp=rule["false_positives"],
                recall=rule["recall"],
                positives=rule["positives"],
                wrong=rule["wrong_accepts"],
                sr=rule["semantic_recall"],
                sp=rule["semantic_positives"],
            )
        )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="의미 검색 채택 규칙 비교")
    parser.add_argument("--set", type=Path, default=DEFAULT_SET_PATH, help="질의 세트 JSON 경로")
    parser.add_argument("--out", type=Path, help="결과 JSON을 저장할 경로")
    args = parser.parse_args()

    report = analyze(args.set)
    parking = report["parking"]
    print(
        "주차 구역이 상위 {k}건 슬롯 {slots}칸 중 {occupied}칸, 1위는 {top1}건".format(
            k=report["top_k"],
            slots=parking["top_k_slots"],
            occupied=parking["parking_slots"],
            top1=parking["parking_top1"],
        )
    )
    print()
    print(_rule_table(report))

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n결과 저장: {args.out}")


if __name__ == "__main__":
    main()
