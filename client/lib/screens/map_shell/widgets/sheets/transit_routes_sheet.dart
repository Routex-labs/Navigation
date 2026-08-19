import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../models/route/transit_route.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/sheet_header.dart';
import '../../../../domain/route/transit_itinerary_filter.dart';
import '../../../../widgets/transit_itinerary_card.dart';

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

  /// 지금 고른 갈래. **목록만 좁힌다** — 지도에 그려진 경로는 건드리지 않는다.
  /// 필터는 보는 범위를 줄이는 것이지 선택을 바꾸는 것이 아니다.
  TransitFilter _filter = TransitFilter.all;

  /// **접어 둔** 줄. 기본은 전부 펼침이다 — 카드가 접히면 소요와 요금만 남아
  /// 후보를 견줄 수가 없다. 접기는 긴 목록에서 눈에 걸리는 줄을 치우는 손잡이다.
  ///
  /// 펼침이 아니라 접힘을 세는 이유: 기본값이 "빈 집합 = 전부 펼침"이라 목록이
  /// 바뀌어도 초기화 규칙이 필요 없다.
  final Set<int> _collapsed = <int>{};

  void _markIntentional() => _intentionalPop = true;

  void _pick(TransitItinerary itinerary) {
    _markIntentional();
    Navigator.of(context).pop(itinerary);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.routes.itineraries;
    final filters = availableTransitFilters(all);
    // 목록이 바뀌어 고른 갈래가 사라졌으면 전체로 되돌린다. 그러지 않으면 아무
    // 탭도 안 눌린 채 빈 목록만 남는다.
    final filter = filters.contains(_filter) ? _filter : TransitFilter.all;
    final itineraries = applyTransitFilter(all, filter);
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
            child: RoutexBottomSheet(
              // 표면은 Runtime Kit이, 드래그와 라우트는 앱이 갖는다. 여백은 조각마다
              // 달라서 본문이 소유한다.
              contentInset: RoutexBottomSheetContentInset.content,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RoutexSheetHandle(),
                  SheetHeader(
                    title: '${widget.destinationLabel}까지 대중교통',
                    onCloseAll: widget.onCloseAll,
                    onIntentionalPop: _markIntentional,
                  ),
                  const RoutexDivider(role: RoutexDividerRole.section),
                  RoutexTabs(
                    // '전체'에는 숫자를 안 붙인다. 전부라는 말 자체가 개수보다
                    // 먼저 읽히고, 나머지 탭의 숫자와 뜻이 겹친다.
                    labels: [
                      for (final item in filters)
                        item == TransitFilter.all
                            ? item.label
                            : '${item.label} ${transitFilterCount(all, item)}',
                    ],
                    selectedIndex: filters.indexOf(filter),
                    onSelected: (index) => setState(() {
                      _filter = filters[index];
                      // 갈래를 바꾸면 같은 인덱스가 다른 경로를 가리킨다. 접힘을
                      // 그대로 두면 엉뚱한 줄이 접힌 채로 뜬다.
                      _collapsed.clear();
                    }),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: 16 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: itineraries.length,
                      separatorBuilder: (_, _) =>
                          const RoutexDivider(role: RoutexDividerRole.row),
                      itemBuilder: (context, index) => TransitItineraryCard(
                        itinerary: itineraries[index],
                        // 첫 줄은 정렬상 가장 빠른 경로다. 그 사실을 배지로
                        // 밝히지 않으면 사용자는 순서의 의미를 추측해야 한다.
                        fastest: index == 0 && itineraries.length > 1,
                        expanded: !_collapsed.contains(index),
                        onExpanded: (open) => setState(
                          () => open
                              ? _collapsed.remove(index)
                              : _collapsed.add(index),
                        ),
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
