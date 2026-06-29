# M1-001 · Flutter 클라이언트 골격 생성

- **상태**: Draft
- **마일스톤**: M1 · 프로젝트 초기 설정
- **컴포넌트**: client
- **GitHub**: -
- **선행 이슈**: 없음 (M1-002와 병렬 가능)

## 설명

측위·RAG 같은 본 기능에 앞서, 앱이 실행되고 지도가 뜨는 **최소 Flutter 골격**을 만든다.
[06-tech-stack.md](../../docs/research/06-tech-stack.md)에서 정한 패키지와 디렉토리 구조를
실제 파일로 옮기는 것이 목표다. 이 골격 위에서 이후 PDR·필터·RAG 기능을 채워 나간다.

## 작업 내용

### 1. 프로젝트 생성

- 저장소 루트에 `client/`로 Flutter 앱을 생성한다.
  ```bash
  flutter create --org com.navigation --project-name navigation_client client
  ```
- `flutter --version`으로 SDK가 stable 채널 3.24+ 인지 확인한다. 없으면 README에 설치 안내를 남긴다.

### 2. 패키지 추가

- `client/pubspec.yaml`에 06 문서의 핵심 패키지를 추가한다.
  ```yaml
  dependencies:
    sensors_plus: ^6.0
    geolocator: ^13.0
    flutter_map: ^7.0
    latlong2: ^0.9
    vector_math: ^2.1
    dio: ^5.0
    flutter_riverpod: ^2.5
    shared_preferences: ^2.3
  dev_dependencies:
    flutter_lints: ^4.0
  ```
- `flutter pub get`이 성공하는지 확인한다.

### 3. 디렉토리 구조 잡기

- 06 문서의 구조대로 `client/lib/` 아래 폴더와 빈 placeholder 파일을 만든다.
  ```
  lib/
  ├─ main.dart
  ├─ core/sensors/        core/math/        core/config/
  ├─ pdr/                 (step_detector.dart 등 빈 stub)
  ├─ navigation/
  ├─ data/models/         data/repositories/
  ├─ features/map/        features/assistant/
  └─ state/
  ```
- stub 파일은 TODO 주석 한 줄만 두어 이후 이슈에서 채울 자리를 표시한다.

### 4. 최소 앱 셸

- `main.dart`에서 `ProviderScope`(Riverpod)로 앱을 감싼다.
- `features/map/`에 `flutter_map` 기반 빈 지도 화면 1개를 띄운다(평면도 오버레이는 placeholder).
- 하단/상단에 "Navigation" 타이틀과 더미 위치 마커 1개를 표시한다.

### 5. 권한 설정

- iOS `Info.plist`, Android `AndroidManifest.xml`에 위치 권한 키를 추가한다
  (실제 사용은 이후 이슈, 여기서는 빌드가 깨지지 않게 키만 선언).

### 6. 문서화

- `client/README.md`에 실행법(`flutter pub get` → `flutter run`)과 SDK 요구 버전을 적는다.

## 파일 (Files)

```
client/pubspec.yaml
client/lib/main.dart
client/lib/features/map/map_screen.dart
client/lib/...               (06 문서 구조의 stub들)
client/README.md
client/ios/Runner/Info.plist          (권한 키)
client/android/app/src/main/AndroidManifest.xml
```

## 수용 기준 (Acceptance Criteria)

- `flutter pub get`이 에러 없이 끝난다.
- `flutter run`(또는 시뮬레이터/에뮬레이터)으로 앱이 실행되고 빈 지도 화면이 뜬다.
- `lib/` 디렉토리 구조가 06 문서와 일치한다.
- `client/README.md`만 보고 다른 팀원이 앱을 띄울 수 있다.
- `flutter analyze`가 통과한다(경고 0 목표).

## 검증 (Verification)

```bash
cd client
flutter pub get
flutter analyze
flutter run          # 시뮬레이터/실기기에서 빈 지도 확인
```

## 메모

- Flutter SDK 미설치 PC가 있을 수 있다. 골격 PR에는 `pubspec.yaml`·`lib/` 구조까지 포함하고,
  실제 `flutter run` 검증은 SDK 보유 팀원이 담당하도록 역할을 나눈다.
- 본 기능(센서·PDR)은 이 이슈 범위가 **아니다.** 빈 화면이 뜨면 성공이다.
