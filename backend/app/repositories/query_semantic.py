# 자연어 질의 의미 검색 (문장 임베딩 + FAISS).
# 형태소 정규화(query_morph)는 경량 1차에만 적용된다 — 여기엔 질의 원문이 그대로 들어온다.
# 문장 임베딩은 조사·어미가 붙은 문장을 그대로 처리하는 게 낫고, 인덱스 텍스트를 바꾸면
# 임계값 0.50의 튜닝 근거(8절)가 무효가 되기 때문이다.
# 경량 매칭이 놓쳤거나 서로 다른 이름을 여럿 잡은 부분 일치를 의미로 보완한다 — 하이브리드의 2차.
# 설계 근거: docs/backend/native/FAISS.md
#
# 핵심 원칙:
# - 모델(ko-sroberta-multitask)은 지연 로드 싱글턴. 로드가 실패해도 예외를 삼켜서
#   경량 경로(1차)는 계속 동작한다. AI 경로만 조용히 비활성된다.
# - faiss·sentence_transformers import는 함수 안에서만. 이 모듈을 건드리지 않는 테스트·요청은
#   무거운 의존성을 로드하지 않는다.
# - 인덱스는 건물별로 최초 질의 때 1회 빌드해 메모리 상주. 코퍼스가 작아 IndexFlatIP 브루트포스로 충분.
# - 코사인 유사도 = L2 정규화 임베딩 + IndexFlatIP 내적. 임계값 미만은 no_match(엉뚱한 매장 방지).
# - 실패는 사유를 구분해 돌려준다(SemanticReason). "모델·인덱스 미가용(degraded)"과
#   "임계값 미달(no_match)"은 화면 문구가 달라야 한다. 사유만 드러내고 예외는 그대로 삼킨다.

from __future__ import annotations

import threading
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING, Any

import numpy as np
from sqlalchemy import func, select

from app.models import Floor, Store
from app.repositories.query_search import _load_stores  # 건물/층 조인 재사용

if TYPE_CHECKING:
    from sqlalchemy.orm import Session

_MODEL_NAME = "jhgan/ko-sroberta-multitask"

# 코사인 유사도 임계값. 이 값 미만이면 no_match로 처리해 엉뚱한 매장 반환을 막는다.
# thehyundai-seoul 실데이터로 튜닝(FAISS.md 8절·11절):
#   유효한 ATM 질의 0.464와 무의미 문자열("asdfqwerzxcv") 0.458의 간격이 0.006뿐이다.
#   임계값을 내리면 둘 다 통과하므로, 틀린 길 안내보다 no_match를 택해 0.50을 유지한다.
#   데이터나 인덱스 문서를 바꾸면 29개 평가 세트로 다시 튜닝한다.
SIMILARITY_THRESHOLD = 0.50

# 상위 몇 건을 받아 층 필터를 적용할지. 코퍼스가 작아 넉넉히 받는다.
_TOP_K = 10


class SemanticReason(str, Enum):
    """의미 검색 결과의 사유. 화면 문구가 사유별로 달라야 해서 구분한다.

    설계 근거: docs/backend/native/conversational-discovery.md 8-4절.
    이전에는 아래 넷이 전부 None 하나로 뭉개져 있어서, 호출부가 "지금 의미 검색을
    못 쓴다"(degraded)와 "찾았지만 안 닮았다"(no_match)를 구분할 수 없었다.

    - OK: 임계값 이상 후보 1건을 찾았다.
    - MODEL_UNAVAILABLE: 모델이 아직 없거나 로드에 실패했다 → degraded.
    - INDEX_UNAVAILABLE: 인덱스를 만들지 못했다(건물에 매장 0건 등) → degraded.
    - BELOW_THRESHOLD: 최상위 유사도가 SIMILARITY_THRESHOLD 미만이다 → no_match.

    str 혼합 Enum이라 로그·JSON 직렬화에서 값이 그대로 문자열로 찍힌다.
    """

    OK = "ok"
    MODEL_UNAVAILABLE = "model_unavailable"
    INDEX_UNAVAILABLE = "index_unavailable"
    BELOW_THRESHOLD = "below_threshold"


