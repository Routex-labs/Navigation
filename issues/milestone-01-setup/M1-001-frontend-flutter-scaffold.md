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

## 전체 디렉토리 구조 (flutter create 실행 후 실제 상태)

> `flutter create` + `flutter pub get` 실행 결과 생성된 파일 전체 목록이다.  
> `*` 표시는 자동 생성 파일(직접 편집 불필요), 표시 없는 항목은 작업 대상이 될 수 있는 파일이다.  
> `.dart_tool/` · `.idea/` 내부는 모두 자동 생성이므로 대표 파일만 표기했다.

```
client/
├─ .dart_tool/                          * flutter pub get이 생성하는 툴체인 메타데이터 폴더
│   ├─ package_config.json              * 설치된 패키지 경로 맵
│   ├─ package_graph.json               * 패키지 의존성 그래프
│   └─ dartpad/
│       └─ web_plugin_registrant.dart   * DartPad 웹 플러그인 자동 등록
├─ .idea/                               * Android Studio / IntelliJ IDE 설정 폴더
│   ├─ modules.xml                      * 프로젝트 모듈 목록
│   ├─ workspace.xml                    * 개인 작업공간 상태 (열린 파일, 창 배치 등)
│   └─ libraries/
│       ├─ Dart_SDK.xml                 * Dart SDK 경로 참조
│       └─ KotlinJavaRuntime.xml        * Kotlin/Java 런타임 경로 참조
│   └─ runConfigurations/
│       └─ main_dart.xml                * lib/main.dart 실행 구성
├─ android/
│   ├─ .gitignore
│   ├─ build.gradle.kts                 프로젝트 전체 Gradle 플러그인 버전 설정
│   ├─ gradle.properties                Gradle 동작 옵션 (AndroidX, JVM 메모리 등)
│   ├─ gradlew                          * Linux/macOS용 Gradle Wrapper 실행 스크립트
│   ├─ gradlew.bat                      * Windows용 Gradle Wrapper 실행 스크립트
│   ├─ local.properties                 로컬 SDK 경로 (.gitignore 포함, VCS 제외)
│   ├─ navigation_client_android.iml    * Android Studio 모듈 정의
│   ├─ settings.gradle.kts              Gradle 모듈 선언 및 저장소 설정
│   ├─ app/
│   │   ├─ build.gradle.kts             앱 모듈 빌드 설정 (compileSdk, minSdk, 앱 ID 등)
│   │   └─ src/
│   │       ├─ debug/
│   │       │   └─ AndroidManifest.xml  디버그 빌드 전용 매니페스트
│   │       ├─ profile/
│   │       │   └─ AndroidManifest.xml  프로파일링 빌드 전용 매니페스트
│   │       └─ main/
│   │           ├─ AndroidManifest.xml  앱 선언 (액티비티, 권한 등) ← 권한 추가 필요
│   │           ├─ java/io/flutter/plugins/
│   │           │   └─ GeneratedPluginRegistrant.java  * 플러그인 자동 등록 (자동 생성)
│   │           ├─ kotlin/com/navigation/navigation_client/
│   │           │   └─ MainActivity.kt  Android 네이티브 진입점
│   │           └─ res/
│   │               ├─ drawable/
│   │               │   └─ launch_background.xml        스플래시 배경 (라이트 모드)
│   │               ├─ drawable-v21/
│   │               │   └─ launch_background.xml        스플래시 배경 (API 21+)
│   │               ├─ mipmap-hdpi/ic_launcher.png      앱 아이콘 (hdpi)
│   │               ├─ mipmap-mdpi/ic_launcher.png      앱 아이콘 (mdpi)
│   │               ├─ mipmap-xhdpi/ic_launcher.png     앱 아이콘 (xhdpi)
│   │               ├─ mipmap-xxhdpi/ic_launcher.png    앱 아이콘 (xxhdpi)
│   │               ├─ mipmap-xxxhdpi/ic_launcher.png   앱 아이콘 (xxxhdpi)
│   │               ├─ values/styles.xml                LaunchTheme / NormalTheme 정의
│   │               └─ values-night/styles.xml          다크모드 테마 정의
│   └─ gradle/wrapper/
│       └─ gradle-wrapper.properties    사용할 Gradle 버전 명시
├─ ios/
│   ├─ .gitignore
│   ├─ Flutter/
│   │   ├─ AppFrameworkInfo.plist       Flutter 프레임워크 버전 정보
│   │   ├─ Debug.xcconfig               디버그 빌드 Xcode 변수
│   │   ├─ Generated.xcconfig           * flutter build 시 자동 갱신되는 빌드 변수
│   │   ├─ Release.xcconfig             릴리즈 빌드 Xcode 변수
│   │   ├─ flutter_export_environment.sh * Flutter 환경 변수 익스포트 스크립트
│   │   └─ ephemeral/                   * flutter pub get이 생성하는 임시 파일 (VCS 제외)
│   │       ├─ flutter_lldb_helper.py   * LLDB 디버깅 헬퍼
│   │       ├─ flutter_lldbinit         * LLDB 초기화 스크립트
│   │       ├─ flutter_native_integration.env  * 네이티브 통합 환경값
│   │       └─ Packages/FlutterGeneratedPluginSwiftPackage/
│   │           ├─ Package.swift        * Swift Package Manager 플러그인 패키지 정의
│   │           └─ Sources/.../FlutterGeneratedPluginSwiftPackage.swift  * 플러그인 등록
│   ├─ Runner/
│   │   ├─ AppDelegate.swift            iOS 앱 진입점, Flutter 엔진 초기화
│   │   ├─ SceneDelegate.swift          iOS 13+ Scene 생명주기 처리
│   │   ├─ Info.plist                   앱 설정 및 권한 선언 ← 위치 권한 추가 필요
│   │   ├─ Runner-Bridging-Header.h     Swift ↔ Objective-C 브릿지 헤더
│   │   ├─ GeneratedPluginRegistrant.h  * 플러그인 등록 헤더 (자동 생성)
│   │   ├─ GeneratedPluginRegistrant.m  * 플러그인 등록 구현 (자동 생성)
│   │   ├─ Assets.xcassets/
│   │   │   ├─ AppIcon.appiconset/      앱 아이콘 (해상도별 PNG + Contents.json)
│   │   │   └─ LaunchImage.imageset/    런치 이미지 (해상도별 PNG + Contents.json)
│   │   └─ Base.lproj/
│   │       ├─ LaunchScreen.storyboard  스플래시 화면 레이아웃
│   │       └─ Main.storyboard          메인 화면 진입 스토리보드
│   ├─ Runner.xcodeproj/
│   │   ├─ project.pbxproj              Xcode 프로젝트 정의 (직접 편집 금지)
│   │   ├─ project.xcworkspace/         Xcode 워크스페이스 메타데이터
│   │   └─ xcshareddata/xcschemes/
│   │       └─ Runner.xcscheme          Xcode 빌드/실행 스킴
│   ├─ Runner.xcworkspace/              CocoaPods 포함 통합 워크스페이스 (Xcode 열 때 사용)
│   └─ RunnerTests/
│       └─ RunnerTests.swift            iOS 네이티브 단위 테스트
├─ lib/
│   └─ main.dart                        Dart 진입점 ← 이 이슈에서 교체 대상
├─ linux/
│   ├─ .gitignore
│   ├─ CMakeLists.txt                   Linux 최상위 CMake 빌드 스크립트
│   ├─ flutter/
│   │   ├─ CMakeLists.txt              Flutter 엔진 연결 CMake
│   │   ├─ generated_plugin_registrant.cc  * 플러그인 자동 등록 구현
│   │   ├─ generated_plugin_registrant.h   * 플러그인 자동 등록 헤더
│   │   └─ generated_plugins.cmake     * 플러그인 목록 CMake 변수
│   └─ runner/
│       ├─ CMakeLists.txt              러너 빌드 스크립트
│       ├─ main.cc                     Linux 앱 진입점
│       ├─ my_application.cc           GTK 윈도우 + Flutter 엔진 구현
│       └─ my_application.h            위 헤더
├─ macos/
│   ├─ .gitignore
│   ├─ Flutter/
│   │   ├─ Flutter-Debug.xcconfig      디버그 빌드 Xcode 변수
│   │   ├─ Flutter-Release.xcconfig    릴리즈 빌드 Xcode 변수
│   │   ├─ GeneratedPluginRegistrant.swift  * 플러그인 자동 등록 (자동 생성)
│   │   └─ ephemeral/                  * 임시 파일 (VCS 제외, iOS와 동일 구조)
│   ├─ Runner/
│   │   ├─ AppDelegate.swift           macOS 앱 진입점
│   │   ├─ MainFlutterWindow.swift     macOS Flutter 윈도우 초기화
│   │   ├─ Info.plist                  앱 설정
│   │   ├─ DebugProfile.entitlements   디버그/프로파일 빌드 샌드박스 권한
│   │   ├─ Release.entitlements        릴리즈 빌드 샌드박스 권한
│   │   ├─ Assets.xcassets/AppIcon.appiconset/  앱 아이콘 (해상도별)
│   │   ├─ Base.lproj/MainMenu.xib     macOS 메뉴바·윈도우 레이아웃
│   │   └─ Configs/
│   │       ├─ AppInfo.xcconfig        앱 이름·버전 Xcode 변수
│   │       ├─ Debug.xcconfig
│   │       ├─ Release.xcconfig
│   │       └─ Warnings.xcconfig       컴파일러 경고 설정
│   ├─ Runner.xcodeproj/               Xcode 프로젝트 (직접 편집 금지)
│   ├─ Runner.xcworkspace/             통합 워크스페이스
│   └─ RunnerTests/
│       └─ RunnerTests.swift           macOS 네이티브 단위 테스트
├─ test/
│   └─ widget_test.dart                Flutter 위젯 테스트 (기본 카운터 앱 테스트)
├─ web/
│   ├─ favicon.png                     브라우저 탭 아이콘
│   ├─ index.html                      웹 플랫폼 진입점 HTML
│   ├─ manifest.json                   PWA 메타데이터 (앱 이름, 아이콘, 테마색)
│   └─ icons/
│       ├─ Icon-192.png                PWA 아이콘 (192×192)
│       ├─ Icon-512.png                PWA 아이콘 (512×512)
│       ├─ Icon-maskable-192.png       Android 어댑티브 아이콘용 (192×192)
│       └─ Icon-maskable-512.png       Android 어댑티브 아이콘용 (512×512)
├─ windows/
│   ├─ .gitignore
│   ├─ CMakeLists.txt                  Windows 최상위 CMake 빌드 스크립트
│   ├─ flutter/
│   │   ├─ CMakeLists.txt
│   │   ├─ generated_plugin_registrant.cc  * 플러그인 자동 등록 구현
│   │   ├─ generated_plugin_registrant.h   * 플러그인 자동 등록 헤더
│   │   └─ generated_plugins.cmake         * 플러그인 목록 CMake 변수
│   └─ runner/
│       ├─ CMakeLists.txt
│       ├─ Runner.rc                   앱 아이콘·버전 정보 리소스 스크립트
│       ├─ flutter_window.cpp          Win32 윈도우에 Flutter 뷰 삽입
│       ├─ flutter_window.h
│       ├─ main.cpp                    Windows 앱 진입점 (wWinMain)
│       ├─ resource.h                  리소스 ID 상수 정의
│       ├─ runner.exe.manifest         DPI 인식·UAC 권한 실행 매니페스트
│       ├─ utils.cpp                   UTF-8 ↔ UTF-16 변환 유틸
│       ├─ utils.h
│       ├─ win32_window.cpp            Win32 창 생성·메시지 루프
│       ├─ win32_window.h
│       └─ resources/
│           └─ app_icon.ico            Windows 앱 아이콘
├─ .gitignore
├─ .metadata                           * Flutter 툴이 프로젝트 유형을 식별하는 메타데이터
├─ README.md                           실행법·SDK 요구 버전 ← 이 이슈에서 작성 대상
├─ analysis_options.yaml               Dart 린트 규칙 설정
├─ navigation_client.iml               * Android Studio 모듈 정의
├─ pubspec.lock                        * 패키지 버전 잠금 파일 (VCS에 커밋)
└─ pubspec.yaml                        패키지 의존성·앱 설정 ← 이 이슈에서 패키지 추가 대상
```

