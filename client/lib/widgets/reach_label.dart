import '../domain/dijkstra.dart';

/// 실내 보행 속도(m/s). 값과 이름을 `indoor_map_screen.dart`의 ETA 계산과 맞춰,
/// 목록·상세에 적힌 "도보 N분"과 경로를 그린 뒤 ETA 카드의 분이 어긋나지 않게 한다.
const _walkingSpeedMetersPerSecond = 1.2;

/// 현재 위치에서 어떤 지점까지의 "몇 m · 도보 몇 분".
///
/// **거리와 시간의 출처가 다르다.** 거리는 실제 이동 거리([NodeReach.distanceM]),
/// 시간은 라우팅 비용([NodeReach.costM]) 기준이다. 비용에는 엘리베이터 대기·탑승이
/// 인코딩돼 있어서, 시간까지 거리로 계산하면 다른 층 매장이 실제보다 가깝게
/// 느껴진다. 반대로 거리를 비용으로 적으면 그만큼 부풀어 보인다. ETA 카드가 이미
/// 같은 규칙을 쓴다.
///
/// 검색 결과 목록과 매장 상세가 같은 함수를 쓴다 — 두 화면이 같은 매장에 다른
/// 거리를 적으면 어느 쪽을 믿어야 할지 알 수 없다.
String reachLabel(NodeReach reach) {
  final minutes = (reach.costM / _walkingSpeedMetersPerSecond / 60)
      .ceil()
      .clamp(1, 999);
  return '${reach.distanceM.round()}m · 도보 $minutes분';
}
