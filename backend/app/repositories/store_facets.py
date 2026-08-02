"""검색용 매장 facet — 파생 규칙 + 수작업 오버레이 병합.

**이 모듈은 순수 함수 모듈이다.** DB·ORM·시드를 몰라야 하고, dict와 문자열만 다룬다.
`Session`을 인자로 받지 않고, `models.place.Store`를 import하지 않는다. Wave 1에서
H 갈래(`seed_navigation.py`)가 이 모듈과 동시에 작업 중인데, 두 갈래가 서로의 모듈을
import하지 않아도 각자 완결되도록 하기 위해서다(경계는
`docs/backend/native/conversational-discovery.md` 5절, wave1/README.md 참고).

## 왜 파생 규칙을 코드 상수로 두는가

`styles` 값은 패션 매장 266건 중 204건에서 **소분류 하나로 결정적으로 유도된다**
(예: subcategory="스포츠·아웃도어" → styles=["스포츠"]). 이 대응을 수작업 JSON에
옮겨 적으면 `subcategory`와 `styles`가 같은 정보를 두 벌로 들고 있게 되고, Studio에서
소분류가 바뀌면 JSON은 조용히 낡은 값을 들고 드리프트한다(설계 문서 2절 실패 조건
"태그 JSON과 매장 데이터가 드리프트"). 그래서 결정적으로 유도되는 부분은 코드
상수(`_SUBCATEGORY_TO_STYLES`)로 두고, 사람이 개별 판단해야 하는 것만(예: 슈즈 8건처럼
소분류 하나에 스타일이 여러 갈래로 갈리는 경우) 오버레이 JSON에 손으로 적는다.
`store_categories.json`이 이미 쓰는 "Studio 원본 + 수작업 오버라이드" 패턴과 같은 구조다.

## 파일 배치

```
backend/resources/store_search_facets/
├─ _vocabulary.json    ← 어휘 선언. `_`로 시작해 오버레이 대상에서 제외된다.
├─ _intents.json       ← intent별 규칙 + 예외 매장. 역시 `_` 접두라 오버레이가 아니다.
└─ fashion.json         ← 카테고리별로 쪼갠 수작업 오버레이. 여러 파일로 나눌 수 있다.
```

vocabulary 파일과 오버레이 파일을 분리한 이유: vocabulary는 "어떤 값이 허용되는가"를
선언하는 스키마이고, 오버레이는 "이 매장에 어떤 값을 붙일까"라는 데이터다. 성격이
다른 두 가지를 한 파일에 두면 vocabulary 값 하나를 늘릴 때마다 거대한 데이터 파일을
열어야 한다. 오버레이는 카테고리별로 쪼갤 수 있어야 리뷰 단위가 작아진다(요구사항).

## 왜 intents는 매장 태그가 아니라 "규칙 + 예외" 파일인가

intents 스키마는 **소분류 규칙 객체 + 예외 매장 id**로 확정했고(wave0 D 조사 보고서 제안),
설계 문서 12절 "확정" 목록과 5-1-1절도 이 결정으로 갱신됐다. intent는 사용자가 치는
말("신발"·"밥집")이고, 후보 대부분은 소분류에서 규칙으로 유도된다. 145건을 매장별
배열(`"intents": ["신발"]`)로 손으로 나열하면 `styles`에서 이미 겪은 드리프트가
그대로 재현된다 — Studio에서 소분류가 바뀌어도 JSON은 조용히 낡은 후보 집합을
들고 있게 된다. 그래서

- 규칙(`rules`)이 소분류로 대부분을 잡고,
- 규칙으로 잡히지 않는 것(예: 나이키 라이즈처럼 소분류는 `캐주얼·스트리트`인데 신발을
  파는 매장 145건)만 `extra_store_ids`로 보태고,
- 규칙이 잘못 끌어온 매장은 `excluded_store_ids`로 뺀다.

`rules`를 `{"subcategory": [...]}`처럼 **필드 이름을 적는 객체**로 둔 이유는 원래
`식사`가 어느 필드를 보는지를 파일에서 드러내기 위해서였다. 당시 대분류는 `식음료`
138건이라 그걸로 잡으면 "밥집" 질의에 야채·정육·수산이 섞였고, 그래서
`subcategory=레스토랑`(57건)을 기준으로 삼는 것이 설계의 핵심이었다.

**그 전제는 대분류 재편으로 사라졌다.** `식음료`가 음식점(57)·카페(53)·식품관(28)로
갈리면서 `category=음식점`이 곧 `subcategory=레스토랑`과 같은 집합이 됐고, 정육·야채는
애초에 식품관으로 빠졌다. 그래서 `식사`·`카페` intent는 소분류가 아니라 **대분류**를
본다 — 지도 필터 pill이 쓰는 분류와 같은 축을 보게 되어, 나중에 음식점 밑에 소분류가
하나 늘어도(예: 푸드코트) intent가 자동으로 따라간다. 소분류로 못 박아 두면 그때
조용히 빠지는데, 이 파일이 애초에 막으려던 드리프트가 바로 그것이다.

필드 이름을 적는 형식 자체는 그대로 둔다. 어떤 intent는 여전히 소분류가 맞고
(`신발`=슈즈, `출구`=교통), 파일만 보고 그 차이를 알 수 있어야 한다.
JSON은 주석을 못 달기 때문에 이 근거는 여기 남긴다.

intent 이름은 `_vocabulary.json`에 **넣지 않는다.** vocabulary는 "매장에 붙일 수 있는
태그 값"의 선언이고, vocabulary에 `intents` 축을 만들면 오버레이 파일이 매장별로
`"intents": [...]`를 적을 수 있게 되어 위에서 배제한 방식이 뒷문으로 들어온다.
intent 이름의 선언은 `_intents.json`의 `intents` 키 자체다.
"""

