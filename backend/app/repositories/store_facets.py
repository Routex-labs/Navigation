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
└─ fashion.json         ← 카테고리별로 쪼갠 수작업 오버레이. 여러 파일로 나눌 수 있다.
```

vocabulary 파일과 오버레이 파일을 분리한 이유: vocabulary는 "어떤 값이 허용되는가"를
선언하는 스키마이고, 오버레이는 "이 매장에 어떤 값을 붙일까"라는 데이터다. 성격이
다른 두 가지를 한 파일에 두면 vocabulary 값 하나를 늘릴 때마다 거대한 데이터 파일을
열어야 한다. 오버레이는 카테고리별로 쪼갤 수 있어야 리뷰 단위가 작아진다(요구사항).
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


def derive_facets(category: str | None, subcategory: str | None) -> dict[str, list[str]]:
    """소분류에서 결정적으로 유도되는 facet. 없으면 빈 dict.

    `category`는 지금은 쓰지 않지만 시그니처에 남겨 둔다 — Wave 2에서 cuisines
    (category=식음료 하위) 같은 축이 추가되면 대분류 조건이 필요해진다.
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
        errors.append(
            f"지원하지 않는 version입니다: {version!r} (지원: {SUPPORTED_VERSION})"
        )
        # version이 안 맞으면 아래 구조 자체를 신뢰할 수 없으므로 더 진행하지 않는다.
        return errors

    allowed_values: dict[str, set[str]] = {
        axis: set(values) for axis, values in vocabulary.items()
    }

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
                f"{store_id!r}의 name이 실제 매장명과 다릅니다: "
                f"overlay={overlay_name!r} actual={actual_name!r}"
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
                    errors.append(
                        f"{store_id!r}.{axis}: 문자열이 아닌 태그 값입니다: {value!r}"
                    )
                    continue

                # 5. 같은 배열 안의 중복 태그
                if value in seen:
                    errors.append(f"{store_id!r}.{axis}: 배열 안에 중복된 태그입니다: {value!r}")
                    continue
                seen.add(value)

                # 4. vocabulary에 없는 태그 값
                if value not in allowed_values[axis]:
                    errors.append(
                        f"{store_id!r}.{axis}: vocabulary에 없는 값입니다: {value!r}"
                    )

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