---

## 현재 디렉토리 구조 (flutter create 직후 상태)

```
client/
├─ lib/
│   └─ main.dart                  # Flutter 기본 카운터 앱 (교체 대상)
├─ android/
│   └─ app/src/main/
│       ├─ AndroidManifest.xml    # 위치 권한 키 미선언 (작업 필요)
│       └─ kotlin/.../MainActivity.kt
├─ ios/
│   └─ Runner/
│       ├─ Info.plist             # 위치 권한 키 미선언 (작업 필요)
│       └─ AppDelegate.swift
├─ pubspec.yaml                   # 핵심 패키지 미추가 (작업 필요)
├─ analysis_options.yaml          # flutter_lints 기본 설정
└─ README.md                      # 없음 (작업 필요)
```

**이 이슈에서 해야 할 변경**

```
client/
├─ lib/
│   ├─ main.dart                  # ProviderScope 감싸기, 지도 화면 연결
│   ├─ core/
│   │   ├─ sensors/               # sensors_plus 래퍼 stub
│   │   ├─ math/                  # 벡터·좌표 변환 유틸 stub
│   │   └─ config/                # 상수·환경값 stub
│   ├─ pdr/
│   │   ├─ step_detector.dart     # TODO stub
│   │   ├─ stride_estimator.dart  # TODO stub
│   │   ├─ heading_filter.dart    # TODO stub
│   │   ├─ pdr_engine.dart        # TODO stub
│   │   └─ particle_filter.dart   # TODO stub
│   ├─ navigation/
│   │   ├─ io_transition.dart     # TODO stub
│   │   └─ route_planner.dart     # TODO stub
│   ├─ data/
│   │   ├─ models/                # freezed 모델 stub
│   │   └─ repositories/          # FastAPI 호출 stub
│   ├─ features/
│   │   ├─ map/
│   │   │   └─ map_screen.dart    # flutter_map 빈 지도 화면 (실제 구현)
│   │   └─ assistant/             # RAG UI stub
│   └─ state/                     # Riverpod providers stub
├─ android/app/src/main/
│   └─ AndroidManifest.xml        # ACCESS_FINE_LOCATION 권한 추가
├─ ios/Runner/
│   └─ Info.plist                 # NSLocationWhenInUseUsageDescription 추가
├─ pubspec.yaml                   # 핵심 패키지 추가
└─ README.md                      # 실행법·SDK 요구 버전 문서화
```

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

