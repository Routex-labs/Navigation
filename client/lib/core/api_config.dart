/// 기본값은 Android 에뮬레이터에서 호스트 localhost를 가리키는 특수 주소다.
/// 다른 플랫폼(웹/데스크톱/실기기)에서 개발 서버를 붙일 땐
///   flutter run --dart-define=API_BASE_URL=http://localhost:8001
/// 로 덮어쓴다.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8001',
);

/// 데모 건물 ID. 백엔드(api/)에 실제로 적재된 test-center 건물과 맞춰야
/// 실내 지도·목적지 검색·경로 안내가 전부 백엔드 다익스트라 그래프로
/// 동작한다. 더현대 서울(thehyundai-seoul)은 별도 건물로, 개발용 미리보기
/// 화면(floor_map_preview_screen.dart)에서만 직접 참조한다.
const demoBuildingId = 'test-center';

/// TMAP(SK Open API) 보행자 경로 안내. https://openapi.sk.com 에서 앱 등록 후 발급.
/// 키를 소스코드에 직접 적지 않고 실행 시점에 주입한다:
///   flutter run --dart-define=TMAP_APP_KEY=발급받은키
/// 값을 안 넘기면 빈 문자열이 되고, service_locator.dart가 이 경우 자동으로
/// MockDirectionsRepository를 사용한다.
const tmapAppKey = String.fromEnvironment('TMAP_APP_KEY');
const tmapBaseUrl = 'https://apis.openapi.sk.com/tmap';

/// VWorld(국토교통부) 배경지도 타일. https://www.vworld.kr/dev 에서 도메인 등록 후 발급.
/// 키를 소스코드에 직접 적지 않고 실행 시점에 주입한다:
///   flutter run --dart-define=VWORLD_API_KEY=발급받은키
/// 값을 안 넘기면 빈 문자열이 되고, outdoor_map_screen.dart가 이 경우 OSM 타일로 대체한다.
const vworldApiKey = String.fromEnvironment('VWORLD_API_KEY');
