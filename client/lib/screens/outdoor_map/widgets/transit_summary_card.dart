import 'package:flutter/material.dart';

import '../../../models/route/transit_route.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/transit_style.dart';

/// 대중교통 경로를 그리는 동안 화면 하단에 놓는 요약 카드. [EtaCard] 자리를
/// 대신한다 — 둘을 같이 띄우면 서로 다른 소요 시간이 한 화면에 뜬다.
///
/// **"도보로 보기" 버튼은 없다** — 이동 수단을 고르는 자리는 [TravelModeBar]
/// 하나여야 한다. **"안내 종료"는 [EtaCard]와 같은 오른쪽 아래**다(수단마다 자리가
/// 옮겨 다니면 매번 버튼을 다시 찾아야 한다).
class TransitSummaryCard extends StatelessWidget {
  const TransitSummaryCard({
    super.key,
    required this.itinerary,
    required this.label,
    required this.onClose,
    this.onClosePointerDown,
  });

  final TransitItinerary itinerary;

  /// "OO까지"처럼 도착지를 가리키는 문구.
  final String label;

  final VoidCallback onClose;

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
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            // 구간 칩과 "안내 종료"가 같은 줄이다. 칩이 길면 가로로 스크롤되는데,
            // 종료 버튼은 스크롤 밖에 두어 언제나 같은 자리에 남는다 — 스크롤
            // 안에 넣으면 환승이 많은 경로에서 버튼이 화면 밖으로 밀려난다.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
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
          ],
        ),
      ),
    );
  }
}
