import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// 아래 dart-define 값들은 `client/config.local.json`(gitignore 대상, 템플릿은
/// `config.example.json`)에 모아 두고 한 번에 넘길 수 있다:
///   flutter run --dart-define-from-file=config.local.json
///
/// dart-define으로 넘기면 플랫폼 무관하게 최우선 적용된다(실기기 등):
///   flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8001
/// 배포 URL·외부 API 키를 매번 치기 번거로우면 git에 안 올리는 로컬 파일에 모아
/// 한 번에 주입한다(형식은 client/config.example.json 참고):
///   flutter run --dart-define-from-file=config.local.json
const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// 안드로이드 에뮬레이터는 호스트의 localhost를 `10.0.2.2`로 가리켜야 접속되고,
/// 웹/데스크톱/iOS 시뮬레이터는 `localhost`가 그대로 동작한다. 플랫폼별로
/// 맞는 기본값을 자동 선택해서, 로컬 개발 서버(`uvicorn app.main:app --reload`,
/// 기본 포트 8001)를 dart-define 없이 바로 붙일 수 있게 한다.
String get apiBaseUrl {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8001';
  }
  return 'http://localhost:8001';
}

/// Studio 1F만 적재하는 기본 개발 DB와 맞춘 데모 건물 ID.
const demoBuildingId = 'thehyundai-seoul';

/// TMAP(SK Open API) 보행자 경로 안내. https://openapi.sk.com 에서 앱 등록 후 발급.
/// 키를 소스코드에 직접 적지 않고 실행 시점에 주입한다:
///   flutter run --dart-define=TMAP_APP_KEY=발급받은키
/// 값을 안 넘기면 빈 문자열이 되고, service_locator.dart가 이 경우 자동으로
/// MockDirectionsRepository를 사용한다.
/// 같은 키로 보행자 경로·POI 통합검색·대중교통 경로를 모두 호출한다.
const tmapAppKey = String.fromEnvironment('TMAP_APP_KEY');
const tmapBaseUrl = 'https://apis.openapi.sk.com/tmap';

/// 대중교통 경로안내만 base path가 `/tmap`이 아니라 `/transit`이다. 같은
/// 호스트라 헷갈리기 쉬운데, `/tmap/routes/transit`으로 부르면 404다.
const tmapTransitBaseUrl = 'https://apis.openapi.sk.com/transit';

/// VWorld(국토교통부) 배경지도 타일. https://www.vworld.kr/dev 에서 도메인 등록 후 발급.
/// 키를 소스코드에 직접 적지 않고 실행 시점에 주입한다:
///   flutter run --dart-define=VWORLD_API_KEY=발급받은키
/// 값을 안 넘기면 빈 문자열이 되고, outdoor_map_screen.dart가 이 경우 OSM 타일로 대체한다.
const vworldApiKey = String.fromEnvironment('VWORLD_API_KEY');
