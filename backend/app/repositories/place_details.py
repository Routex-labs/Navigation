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
_ALLOWED_FIELDS = {"summary", "tags", "keyValue", "notice"}


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
            errors.append(
                f"{place_id}: 이름 불일치 (오버레이 '{written_name}' ≠ 원본 '{names.get(place_id)}')"
            )

        unknown = set(overlay) - _ALLOWED_FIELDS - RESERVED_KEYS
        if unknown:
            errors.append(f"{place_id}: 스키마에 없는 키 {sorted(unknown)}")

        errors += _validate_values(place_id, overlay, schema, forbidden, today)

    return errors


def _validate_values(
    place_id: str,
    overlay: dict[str, Any],
    schema: dict[str, Any],
    forbidden: set[str],
    today: str,
) -> list[str]:
    errors: list[str] = []
    fields = schema.get("fields", {})

    summary = overlay.get("summary")
    if summary is not None:
        max_length = fields.get("summary", {}).get("max_length", 60)
        if not isinstance(summary, str) or not summary.strip():
            errors.append(f"{place_id}: summary가 비어 있습니다")
        elif len(summary) > max_length:
            errors.append(f"{place_id}: summary가 {max_length}자를 넘습니다")

    tags = overlay.get("tags")
    if tags is not None:
        max_items = fields.get("tags", {}).get("max_items", 6)
        if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
            errors.append(f"{place_id}: tags는 문자열 배열이어야 합니다")
        elif len(tags) > max_items:
            errors.append(f"{place_id}: tags가 {max_items}개를 넘습니다")

    for item in overlay.get("keyValue") or []:
        if not isinstance(item, dict) or "label" not in item or "value" not in item:
            errors.append(f"{place_id}: keyValue 항목에 label/value가 필요합니다")
            continue
        # 출처 없는 값(영업시간·전화·평점)을 막는 지점. 영업시간류는 시간이
        # 지나면 자동으로 거짓이 되므로 규칙을 리뷰어 눈이 아니라 코드에 둔다.
        if str(item["label"]).strip() in forbidden:
            errors.append(
                f"{place_id}: '{item['label']}'은(는) 출처가 없어 넣을 수 없는 항목입니다"
            )

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
