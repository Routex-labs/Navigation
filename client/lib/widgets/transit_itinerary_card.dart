import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../models/route/transit_route.dart';
import 'transit_style.dart';

/// 대중교통 경로 후보 한 장.
///
/// 실시간 도착·혼잡도·기후동행은 그리지 않는다 — 카카오 응답에 없다. 없는 칸은
/// 자리도 남기지 않는다. 근거는
/// `docs/superpowers/specs/2026-08-19-transit-screen-redesign-design.md`.
class TransitItineraryCard extends StatelessWidget {
  const TransitItineraryCard({
    super.key,
    required this.itinerary,
    required this.fastest,
    required this.expanded,
    required this.onExpanded,
    required this.onTap,
    this.selected = false,
  });

  final TransitItinerary itinerary;

  /// 목록 첫 줄인지. 맞으면 `최적` 배지를 단다 — 정렬의 뜻을 밝히지 않으면
  /// 사용자가 첫 줄이 왜 첫 줄인지 추측해야 한다.
  final bool fastest;

  /// 상세보기가 펼쳐져 있는지. **상태는 목록이 들고 있다** — 카드마다 두면
  /// 여러 줄이 동시에 펼쳐져 목록이 화면 밖으로 밀린다.
  final bool expanded;

  final ValueChanged<bool> onExpanded;
  final VoidCallback onTap;
  final bool selected;

  /// 탈것 구간만. 승·하차 줄과 노선 배지가 읽는 값이다.
  List<TransitLeg> get _rides => [
    for (final leg in itinerary.legs)
      if (!leg.mode.isWalk) leg,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final fare = itinerary.fare;
    final rides = _rides;
    final arrival = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(seconds: itinerary.totalTimeSeconds)),
    ).format(context);

    return Material(
      color: selected ? colors.actionPrimarySubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(RoutexSpacing.contentGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fastest) ...[
                const RoutexBadge(label: '최적', tone: RoutexBadgeTone.info),
                const SizedBox(height: RoutexSpacing.inlineGap),
              ],
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RoutexSpacing.controlGap,
                runSpacing: RoutexSpacing.inlineGap,
                children: [
                  Text(
                    formatTransitDuration(itinerary.totalTimeSeconds),
                    style: RoutexTypography.tabular(RoutexTypography.headline),
                  ),
                  Text(
                    '$arrival 도착',
                    style: RoutexTypography.bodySmall.copyWith(
                      color: colors.contentSecondary,
                    ),
                  ),
                  if (fare != null && fare > 0)
                    Text(
                      formatTransitFare(fare),
                      style: RoutexTypography.bodySmall.copyWith(
                        color: colors.contentSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: RoutexSpacing.contentGap),
              _LegBar(itinerary: itinerary),
              if (rides.isNotEmpty) ...[
                const SizedBox(height: RoutexSpacing.contentGap),
                for (final ride in rides) _RideRow(leg: ride),
                if (rides.last.endName case final drop?) ...[
                  const SizedBox(height: RoutexSpacing.inlineGap),
                  _LabeledRow(label: '하차', value: drop),
                ],
              ],
              const SizedBox(height: RoutexSpacing.inlineGap),
              RoutexDisclosure(
                header: const Text('상세보기', style: RoutexTypography.bodySmall),
                expanded: expanded,
                onExpanded: onExpanded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final leg in itinerary.legs) _StepRow(leg: leg),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 구간을 소요 시간 비율대로 이은 막대.
///
/// 총 소요가 0이면 그리지 않는다 — 비율을 낼 수 없다. 짧은 구간이 사라지지
/// 않도록 [Expanded]의 flex를 최소 1로 올린다. 비율이 그만큼 거짓이 되지만,
/// 1픽셀짜리 칸은 있으나 마나다.
class _LegBar extends StatelessWidget {
  const _LegBar({required this.itinerary});

  final TransitItinerary itinerary;

  @override
  Widget build(BuildContext context) {
    final total = itinerary.totalTimeSeconds;
    if (total <= 0 || itinerary.legs.isEmpty) return const SizedBox.shrink();
    final colors = context.routexColors;

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          for (final leg in itinerary.legs)
            Expanded(
              flex: (leg.sectionTimeSeconds * 100 / total).round().clamp(1, 100),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: leg.mode.isWalk
                        ? colors.contentSecondary.withValues(alpha: 0.25)
                        : transitLegColor(leg),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      formatTransitDuration(leg.sectionTimeSeconds),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: RoutexTypography.caption.copyWith(
                        color: leg.mode.isWalk
                            ? colors.contentSecondary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 탈것 한 줄 — 수단 배지 + 승차 정류장 + 노선 번호 + 정류장 수.
class _RideRow extends StatelessWidget {
  const _RideRow({required this.leg});

  final TransitLeg leg;

  /// `간선:472`의 앞머리. 카카오는 접두사를 안 주므로 수단 이름으로 떨어진다.
  String get _kind {
    final route = leg.routeName;
    if (route == null) return leg.modeLabel;
    final colon = route.indexOf(':');
    if (colon <= 0) return leg.modeLabel;
    return route.substring(0, colon);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final color = transitLegColor(leg);

    return Padding(
      padding: const EdgeInsets.only(bottom: RoutexSpacing.inlineGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoutexBadge(
            label: _kind,
            icon: transitModeIcon(leg.mode),
            accent: RoutexBadgeAccent(
              surface: color.withValues(alpha: 0.14),
              ink: color,
            ),
          ),
          const SizedBox(width: RoutexSpacing.controlGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leg.startName case final board?)
                  Text(board, style: RoutexTypography.body),
                const SizedBox(height: RoutexSpacing.inlineGap),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: RoutexSpacing.controlGap,
                  children: [
                    Text(
                      leg.shortLabel,
                      style: RoutexTypography.tabular(
                        RoutexTypography.body,
                      ).copyWith(color: color),
                    ),
                    if (leg.stationCount > 0)
                      Text(
                        '${leg.stationCount}정류장',
                        style: RoutexTypography.bodySmall.copyWith(
                          color: colors.contentSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Row(
      children: [
        Text(
          label,
          style: RoutexTypography.bodySmall.copyWith(
            color: colors.contentSecondary,
          ),
        ),
        const SizedBox(width: RoutexSpacing.controlGap),
        Expanded(child: Text(value, style: RoutexTypography.body)),
      ],
    );
  }
}

/// 상세보기 안의 구간 한 줄. 도보까지 전부 적는다.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.leg});

  final TransitLeg leg;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final where = leg.startName;
    return Padding(
      padding: const EdgeInsets.only(bottom: RoutexSpacing.inlineGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            transitModeIcon(leg.mode),
            size: RoutexMetrics.iconSmall,
            color: leg.mode.isWalk
                ? colors.contentSecondary
                : transitLegColor(leg),
          ),
          const SizedBox(width: RoutexSpacing.controlGap),
          Expanded(
            child: Text(
              leg.mode.isWalk
                  ? '도보 ${formatTransitDuration(leg.sectionTimeSeconds)}'
                  : '${leg.shortLabel} · ${formatTransitDuration(leg.sectionTimeSeconds)}'
                        '${where == null ? '' : ' · $where 승차'}',
              style: RoutexTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