from __future__ import annotations

import json
from pathlib import Path

# 소분류 → styles. 5절/README에 확정된 값이므로 임의로 늘리거나 줄이지 않는다.
# 다른 소분류(슈즈·잡화·시계·아이웨어·이너웨어 등)는 "스타일"이 아니라 "무엇을 파는지"를
# 말하는 품목 축이라 여기서 다루지 않는다(intents는 Wave 2 몫 — wave0/D-vocabulary.md 3절).
_SUBCATEGORY_TO_STYLES: dict[str, list[str]] = {
    "스포츠·아웃도어": ["스포츠"],
    "캐주얼·스트리트": ["캐주얼"],
    "컨템포러리": ["컨템포러리"],
    "명품": ["명품"],
    "골프": ["골프"],
}

# 오버레이 파일 안에서 facet이 아닌 예약 키. "name"은 사람이 diff를 검토하기 위한
# 중복 정보이며(store_categories.json과 같은 관례) 조인·병합 키로 쓰지 않는다.
_RESERVED_OVERLAY_KEYS = {"name"}

SUPPORTED_VERSION = 1

# intents 정의 파일명. `_` 접두라 `_iter_overlay_files`가 오버레이로 읽지 않는다.
INTENTS_FILENAME = "_intents.json"

# `rules`에서 조건으로 쓸 수 있는 매장 필드. 임의 키를 허용하지 않는 이유는 오타가
# "아무 매장도 안 잡히는 규칙"으로 조용히 통과하는 것을 막기 위해서다.
_ALLOWED_RULE_FIELDS = {"category", "subcategory"}


def derive_facets(category: str | None, subcategory: str | None) -> dict[str, list[str]]:
    """소분류에서 결정적으로 유도되는 facet. 없으면 빈 dict.

    `category`는 지금은 쓰지 않지만 시그니처에 남겨 둔다 — Wave 2에서 cuisines
    (category=음식점 하위) 같은 축이 추가되면 대분류 조건이 필요해진다.
    """
    del category  # 현재는 subcategory만으로 충분하다(Phase 1 = styles 하나).
    if subcategory in _SUBCATEGORY_TO_STYLES:
        # 빈 배열을 만들지 않는다 — 매핑에 없는 소분류는 아예 키를 만들지 않는다.
        return {"styles": list(_SUBCATEGORY_TO_STYLES[subcategory])}
    return {}


