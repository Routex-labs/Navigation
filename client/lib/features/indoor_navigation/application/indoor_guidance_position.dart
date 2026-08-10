import 'package:indoor_pdr_core/indoor_pdr_core.dart';

/// 화면에 그릴 현재 위치가 **어디서 나왔는지**.
///
/// 예전에는 이 구분이 없어서 GPS 추정점과 걸음으로 따라간 위치가 같은 레이어에
/// 같은 모양으로 그려졌다. 사용자 입장에서는 30초짜리 폴백과 확정된 내 위치가
/// 구분되지 않았고, 추정을 확정으로 읽었다. 위치를 내보내는 쪽이 출처를 함께
/// 내보내야 화면이 다르게 그릴 수 있다.
enum GuidancePositionSource {
  /// 앵커가 있고 걸음까지 반영된 복도 보정 위치. 가장 신뢰도가 높다.
  tracked,

  /// 앵커는 확정됐지만 아직 보정할 걸음이 없다. 위치는 맞지만 방향은 모른다.
  anchorOnly,

  /// 앵커가 없어 GPS·입구 추정으로 대신 그리는 값.
  ///
  /// **확정이 아니다.** 이 출처일 때 화면은 반투명·정확도 원처럼 "대략"이라는
  /// 것이 보이게 그려야 한다. 그렇다고 아무것도 안 그리면 사용자는 앱이 내
  /// 위치를 전혀 모른다고 읽으므로, 지우지 않고 약하게 그린다.
  estimate,
}

/// 세션이 화면에 내주는 현재 위치 한 건.
class GuidancePosition {
  const GuidancePosition({
    required this.localM,
    required this.source,
    this.headingDeg,
    this.accuracyM,
  });

  /// 지금 보고 있는 층의 local m 좌표.
  final PdrLocalPoint localM;

  final GuidancePositionSource source;

  /// 마커 원뿔이 쓰는 방향. [GuidancePositionSource.tracked]가 아니면 null이다 —
  /// 앵커만 있거나 추정점인 상태에서 방향을 그리면 서 있는 사람에게 엉뚱한
  /// 방향을 가리켜 준다.
  final double? headingDeg;

  /// 추정점의 GPS 정확도(m). 다른 출처에서는 null.
  final double? accuracyM;

  bool get isConfirmed => source != GuidancePositionSource.estimate;

  @override
  bool operator ==(Object other) =>
      other is GuidancePosition &&
      other.localM.eastM == localM.eastM &&
      other.localM.northM == localM.northM &&
      other.source == source &&
      other.headingDeg == headingDeg &&
      other.accuracyM == accuracyM;

  @override
  int get hashCode =>
      Object.hash(localM.eastM, localM.northM, source, headingDeg, accuracyM);

  @override
  String toString() =>
      'GuidancePosition(${localM.eastM.toStringAsFixed(2)}, '
      '${localM.northM.toStringAsFixed(2)}, $source)';
}
