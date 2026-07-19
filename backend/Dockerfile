FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p /app/data \
    && useradd --create-home --shell /bin/bash appuser \
    && chown -R appuser:appuser /app

USER appuser

# Cloud Run은 $PORT(기본 8080)로 요청을 보낸다. 로컬 실행 시에는 8080으로 뜬다.
EXPOSE 8080

# 컨테이너 시작 시 개발 DB를 시드한 뒤 서버를 띄운다.
# (data/는 .dockerignore로 이미지에 포함되지 않고, Cloud Run 파일시스템은 휘발성이므로 매 시작마다 시드)
CMD ["sh", "-c", "python -m scripts.seed.reset_and_seed && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
