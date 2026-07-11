import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_config.dart';
import '../repositories/building_repository.dart';
import '../repositories/destination_repository.dart';
import '../repositories/directions_repository.dart';
import '../repositories/http_building_repository.dart';
import '../repositories/mock_destination_repository.dart';
import '../repositories/mock_directions_repository.dart';
import '../repositories/tmap_directions_repository.dart';

/// 실내 지도·목적지 검색·경로 안내가 전부 백엔드(api/) 다익스트라 그래프로
/// 동작하도록 HttpBuildingRepository를 쓴다. 백엔드 없이 오프라인으로 확인할
/// 땐 이 한 줄만 MockBuildingRepository()로 되돌리면 된다.
///
/// watchPosition/requestStartupPermissions와 같은 이유로 final이 아니다 —
/// 플랫폼 채널·네트워크가 없는 위젯 테스트 환경에서는 이 변수를
/// MockBuildingRepository()로 교체해 실제 HTTP 호출 없이 동작을 검증한다.
BuildingRepository buildingRepository = HttpBuildingRepository();

/// 백엔드 RAG가 준비되면 이 한 줄만 [HttpDestinationRepository]로 바꾼다.
/// buildingRepository를 감싸므로, 테스트에서 buildingRepository를 교체했다면
/// 이 변수도 같은 인스턴스로 다시 만들어 줘야 한다.
DestinationRepository destinationRepository = MockDestinationRepository(
  buildingRepository,
);

/// --dart-define=TMAP_APP_KEY=... 로 키를 넘기면 자동으로 실제 API를 쓰고,
/// 안 넘기면(테스트·키 미발급 상태) 직선 경로로 동작하는 Mock을 쓴다.
final DirectionsRepository directionsRepository = tmapAppKey.isEmpty
    ? MockDirectionsRepository()
    : TmapDirectionsRepository();

Future<Map<Permission, PermissionStatus>> defaultRequestStartupPermissions() {
  return [
    Permission.locationWhenInUse,
    Permission.activityRecognition,
  ].request();
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
