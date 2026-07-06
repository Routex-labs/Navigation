import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../repositories/building_repository.dart';
import '../repositories/destination_repository.dart';
import '../repositories/directions_repository.dart';
import '../repositories/mock_building_repository.dart';
import '../repositories/mock_destination_repository.dart';
import '../repositories/mock_directions_repository.dart';

/// 백엔드가 준비되면 이 한 줄만 [HttpBuildingRepository]로 바꾼다.
final BuildingRepository buildingRepository = MockBuildingRepository();

/// 백엔드 RAG가 준비되면 이 한 줄만 [HttpDestinationRepository]로 바꾼다.
final DestinationRepository destinationRepository = MockDestinationRepository(
  buildingRepository,
);

/// TMAP appKey(core/api_config.dart의 tmapAppKey) 발급받으면
/// 이 한 줄만 [TmapDirectionsRepository]로 바꾼다.
final DirectionsRepository directionsRepository = MockDirectionsRepository();

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

Future<Position> defaultGetCurrentPosition() {
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}

/// 야외 지도 화면의 현재 위치 조회. 플랫폼 채널이 없는 테스트 환경에서는
/// 이 변수를 가짜 [Position]을 즉시 반환하는 함수로 교체한다.
Future<Position> Function() getCurrentPosition = defaultGetCurrentPosition;
