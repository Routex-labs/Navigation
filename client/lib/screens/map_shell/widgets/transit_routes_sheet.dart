import 'package:flutter/material.dart';

import '../../../models/transit_route.dart';
import '../../../widgets/map_overlay_guard.dart';
import '../../../widgets/sheet_grab_handle.dart';
import '../../../widgets/sheet_header.dart';
import '../../../widgets/transit_itinerary_tile.dart';

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
                      itemBuilder: (context, index) => TransitItineraryTile(
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
