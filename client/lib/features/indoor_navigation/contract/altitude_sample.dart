import 'dart:math' as math;

/// 기압계 가용 상태. native가 snapshot 이벤트에 실어 보낸다.
///
/// Android는 `TYPE_PRESSURE` 미탑재 기기가 실제로 있고, iOS도 iPhone 5s 이하는
/// `CMAltimeter`가 없다. 이 값이 false면 층 전이 판정을 아예 돌리지 않는다 —
/// "판정을 기다리는 중"과 "판정할 수 없는 기기"는 UI·로그에서 구분돼야 한다.
class AltimeterStatus {
  const AltimeterStatus({
    required this.available,
    required this.source,
    this.sensorName,
  });

  const AltimeterStatus.unavailable()
    : available = false,
      source = 'unavailable',
      sensorName = null;

  final bool available;

  /// `ios_cmaltimeter` · `android_pressure` · `unavailable`.
  final String source;

  /// Android 센서 이름(기기별 기압계 모델). iOS는 null.
  final String? sensorName;
}

/// 기압계 한 샘플.
///
/// **층 전이 판정 전용이다.** PDR 위치·거리 추정에는 들어가지 않는다. 기압은
/// 수평 위치에 대해 아무 정보도 주지 않고, 반대로 위치 파이프라인에 섞으면
/// HVAC 교란이 걸음 배치까지 흔들 수 있다.
class AltitudeSample {
  const AltitudeSample({
    required this.timestampMs,
    required this.pressureHpa,
    required this.source,
    this.relativeAltitudeM,
  });

  /// 센서 시각(unix ms).
  final int timestampMs;

  final double pressureHpa;

  /// `ios_cmaltimeter` · `android_pressure`.
  final String source;

  /// iOS `CMAltimeter`가 주는 세션 상대고도(m). Android는 null.
  ///
  /// 판정에는 쓰지 않는다. [altitudeM]을 기압에서 직접 계산하는 한 경로만
  /// 두어 두 플랫폼이 같은 코드로 판정되게 하고, 이 값은 그 계산이 실측에서
  /// 맞는지 대조하는 진단값으로만 남긴다.
  final double? relativeAltitudeM;

  /// 표준대기 기압고도(m).
  ///
  /// 절대 고도로는 쓸 수 없다(해면기압이 날씨에 따라 매일 바뀐다). 이 값은
  /// 오직 **baseline과의 차이**로만 쓰며, 그 차이는 해면기압 가정과 무관하다.
  double get altitudeM => pressureAltitudeM(pressureHpa);
}

/// ISA 표준대기 기압고도. `h = 44330 · (1 - (p/1013.25)^0.190295)`.
///
/// 층 판정은 두 시점의 차이만 보므로 기준 기압(1013.25 hPa) 선택은 결과에
/// 거의 영향을 주지 않는다(1000 hPa 부근에서 1 hPa ≈ 8.4 m는 동일).
/// 0 이하 기압은 센서 오류이므로 0을 돌려준다.
double pressureAltitudeM(double pressureHpa) {
  if (pressureHpa <= 0) return 0;
  return 44330.0 * (1.0 - math.pow(pressureHpa / 1013.25, 0.190295));
}
