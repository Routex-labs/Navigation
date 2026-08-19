/// 대중교통 경로 하나를 자세히 보는 시트. 목록 시트 **위에** 쌓인다.
///
/// 여기서는 아무것도 확정되지 않는다 — 지도를 바꾸는 것은 `안내 시작`뿐이다.
/// 실시간 도착·혼잡도·정류장 번호는 응답에 없어 자리도 두지 않는다. 근거는
/// `docs/superpowers/specs/2026-08-19-route-alternatives-and-guidance-design.md` 4단계 F절.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../domain/geo/distance_format.dart';
import '../../../../models/route/transit_route.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/transit_style.dart';

/// 고른 경로 한 가지의 상세. **보는 화면이지 고르는 화면이 아니다.**
///
/// 뒤로 닫으면 목록이 그대로 남아 다른 경로를 눌러 볼 수 있어야 하므로,
/// 목록 시트를 대체하지 않고 그 위에 모달로 한 겹 쌓는다.
class TransitRouteDetailSheet extends StatefulWidget {
  const TransitRouteDetailSheet({
    super.key,
    required this.itinerary,
    required this.destinationLabel,
    this.departureAt,
  });

  final TransitItinerary itinerary;

  /// 헤더와 마지막 타임라인 칸에 적을 도착지 이름.
  final String destinationLabel;

  /// 지금 출발한다고 볼 시각. 구간 시작 시각과 도착 예정 시각의 기준이며,
  /// null이면 화면을 그리는 순간이다(테스트만 값을 넘긴다).
  final DateTime? departureAt;

  /// 목록 시트 위에 상세를 띄운다.
  ///
  /// `안내 시작`을 눌렀을 때만 **true**를 돌려주고, 뒤로·바깥 탭으로 닫으면
  /// null이다. 상세는 보는 화면이라 열고 닫는 것만으로는 지도에 아무 일도
  /// 일어나지 않는다 — 배선하는 쪽은 true일 때만 경로를 확정한다.
  static Future<bool?> show(
    BuildContext context, {
    required TransitItinerary itinerary,
    required String destinationLabel,
    DateTime? departureAt,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: TransitRouteDetailSheet(
          itinerary: itinerary,
          destinationLabel: destinationLabel,
          departureAt: departureAt,
        ),
      ),
    );
  }

  @override
  State<TransitRouteDetailSheet> createState() =>
      _TransitRouteDetailSheetState();
}

class _TransitRouteDetailSheetState extends State<TransitRouteDetailSheet> {
  /// 정류장 목록을 펼쳐 둔 구간의 인덱스. 20개짜리 구간이 둘이면 접힌 채로
  /// 시작해야 화면 안에 흐름이 들어온다.
  final _expanded = <int>{};

  /// 화면을 다시 그려도 시각이 흔들리지 않게 한 번만 읽는다.
  late final DateTime _departure = widget.departureAt ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final itinerary = widget.itinerary;
    final total = itinerary.totalTimeSeconds;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: RoutexBottomSheet(
        // 표면은 Runtime Kit이, 여백은 조각마다 다르므로 본문이 갖는다.
        contentInset: RoutexBottomSheetContentInset.content,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RoutexSheetHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RoutexSpacing.contentGap,
              ),
              child: RoutexSheetHeader(
                title: '${widget.destinationLabel}까지',
                // 뒤로는 이 시트만 닫는다. 목록이 그대로 남아 다른 경로를
                // 눌러 보는 것이 이 화면의 존재 이유다.
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            _Summary(itinerary: itinerary, arrival: _arrival(total)),
            const RoutexDivider(role: RoutexDividerRole.section),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: RoutexSpacing.componentPadding,
                  vertical: RoutexSpacing.contentGap,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _timeline(context),
                ),
              ),
            ),
            const RoutexDivider(role: RoutexDividerRole.section),
            Padding(
              padding: EdgeInsets.fromLTRB(
                RoutexSpacing.componentPadding,
                RoutexSpacing.contentGap,
                RoutexSpacing.componentPadding,
                RoutexSpacing.contentGap + MediaQuery.paddingOf(context).bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: RoutexButton(
                  label: '안내 시작',
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 총 소요를 모르면(0) 도착 시각도 모른다. 지금 시각을 도착이라고 적으면
  /// 사용자는 그것을 "다 왔다"로 읽는다.
  DateTime? _arrival(int totalSeconds) => totalSeconds <= 0
      ? null
      : _departure.add(Duration(seconds: totalSeconds));

  List<Widget> _timeline(BuildContext context) {
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
          time: _departure.add(Duration(seconds: elapsed)),
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
        time: _arrival(widget.itinerary.totalTimeSeconds),
        last: true,
        child: Text(
          widget.destinationLabel,
          style: RoutexTypography.bodyStrong,
        ),
      ),
    );
    return nodes;
  }
}

/// 총 소요 · 요금 · 도착 예정 시각.
class _Summary extends StatelessWidget {
  const _Summary({required this.itinerary, required this.arrival});

  final TransitItinerary itinerary;
  final DateTime? arrival;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final fare = itinerary.fare;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RoutexSpacing.componentPadding,
        RoutexSpacing.controlGap,
        RoutexSpacing.componentPadding,
        RoutexSpacing.contentGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                formatTransitDuration(itinerary.totalTimeSeconds),
                style: RoutexTypography.tabular(RoutexTypography.headline),
              ),
              // 요금이 없으면 구분선도 함께 뺀다 — 안 그러면 `19분 │`로 끝난다.
              if (fare != null && fare > 0) ...[
                Container(
                  width: 1,
                  height: 12,
                  margin: const EdgeInsets.symmetric(
                    horizontal: RoutexSpacing.controlGap,
                  ),
                  color: colors.borderStrong,
                ),
                Text(
                  formatTransitFare(fare),
                  style: RoutexTypography.bodySmall.copyWith(
                    color: colors.contentSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (arrival case final arrival?) ...[
            const SizedBox(height: RoutexSpacing.inlineGap),
            Text(
              '${_formatClockTime(arrival)} 도착',
              style: RoutexTypography.bodySmall.copyWith(
                color: colors.contentSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 타임라인 한 칸 — 아이콘 열 + 본문 + 시작 시각.
///
/// 아이콘 아래 짧은 선은 `RoutexStepList`와 같은 모양이다. 본문 높이만큼
/// 늘이지 않는 이유는 그러려면 행마다 intrinsic 측정이 필요한데, 이 시트는
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
            _formatClockTime(time),
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

/// `오후 3:25`. intl 의존 없이 적는다. 다른 화면도 쓰게 되면 `domain/`으로 내린다.
String _formatClockTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '${time.hour < 12 ? '오전' : '오후'} $hour:'
      '${time.minute.toString().padLeft(2, '0')}';
}
