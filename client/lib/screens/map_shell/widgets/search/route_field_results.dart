import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../domain/route/dijkstra.dart';
import '../../../../domain/search/store_suggestions.dart';
import '../../../../domain/store/nearest_store.dart';
import '../../../../domain/store/reach_label.dart';
import '../../../../models/route/directions_candidate.dart';
import '../../../../models/route/route_plan_mode.dart';
import '../../../../service_locator.dart';

/// 출발지·도착지를 고르는 후보를 Runtime Kit 목록 패턴으로 표시한다.
///
/// 후보 생성·거리 계산·최근 기록은 앱이 소유하고, 행의 위계와 로딩 표현은
/// `RoutexResultList`와 `RoutexListCell`이 소유한다.
class RouteFieldResults extends StatelessWidget {
  const RouteFieldResults({
    super.key,
    required this.field,
    required this.results,
    required this.searching,
    required this.onPicked,
    required this.onPickOnMap,
    required this.showPickOnMap,
    required this.onCurrentLocation,
    this.suggestions = const [],
    this.onSuggestionPicked,
    this.reachByNodeId,
  });

  final RoutePlanField field;
  final List<DirectionsCandidate> results;
  final bool searching;
  final ValueChanged<DirectionsCandidate> onPicked;
  final VoidCallback onPickOnMap;
  final bool showPickOnMap;
  final VoidCallback onCurrentLocation;
  final List<StoreSuggestion> suggestions;
  final ValueChanged<StoreSuggestion>? onSuggestionPicked;
  final Map<String, NodeReach>? reachByNodeId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recentRoutePointsController,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final isOrigin = field == RoutePlanField.origin;
    final hasShortcut = showPickOnMap || isOrigin;
    final showSuggestions =
        suggestions.isNotEmpty && onSuggestionPicked != null;
    final recents = results.isEmpty && !searching && !showSuggestions
        ? recentRoutePointsController.points
        : const <DirectionsCandidate>[];
    if (!hasShortcut &&
        results.isEmpty &&
        !searching &&
        !showSuggestions &&
        recents.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasResults = results.isNotEmpty || searching;
    return RoutexSurface(
      role: RoutexSurfaceRole.chrome,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showPickOnMap)
            RoutexListCell(
              key: const Key('route-field-pick-on-map'),
              title: '지도에서 선택',
              subtitle: isOrigin
                  ? '지도에서 매장을 눌러 출발지로 지정합니다'
                  : '지도에서 매장을 눌러 도착지로 지정합니다',
              leadingIcon: RoutexIcons.placeLocation,
              trailingIcon: RoutexIcons.forward,
              onPressed: onPickOnMap,
            ),
          if (isOrigin)
            RoutexListCell(
              key: const Key('route-field-current-location'),
              title: '현재 위치',
              leadingIcon: RoutexIcons.currentLocation,
              onPressed: onCurrentLocation,
            ),
          if (hasShortcut &&
              (recents.isNotEmpty || showSuggestions || hasResults))
            const RoutexDivider(role: RoutexDividerRole.section),
          if (recents.isNotEmpty) ...[
            RoutexSectionHeader(
              title: '최근 출발지 · 목적지',
              actionLabel: '전체 삭제',
              onAction: recentRoutePointsController.clear,
            ),
            for (final point in recents)
              RoutexListCell(
                key: Key('route-field-recent-${point.dedupeKey}'),
                title: point.title,
                subtitle: point.subtitle.isEmpty ? null : point.subtitle,
                leadingIcon: RoutexIcons.recent,
                leadingIconTone: RoutexListIconTone.quiet,
                trailingActionLabel: '${point.title} 삭제',
                trailingActionIcon: RoutexIcons.close,
                onTrailingAction: () =>
                    recentRoutePointsController.remove(point),
                onPressed: () => onPicked(point),
              ),
          ],
          if (showSuggestions) ...[
            if (recents.isNotEmpty)
              const RoutexDivider(role: RoutexDividerRole.section),
            for (final suggestion in suggestions) _suggestionCell(suggestion),
          ],
          if (showSuggestions && hasResults)
            const RoutexDivider(role: RoutexDividerRole.section),
          if (hasResults)
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                      ? RoutexSpacing.controlGap
                      : 0,
                ),
                child: RoutexResultList(
                  status: searching && results.isEmpty
                      ? RoutexResultStatus.loading
                      : RoutexResultStatus.ready,
                  loadingMessage: '경로 후보를 찾는 중',
                  children: [
                    for (final candidate in results) _candidateCell(candidate),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _candidateCell(DirectionsCandidate candidate) {
    final unroutable = candidate.floor != null && candidate.nodeId == null;
    final subtitle =
        candidate.reason ??
        (unroutable ? '${candidate.subtitle} · 경로 안내 불가' : candidate.subtitle);
    final nodeId = candidate.nodeId;
    final reach = nodeId == null ? null : reachByNodeId?[nodeId];
    return RoutexListCell(
      title: candidate.title,
      subtitle: subtitle,
      metric: reach == null ? null : reachLabel(reach),
      leadingIcon: candidate.buildingId == null
          ? RoutexIcons.place
          : RoutexIcons.building,
      leadingIconTone: RoutexListIconTone.quiet,
      onPressed: () => onPicked(candidate),
    );
  }

  Widget _suggestionCell(StoreSuggestion suggestion) {
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: reachByNodeId,
    );
    final store = nearest.store;
    final count = suggestion.stores.length;
    return RoutexListCell(
      key: Key('route-field-suggestion-${store.id}'),
      title: store.name,
      subtitle: count > 1 ? '${store.floorName} 등 $count곳' : store.floorName,
      metric: nearest.reach == null ? null : reachLabel(nearest.reach!),
      leadingIcon: RoutexIcons.search,
      leadingIconTone: RoutexListIconTone.quiet,
      onPressed: () => onSuggestionPicked?.call(suggestion),
    );
  }
}
