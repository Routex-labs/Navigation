# 환경변수 기반 애플리케이션 설정.

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


API_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = f"sqlite:///{(API_ROOT / 'data' / 'navigation.db').as_posix()}"


# 프로세스 단위로 재사용하는 설정값.
class Settings(BaseSettings):
    database_url: str = DEFAULT_DATABASE_URL

    model_config = SettingsConfigDict(env_prefix="NAV_", case_sensitive=False)


settings = Settings()
