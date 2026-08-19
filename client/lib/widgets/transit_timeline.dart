/// 대중교통 경로의 **구간별 세부 설명** — 아이콘 열 + 본문 + 시작 시각.
///
/// 상세 화면과 하단 요약 카드의 펼침이 같은 그림을 써야 해서 여기 둔다.
/// 실시간 도착·혼잡도·정류장 번호는 응답에 없어 자리도 두지 않는다. 근거는
/// `docs/superpowers/specs/2026-08-19-route-alternatives-and-guidance-design.md` F절.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../domain/geo/distance_format.dart';
import '../models/route/transit_route.dart';
import 'transit_style.dart';

/// 출발부터 도착까지 구간을 세로로 늘어놓는다.
///
/// 시각은 [departureAt]에 앞 구간 소요를 누적해 적는다. 지나는 정류장의 펼침
/// 상태는 이 위젯이 스스로 들고 있다 — 30개짜리 구간이 둘이면 접힌 채로
/// 시작해야 화면 안에 흐름이 들어온다.
class TransitTimeline extends StatefulWidget {
  const TransitTimeline({
    super.key,
    required this.itinerary,
    required this.destinationLabel,
    required this.departureAt,
  });

  final TransitItinerary itinerary;

  /// 마지막 칸에 적을 도착지 이름.
  final String destinationLabel;

  final DateTime departureAt;

  @override
  State<TransitTimeline> createState() => _TransitTimelineState();
}

class _TransitTimelineState extends State<TransitTimeline> {
  /// 정류장 목록을 펼쳐 둔 구간의 인덱스.
  final _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final legs = widget.itinerary.legs;
    final nodes = <Widget>[];
    var elapsed = 0;

    for (var index = 0; index < legs.length; index++) {
      final leg = legs[index];
      nodes.add(
        _TimelineNode(
          icon: transitModeIcon(leg.mode),
          iconColor: leg.mode.isWalk
              ? colors.contentSecondary
              : transitLegColor(leg),
          time: widget.departureAt.add(Duration(seconds: elapsed)),
          last: false,
          child: leg.mode.isWalk
              ? _WalkBody(leg: leg)
              : _RideBody(
                  leg: leg,
                  expanded: _expanded.contains(index),
                  onExpanded: (value) => setState(() {
                    if (value) {
                      _expanded.add(index);
                    } else {
                      _expanded.remove(index);
                    }
                  }),
                ),
        ),
      );
      elapsed += leg.sectionTimeSeconds;
    }

    nodes.add(
      _TimelineNode(
        icon: RoutexIcons.arrived,
        iconColor: colors.contentPrimary,
        // 구간 시간의 합이 아니라 총 소요로 잡는다. 카카오는 첫 승차 전과 마지막
        // 하차 뒤의 도보를 구간으로 주지 않고 총계에만 넣는다.
        time: transitArrivalTime(widget.departureAt, widget.itinerary),
        last: true,
        child: Text(
          widget.destinationLabel,
          style: RoutexTypography.bodyStrong,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes,
    );
  }
}

/// 타임라인 한 칸 — 아이콘 열 + 본문 + 시작 시각.
///
/// 아이콘 아래 짧은 선은 `RoutexStepList`와 같은 모양이다. 본문 높이만큼
/// 늘이지 않는 이유는 그러려면 행마다 intrinsic 측정이 필요한데, 이 화면은
/// 정류장 30개를 펼칠 수 있어서 그 비용이 스크롤에 그대로 얹히기 때문이다.
class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.icon,
    required this.iconColor,
    required this.time,
    required this.last,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final DateTime? time;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: RoutexMetrics.iconLarge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: RoutexMetrics.iconMedium, color: iconColor),
              if (!last)
                Padding(
                  padding: const EdgeInsets.only(top: RoutexSpacing.inlineGap),
                  child: SizedBox(
                    width: RoutexStroke.emphasis,
                    height: RoutexSpacing.componentPadding,
                    child: ColoredBox(color: iconColor),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: RoutexSpacing.contentGap),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: last ? 0 : RoutexSpacing.componentPadding,
            ),
            child: child,
          ),
        ),
        if (time case final time?) ...[
          const SizedBox(width: RoutexSpacing.controlGap),
          Text(
            formatTransitClockTime(time),
            style: RoutexTypography.tabular(
              RoutexTypography.caption,
            ).copyWith(color: colors.contentSecondary),
          ),
        ],
      ],
    );
  }
}

