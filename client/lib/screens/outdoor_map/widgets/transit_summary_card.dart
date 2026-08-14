import 'package:flutter/material.dart';

import '../../../models/transit_route.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/transit_style.dart';

/// 대중교통 경로를 지도에 그리는 동안 화면 하단에 놓는 요약 카드.
///
/// 도보 안내의 [EtaCard] 자리를 대신한다. 같은 자리에 둘 다 띄우지 않는 이유는
/// 두 카드가 서로 다른 소요 시간을 말하기 때문이다 — 한 화면에 "약 42분"과
/// "약 12분"이 동시에 있으면 어느 쪽이 지금 그려진 선인지 알 수 없다.
///
/// **"도보로 보기" 버튼은 없다.** 한동안 이 카드에 뒀는데, 이동 수단을 고르는
/// 자리는 상단 이동 수단 줄 하나여야 한다([TravelModeBar]). 같은 선택이 두
/// 군데에 흩어지면 사용자는 어느 쪽이 지금 선택인지 카드와 줄을 번갈아 봐야
/// 한다. [EtaCard]가 같은 이유로 수단 버튼을 이미 걷어냈고, 이 카드만 남겨
/// 두면 대중교통일 때만 규칙이 다른 화면이 된다.
///
/// **"안내 종료"는 오른쪽 아래다.** [EtaCard]와 같은 자리에 둔다 — 수단이
/// 바뀌었다고 종료 버튼이 카드 위아래로 옮겨 다니면, 안내를 그만두려는
/// 사용자가 매번 버튼을 다시 찾아야 한다.
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
