# M1-003 · 프론트–백엔드 연동 스모크 테스트

- **상태**: Draft
- **마일스톤**: M1 · 프로젝트 초기 설정
- **컴포넌트**: client / api
- **GitHub**: -
- **선행 이슈**: M1-001, M1-002 (둘 다 완료 후 시작)

## 설명

Flutter 골격(M1-001)과 FastAPI 골격(M1-002)이 각각 동작하는 것을 넘어,
**앱이 실제로 서버를 호출해 받은 데이터를 화면에 표시**하는 end-to-end 연결을 확인한다.
이 연결이 되면 마일스톤 1의 "Walking Skeleton"이 완성되고, 이후 모든 기능은
이미 뚫린 이 통로 위에 얹기만 하면 된다.

## 작업 내용

### 1. 클라이언트 API 클라이언트

- `client/lib/data/repositories/`에 `dio` 기반 API 클라이언트를 만든다.
- base URL을 `core/config/`에 환경값으로 둔다(개발: `http://10.0.2.2:8000` 안드로이드 에뮬레이터,
  `http://localhost:8000` iOS 시뮬레이터 — 플랫폼별 주소 차이 주의).

### 2. 모델 매핑

- M1-002의 `/buildings` 응답을 받을 Dart 모델(`Building`)을 `data/models/`에 정의한다.
- JSON → 모델 파싱이 동작하는지 확인한다.

### 3. 화면 연결

- M1-001의 지도 화면 진입 시 `/buildings`를 호출한다.
- 받은 건물 목록을 화면(리스트 또는 지도 마커)에 표시한다.
- 로딩/에러 상태를 Riverpod provider로 관리한다.

### 4. 실패 경로 처리

- 서버가 꺼져 있을 때 앱이 크래시하지 않고 "서버에 연결할 수 없음" 메시지를 보여준다.

### 5. 문서화

- 루트 `README.md`(또는 `docs/`)에 **로컬 풀스택 실행 순서**를 적는다:
  서버 먼저 띄우고 → 앱 실행 → 화면에 건물 목록 확인.

## 파일 (Files)

```
client/lib/data/repositories/building_repository.dart
client/lib/data/models/building.dart
client/lib/core/config/api_config.dart
client/lib/features/map/map_screen.dart      (M1-001에서 만든 것 수정)
client/lib/state/buildings_provider.dart
README.md                                     (풀스택 실행 순서 추가)
```

## 수용 기준 (Acceptance Criteria)

- 서버를 띄운 상태에서 앱을 실행하면 `/buildings` 응답이 화면에 표시된다.
- 서버가 꺼진 상태에서 앱이 크래시 없이 에러 메시지를 보여준다.
- CORS 문제 없이 호출이 성공한다(M1-002의 CORS 설정 검증 포함).
- README의 실행 순서대로 따라 하면 누구나 동일한 결과를 재현할 수 있다.

## 검증 (Verification)

```bash
# 1) 백엔드
cd api && uvicorn app.main:app --reload

# 2) 프론트엔드 (다른 터미널)
cd client && flutter run

# 3) 화면에서 건물 목록이 보이는지 확인
# 4) 서버를 끄고 앱을 새로고침 → 에러 메시지가 뜨는지 확인
```

## 메모

- 안드로이드 에뮬레이터에서 host의 localhost는 `10.0.2.2`다. 이 주소 차이로 "연결 안 됨"이
  자주 발생하므로 `api_config.dart`에서 플랫폼 분기 또는 명확한 주석을 남긴다.
- 이 이슈가 끝나면 마일스톤 1의 Definition of Done이 충족된다(README 참고).