# degraded로 안내해야 하는 사유들. "의미 검색 기능 자체를 지금 못 쓴다"는 뜻이며,
# 질의를 바꿔도 결과가 달라지지 않는다. BELOW_THRESHOLD는 여기 들어가지 않는다 —
# 그건 기능은 정상이고 이 질의만 안 닮은 것이라 "다른 말로 다시"가 맞는 안내다.
_DEGRADED_REASONS = frozenset(
    {SemanticReason.MODEL_UNAVAILABLE, SemanticReason.INDEX_UNAVAILABLE}
)


@dataclass(frozen=True)
class SemanticResult:
    """의미 검색 1건의 결과와 사유.

    hit은 reason이 OK일 때만 채워진다. 호출부는 `result.hit`만 봐도 기존과 동일하게
    동작하고, 문구를 나눠야 할 때만 `result.is_degraded`를 본다.
    """

    reason: SemanticReason
    hit: tuple[float, "Store", "Floor"] | None = None

    @property
    def is_degraded(self) -> bool:
        """지금 의미 검색 기능을 쓸 수 없는 상태인가(모델·인덱스 미가용)."""
        return self.reason in _DEGRADED_REASONS

_model_lock = threading.Lock()
_model: Any | None = None
_model_load_failed = False

_index_lock = threading.Lock()
# building_id -> (faiss.Index, [store_id ...], fingerprint) — 벡터 행 순서와 store_id를
# 짝지어 역참조하고, fingerprint로 이 인덱스가 어느 시점의 DB 데이터를 반영하는지 기억한다.
_indexes: dict[str, tuple[Any, list[str], "_Fingerprint"]] = {}

# 매장 수 + max(store.id)의 건물별 지문. 별도 프로세스(reset_and_seed)가 재시딩해도
# 서버 프로세스는 그 사실을 모른다 — semantic_search 진입 때마다 이 지문을 값싼 SQL로
# 재계산해 옛 인덱스(_indexes)와 다르면 그 건물만 버리고 재빌드한다.
# count(*) 1건 수준의 비용이라 매 요청에 걸어도 된다(문서 상단 핵심 원칙 — 무거운 것은
# 함수 안 지연 import). max(id)까지 같이 보는 이유: 매장 수가 같아도 삭제+추가로
# 구성원이 바뀌는 재시딩을 놓치지 않기 위해서다(완벽한 체크섬은 아니지만 실전 재시딩
# 패턴 — 전체 삭제 후 재적재 — 은 id 구성이 통째로 바뀌므로 count만으로도 대부분 걸러지고,
# max(id)가 우연히 같은 count에서 구성이 바뀐 경우의 보강 신호가 된다).
_Fingerprint = tuple[int, str | None]


def _compute_fingerprint(session: "Session", building_id: str) -> _Fingerprint:
    """건물의 매장 수 + 최대 id를 값싼 집계 쿼리 한 번으로 계산한다."""
    row = session.execute(
        select(func.count(Store.id), func.max(Store.id))
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id)
    ).one()
    count, max_id = row
    return int(count), max_id


def _load_model() -> Any:
    """로컬 캐시를 먼저 보고, 없을 때만 Hub에서 내려받는다.

    캐시가 있어도 기본 로드는 리비전 확인용 익명 HTTP 요청을 보내
    "unauthenticated requests to the HF Hub" 경고와 함께 왕복 지연을 만든다
    (실측: 온라인 11.0초 / 로컬 전용 6.5초). 캐시 히트가 정상 경로이므로
    local_files_only를 먼저 시도하고, 캐시가 없는 새 머신에서만 Hub로 폴백한다.

    HF_HUB_OFFLINE 환경변수 대신 인자로 거는 이유: 그 변수는 huggingface_hub
    import 시점에 읽히는데 이 모듈은 지연 import라 설정 순서가 깨지기 쉽고,
    캐시 없는 환경을 폴백 없이 막아버린다.
    """
    from sentence_transformers import SentenceTransformer

    try:
        return SentenceTransformer(_MODEL_NAME, local_files_only=True)
    except Exception as error:  # noqa: BLE001 - 캐시 미스·손상 모두 Hub 재시도로 회복
        print(f"임베딩 모델 로컬 캐시 미스({_MODEL_NAME}): {error} → Hub에서 내려받는다")
        return SentenceTransformer(_MODEL_NAME)


