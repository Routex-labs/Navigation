# 환경변수 기반 애플리케이션 설정.

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

API_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = f"sqlite:///{(API_ROOT / 'data' / 'navigation.db').as_posix()}"


# 프로세스 단위로 재사용하는 설정값.
class Settings(BaseSettings):
    database_url: str = DEFAULT_DATABASE_URL
    # 실행 환경. "production"이면 CORS 기본값이 localhost 허용을 버리고, 명시된
    # origin만 허용한다(아무것도 지정하지 않으면 교차 출처를 전부 막는다). 개발
    # 기본값에서는 localhost의 임의 포트를 허용해 Flutter 웹(random 포트)을 편하게 붙인다.
    environment: str = "development"
    # 운영 CORS 화이트리스트. 콤마로 여러 개(예: "https://app.example.com,https://admin.example.com").
    # 와일드카드('*')는 절대 기본값으로 두지 않는다 — 필요하면 origin을 명시해서 넣는다.
    # 콤마 구분 문자열로 받는 이유: pydantic-settings는 list 필드를 JSON으로 파싱하려 해
    # "a,b" 같은 평범한 env 값에서 깨진다. 파싱은 cors_origins_list 프로퍼티가 담당한다.
    cors_origins: str = ""
    # TrustedHost 화이트리스트(Host 헤더). 비어 있으면 미들웨어를 아예 걸지 않아(=필터 없음)
    # 기존 동작과 Cloud Run의 동적 호스트명·테스트 클라이언트를 깨지 않는다. 운영에서
    # 잠그려면 콤마로 호스트를 지정한다(예: "navigation-api-....run.app").
    allowed_hosts: str = ""
    # 요청 본문 최대 크기(바이트). 초과 요청은 본문을 다 읽기 전에 413으로 거절한다.
    # 우리 API는 짧은 JSON 질의만 받으므로 1MB면 충분하다. 0 이하면 제한을 끈다.
    max_request_body_bytes: int = 1_000_000
    # MVT 타일 응답의 Cache-Control max-age(초). 짧게 잡는 이유는 재시드가
    # 서버 재시작 없이 일어날 수 있어서다 — 60초면 줌 전환·층 재방문으로 요청이
    # 몰리는 구간은 덮으면서, 시드를 다시 돌린 개발자가 오래 기다리지는 않는다.
    # 만료 뒤에도 ETag 재검증이 본문 없는 304로 끝난다.
    tile_cache_max_age: int = 60
    # revision(`?v=`)이 붙은 타일 요청의 Cache-Control max-age(초). URL이 곧
    # 버전이라 내용이 바뀌면 주소가 달라진다 — 그래서 길게 잡고 immutable을
    # 함께 준다. 재검증(304)조차 나가지 않으므로 층을 오갈 때 왕복이 사라진다.
    # 1년은 RFC가 권하는 사실상의 상한이다.
    tile_versioned_cache_max_age: int = 31_536_000
    # 글리프(.pbf) 응답의 Cache-Control max-age(초). 글리프는 리소스로 커밋된
    # 사실상 불변 파일이라 하루로 길게 잡는다. 다만 URL이 내용이 아니라
    # (폰트, 범위) 이름 기반이라 immutable은 붙이지 않는다 — make_glyphs.js로
    # 다시 만들었을 때 낡은 글리프가 영원히 눌러앉는다.
    glyph_cache_max_age: int = 86400
    # MVT 타일 바이트 캐시(프로세스 메모리)의 상한 — 항목 수와 총 바이트 두 축.
    # 데모 규모 기준의 보수적 값이다: 건물 1~2동 × 층 수 × 워밍 줌(15~18) ×
    # 타일 격자 = 수백~수천 항목이고 타일 하나는 보통 수 KB~수십 KB라, 전 층을
    # 다 채워도 수십 MB 안에 든다. 무제한 dict였던 예전 구현이 오래 사는 배포
    # 프로세스에서 상한 없이 커지던 것을 이 두 상한이 막는다. 둘 중 먼저 걸리는
    # 쪽이 LRU 축출을 유발한다(작은 타일이 많으면 항목 수가, 큰 타일이 섞이면
    # 바이트가 먼저 찬다).
    tile_cache_max_entries: int = 2048
    tile_cache_max_bytes: int = 64 * 1024 * 1024  # 64MB
    # 기동 워밍업을 기본 층(앱이 처음 여는 지상 1층)만 대상으로 할지 여부.
    # True면 사용자가 즉시 보는 층의 소켓 폭주만 선제 제거하고, 나머지 층은
    # 첫 방문 때 lazy로 채운다 — 워밍 작업량·상주 메모리를 층 수만큼 줄인다.
    # False면 예전처럼 전 층을 미리 인코딩한다.
    tile_warm_default_floor_only: bool = True
    # 기동 직후 백그라운드로 임베딩 모델을 올려 첫 /query/ai의 로드 대기를 없앤다.
    # 기본은 비활성 — 켜면 앱을 만드는 모든 프로세스(테스트 포함)가 torch를 로드하고
    # 400MB대 메모리를 상주시킨다. 배포 이미지에서만 켠다.
    warm_embedding: bool = False
    # 운영 로깅 레벨(요청 상태·에러). stdout으로 남으며 Cloud Run 등이 자동 수집한다.
    # DEBUG로 내리면 우리 코드(app.*)의 상세 로그까지 볼 수 있다.
    log_level: str = "INFO"
    # 매장 입구를 가장 가까운 그래프 노드에 스냅할 때 허용하는 최대 거리(m). 이보다 멀면
    # 잘못된 원본 좌표가 벽 반대편·건물 반대편 노드에 강제 연결된 것으로 보고, 자동 연결하지
    # 않고 시드 리포트에 unresolved로 남긴다(사람 검수 대상). 실데이터 분포상 정상 입구는
    # 대부분 ~10m 안, p99≈18m이라 25m를 넘으면 오연결일 가능성이 크다. 건물 특성이 다르면
    # NAV_STORE_ENTRANCE_SNAP_MAX_M로 조정한다.
    store_entrance_snap_max_m: float = 25.0

    model_config = SettingsConfigDict(env_prefix="NAV_", case_sensitive=False)

    # 운영 환경 여부. CORS 기본 정책을 가른다.
    @property
    def is_production(self) -> bool:
        return self.environment.strip().lower() == "production"

    # 콤마 구분 env를 origin 리스트로 정리한다(공백·빈 항목 제거).
    @property
    def cors_origins_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]

    # 콤마 구분 env를 Host 리스트로 정리한다(공백·빈 항목 제거).
    @property
    def allowed_hosts_list(self) -> list[str]:
        return [item.strip() for item in self.allowed_hosts.split(",") if item.strip()]


settings = Settings()