def _iter_overlay_files(path: Path):
    """디렉터리에서 `_`로 시작하지 않는 JSON 파일을 이름순으로 순회한다.

    이름순 정렬은 재현성 때문이다 — 중복 store_id 오류 메시지가 실행마다 파일
    나열 순서에 따라 달라지면 디버깅하기 어렵다.
    """
    for file in sorted(path.glob("*.json")):
        if file.name.startswith("_"):
            continue
        yield file


def load_overlay(path: Path) -> dict[str, dict[str, list[str]]]:
    """수작업 오버레이를 store_id -> facets 로 읽는다. 파일/디렉터리 없으면 빈 dict.

    디렉터리 안의 `_`로 시작하지 않는 JSON을 전부 읽어 병합한다(카테고리별로
    쪼갠 오버레이 파일들을 하나의 store_id -> facets 맵으로 합친다).
    각 파일은 `{"version": 1, "stores": {store_id: {"name": ..., <facet>: [...]}}}` 모양이다.

    **같은 store_id가 두 파일에 나오면 오류다.** 조용히 덮지 않고 예외를 던진다 —
    기존 `_load_store_categories`는 파일 하나만 다뤄서 이 문제가 없었지만, 여기는
    여러 파일을 병합하므로 겹치는 매장을 못 보고 넘어가면 어느 파일 값이 실제로
    쓰이는지 아무도 모르게 된다.
    """
    if not path.exists() or not path.is_dir():
        return {}

    merged: dict[str, dict[str, list[str]]] = {}
    origin: dict[str, str] = {}  # store_id -> 처음 발견한 파일명 (오류 메시지용)

    for file in _iter_overlay_files(path):
        payload = json.loads(file.read_text(encoding="utf-8"))
        stores = payload.get("stores", {})
        for store_id, facets in stores.items():
            if store_id in origin:
                raise ValueError(
                    f"store_id {store_id!r}가 {origin[store_id]!r}와 {file.name!r} "
                    "두 파일에 모두 있습니다. 오버레이 파일은 store_id가 서로 겹치지 않아야 합니다."
                )
            origin[store_id] = file.name
            merged[store_id] = facets

    return merged


def resolve_facets(
    store_id: str,
    category: str | None,
    subcategory: str | None,
    overlay: dict[str, dict[str, list[str]]],
) -> dict[str, list[str]]:
    """파생 + 오버레이 병합. 오버레이가 이긴다.

    병합은 **축(facet 키) 단위**로 한다 — 매장 전체를 오버레이가 통째로 갈아치우지
    않는다. 근거: 슈즈 8건은 소분류 하나(`슈즈`)에 스타일이 스포츠/캐주얼/명품/컴포트로
    흩어져 있어 `styles`를 매장별로 손으로 지정해야 하지만(wave0/D-vocabulary.md 3-3),
    Wave 2에서 cuisines 같은 다른 축이 파생 규칙을 갖게 되면 그 축까지 오버레이가
    지워 버릴 이유가 없다. 통째로 갈아치우면 오버레이 작성자가 매번 "다른 축도
    같이 옮겨 적어야 하나"를 고민해야 하고, 그게 곧 드리프트의 원인이 된다.

    오버레이가 어떤 축을 **빈 배열**로 명시하면 그 축을 제거한다는 뜻으로 해석한다
    (파생값을 오버레이로 지우고 싶을 때의 유일한 표현 방법). 결과에는 5-1절 규칙대로
    빈 배열을 남기지 않는다.
    """
    resolved = dict(derive_facets(category, subcategory))

    override = overlay.get(store_id)
    if override:
        for axis, values in override.items():
            if axis in _RESERVED_OVERLAY_KEYS:
                continue
            resolved[axis] = values

    # 빈 배열은 저장하지 않는다(설계 문서 5-1) — 오버레이가 명시적으로 비워도,
    # 파생 결과가 우연히 비어도 최종 결과에서는 키 자체를 없앤다.
    return {axis: values for axis, values in resolved.items() if values}


