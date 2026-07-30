# 헬스 체크 라우터 — liveness와 readiness를 분리한다.
#   GET /health       → liveness (하위호환 유지: 항상 {"status":"ok"})
#   GET /health/live  → liveness 별칭
#   GET /health/ready → readiness (DB 등 의존성 확인, 안 되면 503)
#
# liveness는 "프로세스가 죽었으면 재시작하라"는 신호라 의존성을 보지 않는다.
# readiness는 "트래픽을 받아도 되냐"라 DB 같은 필수 의존성을 실제로 확인한다.
# Cloud Run·k8s 등은 이 둘을 다른 프로브로 쓴다(liveness 실패=재시작, readiness
# 실패=트래픽 제외). 기존 Docker healthcheck와 Flutter는 /health를 그대로 쓴다.

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.dto.health import HealthResponse, ReadinessResponse

router = APIRouter(tags=["health"])


# liveness. 프로세스가 응답을 돌려줄 수 있으면 항상 ok.
@router.get("/health", response_model=HealthResponse)
def health() -> dict[str, str]:
    return {"status": "ok"}


# liveness 별칭(/health/live). 프로브 이름을 명시적으로 쓰고 싶을 때.
@router.get("/health/live", response_model=HealthResponse)
def health_live() -> dict[str, str]:
    return {"status": "ok"}


# readiness. DB가 응답하면 ready, 안 되면 503으로 떨어져 트래픽에서 제외되게 한다.
@router.get("/health/ready", response_model=ReadinessResponse)
def health_ready(db: Session = Depends(get_db)) -> dict[str, str]:
    try:
        db.execute(text("SELECT 1"))
    except Exception as error:  # noqa: BLE001 - 어떤 DB 오류든 준비 안 됨(503)으로 본다
        raise HTTPException(status_code=503, detail="Database not ready") from error

    # TODO(06): query_semantic이 임베딩 워밍 상태를 공개하면(예: readiness_status())
    # 여기서 읽어 "ready"/"unknown"을 채운다. 지금은 torch 지연 로드 원칙을 지키려
    # 모델을 건드리지 않고 "unknown"으로 둔다 — /query/ai 준비 여부가 전체 readiness를
    # 막지는 않는다(DB만 필수).
    return {"status": "ready", "database": "ok", "embedding_model": "unknown"}