/// `도보 5분` + 거리.
class _WalkBody extends StatelessWidget {
  const _WalkBody({required this.leg});

  final TransitLeg leg;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final distance = leg.distanceMeters > 0
        ? formatDistance(leg.distanceMeters)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '도보 ${formatTransitDuration(leg.sectionTimeSeconds)}',
          style: RoutexTypography.bodyStrong,
        ),
        if (distance.isNotEmpty)
          Text(
            distance,
            style: RoutexTypography.bodySmall.copyWith(
              color: colors.contentSecondary,
            ),
          ),
      ],
    );
  }
}

/// 승차 정류장 → 노선 칩 → 정류장 수(펼치면 지나는 정류장) → 하차 정류장.
class _RideBody extends StatelessWidget {
  const _RideBody({
    required this.leg,
    required this.expanded,
    required this.onExpanded,
  });

  final TransitLeg leg;
  final bool expanded;
  final ValueChanged<bool> onExpanded;

  /// 승차·하차를 뺀 중간 정류장. 둘은 위아래 줄에 이미 이름이 있다.
  List<String> get _middle => leg.stopNames.length <= 2
      ? const []
      : leg.stopNames.sublist(1, leg.stopNames.length - 1);

  /// 칩에 적을 노선들. `vehicles`가 비면(TMAP 경로) 노선명 하나로 대신하고,
  /// 그것도 없으면 빈 목록이다 — 빈 칩 자리를 남기지 않는다.
  List<String> get _labels {
    if (leg.vehicles.isNotEmpty) {
      return [
        for (final vehicle in leg.vehicles)
          vehicle.type == null
              ? vehicle.name
              : '${vehicle.type} ${vehicle.name}',
      ];
    }
    return leg.routeName == null ? const [] : [leg.shortLabel];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final color = transitLegColor(leg);
    // 알약 색은 목록 카드·지도와 같은 배합을 써야 같은 노선으로 읽힌다.
    final accent = routexTransitLeg(leg).accent;
    final labels = _labels;
    final middle = _middle;
    final stations = leg.stationCount > 0
        ? Text(
            '${leg.stationCount}개 정류장 이동',
            style: RoutexTypography.bodySmall.copyWith(
              color: colors.contentSecondary,
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          leg.startName ?? leg.modeLabel,
          style: RoutexTypography.bodyStrong,
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: RoutexSpacing.controlGap),
          Wrap(
            spacing: RoutexSpacing.inlineGap,
            runSpacing: RoutexSpacing.inlineGap,
            children: [
              for (final label in labels)
                RoutexBadge(label: label, accent: accent),
            ],
          ),
        ],
        if (stations != null) ...[
          const SizedBox(height: RoutexSpacing.controlGap),
          if (middle.isEmpty)
            stations
          else
            RoutexDisclosure(
              header: stations,
              expanded: expanded,
              onExpanded: onExpanded,
              child: Padding(
                padding: const EdgeInsets.only(top: RoutexSpacing.inlineGap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final stop in middle)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: RoutexSpacing.inlineGap,
                        ),
                        child: Text(
                          stop,
                          style: RoutexTypography.bodySmall.copyWith(
                            color: colors.contentSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (leg.endName case final drop?) ...[
          const SizedBox(height: RoutexSpacing.controlGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.circle_outlined,
                size: RoutexMetrics.iconSmall,
                color: color,
              ),
              const SizedBox(width: RoutexSpacing.inlineGap),
              Expanded(child: Text(drop, style: RoutexTypography.body)),
            ],
          ),
        ],
      ],
    );
  }
}
