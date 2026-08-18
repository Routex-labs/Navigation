import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../domain/geo/distance_format.dart';
import '../models/route/directions_route.dart';
import 'transit_style.dart' show formatTransitDuration;

/// 자동차 경로 후보 목록. 좌표열이 겹치는 후보를 이미 합친
/// [DirectionsRouteOption] 리스트를 그대로 받아 한 줄씩 그린다.
///
/// 옵션이 1개면 아무것도 그리지 않는다 — 고를 게 없는데 카드만 하나
/// 있으면 "이게 왜 있지" 하는 UI가 된다.
class DirectionsRouteOptionsPanel extends StatelessWidget {
  const DirectionsRouteOptionsPanel({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<DirectionsRouteOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (options.length < 2) return const SizedBox.shrink();
    return RoutexStack(
      gap: RoutexStackGap.inline,
      children: [
        for (var i = 0; i < options.length; i++)
          RoutexRouteOption(
            title: options[i].kinds.map((kind) => kind.label).join(' · '),
            detail: formatDistance(options[i].route.distanceMeters),
            meta: formatTransitDuration(options[i].route.durationSeconds),
            selected: i == selectedIndex,
            onPressed: () => onSelect(i),
          ),
      ],
    );
  }
}
