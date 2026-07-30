# 서버 생존/준비 확인 응답 모델.

from typing import Literal

from pydantic import BaseModel


# 서버가 살아 있는지만 알린다(liveness). Docker healthcheck와 Flutter 연결 확인이 호출한다.
# 프로세스가 응답을 돌려줄 수 있으면 항상 "ok" — 의존성(DB·모델)은 보지 않는다.
class HealthResponse(BaseModel):
    status: Literal["ok"]  # 살아 있으면 항상 "ok". 죽었으면 응답 자체가 없다


# 트래픽을 받을 준비가 됐는지 알린다(readiness). liveness와 달리 의존성을 확인한다.
#   database        — 요청 처리에 필수. SELECT 1이 되면 "ok", 실패면 503으로 떨어진다.
#   embedding_model — /query/ai 워밍 상태. 06번이 공개할 상태 함수와 연계 예정이라
#                     지금은 "unknown"으로 둔다(TODO: 06 연계). 준비 여부를 막지는 않는다.
class ReadinessResponse(BaseModel):
    status: Literal["ready"]  # 준비되면 "ready", 아니면 응답 자체가 503
    database: Literal["ok"]
    embedding_model: Literal["ready", "unknown"]
