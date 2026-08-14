import '../route/dijkstra.dart';

/// 실내 보행 속도(m/s). ETA 카드와 같은 값이어야 "도보 N분"이 어긋나지 않는다.
const _walkingSpeedMetersPerSecond = 1.2;

/// 현재 위치에서 어떤 지점까지의 "몇 m · 도보 몇 분".
///
/// **거리와 시간의 출처가 다르다** — 거리는 실제 이동 거리, 시간은 라우팅 비용이다.
/// 비용에는 엘리베이터 대기·탑승이 인코딩돼 있어, 시간까지 거리로 재면 다른 층
/// 매장이 실제보다 가깝게 느껴진다.
///
/// 검색 결과와 매장 상세가 같은 함수를 쓴다 — 두 화면이 다른 거리를 적으면 어느
/// 쪽을 믿어야 할지 알 수 없다.
String reachLabel(NodeReach reach) {
  final minutes = (reach.costM / _walkingSpeedMetersPerSecond / 60)
      .ceil()
      .clamp(1, 999);
  return '${reach.distanceM.round()}m · 도보 $minutes분';
}
