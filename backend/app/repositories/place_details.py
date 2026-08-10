"""매장 상세 오버레이 로더 — 표시용 수작업 데이터를 읽어 온다.

**이 모듈은 순수 함수 모듈이다.** DB·ORM·시드를 모르고, dict와 문자열만 다룬다.
`Session`을 받지 않고 `models.place.Store`를 import하지 않는다. 상세 데이터 작성
작업(오버레이 JSON + 검증 스크립트)이 이 모듈과 병렬로 진행되는데, 두 갈래가 서로를
import하지 않아도 각자 완결되도록 하기 위해서다. 경계는 아래 두 가지 문자열 계약뿐이다.

- 리소스 경로: `backend/resources/store_details/`
- 로더 시그니처: `load_overlays() -> dict[str, dict]` (매장 id → 오버레이)

## 디렉터리가 없으면 빈 dict를 반환한다

상세 API가 먼저 서고 데이터가 나중에 채워지는 순서이기 때문이다. 파일이 하나도 없는
상태에서도 API는 200으로 코어를 반환해야 하고(설계 문서 8절), 그래야 클라이언트 작업이
데이터를 기다리지 않는다. "파일이 없다"를 에러로 만들면 그 병렬성이 사라진다.

## 왜 표시용 값을 DB 컬럼이 아니라 JSON에 두는가

원본(Studio)에 표시용 정보가 아예 없어서 사람이 쓰는 수밖에 없는데, 사람이 쓴 것을
DB에 넣으면 재시드할 때마다 날아가거나 시드 스크립트가 사람의 편집을 덮어쓴다.
`store_categories.json`이 이미 같은 이유로 리소스 JSON에 있다. 같은 패턴을 세 번째로
새로 만들지 않고 그대로 따른다.

## 조인 키는 항상 id다

이름은 유일 키가 아니다 — 에스컬레이터 152건·엘리베이터 60건·화장실 19건이 동명이고,
상세 대상 539건 안에도 페어몬트 호텔 3건, POP-UP STUDIO A/B 각 2건 같은 중복이 있다.
오버레이 파일이 적어 두는 `name`은 **사람이 diff를 읽기 위한 중복 정보**이며 병합에
쓰지 않는다(검증 스크립트가 원본과 다른지만 확인한다).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

# 오버레이가 아닌 예약 파일. `_`로 시작하는 파일은 스키마 선언 같은 메타데이터다.
_META_PREFIX = "_"

# 오버레이 항목 안에서 facet이 아닌 예약 키.
# name: 사람이 diff를 읽기 위한 중복 정보(조인 키 아님)
# updated_at: 최종 확인일 → Provenance로 올라간다
RESERVED_KEYS = {"name", "updated_at"}

_RESOURCE_DIR = Path(__file__).resolve().parents[2] / "resources" / "store_details"


# 매장 id → 오버레이 dict. 디렉터리·파일이 없으면 빈 dict.
def load_overlays(resource_dir: Path | None = None) -> dict[str, dict[str, Any]]:
    directory = resource_dir or _RESOURCE_DIR
    if not directory.is_dir():
        return {}

    merged: dict[str, dict[str, Any]] = {}
    for path in sorted(directory.glob("*.json")):
        if path.name.startswith(_META_PREFIX):
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            continue
        # 같은 id가 두 파일에 있으면 나중 파일이 이긴다. 정상 상태가 아니므로
        # 검증 스크립트가 별도로 잡는다 — 여기서 예외를 던지면 데이터 한 건
        # 때문에 API 전체가 죽는다.
        for place_id, overlay in payload.items():
            if isinstance(overlay, dict):
                merged[place_id] = overlay
    return merged


# 스키마 선언 파일. 오버레이가 아니므로 `_` 접두를 쓴다.
SCHEMA_FILENAME = "_schema.json"

_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_ALLOWED_FIELDS = {
    "summary",
    "source",
    "tags",
    "keyValue",
    "notice",
    "hero",
    "menu",
    "businessInfo",
    "demoInfo",
    "links",
}


# 오버레이 한 파일을 검증한다. 오류 메시지 목록(빈 목록이면 정상).
#
# 시드가 적재 **전에** 호출한다. 잘못된 내용이 DB에 들어간 뒤 실패하면 반쯤 시드된
# DB가 남고, 무엇보다 틀린 정보가 사용자에게 한 번은 보인다.
#
# `today`를 인자로 받는 이유: 만료 검사는 "오늘"에 의존하는데 함수 안에서 날짜를
# 읽으면 테스트가 시간에 따라 통과했다 실패했다 한다.
def validate_overlay(
    payload: dict[str, Any],
    known_ids: set[str],
    names: dict[str, str],
    schema: dict[str, Any],
    today: str,
) -> list[str]:
    errors: list[str] = []
    forbidden = {label.strip() for label in schema.get("forbidden_labels", [])}
    demo_allowlist = {str(place_id).strip() for place_id in schema.get("demo_allowlist", [])}

    for place_id, overlay in payload.items():
        if not isinstance(overlay, dict):
            errors.append(f"{place_id}: 오버레이는 객체여야 합니다")
            continue

        # 고아 id. 매장이 사라졌거나 오타다. 이름으로 폴백하지 않는다 —
        # 동명 매장이 있어 엉뚱한 곳에 붙을 수 있다.
        if place_id not in known_ids:
            errors.append(f"{place_id}: 원본에 없는 매장 id")
            continue

        # 이름 드리프트. 이름이 바뀌었다면 적어 둔 내용도 낡았을 가능성이 크므로
        # 조용히 넘기지 않고 사람이 다시 보게 만든다.
        written_name = overlay.get("name")
        if written_name is not None and written_name != names.get(place_id):
            errors.append(f"{place_id}: 이름 불일치 (오버레이 '{written_name}' ≠ 원본 '{names.get(place_id)}')")

        unknown = set(overlay) - _ALLOWED_FIELDS - RESERVED_KEYS
        if unknown:
            errors.append(f"{place_id}: 스키마에 없는 키 {sorted(unknown)}")

        errors += _validate_values(place_id, overlay, schema, forbidden, demo_allowlist, today)

    return errors


def _validate_values(
    place_id: str,
    overlay: dict[str, Any],
    schema: dict[str, Any],
    forbidden: set[str],
    demo_allowlist: set[str],
    today: str,
) -> list[str]:
    errors: list[str] = []
    fields = schema.get("fields", {})

    # 길이는 검사하지 않는다. 한때 60자 상한을 걸었는데, 그 값이 뜻한 것은
    # "짧게 쓰라"였지 60이라는 숫자가 아니었다. 숫자로 굳혀 두니 브랜드가 쓴 공식
    # 문구를 5자 차이로 버리고 뜻이 옅은 다른 문장을 싣는 일이 생겼다 — 검증기가
    # 막아야 할 것은 틀린 값이지 긴 값이 아니다. 짧게 유지하는 것은 쓰는 사람의
    # 판단으로 남긴다.
    summary = overlay.get("summary")
    if summary is not None and (not isinstance(summary, str) or not summary.strip()):
        errors.append(f"{place_id}: summary가 비어 있습니다")

    # 출처. 공식 사이트에서 옮겨 온 문구는 **그 문구가 실제로 있던 페이지**를 남긴다.
    # 홈 주소만 적으면 나중에 다시 찾을 수 없어 확인이 불가능해진다.
    source = overlay.get("source")
    if source is not None:
        max_length = fields.get("source", {}).get("max_length", 300)
        if not isinstance(source, str) or not source.strip():
            errors.append(f"{place_id}: source가 비어 있습니다")
        elif len(source) > max_length:
            errors.append(f"{place_id}: source가 {max_length}자를 넘습니다")
        elif not source.startswith(("http://", "https://")):
            # 브랜드명·"공식 사이트" 같은 말은 근거가 되지 못한다. 다시 열어 볼 수
            # 있는 주소여야 확인일(updated_at)이 뜻을 갖는다.
            errors.append(f"{place_id}: source는 http(s) 주소여야 합니다")

    tags = overlay.get("tags")
    if tags is not None:
        max_items = fields.get("tags", {}).get("max_items", 6)
        if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
            errors.append(f"{place_id}: tags는 문자열 배열이어야 합니다")
        elif len(tags) > max_items:
            errors.append(f"{place_id}: tags가 {max_items}개를 넘습니다")

    errors += _validate_asset_items(place_id, overlay.get("hero"), "hero", fields)
    errors += _validate_asset_items(place_id, overlay.get("menu"), "menu", fields)
    errors += _validate_business_info(place_id, overlay.get("businessInfo"), fields, forbidden)
    errors += _validate_demo_info(place_id, overlay.get("demoInfo"), fields, demo_allowlist)
    errors += _validate_links(place_id, overlay.get("links"), fields)

    for item in overlay.get("keyValue") or []:
        if not isinstance(item, dict) or "label" not in item or "value" not in item:
            errors.append(f"{place_id}: keyValue 항목에 label/value가 필요합니다")
            continue
        # 출처 없는 값(영업시간·전화·평점)을 막는 지점. 영업시간류는 시간이
        # 지나면 자동으로 거짓이 되므로 규칙을 리뷰어 눈이 아니라 코드에 둔다.
        if str(item["label"]).strip() in forbidden:
            errors.append(f"{place_id}: '{item['label']}'은(는) 출처가 없어 넣을 수 없는 항목입니다")

    notice = overlay.get("notice")
    if notice is not None:
        if not isinstance(notice, dict) or not str(notice.get("text", "")).strip():
            errors.append(f"{place_id}: notice에 text가 필요합니다")
        else:
            until = notice.get("until")
            if until is None:
                errors.append(f"{place_id}: notice에는 until(종료일)이 필요합니다")
            elif not _DATE_PATTERN.match(str(until)):
                errors.append(f"{place_id}: notice.until 형식은 YYYY-MM-DD입니다")
            elif str(until) < today:
                # 만료된 고지가 남아 있으면 지난 팝업을 안내하게 된다.
                errors.append(f"{place_id}: notice가 {until}에 만료됐습니다")

    updated_at = overlay.get("updated_at")
    if updated_at is not None and not _DATE_PATTERN.match(str(updated_at)):
        errors.append(f"{place_id}: updated_at 형식은 YYYY-MM-DD입니다")

    return errors


# 필수 키와 선택 키를 스키마에서 읽는다.
#
# 키 목록을 호출부에 하드코딩해 두면 스키마 파일과 코드가 서로 다른 진실을 갖게 되고,
# 스키마만 고친 사람은 검증이 따라온 줄 안다. 선택 키를 **선언한 것만** 허용하는 이유도
# 같다 — `image_assset` 같은 오타는 값이 조용히 사라질 뿐 아무 데서도 실패하지 않는다.
def _validate_asset_items(
    place_id: str,
    value: Any,
    field_name: str,
    fields: dict[str, Any],
) -> list[str]:
    if value is None:
        return []

    errors: list[str] = []
    if not isinstance(value, list):
        return [f"{place_id}: {field_name}는 객체 배열이어야 합니다"]

    spec = fields.get(field_name, {})
    required_keys = tuple(spec.get("required_keys", ()))
    allowed_keys = set(required_keys) | set(spec.get("optional_keys", ()))

    max_items = spec.get("max_items")
    if isinstance(max_items, int) and len(value) > max_items:
        errors.append(f"{place_id}: {field_name}가 {max_items}개를 넘습니다")

    required_label = "/".join(required_keys)
    for item in value:
        if not isinstance(item, dict) or any(
            not isinstance(item.get(key), str) or not item[key].strip() for key in required_keys
        ):
            errors.append(f"{place_id}: {field_name} 항목에 {required_label}가 필요합니다")
            continue

        unknown = set(item) - allowed_keys
        if unknown:
            errors.append(f"{place_id}: {field_name} 항목에 스키마에 없는 키 {sorted(unknown)}")
    return errors


# 링크는 값이 문장이 아니라 주소다. 열리지 않는 주소는 화면에서 아무 일도 일어나지
# 않는 버튼이 되므로, 최소한 형식이 주소인지는 여기서 막는다. 살아 있는지는 사람이
# 확인할 일이다 — 검증기가 네트워크를 타면 시드가 외부 사이트 사정에 묶인다.
def _validate_links(place_id: str, value: Any, fields: dict[str, Any]) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        return [f"{place_id}: links는 객체 배열이어야 합니다"]

    errors: list[str] = []
    max_items = fields.get("links", {}).get("max_items")
    if isinstance(max_items, int) and len(value) > max_items:
        errors.append(f"{place_id}: links가 {max_items}개를 넘습니다")

    for item in value:
        if not isinstance(item, dict):
            errors.append(f"{place_id}: links 항목은 객체여야 합니다")
            continue

        label = item.get("label")
        if not isinstance(label, str) or not label.strip():
            errors.append(f"{place_id}: links 항목에 label이 필요합니다")
            continue

        url = item.get("url")
        if not isinstance(url, str) or not url.startswith(("http://", "https://")):
            errors.append(f"{place_id}: links '{label.strip()}'의 url은 http(s) 주소여야 합니다")

    return errors


# demoInfo가 별도 함수인 이유
#
# 이 필드는 **forbidden_labels를 적용하지 않는 유일한 자리**다. 영업시간·대표번호처럼
# 시간이 지나면 낡는 값을 소개 영상용 매장에 올리려고 열어 뒀다. 예외를 두는 순간
# 문제는 "누가 이걸 쓸 수 있나"로 옮겨 가므로, 두 가지로 가둔다.
#
# 1. `demo_allowlist`에 id를 명시한 매장만 쓸 수 있다. 목록에 없으면 필드가 있다는
#    것만으로 검증이 실패한다 — 이것이 없으면 "데모 전용"은 주석에만 있는 말이 되고,
#    검증기를 통과한다는 이유로 다른 매장에 번져 나간다.
# 2. 항목마다 source(그 값이 실제로 적혀 있던 페이지)와 confirmed_at이 필수다.
#    낡는 것을 막지는 못하지만, 언제 확인한 값인지 모르는 상태는 막는다.
def _validate_demo_info(
    place_id: str,
    value: Any,
    fields: dict[str, Any],
    demo_allowlist: set[str],
) -> list[str]:
    if value is None:
        return []
    if place_id not in demo_allowlist:
        return [f"{place_id}: demoInfo는 demo_allowlist에 있는 매장만 쓸 수 있습니다"]
    if not isinstance(value, list):
        return [f"{place_id}: demoInfo는 객체 배열이어야 합니다"]

    errors: list[str] = []
    max_items = fields.get("demoInfo", {}).get("max_items")
    if isinstance(max_items, int) and len(value) > max_items:
        errors.append(f"{place_id}: demoInfo가 {max_items}개를 넘습니다")

    for item in value:
        if not isinstance(item, dict):
            errors.append(f"{place_id}: demoInfo 항목은 객체여야 합니다")
            continue

        if any(not isinstance(item.get(key), str) or not item[key].strip() for key in ("label", "value")):
            errors.append(f"{place_id}: demoInfo 항목에 label/value가 필요합니다")
            continue

        label = str(item["label"]).strip()
        source = item.get("source")
        if not isinstance(source, str) or not source.startswith(("http://", "https://")):
            errors.append(f"{place_id}: demoInfo '{label}'의 source는 http(s) 주소여야 합니다")

        confirmed_at = item.get("confirmed_at")
        if not isinstance(confirmed_at, str) or not _DATE_PATTERN.match(confirmed_at):
            errors.append(f"{place_id}: demoInfo '{label}'의 confirmed_at 형식은 YYYY-MM-DD입니다")

    return errors


# businessInfo가 별도 함수인 이유
#
# 이 필드는 `keyValue`와 모양이 같은데(label/value) 한동안 `_validate_asset_items`를
# 타면서 **금지 라벨 검사를 통째로 건너뛰었다.** 그 결과 검증기·시드·테스트가 전부
# 통과한 채로 출처 없는 `영업시간`·`대표번호`가 응답에 실려 나갔다. 가드레일이 새 필드를
# 따라오지 못한 전형적인 경우라, 같은 실수가 반복되지 않도록 검사를 명시적으로 둔다.
#
# 규칙은 `keyValue`와 동일하다 — 금지 라벨은 조건 없이 막는다. 한때 "출처를 붙이면
# 통과"라는 예외를 뒀다가 철회했다(설계 9-1). 영업시간처럼 시간이 지나면 자동으로
# 거짓이 되는 값은 근거를 적어 두더라도 낡는 것을 막지 못하기 때문이다.
def _validate_business_info(
    place_id: str,
    value: Any,
    fields: dict[str, Any],
    forbidden: set[str],
) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        return [f"{place_id}: businessInfo는 객체 배열이어야 합니다"]

    errors: list[str] = []
    max_items = fields.get("businessInfo", {}).get("max_items")
    if isinstance(max_items, int) and len(value) > max_items:
        errors.append(f"{place_id}: businessInfo가 {max_items}개를 넘습니다")

    for item in value:
        if not isinstance(item, dict):
            errors.append(f"{place_id}: businessInfo 항목은 객체여야 합니다")
            continue

        label = item.get("label")
        label = label.strip() if isinstance(label, str) else ""
        raw_value = item.get("value")
        if not label or not (isinstance(raw_value, str) and raw_value.strip()):
            errors.append(f"{place_id}: businessInfo 항목에 label/value가 필요합니다")
            continue

        if label in forbidden:
            errors.append(f"{place_id}: '{label}'은(는) 출처가 없어 넣을 수 없는 항목입니다")

    return errors
