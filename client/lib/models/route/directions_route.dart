import 'package:latlong2/latlong.dart';

/// 출발지에서 목적지까지의 **도로 경로**(도보 또는 자동차).
///
/// 두 수단이 같은 모델을 쓰는 이유는 화면이 묻는 것이 같기 때문이다 — 선을
/// 어디에 그리고, 얼마나 걸리고, 얼마나 먼가. 수단마다 모델을 나누면 요약
/// 카드와 지도 레이어가 각각 두 벌이 되는데, 정작 다른 것은 아래 요금 두 줄뿐이다.
class DirectionsRoute {
  const DirectionsRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.tollFareWon,
    this.taxiFareWon,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;

  /// 통행료(원). 자동차 경로에만 있고, 무료 구간이면 0이다.
  ///
  /// **null과 0을 구분한다.** null은 "이 수단엔 통행료 개념이 없다"(도보)이고
  /// 0은 "유료도로를 안 탄다"이다. 하나로 뭉치면 도보 경로에 "통행료 없음"이
  /// 적힌다 — 틀린 말은 아니지만 걸어가는 사람에게 아무 의미가 없는 줄이다.
  final int? tollFareWon;

  /// 같은 구간을 택시로 갔을 때의 예상 요금(원). 자동차 경로에만 있다.
  final int? taxiFareWon;
}