def _get_model() -> Any | None:
    """모델을 한 번만 로드해 재사용. 로드 실패 시 None을 돌려 AI 경로만 비활성한다."""
    global _model, _model_load_failed

    if _model is not None or _model_load_failed:
        return _model

    # 락 안에서 한 번 더 확인 — 동시 요청이 모델을 두 번 로드하지 않게.
    with _model_lock:
        if _model is None and not _model_load_failed:
            try:
                _model = _load_model()
            except Exception as error:  # noqa: BLE001 - 어떤 실패든 경량 경로는 살린다
                print(f"임베딩 모델 로드 실패({_MODEL_NAME}): {error}")
                _model_load_failed = True
    return _model


def warm_model_in_background() -> threading.Thread:
    """모델 로드를 데몬 스레드로 미리 돌려 첫 /query/ai의 대기를 없앤다.

    로드 자체는 캐시가 있어도 CPU로 6초대가 걸린다(실측). 그 시간을 첫 질의가
    아니라 기동 직후에 쓰면 사용자에게는 보이지 않는다. 그동안 /health·타일 같은
    다른 요청은 정상 처리된다 — 이 스레드는 아무 락도 잡고 있지 않다.

    _get_model()이 _model_lock으로 직렬화하므로, 워밍이 끝나기 전에 질의가 들어와도
    모델을 두 번 로드하지 않고 락에서 기다렸다가 같은 인스턴스를 쓴다.
    daemon=True — 로드가 남아 있어도 서버 종료를 막지 않는다.

    주의: Cloud Run 기본 설정은 요청 처리 중이 아닐 때 CPU를 조인다. startup CPU
    boost나 min-instances 없이는 이 워밍이 기동 직후에 끝나지 않을 수 있다.
    """
    thread = threading.Thread(target=_get_model, name="embedding-warmup", daemon=True)
    thread.start()
    return thread


def _document_text(store: "Store") -> str:
    # 매장을 임베딩할 텍스트. 이름 + 카테고리로 의미 신호를 만든다.
    parts = [store.name or ""]
    if store.category:
        parts.append(store.category)
    if store.subcategory:
        parts.append(store.subcategory)
    return " ".join(part for part in parts if part).strip()


def _encode(model: Any, texts: list[str]) -> np.ndarray:
    # normalize_embeddings=True → 코사인용 L2 정규화. faiss는 float32 연속 배열을 요구한다.
    vectors = model.encode(texts, normalize_embeddings=True, convert_to_numpy=True)
    return np.ascontiguousarray(vectors, dtype="float32")


def _build_index(session: "Session", building_id: str) -> tuple[Any, list[str]] | None:
    model = _get_model()
    if model is None:
        return None

    rows = _load_stores(session, building_id)  # 건물 전체(층 필터는 검색 후 적용)
    if not rows:
        return None

    import faiss

    # 벡터 행 순서와 store_ids 순서가 1:1로 대응한다 — 검색 결과 position으로 역참조한다.
    store_ids = [store.id for store, _floor in rows]
    vectors = _encode(model, [_document_text(store) for store, _floor in rows])

    index = faiss.IndexFlatIP(vectors.shape[1])
    index.add(vectors)

    return index, store_ids


def _get_index(session: "Session", building_id: str) -> tuple[Any, list[str]] | None:
    # 값싼 지문 재계산(count(*) + max(id) 한 번) — 매 질의마다 실행되므로 반드시 저렴해야
    # 한다. 지문이 캐시와 같으면 임베딩 재계산(수 초) 없이 그대로 재사용한다.
    fingerprint = _compute_fingerprint(session, building_id)

    cached = _indexes.get(building_id)
    if cached is not None and cached[2] == fingerprint:
        return cached[0], cached[1]

    # 모델 로드와 같은 이유로 락 안에서 재확인 — 인덱스를 중복 빌드하지 않게.
    # 락 안에서도 지문을 다시 확인한다: 대기 중에 다른 스레드가 이미 최신으로 갱신했을 수 있다.
    with _index_lock:
        cached = _indexes.get(building_id)
        if cached is None or cached[2] != fingerprint:
            built = _build_index(session, building_id)
            if built is None:
                return None  # 캐시하지 않음 — 모델 준비되면 다음 요청에서 재시도
            index, store_ids = built
            _indexes[building_id] = (index, store_ids, fingerprint)
            cached = _indexes[building_id]
    return cached[0], cached[1]


