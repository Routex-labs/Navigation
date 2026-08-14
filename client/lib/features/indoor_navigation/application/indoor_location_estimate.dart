import 'package:flutter/foundation.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:latlong2/latlong.dart';

import '../../../domain/geo/geo_transform.dart';
import '../../../models/building/floor_graph.dart';
import 'floor_map_matcher.dart';

const trustedIndoorGpsAccuracyM = 15.0;
const maxIndoorGpsSnapDistanceM = 12.0;
const maxIndoorEntranceSnapDistanceM = 25.0;

/// GPS 추정점을 사용자 입력 없이 PDR 기준점으로 승격해도 되는지 판단한다.
///
/// 자북 기준 heading이면 `confirmAnchorByPin`이 화면 방향 질문 없이 도면 회전을
/// 계산할 수 있다. 짧은 대기 시간 안에 `headingConverged`가 true가 되지 않았다는
/// 이유만으로 막지는 않는다. 수렴 플래그는 흔들림의 안정도일 뿐 자북 기준의
/// 유효 여부와 다르고, 이를 필수로 두면 마커가 GPS 한 점에 영구 정지한다.
bool canAutoAnchorEstimatedLocation({
  required bool hasHeading,
  required bool headingReferenceIsMagneticNorth,
}) => hasHeading && headingReferenceIsMagneticNorth;

/// GPS를 건물 층 그래프에 투영해 얻은 절대 위치 추정값.
///
/// PDR 앵커와 별도로 보존한다. 둘을 같은 값으로 덮어쓰면 이후 화면이 "GPS가
/// 추정한 위치"와 "핀 이후 PDR 위치"를 구분할 수 없고, 오래된 GPS가 최신 PDR을
/// 되돌리는 사고도 막을 수 없다.
class IndoorLocationEstimate {
  const IndoorLocationEstimate({
    required this.buildingId,
    required this.floorId,
    required this.localM,
    required this.wgs84,
    required this.accuracyMeters,
    required this.observedAt,
    required this.source,
  });

  final String buildingId;
  final String floorId;
  final PdrLocalPoint localM;
  final LatLng wgs84;
  final double accuracyMeters;
  final DateTime observedAt;

  /// `gps`는 실제 GPS 좌표를 통로에 투영한 폴백, `entrance`는 기본 정책으로
  /// 건물 입구를 통로에 투영한 값이다.
  final String source;

  bool isFresh(DateTime now, {Duration maxAge = const Duration(seconds: 30)}) =>
      !observedAt.isAfter(now) && now.difference(observedAt) <= maxAge;
}

class IndoorLocationEstimateController extends ChangeNotifier {
  IndoorLocationEstimate? _current;

  IndoorLocationEstimate? get current => _current;

  void update(IndoorLocationEstimate estimate) {
    _current = estimate;
    notifyListeners();
  }

  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}

/// GPS 한 점을 해당 층의 통행 그래프에 붙여 실내 절대위치로 바꾼다.
///
/// 정확도가 낮거나, 좌표 변환이 불가능하거나, 가장 가까운 통로가 너무 멀면
/// null을 반환한다. 호출자가 임의의 입구나 경로 시작점으로 대체하지 않게 실패를
/// 명시적으로 유지하는 것이 핵심이다.
IndoorLocationEstimate? estimateIndoorLocationFromGps({
  required String buildingId,
  required String floorId,
  required FloorGraph graph,
  required double latitude,
  required double longitude,
  required double accuracyMeters,
  required DateTime observedAt,
  DateTime? now,
  double maxAccuracyMeters = trustedIndoorGpsAccuracyM,
  double maxSnapDistanceMeters = maxIndoorGpsSnapDistanceM,
}) {
  if (graph.nodes.isEmpty ||
      graph.edges.isEmpty ||
      !latitude.isFinite ||
      !longitude.isFinite ||
      !accuracyMeters.isFinite ||
      accuracyMeters < 0 ||
      accuracyMeters > maxAccuracyMeters) {
    return null;
  }

  final transform = fitFloorGeoTransform(graph.nodes);
  final local = transform.invert(latitude, longitude);
  if (local == null) return null;
  final snapped = FloorMapMatcher(
    graph,
  ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
  if (snapped == null || snapped.distanceToGraphM > maxSnapDistanceMeters) {
    return null;
  }

  final wgs84 = transform.apply(snapped.point.eastM, snapped.point.northM);
  final estimate = IndoorLocationEstimate(
    buildingId: buildingId,
    floorId: floorId,
    localM: snapped.point,
    wgs84: LatLng(wgs84.$1, wgs84.$2),
    accuracyMeters: accuracyMeters,
    observedAt: observedAt,
    source: 'gps',
  );
  return estimate.isFresh(now ?? DateTime.now()) ? estimate : null;
}

/// 건물 입구를 해당 층 통행망에 붙여 기본 실내 기준점을 만든다.
///
/// 실내 GPS는 현재 층을 알 수 없고 신호가 크게 튀므로 자동 앵커의 기본값으로
/// 쓰지 않는다. 입구와 통행망이 너무 멀면 잘못된 복도에 억지로 붙이지 않고 null을
/// 반환해 수동 위치 지정으로 넘긴다.
IndoorLocationEstimate? estimateIndoorLocationFromEntrance({
  required String buildingId,
  required String floorId,
  required FloorGraph graph,
  required double latitude,
  required double longitude,
  required DateTime observedAt,
  double maxSnapDistanceMeters = maxIndoorEntranceSnapDistanceM,
}) {
  if (graph.nodes.isEmpty ||
      graph.edges.isEmpty ||
      !latitude.isFinite ||
      !longitude.isFinite) {
    return null;
  }
  final transform = fitFloorGeoTransform(graph.nodes);
  final local = transform.invert(latitude, longitude);
  if (local == null) return null;
  final snapped = FloorMapMatcher(
    graph,
  ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
  if (snapped == null || snapped.distanceToGraphM > maxSnapDistanceMeters) {
    return null;
  }
  final wgs84 = transform.apply(snapped.point.eastM, snapped.point.northM);
  return IndoorLocationEstimate(
    buildingId: buildingId,
    floorId: floorId,
    localM: snapped.point,
    wgs84: LatLng(wgs84.$1, wgs84.$2),
    accuracyMeters: snapped.distanceToGraphM,
    observedAt: observedAt,
    source: 'entrance',
  );
}
