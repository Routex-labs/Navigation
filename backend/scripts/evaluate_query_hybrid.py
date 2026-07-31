"""실데이터 29개로 최종 AI 하이브리드 경로와 FAISS 단독 결과를 비교한다.

`backend/`에서 실행:
    python -m scripts.seed.reset_and_seed
    python -m scripts.evaluate_query_hybrid

기대 패턴은 인덱스 문서 텍스트(현재 이름·카테고리·서브카테고리)에 대한 최소 자동 판정이다.
숫자는 회귀 비교용이며, 최종 안내 적합성은 실패 행을 사람이 함께 확인한다.

`--out`으로 결과를 JSON 파일에 남기고 `--baseline`으로 이전 실행과 대조한다.
인덱스 문서에 facet 태그를 붙이는 변경(conversational-discovery.md 7-1)에서
"바꾸기 전 기준선"과 "바꾼 뒤"를 같은 형식으로 비교하기 위한 장치다.

    python -m scripts.evaluate_query_hybrid --out eval_before.json
    python -m scripts.evaluate_query_hybrid --baseline eval_before.json --out eval_after.json
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from time import perf_counter
from typing import Any

from app.core.database import SessionLocal
from app.repositories import query_search, query_semantic

BUILDING_ID = "thehyundai-seoul"

# (label, query, expected) — expected는 매칭 대상 텍스트에 대한 정규식이다.
# 매칭 대상은 `_document_text()`가 만드는 인덱스 문서와 같은 축이라, facet 태그가
# 인덱스 문서에 추가되면 기대 패턴도 facet 값을 그대로 쓸 수 있다(7-1절).
POSITIVE_QUERIES = [
    ("음식", "밥 먹을 곳", "restaurant|식음료|취식"),
    ("음식", "배고픈데 뭐 먹지", "restaurant|식음료"),
    ("분식", "김밥 같은 분식", "restaurant|김밥|분식"),
    ("카페", "커피 마시고 싶어", "커피|카페|restaurant"),
    ("디저트", "디저트랑 케이크", "베이커리|케이크|restaurant"),
    ("뷰티", "화장품 사려고", "화장품"),
    ("뷰티", "향수 보고 싶어", "화장품|향수"),
    ("뷰티", "립스틱 어디", "화장품"),
    ("키즈", "애들 옷", "키즈|아동|유아"),
    ("키즈", "아기 장난감", "토이|완구|키즈"),
    ("슈즈", "신발 파는 데", "슈즈"),
    # "운동화 사고 싶다" → 나이키 라이즈는 W7 착수 시 "facet으로 정당화 가능한 후보"로
    # 지목됐으나, 스타일 값을 신발 증거로 쓰자는 안은 기각한다. 나이키 라이즈의 styles는
    # ["캐주얼"] 하나뿐이다(subcategory=캐주얼·스트리트에서 파생). "캐주얼"은
    # 슈즈 8건 오버레이(지미추·크록스·어그 등)에도 공통으로 붙지만, 캐주얼·스트리트
    # 소분류 자체가 신발이 아닌 의류 매장 대다수를 포함하는 광범위한 값이라 이 겹침은
    # "신발을 판다"는 증거가 아니라 우연한 스타일 값 공유다. 신발 취급 여부를 실제로
    # 판정하는 축은 intents이고, 그 근거는 `resources/store_search_facets/_intents.json`의
    # 사람이 검수한 `신발` 목록이다 — 소분류 규칙(슈즈) + 예외 매장 145건으로 스키마가
    # 확정됐고(conversational-discovery.md 12절) 시드가 이를 매장 facet에 적재한다.
    # 따라서 패턴을 "슈즈|스포츠|캐주얼"로 넓히는 것은 원리 없는 완화이므로 하지 않는다.
    ("슈즈", "운동화 사고 싶다", "슈즈|스포츠"),
    ("패션", "가방 보러 왔어", "잡화|액세서리|명품|가방"),
    ("패션", "남자 정장", "컨템포러리|정장|수트"),
    ("명품", "명품 매장", "명품"),
    ("스포츠", "등산복 아웃도어", "아웃도어|스포츠"),
    ("리빙", "그릇이나 주방용품", "리빙|주방"),
    ("문구", "예쁜 문구류", "문구|팬시"),
    ("시설", "화장실 급해", "restroom|화장실"),
    ("시설", "엘리베이터 어디", "elevator|엘리베이터"),
    ("시설", "에스컬레이터", "escalator|에스컬레이터"),
    ("시설", "현금 뽑을 데", "ATM|현금|은행"),
    ("시설", "짐 맡길 곳", "보관|facility"),
    ("선물", "선물 살 만한 곳", "기프트|선물|facility"),
    ("정확명", "스타벅스", "스타벅스|커피|restaurant"),
]

NEGATIVE_QUERIES = ["asdfqwerzxcv", "ㅋㅋㅋㅋㅋ", "zzzzzzz", "19283746"]


def _match_text(match: dict[str, Any] | None) -> str:
    if match is None:
        return ""
    return " ".join(str(match.get(key) or "") for key in ("name", "category", "subcategory"))


def _semantic_text(hit: tuple[Any, Any, Any] | None) -> str:
    """FAISS가 실제로 임베딩한 문서 텍스트로 판정한다.

    `query_semantic._document_text()`를 그대로 쓰는 이유: 인덱스 문서에 facet이
    추가되면 판정 텍스트도 같이 따라와야 "무엇으로 찾았는가"와 "무엇으로 채점하는가"가
    갈라지지 않는다. 지금은 이름+카테고리+서브카테고리라 이전 판정과 동일하다.
    """
    if hit is None:
        return ""
    _score, store, _floor = hit
    return query_semantic._document_text(store)


def _matches(pattern: str, text: str) -> bool:
    return re.search(pattern, text, re.IGNORECASE) is not None


def _light_top(light: list[tuple[Any, ...]]) -> tuple[int | None, str | None]:
    """경량 1차 최상위의 (tier, 이름). 튜플 폭이 바뀌어도 깨지지 않게 뒤에서 센다.

    `_rank_with_candidate()`의 반환 튜플은 정렬 키가 늘면서 폭이 바뀐 적이 있다
    (…, level, store_id, store, floor). 고정 인덱스로 store를 꺼내면 그때마다
    평가 스크립트가 조용히 엉뚱한 값을 읽거나 AttributeError로 죽는다.
    """
    if not light:
        return None, None
    row = light[0]
    store = row[-2]
    return row[0], store.name


def _semantic_reason(session: Any, text: str) -> tuple[Any, str | None]:
    """의미 검색 결과와 사유. 사유 API가 없는 리비전에서도 동작하게 감싼다."""
    search = getattr(query_semantic, "search", None)
    if search is None:
        return query_semantic.semantic_search(session, BUILDING_ID, text), None
    result = search(session, BUILDING_ID, text)
    reason = getattr(result.reason, "value", str(result.reason))
    return result.hit, reason


def evaluate() -> dict[str, Any]:
    session = SessionLocal()
    timings: dict[str, float] = {}
    try:
        started = perf_counter()
        rows = query_search._load_stores(session, BUILDING_ID)
        query_semantic.reset_indexes()
        timings["load_stores_sec"] = round(perf_counter() - started, 3)
        results = []

        for index, (label, text, expected_pattern) in enumerate(POSITIVE_QUERIES):
            query_started = perf_counter()
            light = query_search._rank_with_candidate(rows, text)
            final = query_search.match_ai_destination(session, BUILDING_ID, text)
            semantic, reason = _semantic_reason(session, text)
            final_match = final["match"]
            light_tier, light_name = _light_top(light)
            elapsed = round(perf_counter() - query_started, 3)
            if index == 0:
                # 첫 질의가 모델 로드 + 인덱스 빌드를 통째로 뒤집어쓴다.
                timings["first_query_sec"] = elapsed
            results.append(
                {
                    "label": label,
                    "query": text,
                    "expected": expected_pattern,
                    "route": ("light" if query_search._is_confident_light_match(light) else "semantic"),
                    "light_tier": light_tier,
                    "light_name": light_name,
                    "final_status": final["status"],
                    "final_name": final_match["name"] if final_match else None,
                    "final_floor": final_match["floor_name"] if final_match else None,
                    "final_pass": _matches(expected_pattern, _match_text(final_match)),
                    "semantic_name": semantic[1].name if semantic else None,
                    "semantic_floor": semantic[2].name if semantic else None,
                    "semantic_score": round(semantic[0], 3) if semantic else None,
                    "semantic_reason": reason,
                    "semantic_pass": _matches(expected_pattern, _semantic_text(semantic)),
                    "elapsed_sec": elapsed,
                }
            )

        for text in NEGATIVE_QUERIES:
            query_started = perf_counter()
            final = query_search.match_ai_destination(session, BUILDING_ID, text)
            semantic, reason = _semantic_reason(session, text)
            results.append(
                {
                    "label": "부정",
                    "query": text,
                    "expected": "(no_match)",
                    "route": "semantic",
                    "light_tier": None,
                    "light_name": None,
                    "final_status": final["status"],
                    "final_name": final["match"]["name"] if final["match"] else None,
                    "final_floor": (final["match"]["floor_name"] if final["match"] else None),
                    "final_pass": final["status"] == "no_match",
                    "semantic_name": semantic[1].name if semantic else None,
                    "semantic_floor": semantic[2].name if semantic else None,
                    "semantic_score": round(semantic[0], 3) if semantic else None,
                    "semantic_reason": reason,
                    "semantic_pass": semantic is None,
                    "elapsed_sec": round(perf_counter() - query_started, 3),
                }
            )

        timings["total_sec"] = round(perf_counter() - started, 3)
        return {
            "building_id": BUILDING_ID,
            "threshold": getattr(query_semantic, "SIMILARITY_THRESHOLD", None),
            "top_k": getattr(query_semantic, "_TOP_K", None),
            "store_count": len(rows),
            "summary": {
                "total": len(results),
                "positive": len(POSITIVE_QUERIES),
                "negative": len(NEGATIVE_QUERIES),
                "final_pass": sum(row["final_pass"] for row in results),
                "semantic_pass": sum(row["semantic_pass"] for row in results),
                "light_routes": sum(row["route"] == "light" for row in results),
                "semantic_routes": sum(row["route"] == "semantic" for row in results),
            },
            "timings": timings,
            "results": results,
        }
    finally:
        session.close()


def _failure_table(report: dict[str, Any]) -> str:
    """최종 경로가 실패로 센 행만 사람이 읽는 표로 만든다.

    이 표가 필요한 이유: 기대 패턴은 이름·카테고리·소분류 정규식이라
    `운동화 사고 싶다 → 나이키 라이즈`처럼 사람 눈에는 맞는 결과도 실패로 센다.
    수치만 보면 진짜 회귀와 패턴 미비를 구분할 수 없다.
    """
    failures = [row for row in report["results"] if not row["final_pass"]]
    if not failures:
        return "최종 경로 실패 행 없음"
    lines = [
        "최종 경로 실패 행 (사람 확인 필요)",
        "| 질의 | 경로 | 반환 매장 | 층 | 기대 패턴 | 점수 |",
        "|---|---|---|---|---|---|",
    ]
    for row in failures:
        lines.append(
            "| {query} | {route} | {name} | {floor} | `{expected}` | {score} |".format(
                query=row["query"],
                route=row["route"],
                name=row["final_name"] or "(no_match)",
                floor=row["final_floor"] or "-",
                expected=row["expected"],
                score=row["semantic_score"],
            )
        )
    return "\n".join(lines)


def _compare(baseline: dict[str, Any], current: dict[str, Any]) -> str:
    """이전 실행 JSON과 질의 단위로 대조한다. 총점만 같고 내용이 갈린 경우를 잡는다."""
    before = {row["query"]: row for row in baseline.get("results", [])}
    after = {row["query"]: row for row in current["results"]}
    lines = [
        "기준선 대조: final {b}/{bt} → {a}/{at}, FAISS 단독 {sb} → {sa}".format(
            b=baseline["summary"]["final_pass"],
            bt=baseline["summary"]["total"],
            a=current["summary"]["final_pass"],
            at=current["summary"]["total"],
            sb=baseline["summary"]["semantic_pass"],
            sa=current["summary"]["semantic_pass"],
        )
    ]
    for query, row in after.items():
        old = before.get(query)
        if old is None:
            lines.append(f"  + 새 질의: {query}")
            continue
        if old["final_pass"] != row["final_pass"] or old["final_name"] != row["final_name"]:
            lines.append(
                "  * {q}: {ob}({on}) → {nb}({nn})".format(
                    q=query,
                    ob="pass" if old["final_pass"] else "fail",
                    on=old["final_name"],
                    nb="pass" if row["final_pass"] else "fail",
                    nn=row["final_name"],
                )
            )
    for query in before:
        if query not in after:
            lines.append(f"  - 사라진 질의: {query}")
    if len(lines) == 1:
        lines.append("  질의 단위 변화 없음")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="AI 하이브리드 경로 평가")
    parser.add_argument("--out", type=Path, help="결과 JSON을 저장할 경로")
    parser.add_argument("--baseline", type=Path, help="대조할 이전 실행 JSON 경로")
    args = parser.parse_args()

    report = evaluate()
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print()
    print(_failure_table(report))

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n결과 저장: {args.out}")

    if args.baseline:
        baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        print()
        print(_compare(baseline, report))


if __name__ == "__main__":
    main()
