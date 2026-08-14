import 'package:flutter/material.dart';

import '../models/transit_route.dart';
import '../theme/app_theme.dart';
import './transit_style.dart';

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
    final facts = [
      itinerary.transferCount == 0 ? '환승 없음' : '환승 ${itinerary.transferCount}회',
      '도보 ${formatTransitDuration(itinerary.totalWalkTimeSeconds)}',
      if (fare != null && fare > 0) formatTransitFare(fare),
    ];
    return InkWell(
      onTap: onTap,
      child: Ink(
        color: selected ? AppColors.blue50 : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatTransitDuration(itinerary.totalTimeSeconds),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (fastest)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.blue50,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '최단 시간',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                facts.join(' · '),
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              // 구간을 순서대로 늘어놓는다. 도보까지 포함해야 "지하철역까지 12분
              // 걷는다"는 사실이 목록에서 읽힌다 — 요약 숫자만으로는 안 보인다.
              TransitLegStrip(legs: itinerary.legs),
            ],
          ),
        ),
      ),
    );
  }
}

/// `도보 5분 › 5호선 › 도보 3분`처럼 구간을 화살표로 잇는 줄.
class TransitLegStrip extends StatelessWidget {
  const TransitLegStrip({super.key, required this.legs});

  final List<TransitLeg> legs;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < legs.length; i++) {
      if (i > 0) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right, size: 14, color: AppColors.muted),
          ),
        );
      }
      children.add(TransitLegChip(leg: legs[i]));
    }
    // 구간이 많으면 줄바꿈된다. 가로 스크롤로 두면 지도 위 시트에서 스크롤
    // 방향이 겹쳐(세로 시트 드래그 vs 가로 스트립) 둘 다 잘 안 먹는다.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: children,
    );
  }
}
