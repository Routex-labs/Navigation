import 'package:flutter/material.dart';

import '../models/transit_route.dart';
import '../theme/app_theme.dart';
import 'transit_style.dart';

/// 대중교통 경로를 지도에 그리는 동안 화면 하단에 놓는 요약 카드.
///
/// 도보 안내의 [EtaCard] 자리를 대신한다. 같은 자리에 둘 다 띄우지 않는 이유는
/// 두 카드가 서로 다른 소요 시간을 말하기 때문이다 — 한 화면에 "약 42분"과
/// "약 12분"이 동시에 있으면 어느 쪽이 지금 그려진 선인지 알 수 없다.
///
/// [onWalk]는 "도보로 보기"다. 대중교통이 더 오래 걸리는 짧은 거리에서
/// 사용자가 되돌아갈 길을 남겨 둔다 — 이게 없으면 안내를 끄고 목적지부터
/// 다시 골라야 한다.
class TransitSummaryCard extends StatelessWidget {
  const TransitSummaryCard({
    super.key,
    required this.itinerary,
    required this.label,
    required this.onClose,
    this.onWalk,
    this.onClosePointerDown,
  });

  final TransitItinerary itinerary;

  /// "OO까지"처럼 도착지를 가리키는 문구.
  final String label;

  final VoidCallback onClose;
  final VoidCallback? onWalk;

  /// 지도 오버레이 탭 가드가 쓰는 콜백([EtaCard]와 같은 규칙).
  final ValueChanged<Offset>? onClosePointerDown;

  @override
  Widget build(BuildContext context) {
    final fare = itinerary.fare;
    final facts = [
      itinerary.transferCount == 0 ? '환승 없음' : '환승 ${itinerary.transferCount}회',
      '도보 ${formatTransitDuration(itinerary.totalWalkTimeSeconds)}',
      if (fare != null && fare > 0) formatTransitFare(fare),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_transit_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '약 ${formatTransitDuration(itinerary.totalTimeSeconds)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        facts.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Listener(
                  onPointerDown: (event) =>
                      onClosePointerDown?.call(event.position),
                  child: TextButton(
                    onPressed: onClose,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD93025),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Color(0x33D93025)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('안내 종료'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < itinerary.legs.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(
                                Icons.chevron_right,
                                size: 13,
                                color: AppColors.muted,
                              ),
                            ),
                          TransitLegChip(leg: itinerary.legs[i], compact: true),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onWalk != null)
                  TextButton.icon(
                    key: const ValueKey('transit-switch-to-walk'),
                    onPressed: onWalk,
                    icon: const Icon(Icons.directions_walk_rounded, size: 16),
                    label: const Text('도보'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
