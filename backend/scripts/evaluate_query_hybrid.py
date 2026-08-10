"""실데이터 질의 세트로 최종 AI 하이브리드 경로와 FAISS 단독 결과를 비교한다.

`backend/`에서 실행:
    python -m scripts.seed.reset_and_seed
    python -m scripts.evaluate_query_hybrid

질의 세트는 `scripts/eval/query_eval_set.json`이며 `--set`으로 바꿀 수 있다. 세트를
코드에서 분리한 이유: 질의를 늘리는 일과 판정 로직을 고치는 일이 같은 파일에서 섞이면
"세트가 커져서 점수가 변한 것"과 "경로가 변해서 점수가 변한 것"을 구분할 수 없다.
설계와 검증 기준은 [docs/backend/native/search-eval-set.md](../docs/backend/native/search-eval-set.md).

기대 패턴은 인덱스 문서 텍스트(이름·카테고리·서브카테고리·facet)에 대한 최소 자동
판정이다. 숫자는 회귀 비교용이며, 최종 안내 적합성은 실패 행을 사람이 함께 확인한다.

`--out`으로 결과를 JSON 파일에 남기고 `--baseline`으로 이전 실행과 대조한다.
인덱스 문서에 facet 태그를 붙이는 변경(conversational-discovery.md 7-1)에서
"바꾸기 전 기준선"과 "바꾼 뒤"를 같은 형식으로 비교하기 위한 장치다.

    python -m scripts.evaluate_query_hybrid --out eval_before.json
    python -m scripts.evaluate_query_hybrid --baseline eval_before.json --out eval_after.json

`--validate-only`는 모델·인덱스 없이 세트 자체만 점검한다(정답이 존재하는 질의인지).
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from time import perf_counter
from typing import Any

from app.core.database import SessionLocal
from app.repositories import query_search, query_semantic

BUILDING_ID = "thehyundai-seoul"

DEFAULT_SET_PATH = Path(__file__).resolve().parent / "eval" / "query_eval_set.json"


@dataclass(frozen=True)
class EvalQuery:
    """평가 질의 1건. `expect`가 None이면 부정 질의(= no_match가 정답)다.

    `expect`는 매칭 대상 텍스트에 대한 정규식이다. 매칭 대상은 `_document_text()`가
    만드는 인덱스 문서와 같은 축이라, facet 태그가 인덱스 문서에 추가되면 기대 패턴도
    facet 값을 그대로 쓸 수 있다(conversational-discovery.md 7-1절).
    """

    id: str
    label: str
    query: str
    expect: str | None
    cls: str
    origin: str
    note: str | None = None

    @property
    def is_negative(self) -> bool:
        return self.expect is None


def load_queries(path: Path) -> tuple[list[EvalQuery], dict[str, Any]]:
    """세트 JSON을 읽어 (질의 목록, 메타)로 돌려준다.

    여기서 스키마를 강하게 검사하는 이유: 세트는 사람이 손으로 늘리는 파일이라
    id 중복·정규식 오타가 들어가기 쉽고, 그 상태로 평가가 돌면 조용히 틀린 점수가
    나온다. 죽는 편이 낫다.
    """
    raw = json.loads(path.read_text(encoding="utf-8"))
    queries: list[EvalQuery] = []
    seen_ids: set[str] = set()
    seen_texts: set[str] = set()
    for entry in raw["queries"]:
        item = EvalQuery(
            id=entry["id"],
            label=entry["label"],
            query=entry["query"],
            expect=entry.get("expect"),
            cls=entry["class"],
            origin=entry["origin"],
            note=entry.get("note"),
        )
        if item.id in seen_ids:
            raise ValueError(f"세트에 중복 id: {item.id}")
        if item.query in seen_texts:
            raise ValueError(f"세트에 중복 질의: {item.query}")
        if item.expect is not None:
            re.compile(item.expect)  # 정규식 오타는 평가 시작 전에 터뜨린다
        seen_ids.add(item.id)
        seen_texts.add(item.query)
        queries.append(item)
    meta = {key: value for key, value in raw.items() if key != "queries"}
    return queries, meta


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


def _by_class(results: list[dict[str, Any]]) -> dict[str, dict[str, int]]:
    """클래스별 통과 집계. 총점 하나로는 "어디가 약한지"를 못 본다.

    총점만 보던 W7~W9에서 세 번 연속 23/29가 나왔는데, 그건 개선이 없었다는 뜻일 수도
    있고 세트가 작아 변화를 감지 못한 것일 수도 있었다. 클래스별로 쪼개면 어느 축이
    움직였는지가 드러난다.
    """
    totals: Counter[str] = Counter()
    passes: Counter[str] = Counter()
    for row in results:
        totals[row["class"]] += 1
        passes[row["class"]] += int(row["final_pass"])
    return {name: {"total": totals[name], "final_pass": passes[name]} for name in sorted(totals)}


def evaluate(queries: list[EvalQuery]) -> dict[str, Any]:
    session = SessionLocal()
    timings: dict[str, float] = {}
    try:
        started = perf_counter()
        rows = query_search._load_stores(session, BUILDING_ID)
        query_semantic.reset_indexes()
        timings["load_stores_sec"] = round(perf_counter() - started, 3)
        results = []

        for index, item in enumerate(queries):
            query_started = perf_counter()
            text = item.query
            light = query_search._rank_with_candidate(rows, text)
            final = query_search.match_ai_destination(session, BUILDING_ID, text)
            semantic, reason = _semantic_reason(session, text)
            final_match = final["match"]
            light_tier, light_name = _light_top(light)
            elapsed = round(perf_counter() - query_started, 3)
            if index == 0:
                # 첫 질의가 모델 로드 + 인덱스 빌드를 통째로 뒤집어쓴다.
                timings["first_query_sec"] = elapsed
            if item.is_negative:
                # 부정 질의의 정답은 "아무것도 반환하지 않는 것"이다. 경량 1차가 무엇을
                # 잡았는지는 여전히 기록한다 — 부정이 통과할 때 어느 경로가 통과시켰는지
                # 모르면 고칠 곳을 못 찾는다.
                final_pass = final["status"] == "no_match"
                semantic_pass = semantic is None
            else:
                final_pass = _matches(item.expect or "", _match_text(final_match))
                semantic_pass = _matches(item.expect or "", _semantic_text(semantic))
            results.append(
                {
                    "id": item.id,
                    "class": item.cls,
                    "origin": item.origin,
                    "label": item.label,
                    "query": text,
                    "expected": item.expect if item.expect is not None else "(no_match)",
                    "route": ("light" if query_search._is_confident_light_match(light) else "semantic"),
                    "light_tier": light_tier,
                    "light_name": light_name,
                    "final_status": final["status"],
                    "final_name": final_match["name"] if final_match else None,
                    "final_floor": final_match["floor_name"] if final_match else None,
                    "final_pass": final_pass,
                    "semantic_name": semantic[1].name if semantic else None,
                    "semantic_floor": semantic[2].name if semantic else None,
                    "semantic_score": round(semantic[0], 3) if semantic else None,
                    "semantic_reason": reason,
                    "semantic_pass": semantic_pass,
                    "elapsed_sec": elapsed,
                }
            )

        negatives = [item for item in queries if item.is_negative]
        timings["total_sec"] = round(perf_counter() - started, 3)
        return {
            "building_id": BUILDING_ID,
            "threshold": getattr(query_semantic, "SIMILARITY_THRESHOLD", None),
            "top_k": getattr(query_semantic, "_TOP_K", None),
            "store_count": len(rows),
            "summary": {
                "total": len(results),
                "positive": len(queries) - len(negatives),
                "negative": len(negatives),
                "final_pass": sum(row["final_pass"] for row in results),
                "semantic_pass": sum(row["semantic_pass"] for row in results),
                "light_routes": sum(row["route"] == "light" for row in results),
                "semantic_routes": sum(row["route"] == "semantic" for row in results),
                # 부정 질의가 매장을 반환한 건수. 총점보다 이 값이 먼저다 —
                # 길찾기에서는 "틀린 매장 안내"가 "다시 말해 주세요"보다 나쁘다.
                "false_positives": sum(
                    1 for row in results if row["expected"] == "(no_match)" and not row["final_pass"]
                ),
                "by_class": _by_class(results),
            },
            "timings": timings,
            "results": results,
        }
    finally:
        session.close()


def validate_set(queries: list[EvalQuery]) -> tuple[list[str], list[str]]:
    """세트가 채점 가능한 상태인지 DB로 확인하고 (오류, 경고)를 돌려준다.

    잡으려는 실수는 **정답이 없는 질의**다. 기대 패턴을 만족하는 매장이 건물에 한 건도
    없으면 그 행은 파이프라인이 아무리 좋아져도 영원히 실패하고, 총점은 고칠 수 없는
    실패를 계속 끌고 다닌다. 반대로 부정 질의의 문구가 실재 매장과 겹치면 "정답이
    no_match"라는 전제가 깨진다 — 그건 부정이 아니라 사람이 다시 판단할 행이다.

    모델·인덱스를 건드리지 않으므로 torch 없이도 돈다.
    """
    session = SessionLocal()
    try:
        rows = query_search._load_stores(session, BUILDING_ID)
        documents = [(store, f"{store.name} {store.category} {store.subcategory}") for store, _floor in rows]
        errors: list[str] = []
        warnings: list[str] = []
        for item in queries:
            if item.is_negative:
                hits = [store.name for store, text in documents if item.query in text]
                if hits:
                    warnings.append(f"{item.id} 부정 질의 '{item.query}'가 실재 매장과 겹친다: {hits[:3]}")
                continue
            matched = [store.name for store, text in documents if _matches(item.expect or "", text)]
            if not matched:
                errors.append(f"{item.id} '{item.query}': 기대 패턴 `{item.expect}`을 만족하는 매장이 없다")
            elif len(matched) > 400:
                # 패턴이 너무 넓으면 아무 답이나 통과시켜 점수가 부풀려진다.
                warnings.append(
                    f"{item.id} '{item.query}': 기대 패턴이 {len(matched)}건과 일치 — 너무 넓지 않은지 확인"
                )
        return errors, warnings
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


def _class_table(report: dict[str, Any]) -> str:
    lines = ["클래스별 통과", "| 클래스 | 통과/전체 |", "|---|---|"]
    for name, stat in report["summary"]["by_class"].items():
        lines.append(f"| {name} | {stat['final_pass']}/{stat['total']} |")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="AI 하이브리드 경로 평가")
    parser.add_argument("--set", type=Path, default=DEFAULT_SET_PATH, help="질의 세트 JSON 경로")
    parser.add_argument("--out", type=Path, help="결과 JSON을 저장할 경로")
    parser.add_argument("--baseline", type=Path, help="대조할 이전 실행 JSON 경로")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="세트만 점검하고 평가는 돌리지 않는다(모델 불필요)",
    )
    args = parser.parse_args()

    queries, meta = load_queries(args.set)
    errors, warnings = validate_set(queries)
    for message in warnings:
        print(f"[경고] {message}")
    for message in errors:
        print(f"[오류] {message}")
    if errors:
        raise SystemExit("세트에 정답이 없는 질의가 있다. 고치기 전에는 점수를 믿을 수 없다.")
    print(f"세트 {args.set.name}: 질의 {len(queries)}건 (v{meta.get('version')}) — 점검 통과\n")
    if args.validate_only:
        return

    report = evaluate(queries)
    report["set"] = {"path": str(args.set), "version": meta.get("version"), "count": len(queries)}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print()
    print(_class_table(report))
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
