import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_config.dart';
import '../features/debug_mode/debug_mode_controller.dart';
import '../features/indoor_navigation/application/indoor_navigation_controller.dart';
import '../features/indoor_navigation/application/indoor_location_estimate.dart';
import '../features/indoor_navigation/platform/android_pdr_motion_source.dart';
import '../features/indoor_navigation/platform/ios_pdr_motion_source.dart';
import '../features/indoor_navigation/platform/pdr_motion_source.dart';
import '../repositories/building_repository.dart';
import '../repositories/destination_repository.dart';
import '../repositories/directions_repository.dart';
import '../repositories/http_building_repository.dart';
import '../repositories/http_destination_repository.dart';
import '../repositories/mock_directions_repository.dart';
import '../repositories/http_place_detail_repository.dart';
import '../repositories/kakao_transit_repository.dart';
import '../repositories/outdoor_poi_repository.dart';
import '../repositories/place_detail_repository.dart';
import '../repositories/tmap_directions_repository.dart';
import '../repositories/tmap_poi_repository.dart';
import '../repositories/transit_repository.dart';
import '../state/favorites_controller.dart';
import '../state/recent_searches_controller.dart';

/// 앱 전체에서 공유하는 PDR 센서 소스와 세션 드라이버다. 화면이 바뀌어도
/// 센서 세션을 다시 만들지 않도록 singleton으로 유지한다.
PdrMotionSource createDefaultPdrMotionSource({
  TargetPlatform? platform,
  bool? isWeb,
}) {
  if (isWeb ?? kIsWeb) return const UnsupportedPdrMotionSource();
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS => IosPdrMotionSource(),
    TargetPlatform.android => AndroidPdrMotionSource(),
    _ => const UnsupportedPdrMotionSource(),
  };
}

final PdrMotionSource pdrMotionSource = createDefaultPdrMotionSource();
final IndoorNavigationDriver indoorNavigationDriver = IndoorNavigationDriver(
  source: pdrMotionSource,
);
final IndoorLocationEstimateController indoorLocationEstimateController =
    IndoorLocationEstimateController();

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

/// 장소 상세는 실패해도 길찾기 흐름을 막지 않는 별도 조회다. 위젯 테스트에서
/// HTTP를 피해야 할 때는 이 변수를 MockPlaceDetailRepository로 교체한다.
PlaceDetailRepository placeDetailRepository = HttpPlaceDetailRepository();

/// --dart-define=TMAP_APP_KEY=... 로 키를 넘기면 자동으로 실제 API를 쓰고,
/// 안 넘기면(테스트·키 미발급 상태) 직선 경로로 동작하는 Mock을 쓴다.
final DirectionsRepository directionsRepository = tmapAppKey.isEmpty
    ? MockDirectionsRepository()
    : TmapDirectionsRepository();

/// 건물 **밖** 장소 검색(TMAP POI 통합검색). 키가 없으면 기능 자체가 꺼진
/// 구현이 들어가고, 검색 패널은 "주변 장소" 섹션을 아예 그리지 않는다.
///
/// 도보 경로와 달리 Mock을 두지 않는다. 직선 경로 Mock은 "대충 이 방향"이라도
/// 맞지만, 없는 가게를 지어내면 사용자를 실제로 그 좌표까지 걸어가게 만든다.
///
/// 위젯 테스트에서 HTTP 없이 결과를 주입할 수 있도록 final이 아니다.
OutdoorPoiRepository outdoorPoiRepository = tmapAppKey.isEmpty
    ? const UnavailableOutdoorPoiRepository()
    : TmapPoiRepository();

/// 대중교통 경로(카카오맵). 위와 같은 이유로 키가 없으면 꺼진 구현이다.
///
/// **여기만 TMAP 키가 아니라 카카오 키를 본다.** TMAP 대중교통 무료 제공량이
/// 하루 10건이라 데모 한 번에 소진돼 옮겼다. 되돌리려면 `TmapTransitRepository()`
/// 로 바꾸면 되지만, 그때는 판단 기준도 `tmapAppKey`로 함께 되돌려야 한다.
///
/// 카카오 응답에는 첫 승차지점 앞·마지막 하차지점 뒤 도보가 없다. 그 두 구간은
/// 화면이 [directionsRepository]로 채우므로, 대중교통을 쓰는 흐름은 TMAP 키도
/// 함께 있어야 완전한 경로가 그려진다.
TransitRepository transitRepository = kakaoRestApiKey.isEmpty
    ? const UnavailableTransitRepository()
    : KakaoTransitRepository();

/// 사용자가 "장소" 탭에 저장해둔 매장 목록. SharedPreferences로 앱 재실행
/// 뒤에도 유지된다. 테스트에서는 이 변수를 in-memory 컨트롤러로 교체한다.
FavoritesController favoritesController = FavoritesController();

/// 사용자가 최근에 검색한 말. 검색 패널의 빈 화면(idle)을 채운다. 즐겨찾기와
/// 같은 저장소를 쓰지만 **기기 밖으로 나가지 않는다** — 서버로 보내지 않는다.
RecentSearchesController recentSearchesController = RecentSearchesController();

/// 걸음 센서(PDR)에 필요한 권한. iOS는 Motion & Fitness, Android는
/// ActivityRecognition이며 가속도·자력계 원시값은 권한이 필요 없다.
Permission get pedometerPermission =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? Permission.sensors
    : Permission.activityRecognition;

