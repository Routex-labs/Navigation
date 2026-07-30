# 환경변수 기반 애플리케이션 설정.

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


API_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = f"sqlite:///{(API_ROOT / 'data' / 'navigation.db').as_posix()}"


# 프로세스 단위로 재사용하는 설정값.
class Settings(BaseSettings):
    database_url: str = DEFAULT_DATABASE_URL
    # MVT 타일 응답의 Cache-Control max-age(초). 짧게 잡는 이유는 재시드가
    # 서버 재시작 없이 일어날 수 있어서다 — 60초면 줌 전환·층 재방문으로 요청이
    # 몰리는 구간은 덮으면서, 시드를 다시 돌린 개발자가 오래 기다리지는 않는다.
    # 만료 뒤에도 ETag 재검증이 본문 없는 304로 끝난다.
    tile_cache_max_age: int = 60
    # 글리프(.pbf) 응답의 Cache-Control max-age(초). 글리프는 리소스로 커밋된
    # 사실상 불변 파일이라 하루로 길게 잡는다. 다만 URL이 내용이 아니라
    # (폰트, 범위) 이름 기반이라 immutable은 붙이지 않는다 — make_glyphs.js로
    # 다시 만들었을 때 낡은 글리프가 영원히 눌러앉는다.
    glyph_cache_max_age: int = 86400
    # 기동 직후 백그라운드로 임베딩 모델을 올려 첫 /query/ai의 로드 대기를 없앤다.
    # 기본은 비활성 — 켜면 앱을 만드는 모든 프로세스(테스트 포함)가 torch를 로드하고
    # 400MB대 메모리를 상주시킨다. 배포 이미지에서만 켠다.
    warm_embedding: bool = False
    # 운영 로깅 레벨(요청 상태·에러). stdout으로 남으며 Cloud Run 등이 자동 수집한다.
    # DEBUG로 내리면 우리 코드(app.*)의 상세 로그까지 볼 수 있다.
    log_level: str = "INFO"

    model_config = SettingsConfigDict(env_prefix="NAV_", case_sensitive=False)


settings = Settings()
