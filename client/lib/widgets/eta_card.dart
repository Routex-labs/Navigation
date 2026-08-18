import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../domain/geo/distance_format.dart';
import '../domain/guidance/route_guidance.dart';

/// 앱의 경로 값을 Runtime Kit의 계획·안내 패턴에 연결한다.
///
/// [guidanceStarted]가 false면 출발 전 계획, true면 하단 진행 정보다. 다음 행동은
/// 지도 위쪽의 [GuidanceBanner]가 맡아 Runtime Kit의 안내 구조를 보존한다.
class EtaCard extends StatelessWidget {
  const EtaCard({
    super.key,
    required this.distanceMeters,
    required this.minutes,
    this.label = '목적지까지',
    this.guidanceStarted = false,
    this.onClose,
    this.onStartGuidance,
    this.onClosePointerDown,
    this.routeOptions,
    this.extraMetric,
  });

  final double distanceMeters;
  final int minutes;
  final String label;
  final bool guidanceStarted;
  final VoidCallback? onClose;
  final VoidCallback? onStartGuidance;
  final ValueChanged<Offset>? onClosePointerDown;

  /// 복수 경로 후보를 고를 수 있을 때 요약 위에 놓는 선택 영역. 출발 전
  /// 계획 카드에서만 쓰인다 — 안내 중에는 경로를 바꿀 수 없다.
  final Widget? routeOptions;

  /// 소요·거리 옆에 하나 더 적을 값(통행료 등). `RoutexEtaCard`가 지표를
  /// 3개까지만 받아 통행료·택시비를 동시에 넣을 자리가 없다 — 부르는
  /// 쪽이 어느 쪽을 보여줄지 미리 고른다.
  final RoutexTripMetric? extraMetric;

  @override
  Widget build(BuildContext context) {
    final arrivalTime = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(minutes: minutes)),
    ).format(context);
    if (!guidanceStarted) {
      return RoutexEtaCard(
        title: label,
        arrivalTime: arrivalTime,
        metrics: [
          RoutexTripMetric(value: '$minutes분', label: '소요'),
          RoutexTripMetric(value: formatDistance(distanceMeters), label: '거리'),
          if (extraMetric != null) extraMetric!,
        ],
        routeOptions: routeOptions,
        onStart: onStartGuidance,
      );
    }

    return Listener(
      onPointerDown: (event) => onClosePointerDown?.call(event.position),
      child: RoutexTripProgress(
        metrics: [
          RoutexTripMetric(value: arrivalTime, label: '도착 예정'),
          RoutexTripMetric(value: '$minutes분', label: '남은 시간'),
          RoutexTripMetric(
            value: formatDistance(distanceMeters),
            label: '남은 거리',
          ),
        ],
        onStop: onClose,
      ),
    );
  }
}

/// 안내 중 다음 행동 또는 자동 재탐색 상태를 지도 위쪽에 표시한다.
class GuidanceBanner extends StatelessWidget {
  const GuidanceBanner({super.key, required this.instruction});

  final RouteGuidanceInstruction instruction;

  @override
  Widget build(BuildContext context) {
    if (instruction.action == RouteGuidanceAction.wrongWay) {
      return const RoutexStatusBanner(
        title: '경로를 벗어났습니다',
        detail: '새 경로를 자동으로 찾고 있습니다',
        icon: RoutexIcons.error,
        tone: RoutexStatusBannerTone.error,
      );
    }
    return RoutexManeuverBanner(
      distance: _distanceLabel(instruction.distanceToActionM),
      detail: instruction.primaryText,
      icon: routeGuidanceIcon(instruction.action),
    );
  }
}

String _distanceLabel(double meters) {
  if (!meters.isFinite || meters < 0) return '';
  if (meters < 10) return '${meters.toStringAsFixed(1)}m';
  return formatDistance(meters);
}

/// 안내 배너와 전체 단계 목록이 같은 행동 글리프를 사용한다.
IconData routeGuidanceIcon(RouteGuidanceAction action) => switch (action) {
  RouteGuidanceAction.wrongWay => RoutexIcons.wrongWay,
  RouteGuidanceAction.turnLeft => RoutexIcons.turnLeft,
  RouteGuidanceAction.turnRight => RoutexIcons.turnRight,
  RouteGuidanceAction.escalator => RoutexIcons.escalator,
  RouteGuidanceAction.elevator => RoutexIcons.elevator,
  RouteGuidanceAction.arrived => RoutexIcons.arrived,
  RouteGuidanceAction.straight => RoutexIcons.straight,
};
