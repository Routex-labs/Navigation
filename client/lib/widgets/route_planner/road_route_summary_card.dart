import 'package:flutter/material.dart';

import '../../models/directions_route.dart';
import '../../theme/app_theme.dart';
import '../transit_style.dart';
import 'route_plan_mode.dart';

/// 자동차·도보 경로를 지도에 그린 뒤 화면 **아래**에 놓는 요약 카드.
///
/// 대중교통과 달리 후보 목록이 없다 — 도로 경로는 한 가지를 그려 놓고 시작할지
/// 말지만 물으면 된다. 그래서 목록 화면을 거치지 않고 수단을 고른 즉시 지도와
/// 이 카드가 함께 뜬다.
class RoadRouteSummaryCard extends StatelessWidget {
  const RoadRouteSummaryCard({
    super.key,
    required this.mode,
    required this.route,
    required this.onStart,
  });

  final RoutePlanMode mode;
  final DirectionsRoute route;

  /// "안내시작" — 길찾기 화면을 닫고 지도 위 안내로 넘어간다.
  ///
  /// null이면 버튼 자체를 그리지 않는다. 도보가 그렇다 — 도보는 안내를 시작하지
  /// 않고 경로만 그린 뒤 화면을 닫으므로([_RoutePlannerViewState._computeRoad]),
  /// 누를 것이 없는 버튼을 한 프레임이라도 보여 주면 "눌러야 하나" 싶어진다.
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final toll = route.tollFareWon;
    final taxi = route.taxiFareWon;
    final facts = [
      formatTransitDistance(route.distanceMeters),
      // null과 0을 구분한다([DirectionsRoute.tollFareWon]) — 도보 경로에
      // "통행료 없음"이 붙으면 걸어가는 사람에게 아무 의미가 없는 줄이 된다.
      if (toll != null) toll == 0 ? '통행료 없음' : '통행료 ${formatTransitFare(toll)}',
      if (taxi != null && taxi > 0) '택시 약 ${formatTransitFare(taxi)}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // 자동차는 TMAP의 추천 옵션(교통최적)으로 부르고, 도보는 최단
              // 거리로 온다. 무엇을 기준으로 고른 경로인지 밝혀야 사용자가
              // "왜 이 길인가"를 묻지 않는다.
              mode == RoutePlanMode.car ? '내비 추천' : '최단 거리',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatTransitDuration(route.durationSeconds),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              facts.join(' · '),
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            if (onStart != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('route-planner-start'),
                  onPressed: onStart,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('안내시작'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
