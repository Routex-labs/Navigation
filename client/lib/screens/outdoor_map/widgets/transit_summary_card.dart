import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../models/route/transit_route.dart';
import '../../../widgets/transit_style.dart';

/// 선택한 대중교통 경로를 Runtime Kit의 계획·진행 패턴에 연결한다.
class TransitSummaryCard extends StatelessWidget {
  const TransitSummaryCard({
    super.key,
    required this.itinerary,
    required this.label,
    required this.onClose,
    this.onStartGuidance,
    this.onClosePointerDown,
  });

  final TransitItinerary itinerary;
  final String label;
  final VoidCallback onClose;
  final VoidCallback? onStartGuidance;
  final ValueChanged<Offset>? onClosePointerDown;

  @override
  Widget build(BuildContext context) {
    final duration = formatTransitDuration(itinerary.totalTimeSeconds);
    final arrivalTime = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(seconds: itinerary.totalTimeSeconds)),
    ).format(context);
    final itineraryView = _itineraryView();
    final start = onStartGuidance;
    final child = start == null
        ? RoutexBottomSheet(
            showHandle: false,
            child: RoutexStack(
              gap: RoutexStackGap.content,
              children: [
                itineraryView,
                RoutexButton(
                  label: '안내 종료',
                  variant: RoutexButtonVariant.secondary,
                  onPressed: onClose,
                ),
              ],
            ),
          )
        : RoutexEtaCard(
            title: label,
            arrivalTime: arrivalTime,
            metrics: [
              RoutexTripMetric(value: duration, label: '소요'),
              RoutexTripMetric(
                value: itinerary.transferCount == 0
                    ? '없음'
                    : '${itinerary.transferCount}회',
                label: '환승',
              ),
            ],
            routeOptions: itineraryView,
            onStart: start,
          );
    return Listener(
      onPointerDown: (event) => onClosePointerDown?.call(event.position),
      child: child,
    );
  }

  RoutexTransitItinerary _itineraryView() {
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
      selected: true,
      onPressed: () {},
    );
  }
}