/// 앱 시작 시 필요한 권한을 **하나씩 순서대로** 요청한다.
///
/// 예전에는 `List<Permission>.request()`로 목록을 한 번에 던졌다. 이 호출은
/// 요청을 동시에 보내기 때문에 OS 다이얼로그가 연달아 겹쳐 뜨고, 사용자는 첫
/// 문구를 읽기도 전에 다음 창을 마주해 무엇을 허용했는지 모른 채 넘기게 된다.
/// `await`로 앞 다이얼로그가 닫힌 뒤 다음을 요청하면 순서가 보장된다.
///
/// 두 권한 모두 앱을 쓰려면 결국 필요하므로 시점을 나누지 않고 여기서 함께
/// 받는다. 위치를 먼저 요청하는 이유는 앱이 야외 지도로 시작하기 때문이다 —
/// 사용자가 가장 먼저 보는 화면과 첫 다이얼로그가 맞아야 이유가 납득된다.
Future<Map<Permission, PermissionStatus>>
defaultRequestStartupPermissions() async {
  final statuses = <Permission, PermissionStatus>{};
  for (final permission in [
    Permission.locationWhenInUse,
    pedometerPermission,
  ]) {
    statuses[permission] = await permission.request();
  }
  return statuses;
}

/// 앱 시작 시 권한 요청. 플랫폼 채널이 없는 테스트 환경에서는
/// 이 변수를 즉시 완료되는 가짜 함수로 교체해 실제 플러그인 호출을 피한다.
Future<Map<Permission, PermissionStatus>> Function() requestStartupPermissions =
    defaultRequestStartupPermissions;

/// 걸음 센서 권한이 지금 허용돼 있는지. **다이얼로그를 띄우지 않는다.**
///
/// PDR 상시 실행이 화면 진입마다 센서를 켜려 하므로, 거부된 상태에서 매번
/// 시작을 시도하면 `sensorStartFailed` degraded가 반복해서 쌓인다. 자동 시작
/// 전에 이 값으로 걸러낸다.
///
/// iOS/Android가 아닌 플랫폼은 네이티브 PDR 구현 자체가 없으므로 false다.
/// 모바일 테스트에서 권한 플러그인만 빠진 경우에는 **허용으로 본다**. 이 경우
/// 센서 시작 실패는 driver가 degraded warning으로 바꿔 플랫폼 경계 안에서
/// 처리한다.
Future<bool> defaultIsPedometerPermissionGranted() async {
  if (kIsWeb ||
      defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    return (await pedometerPermission.status).isGranted;
  } on Object {
    return true;
  }
}

/// 자동 시작 게이트. 테스트에서는 교체해 플러그인 호출을 피한다.
Future<bool> Function() isPedometerPermissionGranted =
    defaultIsPedometerPermissionGranted;

/// 야외 위치 스트림을 얼마나 자주 받을지.
///
/// **안드로이드는 간격을 지정하지 않으면 5초에 한 번이다.** 기본
/// [LocationSettings]가 채널로 보내는 값은 accuracy와 distanceFilter뿐인데,
/// geolocator의 안드로이드 구현은 간격이 비어 있으면 5000 ms를 채워 넣고 그 값을
/// `setIntervalMillis`와 `setMinUpdateIntervalMillis`에 **둘 다** 건다. 뒤엣것이
/// 하한이라 신호가 아무리 좋아도 5초보다 빨리 오지 않는다. 이 기본값은
/// 문서에도, 코드에도 드러나지 않아 "GPS가 원래 느린 것"처럼 보였다.
///
/// 여기에 예전의 `distanceFilter: 5`가 겹쳤다. 걷는 사람은 5초에 한 번, 6 m씩
/// 순간이동하는 아이콘을 보게 된다 — 실기기 실험에서 "위치가 실시간으로 안
/// 움직인다"고 관찰된 것이 이것이다. 두 제한을 모두 풀어 1초에 한 번 받는다.
///
/// **비용은 스트림이 아니라 소비 지점에서 막는다.** 예전 주석이 걱정한 것은
/// 좌표가 올 때마다 나가는 TMAP 도보 경로 재요청이었는데, 그건 이제 마지막
/// 요청 지점에서 충분히 움직였을 때만 나간다
/// (`screens/outdoor_map/route_recompute_policy.dart`). 좌표 자체를 덜 받아서
/// 네트워크를 아끼면 화면에 그리는 위치까지 같이 낡는다.
///
/// iOS에는 간격 개념이 없고 거리 필터만 있으므로 그것만 푼다.
LocationSettings positionStreamSettings() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 0,
  );
}

Stream<Position> defaultWatchPosition() {
  return Geolocator.getPositionStream(
    locationSettings: positionStreamSettings(),
  );
}

/// 야외 지도 화면의 실시간 위치 스트림. 걷는 동안 위치 마커·경로·건물 진입
/// 판정이 계속 갱신되도록 한다. 플랫폼 채널이 없는 테스트 환경에서는 이
/// 변수를 가짜 [Position] 스트림으로 교체한다.
Stream<Position> Function() watchPosition = defaultWatchPosition;

/// 실내 화면을 직접 열었을 때 추정위치를 만들기 위한 GPS 1회 조회.
///
/// 자동 초기화가 권한 다이얼로그를 갑자기 띄우면 안 되므로 현재 권한이 이미
/// 허용된 경우에만 조회한다. 위치 서비스가 꺼졌거나 권한이 없거나 5초 안에
/// 좌표를 얻지 못하면 null로 끝내고 사용자의 수동 위치 지정을 남겨 둔다.
Future<Position?> defaultRequestIndoorEstimatePosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 5),
      ),
    );
  } on Object {
    return null;
  }
}

/// 테스트에서는 플랫폼 채널 없이 좌표/실패를 주입할 수 있도록 교체 가능하게 둔다.
Future<Position?> Function() requestIndoorEstimatePosition =
    defaultRequestIndoorEstimatePosition;
