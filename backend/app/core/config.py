# 환경변수 기반 애플리케이션 설정.

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


API_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = f"sqlite:///{(API_ROOT / 'data' / 'navigation.db').as_posix()}"


# 프로세스 단위로 재사용하는 설정값.
class Settings(BaseSettings):
    database_url: str = DEFAULT_DATABASE_URL
    # 개발 중 실제 SQL/파라미터를 sql/queries.sql에 남긴다. 기본은 비활성화한다.
    sql_echo: bool = False
    # Flutter 등 클라이언트가 API로 보낸 JSON과 JSON 응답을 args/에 남긴다.
    http_capture: bool = False

    model_config = SettingsConfigDict(env_prefix="NAV_", case_sensitive=False)


settings = Settings()
