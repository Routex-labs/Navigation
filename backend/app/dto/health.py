# 서버 생존 확인 응답 모델.

from typing import Literal

from pydantic import BaseModel


# 서버가 살아 있는지만 알린다. Docker healthcheck와 Flutter 연결 확인이 호출한다.
class HealthResponse(BaseModel):
    status: Literal["ok"]  # 살아 있으면 항상 "ok". 죽었으면 응답 자체가 없다