def validate_overlay(
    overlay: dict, vocabulary: dict, known_store_ids: set[str], store_names: dict[str, str]
) -> list[str]:
    """설계 문서 5-2의 실패 조건 6가지를 검사한다.

    `overlay`는 오버레이 파일 하나를 그대로 파싱한 dict
    (`{"version": 1, "stores": {store_id: {"name": ..., <facet>: [...]}}}`)다.
    `vocabulary`는 `_vocabulary.json`의 `vocabulary` 값(`{axis: [허용값, ...]}`)이다.

    예외를 던지지 않고 **오류 메시지 목록**을 돌려준다(빈 목록이면 정상). 시드가
    이 목록을 받아 실패시킬지 경고만 할지 정할 수 있게 하기 위해서다(호출부 재량).

    **태그가 없는 매장은 여기서 다루지 않는다.** 5-2절은 "태그 없음"을 실패가 아니라
    커버리지 보고 대상으로 명시적으로 구분하므로, 커버리지는 `facet_coverage_report`가
    따로 계산한다.
    """
    errors: list[str] = []

    # 1. version 미지원
    version = overlay.get("version")
    if version != SUPPORTED_VERSION:
        errors.append(f"지원하지 않는 version입니다: {version!r} (지원: {SUPPORTED_VERSION})")
        # version이 안 맞으면 아래 구조 자체를 신뢰할 수 없으므로 더 진행하지 않는다.
        return errors

    allowed_values: dict[str, set[str]] = {axis: set(values) for axis, values in vocabulary.items()}

    stores = overlay.get("stores", {})
    for store_id, facets in stores.items():
        # 2. 존재하지 않는 store_id (고아)
        if store_id not in known_store_ids:
            errors.append(f"존재하지 않는 store_id입니다: {store_id!r}")
            continue  # 고아면 이름 대조·태그 검증까지 갈 근거 매장이 없다

        # 3. name과 실제 Store 이름 불일치
        overlay_name = facets.get("name")
        actual_name = store_names.get(store_id)
        if overlay_name is not None and actual_name is not None and overlay_name != actual_name:
            errors.append(
                f"{store_id!r}의 name이 실제 매장명과 다릅니다: overlay={overlay_name!r} actual={actual_name!r}"
            )

        for axis, values in facets.items():
            if axis in _RESERVED_OVERLAY_KEYS:
                continue

            # 4. vocabulary에 없는 축 자체도 "없는 태그"로 취급한다.
            if axis not in allowed_values:
                errors.append(f"{store_id!r}.{axis}: vocabulary에 없는 축입니다.")
                continue

            # 6. 문자열이 아닌 태그 값 (배열이 아닌 경우도 여기서 함께 잡는다)
            if not isinstance(values, list):
                errors.append(f"{store_id!r}.{axis}: 배열이어야 합니다: {values!r}")
                continue

            seen: set[str] = set()
            for value in values:
                if not isinstance(value, str):
                    errors.append(f"{store_id!r}.{axis}: 문자열이 아닌 태그 값입니다: {value!r}")
                    continue

                # 5. 같은 배열 안의 중복 태그
                if value in seen:
                    errors.append(f"{store_id!r}.{axis}: 배열 안에 중복된 태그입니다: {value!r}")
                    continue
                seen.add(value)

                # 4. vocabulary에 없는 태그 값
                if value not in allowed_values[axis]:
                    errors.append(f"{store_id!r}.{axis}: vocabulary에 없는 값입니다: {value!r}")

    return errors


def facet_coverage_report(
    stores: list[dict],
    overlay: dict[str, dict[str, list[str]]],
) -> dict[str, dict[str, dict[str, int]]]:
    """건물별·대분류별 태그 적용률을 계산한다(설계 문서 5-2절 커버리지 보고 요구사항).

    `stores`는 순수 dict 목록이다(예: `[{"store_id": ..., "building_id": ...,
    "category": ..., "subcategory": ...}, ...]`) — 이 모듈은 ORM을 모르므로 호출부가
    Store 행을 이 모양으로 변환해 넘긴다.

    태그가 없는 매장은 실패가 아니라 이 보고서의 분모/분자로만 드러난다
    (validate_overlay가 실패로 잡는 6가지와는 별개 — 5-2절이 요구하는 구분).

    반환: `{"by_building": {id: {"total": n, "tagged": n}}, "by_category": {...}}`
    """
    by_building: dict[str, dict[str, int]] = {}
    by_category: dict[str, dict[str, int]] = {}

    def _bump(bucket: dict[str, dict[str, int]], key: str) -> dict[str, int]:
        entry = bucket.setdefault(key, {"total": 0, "tagged": 0})
        entry["total"] += 1
        return entry

    for store in stores:
        store_id = store["store_id"]
        category = store.get("category")
        subcategory = store.get("subcategory")
        building_id = store.get("building_id")

        facets = resolve_facets(store_id, category, subcategory, overlay)
        tagged = bool(facets)

        if building_id is not None:
            entry = _bump(by_building, building_id)
            if tagged:
                entry["tagged"] += 1

        if category is not None:
            entry = _bump(by_category, category)
            if tagged:
                entry["tagged"] += 1

    return {"by_building": by_building, "by_category": by_category}


