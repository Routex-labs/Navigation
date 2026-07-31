FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Cloud Build의 소스 위치가 저장소 루트일 때도 백엔드만 빌드한다.
COPY backend/requirements.txt .

# Cloud Run에는 GPU가 없으므로 CUDA 의존성이 없는 CPU 전용 torch를 사용한다.
RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir \
       --index-url https://download.pytorch.org/whl/cpu torch==2.7.0 \
    && python -m pip install --no-cache-dir -r requirements.txt

RUN useradd --create-home --shell /bin/bash appuser \
    && mkdir -p /app/data \
    && chown appuser:appuser /app /app/data

# Docker 빌드 컨텍스트는 저장소 루트지만, 실행 파일은 backend/ 아래만 복사한다.
COPY --chown=appuser:appuser backend/ .

ENV HF_HOME=/app/.cache/huggingface \
    NAV_WARM_EMBEDDING=1

USER appuser

# 첫 AI 질의에서 모델을 다운로드하지 않도록 이미지를 만들 때 캐시한다.
RUN python -m scripts.warm_embedding_model

EXPOSE 8080

CMD ["sh", "-c", "python -m scripts.seed.reset_and_seed && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
