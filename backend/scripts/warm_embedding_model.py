# AI 질의(/query/ai)용 문장 임베딩 모델을 로컬 캐시에 미리 받아 두는 CLI.
# 실행 방법 (backend/ 디렉토리에서):
#   python -m scripts.warm_embedding_model
#
# 왜 필요한가:
#   query_semantic._load_model()은 로컬 캐시를 먼저 보고 없을 때만 Hub로 폴백한다.
#   캐시가 비어 있으면 그 폴백이 "첫 /query/ai 요청" 시점에 일어나 사용자가 다운로드를
#   기다리게 된다(모델 약 420MB). 새 머신 세팅과 Docker 이미지 빌드에서 이 스크립트로
#   캐시를 미리 채워 두면, 런타임 첫 질의는 캐시 히트만 하고 끝난다.
#
# 캐시 위치는 HF_HOME 환경변수를 따른다(기본: ~/.cache/huggingface).

from __future__ import annotations

from app.repositories.query_semantic import _MODEL_NAME, _MODEL_REVISION, _load_model


def warm_embedding_model() -> None:
    # _load_model()은 _MODEL_NAME과 _MODEL_REVISION(commit hash)을 함께 고정해
    # 받으므로, 워밍 캐시와 런타임 로드가 동일한 artifact를 가리킨다.
    model = _load_model()
    # 실제로 인코딩까지 돌려 가중치·토크나이저가 모두 갖춰졌는지 확인한다.
    # 파일만 받아지고 로드가 깨지는 경우를 빌드 시점에 잡기 위해서다.
    model.encode(["화장실"], normalize_embeddings=True, convert_to_numpy=True)


if __name__ == "__main__":
    warm_embedding_model()
    print(f"임베딩 모델 캐시 준비 완료({_MODEL_NAME}@{_MODEL_REVISION})")