# ── intents — 소분류 규칙 + 예외 매장 ─────────────────────────────────────


def load_intents(path: Path) -> dict[str, dict]:
    """intent 정의를 `{intent: 정의}`로 읽는다. 파일이 없으면 빈 dict.

    `path`는 정의 파일(`_intents.json`) 자체거나 그 파일이 들어 있는 디렉터리
    (`resources/store_search_facets/`)여도 된다. 호출부가 이미 오버레이 디렉터리
    상수를 들고 있으므로 같은 값을 그대로 넘길 수 있게 하기 위한 편의다.

    파일이 없을 때 예외가 아니라 빈 dict인 것은 `load_overlay`와 같은 관용이다 —
    intent 정의 없이도 시드·검색은 (탐색 후보 없이) 돌아야 한다.

    `version`은 여기서 검사하지 않는다. `validate_intents`가 오류 목록으로 돌려주고
    호출부가 실패시킬지 경고할지 정하는 편이, 로더가 예외로 시드를 끊는 것보다
    기존 검증 흐름(`validate_overlay`)과 일관된다.
    """
    file = path / INTENTS_FILENAME if path.is_dir() else path
    if not file.exists():
        return {}
    payload = json.loads(file.read_text(encoding="utf-8"))
    return payload.get("intents", {})


def _matches_rules(store: dict, rules: dict[str, list[str]]) -> bool:
    """매장 하나가 규칙을 만족하는지. 필드 간 AND, 같은 필드의 값들끼리 OR.

    지원하지 않는 필드는 예외를 던진다. 조용히 무시하면 조건이 하나 사라져 후보
    집합이 **넓어지는** 방향으로 틀리는데, 그건 "밥집에 정육점이 섞인다"와 같은
    실패다. 파일은 `validate_intents`가 먼저 걸러야 한다는 계약을 예외로 강제한다.
    """
    for field, values in rules.items():
        if field not in _ALLOWED_RULE_FIELDS:
            raise ValueError(f"규칙에 쓸 수 없는 필드입니다: {field!r} (허용: {sorted(_ALLOWED_RULE_FIELDS)})")
        if store.get(field) not in values:
            return False
    return True


def _matches_intent(store: dict, definition: dict) -> bool:
    """매장 하나가 intent 정의에 걸리는가 = (규칙 유도 ∪ extra) − excluded.

    intent 하나를 매장 관점에서 판정하는 **단일 지점**이다. 집합 함수
    (`resolve_intent_store_ids`)와 매장별 함수(`resolve_intents`)가 이 규칙을 각자
    구현하면, 한쪽만 고쳤을 때 시드가 붙인 태그와 검색이 세는 후보가 조용히 갈린다.

    `excluded`를 맨 먼저 보는 이유는 그 키의 유일한 용도가 "규칙으로 들어왔든 손으로
    넣었든 결국 제외"이기 때문이다 — 순서가 곧 의미다.
    """
    store_id = store["store_id"]
    if store_id in (definition.get("excluded_store_ids") or {}):
        return False
    rules = definition.get("rules") or {}
    if rules and _matches_rules(store, rules):
        return True
    return store_id in (definition.get("extra_store_ids") or {})