def reset_indexes() -> None:
    """빌드된 인덱스 캐시를 비운다. 데이터가 바뀐 테스트 사이에서 쓴다."""
    with _index_lock:
        _indexes.clear()


def search(
    session: "Session",
    building_id: str,
    text: str,
) -> SemanticResult:
    """건물 인덱스에서 임계값 이상 최상위 1건을 사유와 함께 돌려준다.

    검색 범위는 건물 전체다 — 현재 층으로 좁히지 않는다. 자연어 질의를 던지는 사용자는
    대상이 몇 층인지 모르는 상태이고, 응답의 floor_name이 층까지 안내하기 때문이다.
    이전에는 현재 층 필터를 받았는데, 1F에서 "밥집"을 물으면 상위 후보(전부 B1 식당가)가
    필터에 전멸해 no_match가 나왔다. 현재 층 우선이 필요한 시설 찾기는 1차 경량 경로가
    층 스코프를 유지한 채 담당한다(match_ai_destination).

    실패해도 예외를 올리지 않는다 — 사유만 드러내고 예외는 그대로 삼킨다. 모델 로드
    실패가 요청을 500으로 만들면 경량 1차 경로까지 죽는다(모듈 상단 핵심 원칙).
    사유 구분은 SemanticReason 참고.
    """
    model = _get_model()
    if model is None:
        return SemanticResult(SemanticReason.MODEL_UNAVAILABLE)

    got = _get_index(session, building_id)
    if got is None:
        # _get_index는 "모델 미가용"과 "매장 0건"을 모두 None으로 준다. 다만 위에서
        # 모델을 이미 확인했고 _model은 한 번 로드되면 None으로 돌아가지 않으므로,
        # 여기까지 왔다는 건 사실상 인덱스를 못 만든 쪽이다. 둘 다 degraded라
        # 사용자 안내는 어차피 같다.
        return SemanticResult(SemanticReason.INDEX_UNAVAILABLE)
    index, store_ids = got

    # 인덱스는 store_id만 캐시한다(교차 요청 지속). ORM 객체는 매 요청 현재 세션으로 새로 로드해
    # detached 객체·stale 층 정보를 피한다.
    rows = {store.id: (store, floor) for store, floor in _load_stores(session, building_id)}

    query_vec = _encode(model, [text])
    k = min(_TOP_K, index.ntotal)
    scores, positions = index.search(query_vec, k)

    # 내림차순 정렬됨. 살아 있는 최상위 후보 1건으로 판정한다.
    # top-K를 1이 아니라 넉넉히 받는 이유는 인덱스 빌드 후 삭제된 매장을 건너뛰기 위해서다.
    for score, pos in zip(scores[0], positions[0]):
        if pos < 0:
            continue
        pair = rows.get(store_ids[pos])
        if pair is None:
            continue  # 인덱스 빌드 후 삭제된 매장 방어
        store, floor = pair
        if float(score) < SIMILARITY_THRESHOLD:
            # 최상위가 미달이면 이후도 미달 → no_match("다른 말로 다시 찾아보세요").
            return SemanticResult(SemanticReason.BELOW_THRESHOLD)
        return SemanticResult(SemanticReason.OK, (float(score), store, floor))

    # 살아 있는 후보가 하나도 없다(인덱스 빌드 후 전부 삭제 등). 인덱스가 현재 데이터를
    # 반영하지 못한 상태라 질의를 바꿔도 소용없다 → degraded 쪽으로 본다.
    return SemanticResult(SemanticReason.INDEX_UNAVAILABLE)


def semantic_search(
    session: "Session",
    building_id: str,
    text: str,
) -> tuple[float, "Store", "Floor"] | None:
    """search()의 하위 호환 래퍼. 임계값 이상 최상위 (score, Store, Floor) 1건, 없으면 None.

    사유가 필요 없는 기존 호출부(match_ai_destination·평가 스크립트)를 그대로 두기 위한
    얇은 어댑터다. 사유로 문구를 나눠야 하는 새 호출부는 search()를 쓴다.
    """
    return search(session, building_id, text).hit
