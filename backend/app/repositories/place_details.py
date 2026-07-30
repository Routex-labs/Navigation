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