def resolve_intents(store: dict, intents: dict[str, dict]) -> list[str]:
    """매장 하나가 속하는 intent 이름들. 정의 파일의 선언 순서를 유지한다.

    `resolve_intent_store_ids`를 매장 관점으로 뒤집은 것이다. 시드는 매장을 한 건씩
    조립하므로(`studio_adapter._reshape_stores`) 매장마다 intent별 전 매장 스캔을
    돌릴 이유가 없다.

    **순서를 정의 파일 순서로 고정하는 게 계약이다.** 이 값은 `Store.search_facets`에
    그대로 저장되고 임베딩 문서 텍스트로도 들어가므로(`query_semantic._document_text`),
    순서가 흔들리면 같은 매장이 실행마다 다른 문서 텍스트를 만들어 재현성이 깨진다.

    빈 목록을 돌려줄 수 있다 — 호출부가 5-1절 규칙대로 빈 축을 저장하지 않는다.
    """
    return [intent for intent, definition in intents.items() if definition and _matches_intent(store, definition)]


def resolve_intent_store_ids(
    intent: str,
    stores: list[dict],
    intents: dict[str, dict],
) -> set[str]:
    """intent 하나의 후보 store_id 집합 = 규칙 유도분 ∪ extra − excluded.

    `stores`는 `facet_coverage_report`와 같은 순수 dict 목록이다
    (`[{"store_id": ..., "category": ..., "subcategory": ...}, ...]`) — 이 모듈은
    ORM을 모르므로 호출부가 Store 행을 이 모양으로 변환해 넘긴다.

    모르는 intent는 빈 집합이다. 사용자 질의어를 intent로 옮기는 책임은 호출부에
    있고, 매핑이 실패했을 때 후보가 없다는 결과는 정상 흐름(no_match)이다.

    `excluded_store_ids`를 마지막에 빼는 순서가 중요하다 — 규칙이 잘못 끌어온 매장을
    빼는 것이 이 키의 유일한 용도이므로, extra보다 뒤에 적용해야 "규칙으로 들어왔든
    손으로 넣었든 결국 제외"라는 뜻이 된다.
    """
    definition = intents.get(intent)
    if not definition:
        return set()

    matched = {store["store_id"] for store in stores if _matches_intent(store, definition)}
    # `_matches_intent`는 `stores`에 있는 매장만 본다. 실데이터에 없는 extra id(고아)도
    # 정의가 가리키는 집합의 일부라 여기서 다시 합친다 — 고아 자체는 `validate_intents`가
    # 오류로 잡는 몫이고, 이 함수가 조용히 지워 버리면 그 오류가 보이지 않게 된다.
    matched |= set(definition.get("extra_store_ids") or {})
    return matched - set(definition.get("excluded_store_ids") or {})


def _iter_store_id_entries(definition: dict, key: str):
    """`extra_store_ids`/`excluded_store_ids`를 `(store_id, name)`으로 순회한다.

    두 키는 `{store_id: 매장명}` 객체다. 값이 이름인 이유는 오버레이의 `name`과 같다 —
    사람이 145줄 diff를 검토할 수 있어야 하는데 JSON에는 주석을 달 수 없다. 이름은
    검토용 중복 정보이며 조인 키가 아니다(`validate_intents`가 실데이터와 대조만 한다).
    """
    entries = definition.get(key) or {}
    if not isinstance(entries, dict):
        return
    yield from entries.items()


