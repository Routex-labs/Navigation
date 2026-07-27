import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_config.dart';
import '../features/debug_mode/debug_mode_controller.dart';
import '../features/indoor_navigation/application/corridor_tracking_session.dart';
import '../features/indoor_navigation/application/indoor_navigation_controller.dart';
import '../features/indoor_navigation/platform/android_pdr_motion_source.dart';
import '../features/indoor_navigation/platform/ios_pdr_motion_source.dart';
import '../features/indoor_navigation/platform/pdr_motion_source.dart';
import '../repositories/building_repository.dart';
import '../repositories/destination_repository.dart';
import '../repositories/directions_repository.dart';
import '../repositories/http_building_repository.dart';
import '../repositories/http_destination_repository.dart';
import '../repositories/mock_directions_repository.dart';
import '../repositories/tmap_directions_repository.dart';
import '../state/favorites_controller.dart';

/// 앱 전체에서 공유하는 PDR 센서 소스와 세션 드라이버다. 화면이 바뀌어도
/// 센서 세션을 다시 만들지 않도록 singleton으로 유지한다.
final PdrMotionSource pdrMotionSource = switch (defaultTargetPlatform) {
  TargetPlatform.android => AndroidPdrMotionSource(),
  _ => IosPdrMotionSource(),
};
final IndoorNavigationDriver indoorNavigationDriver = IndoorNavigationDriver(
  source: pdrMotionSource,
);
final CorridorTrackingSession corridorTrackingSession =
    CorridorTrackingSession();

/// 디버그 모드 설정도 화면 간에 공유한다. 실내 지도와 야외 지도의 실내 진입
/// 오버레이가 각자 컨트롤러를 만들면, 한쪽에서 디버그 모드를 켜도 다른 쪽은
/// 자기 메모리 값(꺼짐)을 계속 보여줘 같은 세션 안에서 PDR 진입점이 있다
/// 없다 한다. MapShellScreen이 두 body를 IndexedStack으로 동시에 살려 두기
/// 때문에 특히 눈에 띈다 — 하나만 두고 양쪽이 같은 상태를 구독한다.
///
/// 다른 전역들과 달리 교체 가능한 var가 아니라 final이다. 위젯이 구독하는
/// ChangeNotifier라, 실행 중에 다른 인스턴스로 갈아끼우면 이미 구독 중인
/// 화면들이 옛 인스턴스만 계속 바라보게 된다. 테스트에서 설정을 바꿔야 하면
/// 인스턴스를 교체하지 말고 [DebugModeController.reload]를 쓴다.
final DebugModeController debugModeController = DebugModeController();

/// 실내 지도·목적지 검색·경로 안내가 전부 백엔드(api/) 다익스트라 그래프로
/// 동작하도록 HttpBuildingRepository를 쓴다. 백엔드 없이 오프라인으로 확인할
/// 땐 이 한 줄만 MockBuildingRepository()로 되돌리면 된다.
///
/// watchPosition/requestStartupPermissions와 같은 이유로 final이 아니다 —
/// 플랫폼 채널·네트워크가 없는 위젯 테스트 환경에서는 이 변수를
/// MockBuildingRepository()로 교체해 실제 HTTP 호출 없이 동작을 검증한다.
BuildingRepository buildingRepository = HttpBuildingRepository();

/// 목적지 자연어 질의는 백엔드의 POST /query/destination(라우터 하나로
/// 최적 매장 1건을 반환)을 그대로 호출한다. 테스트나 백엔드가 아직
/// 없을 때만 [MockDestinationRepository](buildingRepository)로 되돌린다 —
/// 기본은 실제 API를 붙여야 상단 검색·길찾기 시트가 서버의 정규화/동의어
/// 사전을 함께 쓴다.
DestinationRepository destinationRepository = HttpDestinationRepository();

/// --dart-define=TMAP_APP_KEY=... 로 키를 넘기면 자동으로 실제 API를 쓰고,
/// 안 넘기면(테스트·키 미발급 상태) 직선 경로로 동작하는 Mock을 쓴다.
final DirectionsRepository directionsRepository = tmapAppKey.isEmpty
    ? MockDirectionsRepository()
    : TmapDirectionsRepository();

/// 사용자가 "장소" 탭에 저장해둔 매장 목록. SharedPreferences로 앱 재실행
/// 뒤에도 유지된다. 테스트에서는 이 변수를 in-memory 컨트롤러로 교체한다.
FavoritesController favoritesController = FavoritesController();

Future<Map<Permission, PermissionStatus>> defaultRequestStartupPermissions() {
  final permissions = <Permission>[Permission.locationWhenInUse];
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    permissions.add(Permission.sensors);
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    permissions.add(Permission.activityRecognition);
  }
  return permissions.request();
}

/// 스플래시 화면의 시작 권한 요청. 플랫폼 채널이 없는 테스트 환경에서는
/// 이 변수를 즉시 완료되는 가짜 함수로 교체해 실제 플러그인 호출을 피한다.
Future<Map<Permission, PermissionStatus>> Function() requestStartupPermissions =
    defaultRequestStartupPermissions;

Stream<Position> defaultWatchPosition() {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      // 5m 이상 움직였을 때만 새 이벤트를 받는다. 매 GPS 틱마다 반응하면
      // 위치 마커/경로 재계산(TMAP 호출 포함)이 과도하게 자주 일어난다.
      distanceFilter: 5,
    ),
  );
}

/// 야외 지도 화면의 실시간 위치 스트림. 걷는 동안 위치 마커·경로·건물 진입
/// 판정이 계속 갱신되도록 한다. 플랫폼 채널이 없는 테스트 환경에서는 이
/// 변수를 가짜 [Position] 스트림으로 교체한다.
Stream<Position> Function() watchPosition = defaultWatchPosition;
