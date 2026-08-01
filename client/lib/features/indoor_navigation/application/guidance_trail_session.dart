import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'corridor_position_tracker.dart';

/// 한 번의 길안내 동안 실제로 수용한 복도 보정 궤적을 누적한다.
///
/// 경로 재탐색은 앞으로 갈 파란선만 바꾸므로 이 상태를 초기화하지 않는다.
/// tracker가 대표 가설을 교체해 과거 경로를 다시 쓰더라도 이미 화면에 확정해
/// 둔 회색 궤적은 보존하고, 마지막 확정점과 이어지는 새 꼬리만 덧붙인다.
class GuidanceTrailSession {
  static const _samePointToleranceM = 0.05;
  static const _reconnectToleranceM = 1.5;
  static const _maxContinuousStepM = 3.0;

  final Map<String, List<List<PdrLocalPoint>>> _segmentsByFloor = {};
  bool _active = false;

  bool get isActive => _active;

  void start({
    required String floorId,
    required CorridorTrackingResult? result,
  }) {
    clear();
    _active = true;
    if (result != null) {
      _segmentsByFloor[floorId] = [
        [result.correctedPosition],
      ];
    }
  }

  void clear() {
    _active = false;
    _segmentsByFloor.clear();
  }

  void update({
    required String floorId,
    required CorridorTrackingResult result,
  }) {
    if (!_active) return;
    final floorSegments = _segmentsByFloor.putIfAbsent(floorId, () => []);
    if (floorSegments.isEmpty) {
      floorSegments.add([result.correctedPosition]);
      return;
    }

    final last = floorSegments.last.last;
    final path = result.correctedPath;
    var reconnectIndex = -1;
    var reconnectDistanceM = double.infinity;
    for (var index = path.length - 1; index >= 0; index--) {
      final distanceM = (path[index] - last).distance;
      if (distanceM < reconnectDistanceM) {
        reconnectDistanceM = distanceM;
        reconnectIndex = index;
      }
      if (distanceM <= _samePointToleranceM) break;
    }

    if (reconnectIndex >= 0 && reconnectDistanceM <= _reconnectToleranceM) {
      for (final point in path.skip(reconnectIndex + 1)) {
        _appendPoint(floorSegments, point);
      }
      return;
    }

    // 앵커 재설정·층 전환·대표 가설의 큰 재배치는 직선으로 잇지 않는다.
    // 별도 LineString으로 시작해야 지도에 순간이동 선이 생기지 않는다.
    floorSegments.add([result.correctedPosition]);
  }

  /// [previewPath]는 아직 확정되지 않았으므로 저장하지 않고 반환 복사본에만
  /// 붙인다. 다음 snapshot에서 preview가 되돌아가도 누적 회색 이력은 오염되지
  /// 않는다.
  List<List<PdrLocalPoint>> segmentsForFloor(
    String floorId, {
    List<PdrLocalPoint> previewPath = const [],
  }) {
    final stored = _segmentsByFloor[floorId] ?? const [];
    final result = [
      for (final segment in stored) List<PdrLocalPoint>.of(segment),
    ];
    if (!_active || previewPath.isEmpty) return result;

    for (final point in previewPath) {
      _appendPoint(result, point);
    }
    return result;
  }

  static void _appendPoint(
    List<List<PdrLocalPoint>> segments,
    PdrLocalPoint point,
  ) {
    if (segments.isEmpty) {
      segments.add([point]);
      return;
    }
    final last = segments.last.last;
    final distanceM = (point - last).distance;
    if (distanceM <= _samePointToleranceM) return;
    if (distanceM > _maxContinuousStepM) {
      segments.add([point]);
    } else {
      segments.last.add(point);
    }
  }
}