def validate_intents(payload: dict, stores: list[dict]) -> list[str]:
    """intents 정의 파일의 실패 조건을 검사하고 **오류 메시지 목록**을 돌려준다.

    `validate_overlay`와 같은 관용이다 — 예외를 던지지 않으므로 호출부가 실패시킬지
    경고만 할지 정한다. `payload`는 파일을 그대로 파싱한 dict
    (`{"version": 1, "intents": {...}}`)이고, `stores`는 `resolve_intent_store_ids`와
    같은 순수 dict 목록이다.

    잡는 것:

    1. `version` 미지원
    2. intent 정의가 비어 있음(규칙도 extra도 없는 intent는 후보를 못 만든다)
    3. 규칙에 쓸 수 없는 필드
    4. 실데이터에 존재하지 않는 규칙 값(예: 소분류 오타 `"레스토랑 "`)
    5. `extra_store_ids`/`excluded_store_ids`의 고아 store_id
    6. 이름 불일치(오버레이의 `name` 검사와 같은 목적)
    7. 규칙이 이미 잡는 매장을 `extra_store_ids`에 또 적은 중복
    8. 규칙도 extra도 잡지 않는 매장을 `excluded_store_ids`에 적은 무의미한 제외

    4번과 7번이 이 스키마의 핵심 방어다. 4번은 소분류가 Studio에서 바뀌었을 때
    규칙이 조용히 0건이 되는 것을 잡고, 7번은 규칙과 손 목록이 같은 매장을 두 벌로
    들고 있는 상태(= 드리프트의 씨앗)를 잡는다.
    """
    errors: list[str] = []

    version = payload.get("version")
    if version != SUPPORTED_VERSION:
        errors.append(f"지원하지 않는 version입니다: {version!r} (지원: {SUPPORTED_VERSION})")
        return errors

    known_ids = {store["store_id"] for store in stores}
    names = {store["store_id"]: store.get("name") for store in stores}
    field_values: dict[str, set] = {field: {store.get(field) for store in stores} for field in _ALLOWED_RULE_FIELDS}

    intents = payload.get("intents", {})
    for intent, definition in intents.items():
        rules = definition.get("rules") or {}

        # 2. 규칙도 extra도 없으면 후보가 영원히 0건이다.
        if not rules and not (definition.get("extra_store_ids") or {}):
            errors.append(f"{intent!r}: rules도 extra_store_ids도 없습니다.")

        for field, values in rules.items():
            # 3. 지원하지 않는 필드
            if field not in _ALLOWED_RULE_FIELDS:
                errors.append(
                    f"{intent!r}.rules: 규칙에 쓸 수 없는 필드입니다: {field!r} (허용: {sorted(_ALLOWED_RULE_FIELDS)})"
                )
                continue
            if not isinstance(values, list) or not values:
                errors.append(f"{intent!r}.rules.{field}: 비어 있지 않은 배열이어야 합니다: {values!r}")
                continue
            for value in values:
                # 4. 실데이터에 없는 값 — 소분류가 바뀌어 규칙이 죽은 경우를 잡는다.
                if value not in field_values[field]:
                    errors.append(f"{intent!r}.rules.{field}: 실데이터에 없는 값입니다: {value!r}")

        # 규칙이 잡는 집합. 필드가 잘못돼 있으면 위에서 이미 오류로 잡았으므로
        # 여기서 예외가 나지 않게 허용 필드만 남겨서 계산한다.
        safe_rules = {
            field: values
            for field, values in rules.items()
            if field in _ALLOWED_RULE_FIELDS and isinstance(values, list) and values
        }
        rule_matched = {store["store_id"] for store in stores if safe_rules and _matches_rules(store, safe_rules)}

        extra_ids: set[str] = set()
        for store_id, name in _iter_store_id_entries(definition, "extra_store_ids"):
            extra_ids.add(store_id)
            # 5. 고아 id
            if store_id not in known_ids:
                errors.append(f"{intent!r}.extra_store_ids: 존재하지 않는 store_id입니다: {store_id!r}")
                continue
            # 6. 이름 불일치
            actual = names.get(store_id)
            if isinstance(name, str) and actual is not None and name != actual:
                errors.append(
                    f"{intent!r}.extra_store_ids: {store_id!r}의 name이 실제 매장명과 "
                    f"다릅니다: overlay={name!r} actual={actual!r}"
                )
            # 7. 규칙이 이미 잡는 매장
            if store_id in rule_matched:
                errors.append(f"{intent!r}.extra_store_ids: 규칙이 이미 잡는 매장입니다(중복): {store_id!r}")

        for store_id, _name in _iter_store_id_entries(definition, "excluded_store_ids"):
            # 5. 고아 id
            if store_id not in known_ids:
                errors.append(f"{intent!r}.excluded_store_ids: 존재하지 않는 store_id입니다: {store_id!r}")
                continue
            # 8. 뺄 대상이 애초에 후보가 아니다 = 규칙이 바뀐 뒤 남은 찌꺼기
            if store_id not in rule_matched and store_id not in extra_ids:
                errors.append(f"{intent!r}.excluded_store_ids: 규칙도 extra도 잡지 않는 매장입니다: {store_id!r}")

    return errors
