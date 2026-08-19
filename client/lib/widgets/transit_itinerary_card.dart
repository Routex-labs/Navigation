import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../map/style/route_style.dart';
import '../models/route/transit_route.dart';
import 'transit_style.dart';

/// 대중교통 경로 후보 한 장. 배지 박스 없이 색과 글자로만 나눈다.
///
/// 실시간 도착·혼잡도·기후동행은 카카오 응답에 없어 그리지 않는다. 모양의 근거는
/// `docs/superpowers/specs/2026-08-19-route-alternatives-and-guidance-design.md` D절.

/// 지도 본선과 같은 파랑. DS의 `actionPrimary`는 teal이라 여기 쓰면 초록이 된다.
final _accent = Color(
  0xFF000000 | int.parse(kRouteLineColor.substring(1), radix: 16),
);

class TransitItineraryCard extends StatelessWidget {
  const TransitItineraryCard({
    super.key,
    required this.itinerary,
    required this.fastest,
    required this.onTap,
    this.selected = false,
  });

  final TransitItinerary itinerary;

  /// 목록 첫 줄인지. 맞으면 `최적`을 적는다 — 정렬의 뜻을 밝히지 않으면
  /// 사용자가 첫 줄이 왜 첫 줄인지 추측해야 한다.
  final bool fastest;

  /// 카드를 누르면 상세 경로 화면이 열린다. 카드 한 장이 통째로 그 손잡이라
  /// 접기 화살표 같은 별도 버튼은 두지 않는다.
  final VoidCallback onTap;
  final bool selected;

  /// 탈것 구간만. 노선 줄과 하차 줄이 읽는 값이다.
  List<TransitLeg> get _rides => [
    for (final leg in itinerary.legs)
      if (!leg.mode.isWalk) leg,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final fare = itinerary.fare;
    final rides = _rides;

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
              if (fastest)
                Text(
                  '최적',
                  style: RoutexTypography.bodySmall.copyWith(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Row(
                children: [
                  Text(
                    formatTransitDuration(itinerary.totalTimeSeconds),
                    style: RoutexTypography.tabular(RoutexTypography.headline),
                  ),
                  // 요금이 없으면 구분선도 함께 뺀다 — 안 그러면 헤더가
                  // `19분 │`로 끝난다. 짧은 버스는 실제로 null로 온다.
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
              const SizedBox(height: RoutexSpacing.contentGap),
              _LegBar(itinerary: itinerary),
              if (rides.isNotEmpty) ...[
                const SizedBox(height: RoutexSpacing.contentGap),
                for (final ride in rides) _RideRow(leg: ride),
                if (rides.last.endName case final drop?) _DropRow(name: drop),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 구간을 소요 시간 비율대로 이은 막대. 연한 트랙 하나 위에 탈것만 색 pill이다.
///
/// 총 소요가 0이면 그리지 않는다 — 비율을 낼 수 없다. 짧은 구간이 사라지지
/// 않도록 [Expanded]의 flex를 최소 1로 올린다. 비율이 그만큼 거짓이 되지만,
/// 1픽셀짜리 칸은 있으나 마나다.
class _LegBar extends StatelessWidget {
  const _LegBar({required this.itinerary});

  final TransitItinerary itinerary;

  /// 트랙 높이. caption 글리프 12 px가 상하 2 px씩 남기고 들어가는 최소치다.
  static const _height = 16.0;

  @override
  Widget build(BuildContext context) {
    final total = itinerary.totalTimeSeconds;
    if (total <= 0 || itinerary.legs.isEmpty) return const SizedBox.shrink();
    final colors = context.routexColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.borderSubtle,
        borderRadius: BorderRadius.circular(_height / 2),
      ),
      child: SizedBox(
        height: _height,
        child: Row(
          children: [
            for (final leg in itinerary.legs)
              Expanded(
                flex: (leg.sectionTimeSeconds * 100 / total).round().clamp(
                  1,
                  100,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: leg.mode.isWalk
                      ? Center(
                          child: _BarLabel(
                            text: formatTransitDuration(leg.sectionTimeSeconds),
                            color: colors.contentSecondary,
                          ),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: transitLegColor(leg),
                            borderRadius: BorderRadius.circular(_height / 2),
                          ),
                          child: Center(
                            child: _BarLabel(
                              icon: transitModeIcon(leg.mode),
                              text: formatTransitDuration(
                                leg.sectionTimeSeconds,
                              ),
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 막대 한 칸의 아이콘 + 소요 시간. **좁으면 글자를, 더 좁으면 전부 뺀다.**
///
/// 자르지 않는 이유는 실기기에서 "3분"이 "3"으로 잘려 정류장 수로 읽혔기
/// 때문이다. 잘린 숫자는 정보가 아니라 오독이다.
class _BarLabel extends StatelessWidget {
  const _BarLabel({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  static const _iconSize = 11.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    // caption은 `height: 1.5`라 라인박스가 18 px다. 트랙이 16 px이므로 1.0으로
    // 눌러야 들어간다 — 안 누르면 감춰지는 게 아니라 오버플로가 난다.
    final style = RoutexTypography.caption.copyWith(color: color, height: 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final iconWidth = icon == null ? 0.0 : _iconSize + _gap;
        if (painter.width + iconWidth <= constraints.maxWidth) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: _iconSize, color: color),
                const SizedBox(width: _gap),
              ],
              Text(text, maxLines: 1, style: style),
            ],
          );
        }
        if (icon != null && _iconSize <= constraints.maxWidth) {
          return Icon(icon, size: _iconSize, color: color);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// 탈것 한 줄 — 수단 아이콘 + 색 노선번호(왼쪽) + 승차 정류장명(오른쪽).
///
/// 긴 정류장명은 말줄임하고 **노선번호는 자르지 않는다** — 잘린 번호는 다른
/// 노선으로 읽힌다.
class _RideRow extends StatelessWidget {
  const _RideRow({required this.leg});

  final TransitLeg leg;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final color = transitLegColor(leg);

    return Padding(
      padding: const EdgeInsets.only(bottom: RoutexSpacing.inlineGap),
      child: Row(
        children: [
          Icon(
            transitModeIcon(leg.mode),
            size: RoutexMetrics.iconSmall,
            color: color,
          ),
          const SizedBox(width: RoutexSpacing.inlineGap),
          Text(
            leg.shortLabel,
            style: RoutexTypography.tabular(
              RoutexTypography.body,
            ).copyWith(color: color),
          ),
          if (leg.startName case final board?) ...[
            const SizedBox(width: RoutexSpacing.controlGap),
            Expanded(
              child: Text(
                board,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RoutexTypography.bodySmall.copyWith(
                  color: colors.contentSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `○ 하차 <이름>` 한 줄.
class _DropRow extends StatelessWidget {
  const _DropRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Row(
      children: [
        Icon(
          Icons.circle_outlined,
          size: RoutexMetrics.iconSmall,
          color: colors.contentSecondary,
        ),
        const SizedBox(width: RoutexSpacing.inlineGap),
        Text(
          '하차',
          style: RoutexTypography.bodySmall.copyWith(
            color: colors.contentSecondary,
          ),
        ),
        const SizedBox(width: RoutexSpacing.controlGap),
        Expanded(child: Text(name, style: RoutexTypography.body)),
      ],
    );
  }
}
