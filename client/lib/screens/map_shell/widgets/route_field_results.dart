import 'package:flutter/material.dart';

import '../../../domain/route/dijkstra.dart';
import '../../../domain/store/nearest_store.dart';
import '../../../domain/search/store_suggestions.dart';
import '../../../theme/app_theme.dart';
import '../../../models/directions_candidate.dart';
import '../../../domain/store/reach_label.dart';
import '../../../models/route_plan_mode.dart';

/// 상단 길찾기 바에서 한 칸을 치는 동안 **그 바로 아래**에 붙는 후보 목록.
///
/// 검색창의 [SearchPanel]과 자리는 같지만 하는 일이 다르다. 그쪽은 "이 장소가
/// 무엇인지" 보여 주려고 거리·업종까지 붙이고, 이쪽은 "출발지/도착지를 하나
/// 고른다"라 줄이 짧고 맨 위에 지름길 두 개가 붙는다.
///
/// 후보를 만드는 규칙은 여기 없다. `MapShellScreen._searchDirectionsCandidates`가
/// 매장·건물·건물 밖 장소를 합쳐 넘겨준다 — 검색 진입점마다 규칙이 갈리면 같은
/// 검색어가 어디에 치느냐에 따라 다른 곳을 찾아 준다.
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

  /// 지금 고치고 있는 칸. 출발지일 때만 맨 위에 "현재 위치"가 붙는다.
  final RoutePlanField field;

  final List<DirectionsCandidate> results;
  final bool searching;

  final ValueChanged<DirectionsCandidate> onPicked;

  /// "지도에서 선택". 목록을 접고 지도 탭을 기다린다.
  final VoidCallback onPickOnMap;

  /// 그 줄을 보여 줄지. **야외 지도에서는 감춘다.**
  ///
  /// 야외에서 지도를 누르면 이름도 없는 좌표 하나가 잡힌다("지도에서 지정한 도착
  /// 위치, 37.5665, 126.9779"). 매장 이름으로 고르는 흐름과 나란히 두면 같은
  /// 무게로 읽히는데, 실제로 쓸 일은 GPS가 안 잡히는 예외뿐이다 — 그 경우는
  /// 하단 바의 "위치 지정"이 따로 맡는다.
  ///
  /// 도면을 보고 있을 때는 다르다. 거기서 누르는 것은 좌표가 아니라 **매장**이라
  /// 층·노드가 붙어 실내 안내까지 이어진다.
  final bool showPickOnMap;

  /// "현재 위치"로 되돌린다. 출발지를 따로 고르지 않은 상태가 곧 이 값이라,
  /// 다른 곳을 골랐다가 되돌아올 길이 목록 안에 있어야 한다.
  final VoidCallback onCurrentLocation;

  /// 온디바이스 이름 후보(초성·구두점·오타 교정). 서버를 기다리지 않고 0ms에
  /// 나오므로 **목록의 맨 위**에 붙는다 — 상단 검색과 같은 재료를 쓴다.
  final List<StoreSuggestion> suggestions;

  /// 그 후보를 눌렀을 때. 상위가 그 이름으로 검색을 다시 돌린다.
  final ValueChanged<StoreSuggestion>? onSuggestionPicked;

  /// 현재 위치에서 각 그래프 노드까지의 거리·비용. 후보마다 "몇 m · 도보 몇 분"을
  /// 붙이는 데 쓴다. **모르면 줄을 아예 그리지 않는다** — 줄마다 "거리 알 수
  /// 없음"을 반복하면 목록이 읽히지 않는다(상단 검색 결과와 같은 규칙).
  final Map<String, NodeReach>? reachByNodeId;

  @override
  Widget build(BuildContext context) {
    final isOrigin = field == RoutePlanField.origin;
    // 보여 줄 것이 하나도 없으면 **아무것도 그리지 않는다.**
    //
    // 예전에는 이 조건에서도 카드가 남아, 야외에서 길찾기를 열면 이동 수단 줄
    // 아래에 아무 내용 없는 흰 막대가 하나 떠 있었다. 지름길 두 줄이 다 빠지고
    // (야외 + 도착 칸) 아직 아무것도 안 친 상태가 정확히 그 경우다.
    final hasShortcut = showPickOnMap || isOrigin;
    final showSuggestions =
        suggestions.isNotEmpty && onSuggestionPicked != null;
    if (!hasShortcut && results.isEmpty && !searching && !showSuggestions) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPickOnMap)
            ListTile(
              key: const Key('route-field-pick-on-map'),
              onTap: onPickOnMap,
              dense: true,
              leading: const Icon(
                Icons.touch_app_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              title: const Text(
                '지도에서 선택',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              // 제목은 같아도 부제는 갈라야 한다. 출발지 칸에서 눌렀는데 "도착지로
              // 지정합니다"라고 적혀 있으면 사용자는 잘못 눌렀다고 판단해 되돌린다.
              subtitle: Text(
                isOrigin ? '지도에서 매장을 눌러 출발지로 지정합니다' : '지도에서 매장을 눌러 도착지로 지정합니다',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.muted,
              ),
            ),
          if (isOrigin)
            ListTile(
              key: const Key('route-field-current-location'),
              onTap: onCurrentLocation,
              dense: true,
              leading: const Icon(Icons.my_location, color: AppColors.primary),
              title: const Text(
                '현재 위치',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          // 지름길 줄과 목록 사이의 구분선. 한쪽이 비어 있으면 선만 남아 카드
          // 아래에 얇은 회색 줄이 떠다닌다.
          if (hasShortcut &&
              (results.isNotEmpty || searching || showSuggestions))
            const Divider(height: 1),
          // 온디바이스 후보는 서버 결과 **위**다. 0ms에 나오는 값이라 사용자가
          // 치는 동안 이 자리가 먼저 차고, 서버가 답하면 아래가 채워진다.
          if (showSuggestions)
            for (final suggestion in suggestions) _suggestionTile(suggestion),
          if (showSuggestions && (results.isNotEmpty || searching))
            const Divider(height: 1),
          if (results.isNotEmpty || searching)
            Flexible(
              child: searching && results.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      // 셸이 키보드로 화면을 리사이즈하지 않으므로
                      // (`resizeToAvoidBottomInset: false`) 여기서 바닥을 직접
                      // 띄운다 — 안 그러면 목록의 아래쪽이 키보드에 덮여, 스크롤을
                      // 끝까지 내려도 마지막 줄을 누를 수 없다.
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                            ? 8
                            : 0,
                      ),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final candidate = results[index];
                        return _candidateTile(candidate);
                      },
                    ),
            ),
        ],
      ),
    );
  }

  /// 후보 한 줄. 실내 후보인데 입구 노드가 없으면 경로를 계산할 수 없으므로
  /// 미리 알린다 — 고를 수는 있게 둔다(위치는 지도에 보여줄 수 있다).
  Widget _candidateTile(DirectionsCandidate candidate) {
    final unroutable = candidate.floor != null && candidate.nodeId == null;
    final subtitle =
        candidate.reason ??
        (unroutable ? '${candidate.subtitle} · 경로 안내 불가' : candidate.subtitle);
    final nodeId = candidate.nodeId;
    final reach = nodeId == null ? null : reachByNodeId?[nodeId];
    return ListTile(
      dense: true,
      // 건물과 건물 안 매장을 아이콘으로 가른다. 같은 핀으로 두면 목록에서
      // 무엇이 건물인지 읽을 방법이 없다.
      leading: Icon(
        candidate.buildingId == null ? Icons.place : Icons.apartment_outlined,
        color: AppColors.primary,
      ),
      title: Text(
        candidate.title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (reach != null)
            Text(
              reachLabel(reach),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 상단 검색 결과 행과 같은 무게. 두 화면이 같은 값을 다르게 그리면
              // 사용자는 둘이 다른 것을 뜻한다고 읽는다.
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      isThreeLine: reach != null,
      onTap: () => onPicked(candidate),
    );
  }

  /// 온디바이스 후보 한 줄. 같은 이름이 여러 층에 있으면 **가장 가까운 층**을
  /// 대표로 세우고 나머지는 개수로 접는다.
  Widget _suggestionTile(StoreSuggestion suggestion) {
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: reachByNodeId,
    );
    final store = nearest.store;
    final reach = nearest.reach;
    final count = suggestion.stores.length;
    final floorLine = count > 1
        ? '${store.floorName} 등 $count곳'
        : store.floorName;
    return ListTile(
      key: Key('route-field-suggestion-${store.id}'),
      dense: true,
      leading: Icon(
        suggestion.kind.isCorrection ? Icons.auto_fix_high : Icons.search,
        color: AppColors.muted,
      ),
      title: Text(
        store.name,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(floorLine, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (reach != null)
            Text(
              reachLabel(reach),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      isThreeLine: reach != null,
      onTap: () => onSuggestionPicked?.call(suggestion),
    );
  }
}