## 알려진 문제 (Known Issues)

### `flutter upgrade` 실패 — Dart SDK rename 권한 오류

**증상**
```
Rename-Item : 'C:\flutter\bin\cache\dart-sdk' 에 새 파일 액세스가 차단되었습니다.
Error: Unable to update Dart SDK after 3 retries.
```

**원인**: 다른 프로세스(VS Code, Android Studio, 다른 터미널 등)가 `dart-sdk` 폴더를 점유 중이어서 rename이 막힌 것.

**해결**
1. VS Code, Android Studio, 열려 있는 PowerShell/터미널 창 전부 닫기
2. 작업 관리자(Ctrl+Shift+Esc) → `dart.exe`, `flutter_tools` 프로세스 종료
3. 새 터미널에서 `flutter upgrade` 재실행

## Gradle이란

Gradle은 **Android 앱을 빌드하는 자동화 도구**다.

소스 코드를 APK(설치 파일)로 만들려면 컴파일, 리소스 압축, 서명 등 수십 단계의 작업이 순서대로 실행되어야 한다. 이 과정을 매번 손으로 실행하는 대신 Gradle이 자동으로 처리해준다.

Flutter 프로젝트에서 `flutter run`을 입력하면 Flutter CLI가 내부적으로 Gradle을 호출해 Android 빌드를 진행한다. 개발자가 직접 Gradle 명령어를 입력할 일은 거의 없다.

### 이 프로젝트에서 Gradle이 읽는 파일들

```
android/
├─ settings.gradle.kts   ← 빌드에 포함할 모듈 목록 선언
├─ build.gradle.kts      ← 전체 프로젝트 Gradle 플러그인 버전 설정
├─ gradle.properties     ← JVM 메모리, AndroidX 활성화 등 옵션
├─ local.properties      ← 로컬 SDK 경로 (Git에 올리지 않음)
└─ app/
    └─ build.gradle.kts  ← 앱 ID, 최소 Android 버전, 컴파일 버전 등
```

### Gradle Wrapper란

`gradlew` / `gradlew.bat` 파일이 Gradle Wrapper다. Gradle 자체를 PC에 따로 설치하지 않아도 되도록, 지정된 버전의 Gradle을 자동으로 내려받아 실행해주는 스크립트다. `gradle/wrapper/gradle-wrapper.properties`에 사용할 Gradle 버전이 명시되어 있어 팀원 간 버전을 통일할 수 있다.

### `.kts` 확장자가 붙는 이유

Gradle 스크립트는 원래 Groovy 언어(`.gradle`)로 작성했지만, 최근에는 Kotlin DSL(`.gradle.kts`)을 사용한다. Flutter가 새 프로젝트를 생성할 때 기본으로 `.kts`를 택하는 이유는 타입 안전성과 IDE 자동완성이 더 잘 지원되기 때문이다.

### local.properties — 왜 Git에 올리지 않는가

`android/local.properties` 파일을 열면 이런 내용이 있다.

```properties
sdk.dir=C:\Users\user\AppData\Local\Android\Sdk
flutter.sdk=C:\flutter
```

SDK 자체(도구 묶음)가 아니라 **SDK가 내 PC 어디에 설치되어 있는지의 경로**를 담은 파일이다. Gradle이 빌드할 때 Android SDK와 Flutter SDK를 찾아야 하는데, 그 위치를 여기서 읽어온다.

Git에 올리지 않는 이유는 **팀원마다 설치 경로가 다르기 때문**이다.

```
나의 PC        →  sdk.dir=C:\Users\user\AppData\Local\Android\Sdk
팀원 A의 Mac   →  sdk.dir=/Users/teamA/Library/Android/sdk
팀원 B의 Linux →  sdk.dir=/home/teamB/Android/Sdk
```

만약 이 파일을 Git에 커밋하면 내 경로가 저장소에 올라가고, 팀원이 내려받았을 때 경로가 달라 빌드가 실패한다. 경로는 각자의 환경에 맞게 자동으로 생성되어야 하므로 `.gitignore`에 등록해 공유하지 않는다.

`flutter run`을 처음 실행하거나 `flutter pub get`을 실행하면 Flutter CLI가 현재 PC의 SDK 설치 위치를 자동으로 감지해 이 파일을 생성한다. 팀원이 저장소를 새로 클론해도 `flutter pub get` 한 번이면 자신의 환경에 맞는 `local.properties`가 만들어진다.

### JVM과 JVM 메모리 설정

Gradle은 Java로 만들어진 도구라 실행될 때 JVM(Java Virtual Machine) 위에서 동작한다. JVM은 Java·Kotlin 코드를 운영체제에 관계없이 실행할 수 있게 해주는 가상 실행 환경이다. Gradle 자체가 JVM 프로세스이므로, 빌드 중 소스 코드를 분석하고 컴파일하는 작업이 모두 JVM 메모리 안에서 일어난다.

`gradle.properties`의 아래 줄이 JVM에 할당할 메모리를 지정한다.

```properties
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError
```

| 옵션 | 의미 |
|------|------|
| `-Xmx8G` | JVM 힙(Heap) 최대 크기를 8GB로 설정한다. 힙은 컴파일 중 생성되는 객체들이 올라가는 공간이다. 너무 작으면 대형 프로젝트 빌드 중 `OutOfMemoryError`가 발생한다. |
| `-XX:MaxMetaspaceSize=4G` | 메타스페이스 최대 크기를 4GB로 설정한다. 메타스페이스는 클래스 정의(메서드, 필드 구조 등)가 저장되는 공간이다. 플러그인이 많아질수록 로드되는 클래스 수가 늘어 이 공간이 필요해진다. |
| `-XX:ReservedCodeCacheSize=512m` | JIT 컴파일러가 생성한 네이티브 코드를 캐싱하는 공간을 512MB로 설정한다. |
| `-XX:+HeapDumpOnOutOfMemoryError` | 메모리 부족으로 빌드가 실패할 경우 힙 덤프 파일을 생성해 원인 분석을 돕는다. |

### AndroidX란

AndroidX는 **Android 지원 라이브러리의 최신 버전**이다. 배경을 이해하려면 Android 지원 라이브러리의 역사를 간단히 알아야 한다.

Android는 버전마다 새로운 기능을 추가하지만, 구형 기기에서는 최신 API를 쓸 수 없다. Google은 이 문제를 해결하기 위해 구형 Android에서도 최신 기능을 쓸 수 있게 해주는 **지원 라이브러리(Support Library)** 를 별도로 배포해왔다. 그런데 이 라이브러리의 패키지명이 `android.support.*`로 뒤죽박죽 관리되어 버전 충돌이 잦았다.

Google은 2018년에 이를 전면 개편해 `androidx.*`라는 통일된 패키지 구조로 재출시했고, 이것이 AndroidX다. 이후 모든 신규 Android 라이브러리는 AndroidX로만 출시된다.

`gradle.properties`의 아래 줄이 AndroidX 사용을 활성화한다.

```properties
android.useAndroidX=true
```

