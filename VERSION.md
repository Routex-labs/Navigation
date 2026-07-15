# VERSION

서비스별 **기술 스택 버전**과 그에 대응하는 **서버 도커 이미지**를 기록한다.

> 규칙: 베이스 이미지, 런타임, 핵심 의존성 버전을 올릴 때마다 이 표를 갱신하고,
> 큰 변경은 [HISTORY.md](HISTORY.md)에도 한 줄 남긴다.

## 프로젝트 버전

| 항목 | 값 |
|---|---|
| 프로젝트 버전 | `0.1.0` |
| 최종 갱신일 | 2026-07-15 |

## 컴포넌트별 스택 / 이미지

상세 설계 근거는 [docs/research/06-tech-stack.md](docs/research/06-tech-stack.md)를 참조한다.
아래 값은 현재 `client/pubspec.yaml`과 `api/requirements.txt` 기준으로 관리한다.

| 컴포넌트 | 언어 / 런타임 | 핵심 의존성 | 베이스 이미지 | 이미지 태그 | 포트 |
|---|---|---|---|---|---|
| 클라이언트 (앱) | Dart / Flutter | `http`, `permission_handler`, `flutter_map`, `latlong2`, `geolocator`, `flutter_svg` | (앱 빌드, 이미지 없음) | - | - |
| API 서버 | Python 3.12 | FastAPI 0.115.*, `uvicorn` 0.32.*, `pydantic` 2.9.*, SQLAlchemy 2.0+ | `python:3.12-slim` | `navigation/api:0.1.0` | 8001 |
| 데이터 | SQLite | SQLAlchemy ORM 모델, 개발용 reset/seed 스크립트 | - | - | - |

## 버전 정책

- 서버 이미지 태그는 `navigation/<component>:<프로젝트 버전>` 형식을 따른다.
- 시맨틱 버저닝(MAJOR.MINOR.PATCH)을 사용한다.
  - MAJOR: 호환성이 깨지는 변경
  - MINOR: 하위 호환되는 기능 추가
  - PATCH: 버그 수정 / 의존성 패치
- 베이스 이미지 버전을 고정하여 재현 가능한 빌드를 보장한다. `latest` 태그는 사용하지 않는다.

## 갱신 절차

1. 의존성 또는 베이스 이미지 버전을 변경한다.
2. 위 표와 `프로젝트 버전`을 갱신한다.
3. 큰 변경이면 [HISTORY.md](HISTORY.md)에 날짜와 요약을 추가한다.
