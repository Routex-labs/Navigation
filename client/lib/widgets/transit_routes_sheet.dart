import 'package:flutter/material.dart';

import '../models/transit_route.dart';
import '../theme/app_theme.dart';
import 'map_overlay_guard.dart';
import 'sheet_grab_handle.dart';
import 'sheet_header.dart';
import 'transit_style.dart';

/// 대중교통 경로 후보 목록 시트.
///
/// 목록으로 두는 이유는 **가장 빠른 경로가 늘 최선은 아니기 때문**이다. 3분
/// 빠른 대신 두 번 갈아타는 경로와, 조금 느려도 한 번에 가는 경로 중 무엇을
/// 고를지는 사용자만 안다. 그래서 각 줄에 소요 시간뿐 아니라 환승 횟수·도보
/// 시간·요금을 함께 적는다.
class TransitRoutesSheet extends StatefulWidget {
  const TransitRoutesSheet({
    super.key,
    required this.routes,
    required this.destinationLabel,
    required this.onCloseAll,
  });

  final TransitRoutes routes;

  /// "OO까지"에 들어갈 도착지 이름. 시트를 열어 둔 채로도 어디로 가는 경로인지
  /// 확인할 수 있어야 한다.
  final String destinationLabel;

  final VoidCallback onCloseAll;

  static Future<TransitItinerary?> show(
    BuildContext context, {
    required TransitRoutes routes,
    required String destinationLabel,
    required VoidCallback onCloseAll,
  }) {
    return showModalBottomSheet<TransitItinerary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: TransitRoutesSheet(
          routes: routes,
          destinationLabel: destinationLabel,
          onCloseAll: onCloseAll,
        ),
      ),
    );
  }

  @override
  State<TransitRoutesSheet> createState() => _TransitRoutesSheetState();
}

class _TransitRoutesSheetState extends State<TransitRoutesSheet> {
  bool _intentionalPop = false;

  void _markIntentional() => _intentionalPop = true;

  void _pick(TransitItinerary itinerary) {
    _markIntentional();
    Navigator.of(context).pop(itinerary);
  }

  @override
  Widget build(BuildContext context) {
    final itineraries = widget.routes.itineraries;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Material(
              color: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetGrabHandle(),
                  SheetHeader(
                    title: '${widget.destinationLabel}까지 대중교통',
                    onCloseAll: widget.onCloseAll,
                    onIntentionalPop: _markIntentional,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: 16 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: itineraries.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 20, endIndent: 20),
                      itemBuilder: (context, index) => _ItineraryTile(
                        itinerary: itineraries[index],
                        // 첫 줄은 정렬상 가장 빠른 경로다. 그 사실을 배지로
                        // 밝히지 않으면 사용자는 순서의 의미를 추측해야 한다.
                        fastest: index == 0 && itineraries.length > 1,
                        onTap: () => _pick(itineraries[index]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItineraryTile extends StatelessWidget {
  const _ItineraryTile({
    required this.itinerary,
    required this.fastest,
    required this.onTap,
  });

  final TransitItinerary itinerary;
  final bool fastest;
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
            _LegStrip(legs: itinerary.legs),
          ],
        ),
      ),
    );
  }
}

/// `도보 5분 › 5호선 › 도보 3분`처럼 구간을 화살표로 잇는 줄.
class _LegStrip extends StatelessWidget {
  const _LegStrip({required this.legs});

  final List<TransitLeg> legs;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < legs.length; i++) {
      if (i > 0) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right,
              size: 14,
              color: AppColors.muted,
            ),
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
