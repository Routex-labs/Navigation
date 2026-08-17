import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../models/route/transit_route.dart';
import 'transit_style.dart';

/// 대중교통 경로 후보 **한 줄**.
///
/// 소요 시간만 크게 적지 않고 환승 횟수·도보 시간·요금까지 함께 적는 이유는,
/// **가장 빠른 경로가 늘 최선은 아니기 때문**이다. 3분 빠른 대신 두 번 갈아타는
/// 경로와 조금 느려도 한 번에 가는 경로 중 무엇을 고를지는 사용자만 안다.
///
/// 길찾기 화면의 전체 목록과 예전 바텀시트가 **같은 줄**을 써야 한다. 두 곳이
/// 각자 그리면 같은 경로가 화면을 옮길 때마다 다른 정보를 말하게 된다.
class TransitItineraryTile extends StatelessWidget {
  const TransitItineraryTile({
    super.key,
    required this.itinerary,
    required this.fastest,
    required this.onTap,
    this.selected = false,
  });

  final TransitItinerary itinerary;

  /// 목록에서 가장 빠른 경로인지. 맞으면 배지를 단다 — 정렬 순서의 의미를
  /// 밝히지 않으면 사용자가 첫 줄이 왜 첫 줄인지 추측해야 한다.
  final bool fastest;

  /// 지금 지도에 그려져 있는 경로인지. 목록으로 되돌아왔을 때 방금 보던 줄이
  /// 어느 것인지 알 수 있어야 한다.
  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fare = itinerary.fare;
    return RoutexTransitItinerary(
      duration: formatTransitDuration(itinerary.totalTimeSeconds),
      facts: [
        itinerary.transferCount == 0
            ? '환승 없음'
            : '환승 ${itinerary.transferCount}회',
        '도보 ${formatTransitDuration(itinerary.totalWalkTimeSeconds)}',
        if (fare != null && fare > 0) formatTransitFare(fare),
      ],
      legs: [for (final leg in itinerary.legs) routexTransitLeg(leg)],
      fastest: fastest,
      selected: selected,
      onPressed: onTap,
    );
  }
}