이 옵션이 `true`여야 Flutter 플러그인들이 요구하는 AndroidX 라이브러리를 정상적으로 가져올 수 있다. `false`로 두면 최신 플러그인 대부분이 빌드 오류를 낸다.

### 플러그인이란

Flutter에서 플러그인은 **Dart 코드만으로는 접근할 수 없는 기기 기능을 쓸 수 있게 해주는 패키지**다. GPS, 카메라, 센서처럼 운영체제가 직접 관리하는 기능은 Android(Kotlin/Java)나 iOS(Swift/Objective-C) 네이티브 코드로만 호출할 수 있다. 플러그인은 이 네이티브 코드를 Dart에서 호출할 수 있도록 다리를 놓아준다.

예를 들어 이 프로젝트에서 추가할 `geolocator`는 Dart 코드에서 `Geolocator.getCurrentPosition()`을 호출하면, 플러그인이 Android의 `FusedLocationProviderClient`나 iOS의 `CLLocationManager`를 대신 호출해 결과를 돌려준다.

`GeneratedPluginRegistrant`(Android의 `.java`, iOS의 `.m`, macOS의 `.swift`) 파일이 바로 설치된 플러그인들을 Flutter 엔진에 등록하는 역할을 한다. `flutter pub get`을 실행할 때마다 자동으로 갱신된다.

---

## SDK와 패키지란

### SDK (Software Development Kit)

SDK는 **특정 플랫폼이나 언어로 앱을 만드는 데 필요한 도구 묶음**이다. 컴파일러, 표준 라이브러리, 디버거, 에뮬레이터 등이 하나의 패키지로 묶여 제공된다.

이 프로젝트에서 등장하는 SDK는 두 가지다.

| SDK | 역할 |
|-----|------|
| **Flutter SDK** | `flutter` CLI 명령어, Flutter 프레임워크(위젯·렌더링 엔진), Dart SDK를 모두 포함한다. `flutter run`, `flutter build`, `flutter pub get` 같은 명령어가 여기서 온다. |
| **Dart SDK** | Flutter SDK 안에 내장되어 있다. Dart 언어의 컴파일러(`dart compile`), 표준 라이브러리(`dart:core`, `dart:io` 등), 분석기(`dart analyze`)를 제공한다. 별도 설치 불필요. |

`pubspec.yaml`의 아래 항목이 "Flutter SDK 자체를 의존성으로 사용한다"는 선언이다.

```yaml
dependencies:
  flutter:
    sdk: flutter   # pub.dev 패키지가 아니라 SDK 내장 라이브러리를 가리킨다
```

`sdk: flutter`는 pub.dev에서 내려받는 것이 아니라 이미 설치된 Flutter SDK 안의 코드를 참조한다는 의미다.

---

### 패키지 (Package)

