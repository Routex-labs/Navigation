# base image를 digest로 고정한다(공급망 재현성) — 같은 소스가 항상 같은 base 레이어를
# 받도록. 태그(python:3.12-slim)는 이동하므로 digest를 병기한다. 값 갱신 시 태그의
# 현재 digest를 `docker buildx imagetools inspect python:3.12-slim`으로 재확인한다.
FROM python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .

# torch를 CPU 전용 휠로 먼저 고정한다. requirements.txt의 sentence-transformers는
# torch>=1.11만 요구하므로, PyPI 기본 인덱스에 맡기면 리눅스에서 CUDA 빌드를 끌어온다
# (torch 731MB + nvidia-*/triton 14개 2,178MB = 압축 기준 약 2.9GB).
# 서버는 CPU 추론만 하므로 GPU 런타임은 전부 죽은 용량이다. CPU 휠은 168MB.
# requirements.txt는 건드리지 않는다 — Windows/macOS 로컬 개발은 이미 CPU 휠을 받는다.
RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir \
       --index-url https://download.pytorch.org/whl/cpu torch==2.7.0 \
    && python -m pip install --no-cache-dir -r requirements.txt

# appuser를 /app에 큰 파일을 쓰기 전에 만든다. 나중에 chown -R /app을 하면
# 모델 캐시(약 420MB)를 통째로 새 레이어에 복사해 이미지가 약 450MB 불어난다.
# 대신 여기서 유저를 만들고 /app 소유권만 넘긴 뒤, 이후 쓰기를 처음부터 appuser로 한다.
RUN useradd --create-home --shell /bin/bash appuser \
    && mkdir -p /app/data \
    && chown appuser:appuser /app /app/data

# 소스를 처음부터 appuser 소유로 복사한다(런타임에 재-chown 불필요).
COPY --chown=appuser:appuser . .

# 임베딩 모델 캐시를 이미지 안에 고정한다. 지정하지 않으면 빌드는 root의 ~/.cache에,
# 런타임은 appuser의 ~/.cache에 캐시를 찾아 서로 어긋난다.
ENV HF_HOME=/app/.cache/huggingface \
    NAV_WARM_EMBEDDING=1

USER appuser

# AI 질의용 모델(약 420MB)을 빌드 시점에 appuser로 받아 둔다. 캐시가 처음부터 appuser
# 소유라 chown -R가 필요없다. 이걸 빼면 Cloud Run 콜드 스타트마다 첫 /query/ai 요청이
# 다운로드를 기다린다(파일시스템이 휘발성이라 캐시가 남지 않는다).
RUN python -m scripts.warm_embedding_model

# Cloud Run은 $PORT(기본 8080)로 요청을 보낸다. 로컬 실행 시에는 8080으로 뜬다.
EXPOSE 8080

# 컨테이너 시작 = 서버 실행만. 시드는 기본적으로 하지 않는다 — 매 시작마다
# reset-and-seed를 돌리면 재시작이 DB를 통째로 초기화한다(운영에서는 데이터 파괴).
# 시드는 별도 1회성 명령으로 분리한다(로컬: `python -m scripts.seed.reset_and_seed`,
# compose: `docker compose run --rm seed`).
#
# 예외: 휘발성 파일시스템(현재 Cloud Run 데모)은 재시작마다 빈 DB로 뜨므로, 그때만
# NAV_SEED_ON_START=1을 명시해 기동 직전 1회 시드하게 열어 둔다. 기본값(미설정)은
# 시드하지 않는다 — 즉 영속 DB에서는 재시작이 DB를 건드리지 않는다.
CMD ["sh", "-c", "if [ \"$NAV_SEED_ON_START\" = \"1\" ]; then python -m scripts.seed.reset_and_seed; fi; exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
