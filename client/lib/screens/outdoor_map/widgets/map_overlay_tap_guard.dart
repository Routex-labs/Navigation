import 'package:flutter/widgets.dart';

/// Flutter 오버레이가 제거된 직후 같은 포인터의 MapLibre 클릭이 늦게 도착하는
/// 경우를 한 번만 차단한다.
///
/// MapLibre 웹 지도는 Flutter의 gesture arena와 별개인 DOM 캔버스라, 지도 위
/// 버튼이 자신의 탭을 소비해도 동일한 클릭이 지도 콜백으로 이어질 수 있다.
/// 닫기 버튼의 pointer-down 좌표를 짧게 보존하고 다음 지도 콜백 한 건에서만
/// 검사하면, 같은 탭은 막되 사용자의 그다음 별도 지도 탭은 정상 처리할 수 있다.
class MapOverlayTapGuard {
  MapOverlayTapGuard({
    this.retention = const Duration(milliseconds: 700),
    this.hitRadius = 32,
  });

  final Duration retention;
  final double hitRadius;
  Offset? _pointerDownPosition;
  DateTime? _retainedAt;

  void retainPointerDown(Offset globalPosition, {DateTime? at}) {
    _pointerDownPosition = globalPosition;
    _retainedAt = at ?? DateTime.now();
  }

  /// 보존된 pointer-down 근처의 첫 지도 클릭이면 `true`.
  ///
  /// 좌표가 허용 반경 밖이더라도 첫 지도 클릭에서 보존 상태를 소비한다. 따라서
  /// 브라우저가 중복 클릭을 만들지 않은 환경에서도 이후 탭을 계속 막지 않는다.
  bool consumeIfBlocked(Offset globalPoint, {DateTime? now}) {
    final retainedPosition = _pointerDownPosition;
    final retainedAt = _retainedAt;
    _pointerDownPosition = null;
    _retainedAt = null;
    if (retainedPosition == null || retainedAt == null) return false;
    if ((now ?? DateTime.now()).difference(retainedAt) > retention) {
      return false;
    }
    return (globalPoint - retainedPosition).distance <= hitRadius;
  }
}