패키지는 **다른 사람이 만들어 공개한 코드 묶음**이다. 매번 직접 구현하지 않아도 되는 기능을 가져다 쓸 수 있게 해준다. Flutter 생태계의 패키지는 [pub.dev](https://pub.dev)에서 배포되고 검색된다.

`pubspec.yaml`에 이름과 버전을 선언하면 `flutter pub get`이 pub.dev에서 내려받아 `.dart_tool/package_config.json`에 경로를 등록한다.

```yaml
dependencies:
  cupertino_icons: ^1.0.8   # pub.dev에서 내려받는 패키지
```

패키지는 목적에 따라 두 종류로 나뉜다.

| 종류 | `pubspec.yaml` 위치 | 설명 |
|------|-------------------|------|
| **일반 의존성** | `dependencies:` | 앱 실행 시 실제로 포함된다. 사용자 기기에 설치되는 APK/IPA에 들어간다. |
| **개발 의존성** | `dev_dependencies:` | 개발·테스트 중에만 사용한다. 빌드 결과물에는 포함되지 않는다. |

현재 `pubspec.yaml` 기준으로 정리하면 다음과 같다.

```yaml
dependencies:
  flutter:            # SDK 내장 — Flutter 프레임워크 전체
  cupertino_icons:    # pub.dev 패키지 — iOS 스타일 아이콘 폰트

dev_dependencies:
  flutter_test:       # SDK 내장 — Flutter 위젯 테스트 유틸리티
  flutter_lints:      # pub.dev 패키지 — Dart 린트(코드 품질 검사) 규칙 모음
```

---

### SDK vs 패키지 한눈에 비교

| 구분 | SDK | 패키지 |
|------|-----|-------|
| 설치 방법 | Flutter 공식 사이트에서 수동 설치 | `flutter pub get`으로 자동 설치 |
| 선언 위치 | `sdk: flutter` | `패키지명: ^버전` |
| 출처 | 로컬에 설치된 Flutter SDK 폴더 | pub.dev |
| 예시 | `flutter`, `flutter_test`, `dart:core` | `cupertino_icons`, `dio`, `flutter_riverpod` |

---

## Android는 왜 아이콘 의존성이 따로 없는가

`pubspec.yaml`의 현재 의존성은 두 개다.

```yaml
dependencies:
  flutter:         # Flutter SDK 자체
  cupertino_icons: ^1.0.8  # iOS 스타일 아이콘
```

`cupertino_icons`는 있는데 Android 쪽 아이콘 패키지는 보이지 않는다. 이유는 **Android의 기본 아이콘 세트(Material Icons)가 Flutter SDK 안에 이미 포함되어 있기 때문**이다.

### Material Icons — Flutter SDK에 내장

`pubspec.yaml` 하단을 보면 이런 항목이 있다.

```yaml
flutter:
  uses-material-design: true
```

이 한 줄이 핵심이다. `uses-material-design: true`를 선언하면 Flutter SDK가 **Material Icons 폰트 파일**(`MaterialIcons-Regular.otf`)을 앱에 자동으로 번들링한다. 별도 패키지를 설치하지 않아도 아래처럼 바로 쓸 수 있는 이유가 여기에 있다.

```dart
Icon(Icons.add)       // ✅ 추가 패키지 없이 동작
Icon(Icons.map)
Icon(Icons.my_location)
```

`Icons` 클래스는 `flutter/material.dart`에 포함되어 있고, 실제 아이콘 이미지는 SDK가 번들한 폰트 파일에서 가져온다.

### Cupertino Icons — 별도 패키지가 필요한 이유

반면 iOS 스타일 아이콘(`CupertinoIcons`)은 Flutter SDK와 **별개 저장소**에서 관리된다. Apple의 디자인 가이드라인(Human Interface Guidelines)에 맞춘 아이콘 세트로, 모든 Flutter 앱에 기본 포함시키기엔 불필요한 용량이 늘어나므로 선택적 패키지로 분리해 두었다.

```dart
Icon(CupertinoIcons.location)   // cupertino_icons 패키지 필요
Icon(CupertinoIcons.map)
```

`cupertino_icons`를 설치하면 이 패키지의 폰트 파일(`CupertinoIcons.ttf`)이 앱에 추가된다.

### 정리

| 구분 | 아이콘 클래스 | 제공 방식 | 추가 의존성 |
|------|-------------|-----------|------------|
| Android / Material 스타일 | `Icons.*` | Flutter SDK 내장 (`uses-material-design: true`) | 불필요 |
| iOS / Cupertino 스타일 | `CupertinoIcons.*` | 별도 pub.dev 패키지 | `cupertino_icons` 필요 |

Flutter는 크로스플랫폼 프레임워크이므로 `Icons.*`와 `CupertinoIcons.*` 둘 다 Android·iOS 어느 플랫폼에서도 쓸 수 있다. 어느 아이콘 세트를 쓸지는 **플랫폼**이 아니라 **디자인 방향**에 따라 결정한다. 이 프로젝트는 Material Design을 기준으로 UI를 구성하므로 `cupertino_icons`는 당장 필요하지 않다.

---

## Dart란?

Dart는 Google이 만든 프로그래밍 언어로, Flutter 앱을 작성하는 데 사용된다.
`.dart` 파일이 곧 Flutter의 소스 파일이다.

주요 특징:
- **타입 안전**: 정적 타입 언어라 컴파일 전에 타입 오류를 잡아준다.
- **AOT + JIT 컴파일**: 개발 중에는 JIT(핫 리로드 지원), 배포 시에는 AOT로 네이티브 코드로 변환된다.
- **문법**: Java·Kotlin과 유사해 익숙하게 읽힌다.
- **Flutter 전용**: Flutter SDK에 Dart SDK가 함께 포함되어 별도 설치 불필요.

`flutter create` 로 생성된 `lib/main.dart`는 카운터 버튼을 누르면 숫자가 올라가는 기본 예제 앱이다.
이 이슈에서 실제 내비게이션 앱 코드로 교체한다.

## `flutter run` 실행 흐름 — main.dart 전후

`flutter run`을 입력한 순간부터 화면이 뜨기까지 어떤 파일이 어떤 순서로 읽히고 실행되는지 정리한다.  
Android를 기준으로 설명하며, iOS·웹의 차이점은 별도 표기한다.

---

### 1단계 · Flutter 툴이 빌드를 준비한다 (`flutter run` 입력 직후)

```
flutter run
```

Flutter CLI(`flutter_tools`)가 실행되며 아래 파일들을 순서대로 읽는다.

| 순서 | 파일 | 하는 일 |
|------|------|---------|
| ① | `pubspec.yaml` | 앱 이름·버전·SDK 범위·패키지 목록을 파악한다. |
| ② | `pubspec.lock` | 각 패키지의 정확한 버전을 확인해 빌드에 사용할 버전을 고정한다. |
| ③ | `.dart_tool/package_config.json` | 설치된 패키지가 실제로 어느 경로에 있는지 Dart 컴파일러에 알려준다. |
| ④ | `analysis_options.yaml` | 린트 규칙을 로드한다. `flutter analyze`가 아니더라도 IDE 표시에 영향을 준다. |

> `pubspec.lock`이나 `.dart_tool/`이 없으면 CLI가 자동으로 `flutter pub get`을 실행해 먼저 이 파일들을 생성한다.

---

### 2단계 · Android 네이티브 빌드가 실행된다

Flutter CLI가 Gradle을 호출(`./gradlew assembleDebug`)해 Android 앱 패키지(APK)를 만든다.

| 순서 | 파일 | 하는 일 |
|------|------|---------|
| ① | `android/settings.gradle.kts` | Gradle이 빌드에 포함할 모듈(`app`)과 플러그인 저장소를 선언한다. |
| ② | `android/build.gradle.kts` | 전체 프로젝트에 적용할 Gradle 플러그인 버전(Android, Kotlin)을 설정한다. |
| ③ | `android/gradle.properties` | AndroidX 활성화, JVM 메모리 등 Gradle 동작 옵션을 읽는다. |
| ④ | `android/local.properties` | 로컬 머신의 Flutter SDK 경로와 Android SDK 경로를 읽는다. |
| ⑤ | `android/app/build.gradle.kts` | `compileSdk`, `minSdk`, 앱 ID(`com.navigation.navigation_client`), 버전 코드를 확인한다. |
| ⑥ | `android/app/src/main/AndroidManifest.xml` | 앱 이름·아이콘·액티비티·권한을 빌드에 병합한다. 여기서 `MainActivity`가 진입점으로 등록된다. |
| ⑦ | `android/app/src/main/res/values/styles.xml` | `LaunchTheme`(스플래시용)과 `NormalTheme`(Flutter UI 배경)을 컴파일한다. |
| ⑧ | `android/app/src/main/res/drawable/launch_background.xml` | 스플래시 화면 배경 드로어블을 컴파일한다. 현재는 흰 배경만 있다. |
| ⑨ | `android/app/src/main/res/mipmap-*/ic_launcher.png` | 해상도별 앱 아이콘을 APK에 패키징한다. |
| ⑩ | `android/app/src/main/java/.../GeneratedPluginRegistrant.java` | 설치된 Flutter 플러그인을 Flutter 엔진(`FlutterEngine`)에 등록하는 코드를 컴파일한다. 현재는 플러그인이 없어 빈 메서드다. |
| ⑪ | `android/app/src/main/kotlin/.../MainActivity.kt` | 앱의 유일한 Android 액티비티를 컴파일한다. |

빌드가 끝나면 APK가 에뮬레이터·기기에 설치된다.

#### Flutter 엔진이란

Flutter 엔진은 **Dart 코드를 실제 화면에 그려주는 핵심 실행 환경**이다. C++로 작성되어 있으며 APK 안에 함께 패키징된다.

하는 일을 크게 세 가지로 나눌 수 있다.

| 역할 | 설명 |
|------|------|
| **Dart VM 실행** | `lib/main.dart`부터 시작하는 Dart 코드를 실행한다. 디버그 모드에서는 JIT(핫 리로드 지원), 릴리즈 모드에서는 AOT(네이티브 코드로 미리 컴파일)로 동작한다. |
| **렌더링** | Flutter의 위젯 트리를 받아 Skia(또는 Impeller) 그래픽 라이브러리로 직접 픽셀을 그린다. Android의 기본 View 시스템을 거치지 않고 Flutter가 화면을 직접 그리기 때문에 Android·iOS에서 동일한 UI가 나온다. |
| **플랫폼 채널** | Dart 코드와 Android 네이티브 코드(Kotlin/Java) 사이의 메시지를 중계한다. 플러그인이 GPS나 센서 같은 기기 기능을 호출할 때 이 채널을 통한다. |

`MainActivity.kt`가 `FlutterActivity`를 상속하는 것이 바로 "Android 액티비티 안에 Flutter 엔진을 심는다"는 의미다. `GeneratedPluginRegistrant.java`의 `registerWith(flutterEngine)`은 이렇게 생성된 엔진 인스턴스에 플러그인들을 붙여주는 작업이다.

#### JIT와 AOT — 두 가지 컴파일 방식

Flutter 엔진이 Dart 코드를 실행할 때 상황에 따라 두 가지 컴파일 방식 중 하나를 사용한다.

**JIT (Just-In-Time, 실시간 컴파일)**

코드를 **실행하는 도중에 그때그때 컴파일**하는 방식이다. 앱을 시작하기 전에 전체를 미리 번역하지 않고, 실행되는 코드 조각을 즉석에서 기계어로 바꿔 돌린다.

- `flutter run`으로 디버그 모드 실행 시 사용된다.
- 코드가 변경되면 바뀐 부분만 다시 컴파일해 즉시 반영할 수 있다. 이것이 **핫 리로드**가 가능한 이유다.
- 전체를 미리 컴파일하지 않아 앱 시작이 약간 느리고 실행 중 컴파일 오버헤드가 있다.

**AOT (Ahead-Of-Time, 사전 컴파일)**

앱을 기기에 설치하기 **전에 Dart 코드 전체를 미리 네이티브 기계어로 번역**해두는 방식이다. 기기에서는 이미 번역된 코드를 바로 실행하기만 한다.

- `flutter build apk` 또는 `flutter run --release`로 릴리즈 모드 실행 시 사용된다.
- 실행 시점에 컴파일할 필요가 없어 앱 시작이 빠르고 실행 성능이 높다.
- 코드가 이미 기계어로 고정되어 있어 핫 리로드는 불가능하다.

| 구분 | JIT | AOT |
|------|-----|-----|
| 컴파일 시점 | 실행 중 실시간 | 빌드 시 미리 완료 |
| 사용 모드 | 디버그(`flutter run`) | 릴리즈(`flutter build`) |
| 핫 리로드 | 가능 | 불가능 |
| 실행 속도 | 상대적으로 느림 | 빠름 |
| 목적 | 개발 편의성 | 배포 성능 |

---

### 3단계 · Android OS가 앱 프로세스를 시작한다

기기에서 앱 아이콘을 탭하거나 `flutter run`이 앱을 실행하면 Android OS가 개입한다.

| 순서 | 파일/동작 | 하는 일 |
|------|-----------|---------|
| ① | `AndroidManifest.xml` | OS가 이 파일을 읽어 어느 클래스를 먼저 실행할지 결정한다. `<action android:name="android.intent.action.MAIN"/>`이 지정된 `MainActivity`를 실행한다. |
| ② | `res/values/styles.xml` → `LaunchTheme` | OS가 `MainActivity`를 화면에 올리기 전에 `LaunchTheme`을 즉시 적용해 **스플래시 배경**을 표시한다. Flutter UI가 첫 프레임을 그리기 전까지 이 배경이 보인다. |
| ③ | `res/drawable/launch_background.xml` | 위 `LaunchTheme`의 배경으로 참조된다. 현재는 흰 화면. |
| ④ | `MainActivity.kt` 실행 | `FlutterActivity`를 상속한 `MainActivity`가 생성된다. `FlutterActivity`가 Flutter 엔진(`FlutterEngine`)을 내부적으로 초기화한다. |
| ⑤ | `GeneratedPluginRegistrant.java` 실행 | 엔진이 초기화되는 시점에 `registerWith(flutterEngine)`이 호출돼 플러그인을 등록한다. 현재는 플러그인이 없어 아무것도 등록하지 않는다. |

---

### 4단계 · Flutter 엔진이 Dart VM을 시작하고 main.dart를 실행한다

Flutter 엔진이 준비되면 드디어 Dart 코드가 실행된다.

```
lib/main.dart  ←── 여기서부터 Dart 세계
```

| 순서 | 파일/동작 | 하는 일 |
|------|-----------|---------|
| ① | Dart VM 시작 | AOT(배포) 또는 JIT(디버그) 모드로 Dart VM이 구동된다. |
| ② | `lib/main.dart` → `main()` 함수 호출 | Dart 진입점. `runApp(const MyApp())`을 호출해 Flutter 프레임워크에 루트 위젯을 전달한다. |
| ③ | `runApp()` | Flutter 프레임워크가 위젯 트리를 초기화하기 시작한다. 루트 위젯을 화면 전체에 꽉 채워 표시한다. |
| ④ | `MyApp.build()` | `MaterialApp` 위젯이 생성된다. 앱 제목(`'Flutter Demo'`)과 테마(`ColorScheme.fromSeed`)가 설정된다. |
| ⑤ | `MyHomePage` 생성 | `MaterialApp`의 `home:`으로 지정된 `MyHomePage` 위젯이 생성된다. |
| ⑥ | `_MyHomePageState.build()` | `Scaffold` → `AppBar` + `Column` + `FloatingActionButton`으로 이루어진 위젯 트리가 완성된다. |
| ⑦ | Flutter 엔진이 첫 프레임을 렌더링 | GPU에 첫 화면이 그려지는 순간, Android의 `LaunchTheme`(스플래시)이 자동으로 제거되고 Flutter UI가 전면에 표시된다. |

---

#### 루트 위젯이란

Flutter에서 UI는 **위젯을 나무처럼 중첩해서 쌓는 구조(위젯 트리)** 로 만든다. 버튼 하나, 텍스트 하나, 여백 하나가 모두 위젯이고, 이것들이 부모-자식 관계로 연결되어 전체 화면을 구성한다.

```
MyApp                   ← 루트 위젯 (트리의 최상단)
└─ MaterialApp
   └─ MyHomePage
      └─ Scaffold
         ├─ AppBar
         ├─ Column
         │   ├─ Text
         │   └─ Text
         └─ FloatingActionButton
```

이 트리에서 **가장 꼭대기에 있는 위젯**이 루트 위젯이다. `runApp(const MyApp())`에서 `MyApp`이 루트 위젯으로 전달되고, Flutter 엔진은 이 위젯을 시작점으로 삼아 아래로 내려가며 전체 트리를 구성한 뒤 화면에 그린다.

루트 위젯은 앱에 딱 하나만 존재하며 화면 전체를 차지한다. 이 프로젝트에서는 이후 `MyApp`을 `ProviderScope`(Riverpod)로 감싸게 되는데, 그러면 `ProviderScope`가 새로운 루트 위젯이 되고 `MyApp`은 그 아래 자식으로 들어간다.

### 전체 흐름 요약

```
flutter run
    │
    ├─ [빌드 전] pubspec.yaml / pubspec.lock / package_config.json 읽기
    │
    ├─ [Android 빌드] Gradle 실행
    │       settings.gradle.kts → build.gradle.kts → gradle.properties
    │       → local.properties → app/build.gradle.kts
    │       → AndroidManifest.xml → styles.xml → launch_background.xml
    │       → ic_launcher.png → GeneratedPluginRegistrant.java → MainActivity.kt
    │
    ├─ [OS 실행] APK 설치 → 프로세스 시작
    │       AndroidManifest.xml (진입점 결정)
    │       → LaunchTheme 적용 (스플래시 표시)
    │       → MainActivity.kt 실행
    │       → FlutterEngine 초기화
    │       → GeneratedPluginRegistrant.java (플러그인 등록)
    │
    └─ [Dart 실행] Flutter 엔진이 Dart VM 시작
            lib/main.dart → main() → runApp(MyApp())
            → MyApp.build() → MaterialApp
            → MyHomePage → _MyHomePageState.build() → Scaffold
            → 첫 프레임 렌더링 → 스플래시 제거 → 화면 표시
```

---

### iOS에서의 차이

Android와 역할은 동일하지만 읽히는 파일이 다르다.

| Android | iOS 대응 파일 | 차이점 |
|---------|--------------|--------|
| `AndroidManifest.xml` | `ios/Runner/Info.plist` | 앱 설정·권한 선언 |
| `MainActivity.kt` | `ios/Runner/AppDelegate.swift` | 네이티브 진입점 |
| `GeneratedPluginRegistrant.java` | `ios/Runner/GeneratedPluginRegistrant.m` | 플러그인 자동 등록 |
| `styles.xml` + `launch_background.xml` | `LaunchScreen.storyboard` | 스플래시 화면 |
| `build.gradle.kts` | `Runner.xcodeproj/project.pbxproj` | 빌드 설정 |
| `gradle-wrapper.properties` | Xcode 버전 | 빌드 툴 버전 고정 |

iOS에서는 `AppDelegate.swift`의 `didFinishLaunchingWithOptions`가 `MainActivity.onCreate()`에 해당한다. `GeneratedPluginRegistrant.register(with:)`가 플러그인을 등록하는 시점도 이 메서드 안이다.

---

## client/ 디렉토리 파일 구조 설명

`flutter create` 실행 직후 생성된 파일들이다. 각 파일의 역할과 확장자를 정리한다.

### 확장자 종류

| 확장자 | 언어/형식 | 용도 |
|--------|-----------|------|
| `.dart` | Dart | Flutter 앱 소스 코드 |
| `.yaml` / `.yml` | YAML | 패키지 의존성, 린트 설정 등 구성 파일 |
| `.kt` | Kotlin | Android 네이티브 코드 |
| `.java` | Java | Android 플러그인 자동 등록 코드 (자동 생성) |
| `.xml` | XML | Android 매니페스트, 리소스, 스타일 |
| `.gradle.kts` | Kotlin DSL | Android 빌드 스크립트 |
| `.properties` | Java Properties | Android Gradle 속성값 |
| `.swift` | Swift | iOS/macOS 네이티브 코드 |
| `.h` / `.m` | Objective-C | iOS 플러그인 자동 등록 코드 (자동 생성) |
| `.plist` | XML(Property List) | iOS/macOS 앱 설정, 권한 선언 |
| `.pbxproj` | Xcode 프로젝트 | Xcode 빌드 대상·파일 참조 정의 |
| `.xcconfig` | Xcode Config | Xcode 빌드 변수 설정 |
| `.xcscheme` | XML | Xcode 빌드/실행 스킴 |
| `.storyboard` | XML | iOS UI 레이아웃 (Launch Screen 등) |
| `.xib` | XML | macOS UI 레이아웃 |
| `.entitlements` | XML(Plist) | macOS 앱 권한(샌드박스 등) 선언 |
| `.cmake` / `CMakeLists.txt` | CMake | Linux·Windows 네이티브 빌드 스크립트 |
| `.cc` / `.cpp` | C++ | Linux·Windows 네이티브 러너 코드 |
| `.h` | C/C++ 헤더 | 함수·클래스 선언 |
| `.rc` | Windows Resource | Windows 앱 아이콘·버전 정보 |
| `.manifest` | XML | Windows 앱 실행 권한·DPI 설정 |
| `.ico` | 이미지 | Windows 앱 아이콘 |
| `.png` | 이미지 | 앱 아이콘, 런치 이미지 |
| `.json` | JSON | 패키지 설정, 에셋 카탈로그 메타데이터 |
| `.html` | HTML | 웹 플랫폼 진입점 |
| `.iml` | XML | IntelliJ/Android Studio 모듈 정의 |
| `.py` | Python | LLDB 디버깅 헬퍼 스크립트 (자동 생성) |
| `.sh` | Shell | Flutter 환경 변수 익스포트 스크립트 (자동 생성) |
| `.env` | 환경 변수 | Flutter 네이티브 통합 환경값 (자동 생성) |
| `.lock` | YAML | `pubspec.lock` — 패키지 버전 잠금 파일 |

### 루트 레벨

| 파일 | 역할 |
|------|------|
| `pubspec.yaml` | Flutter 프로젝트의 핵심 설정 파일. 앱 이름·버전, 의존 패키지, 에셋 경로를 선언한다. `flutter pub get` 실행 시 이 파일을 읽어 패키지를 설치한다. |
| `pubspec.lock` | `flutter pub get` 이 자동 생성하는 버전 잠금 파일. 팀원 간 동일한 패키지 버전을 보장하기 위해 VCS에 커밋한다. |
| `analysis_options.yaml` | Dart 정적 분석(lint) 규칙 설정. `flutter_lints` 패키지의 권장 규칙을 적용한다. `flutter analyze` 실행 시 참조된다. |
| `README.md` | 프로젝트 설명 문서. 이 이슈에서 실행법과 SDK 요구 버전을 작성할 대상이다. |
| `navigation_client.iml` | Android Studio·IntelliJ가 자동 생성하는 모듈 정의 파일. 직접 편집하지 않는다. |

### lib/

| 파일 | 역할 |
|------|------|
| `lib/main.dart` | Flutter 앱 진입점. `main()` 함수에서 `runApp()`을 호출한다. 이 이슈에서 `ProviderScope`(Riverpod)로 감싸고 지도 화면을 연결하도록 교체한다. |

### android/

| 파일 | 역할 |
|------|------|
| `android/app/src/main/AndroidManifest.xml` | Android 앱 선언 파일. 앱 이름, 액티비티, **위치 권한**(`ACCESS_FINE_LOCATION`) 등을 등록한다. 이 이슈에서 권한 키를 추가해야 한다. |
| `android/app/src/debug/AndroidManifest.xml` | 디버그 빌드 전용 매니페스트. 인터넷 권한 등 개발 중 필요한 항목을 추가로 선언한다. |
| `android/app/src/profile/AndroidManifest.xml` | 프로파일링 빌드 전용 매니페스트. |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Android 네이티브 액티비티 진입점. Flutter 엔진을 호스팅한다. |
| `android/app/src/main/java/.../GeneratedPluginRegistrant.java` | Flutter 플러그인을 Android에 자동 등록하는 파일. `flutter pub get` 시 자동 생성되며 직접 편집하지 않는다. |
| `android/app/build.gradle.kts` | 앱 모듈의 Android 빌드 설정. `compileSdk`, `minSdk`, 앱 ID 등을 정의한다. |
| `android/build.gradle.kts` | 프로젝트 전체 Android 빌드 설정. |
| `android/settings.gradle.kts` | Android 프로젝트 구조 설정. 포함할 모듈을 나열한다. |
| `android/gradle.properties` | Gradle 동작 관련 속성값(JVM 메모리, AndroidX 사용 여부 등). |
| `android/local.properties` | Flutter/Android SDK 경로를 담는 로컬 설정. `.gitignore`에 포함되어 VCS에 올리지 않는다. |
| `android/gradle/wrapper/gradle-wrapper.properties` | 사용할 Gradle 버전을 명시한다. |
| `android/app/src/main/res/` | Android 앱 리소스. `mipmap-*/ic_launcher.png`는 해상도별 앱 아이콘, `drawable*/launch_background.xml`은 스플래시 배경, `values*/styles.xml`은 테마 정의다. |

### ios/

| 파일 | 역할 |
|------|------|
| `ios/Runner/Info.plist` | iOS 앱 설정 파일. **위치 권한 설명 문자열**(`NSLocationWhenInUseUsageDescription`)을 포함하며, 이 이슈에서 권한 키를 추가해야 한다. |
| `ios/Runner/AppDelegate.swift` | iOS 앱 진입점. Flutter 엔진을 초기화한다. |
| `ios/Runner/SceneDelegate.swift` | iOS 13+ 멀티윈도우 Scene 생명주기를 처리한다. |
| `ios/Runner/GeneratedPluginRegistrant.h` / `.m` | Flutter 플러그인을 iOS에 자동 등록하는 Objective-C 파일. `flutter pub get` 시 자동 생성된다. |
| `ios/Runner/Runner-Bridging-Header.h` | Swift에서 Objective-C 코드를 사용할 수 있도록 연결하는 브릿지 헤더. |
| `ios/Runner/Assets.xcassets/` | 앱 아이콘과 런치 이미지를 해상도별로 묶은 에셋 카탈로그. `Contents.json`이 각 이미지의 역할과 배율을 정의한다. |
| `ios/Runner/Base.lproj/LaunchScreen.storyboard` | 앱 시작 시 표시되는 스플래시 화면 레이아웃. |
| `ios/Runner/Base.lproj/Main.storyboard` | 앱 메인 화면 진입 스토리보드. Flutter는 대부분 코드로 UI를 구성하므로 최소 구조만 있다. |
| `ios/Runner.xcodeproj/project.pbxproj` | Xcode 프로젝트 파일. 소스 파일 참조, 빌드 단계, 타깃 설정 등을 담는다. 직접 편집하지 않는다. |
| `ios/Runner.xcworkspace/` | CocoaPods/Swift Package Manager 의존성을 포함한 통합 Xcode 워크스페이스. Xcode 열 때 `.xcproj` 대신 이것을 사용한다. |
| `ios/Flutter/AppFrameworkInfo.plist` | Flutter 프레임워크 버전 정보. |
| `ios/Flutter/*.xcconfig` | Debug/Release 빌드별 Xcode 변수 설정. `flutter build` 시 자동 갱신된다. |
| `ios/Flutter/ephemeral/` | `flutter pub get` 이 자동 생성하는 임시 파일들. VCS에 올리지 않는다. |
| `ios/RunnerTests/RunnerTests.swift` | iOS 네이티브 단위 테스트 파일. |

### macos/

iOS와 거의 동일한 구조다. 차이점만 정리한다.

| 파일 | 역할 |
|------|------|
| `macos/Runner/MainFlutterWindow.swift` | macOS Flutter 윈도우를 초기화하는 진입점. iOS의 `AppDelegate`에 해당한다. |
| `macos/Runner/Base.lproj/MainMenu.xib` | macOS 메뉴바와 윈도우 레이아웃을 정의하는 Interface Builder 파일. |
| `macos/Runner/Configs/*.xcconfig` | Debug/Release/AppInfo/Warnings 별 Xcode 빌드 변수 설정. |
| `macos/Runner/DebugProfile.entitlements` / `Release.entitlements` | macOS 샌드박스 권한 선언. 네트워크 클라이언트 접근 등을 허용한다. |

### linux/

| 파일 | 역할 |
|------|------|
| `linux/CMakeLists.txt` | Linux 빌드의 최상위 CMake 스크립트. Flutter 엔진과 앱 빌드를 조율한다. |
| `linux/runner/main.cc` | Linux 앱 진입점(`main` 함수). |
| `linux/runner/my_application.cc` / `.h` | GTK 앱 윈도우를 생성하고 Flutter 엔진을 삽입하는 구현체. |
| `linux/flutter/CMakeLists.txt` | Flutter 엔진 라이브러리 연결 CMake 스크립트. |
| `linux/flutter/generated_plugin_registrant.cc` / `.h` | Flutter 플러그인을 Linux에 자동 등록하는 파일. `flutter pub get` 시 자동 생성된다. |
| `linux/flutter/generated_plugins.cmake` | 설치된 플러그인 목록을 CMake에 전달하는 파일. 자동 생성된다. |

### windows/

Linux와 동일한 역할의 CMake 기반 구조다. 차이점만 정리한다.

| 파일 | 역할 |
|------|------|
| `windows/runner/main.cpp` | Windows 앱 진입점(`wWinMain` 함수). |
| `windows/runner/flutter_window.cpp` / `.h` | Win32 윈도우에 Flutter 뷰를 삽입하는 구현체. |
| `windows/runner/win32_window.cpp` / `.h` | Win32 창 생성·메시지 루프 처리 기반 클래스. |
| `windows/runner/utils.cpp` / `.h` | UTF-8 ↔ UTF-16 변환 등 Windows 유틸리티 함수. |
| `windows/runner/Runner.rc` | Windows 앱 아이콘, 버전 정보 등 리소스를 정의하는 Resource Script. |
| `windows/runner/resource.h` | `Runner.rc`에서 사용하는 리소스 ID 상수 정의. |
| `windows/runner/runner.exe.manifest` | Windows DPI 인식, UAC 권한 수준 등 실행 매니페스트. |
| `windows/runner/resources/app_icon.ico` | Windows 앱 아이콘 이미지. |

### web/

| 파일 | 역할 |
|------|------|
| `web/index.html` | 웹 플랫폼 진입점 HTML. Flutter 엔진을 로드하고 초기화한다. |
| `web/manifest.json` | PWA(Progressive Web App) 메타데이터. 앱 이름, 테마 색상, 아이콘 경로를 정의한다. |
| `web/favicon.png` | 브라우저 탭 아이콘. |
| `web/icons/` | PWA 설치 시 사용하는 192×192, 512×512 아이콘. `maskable` 버전은 Android 어댑티브 아이콘용이다. |

### test/

| 파일 | 역할 |
|------|------|
| `test/widget_test.dart` | `flutter create` 기본 제공 위젯 테스트. 카운터 앱 기본 동작을 검증한다. 이 이슈에서 지도 화면으로 교체한 뒤 맞게 수정한다. |

### .dart_tool/ (자동 생성, VCS 제외)

| 파일 | 역할 |
|------|------|
| `.dart_tool/package_config.json` | 설치된 패키지의 경로를 Dart 툴체인에 알려주는 파일. `flutter pub get` 시 생성된다. |
| `.dart_tool/package_graph.json` | 패키지 의존성 그래프. |
| `.dart_tool/dartpad/web_plugin_registrant.dart` | DartPad 웹 환경에서 플러그인을 등록하는 자동 생성 파일. |

### .idea/ (IDE 설정, 선택적 VCS 포함)

| 파일 | 역할 |
|------|------|
| `.idea/modules.xml` | Android Studio·IntelliJ 프로젝트 모듈 목록. |
| `.idea/libraries/Dart_SDK.xml` | Dart SDK 경로 참조. |
| `.idea/libraries/KotlinJavaRuntime.xml` | Kotlin/Java 런타임 경로 참조. |
| `.idea/runConfigurations/main_dart.xml` | `Run` 버튼으로 `lib/main.dart`를 실행하는 IDE 실행 구성. |
| `.idea/workspace.xml` | 마지막으로 열린 파일, 창 배치 등 개인 작업공간 상태. 팀 공유 불필요. |

---

## 메모

- Flutter SDK 미설치 PC가 있을 수 있다. 골격 PR에는 `pubspec.yaml`·`lib/` 구조까지 포함하고,
  실제 `flutter run` 검증은 SDK 보유 팀원이 담당하도록 역할을 나눈다.
- 본 기능(센서·PDR)은 이 이슈 범위가 **아니다.** 빈 화면이 뜨면 성공이다.
