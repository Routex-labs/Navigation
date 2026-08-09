import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'directions_candidate.dart';
import 'route_plan_mode.dart';

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
    required this.onCurrentLocation,
  });

  /// 지금 고치고 있는 칸. 출발지일 때만 맨 위에 "현재 위치"가 붙는다.
  final RoutePlanField field;

  final List<DirectionsCandidate> results;
  final bool searching;

  final ValueChanged<DirectionsCandidate> onPicked;

  /// "지도에서 선택". 목록을 접고 지도 탭을 기다린다.
  final VoidCallback onPickOnMap;

  /// "현재 위치"로 되돌린다. 출발지를 따로 고르지 않은 상태가 곧 이 값이라,
  /// 다른 곳을 골랐다가 되돌아올 길이 목록 안에 있어야 한다.
  final VoidCallback onCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final isOrigin = field == RoutePlanField.origin;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              isOrigin ? '지도에서 눌러 출발지로 지정합니다' : '지도에서 눌러 도착지로 지정합니다',
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
          const Divider(height: 1),
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
                      return ListTile(
                        dense: true,
                        // 건물과 건물 안 매장을 아이콘으로 가른다. 같은 핀으로
                        // 두면 목록에서 무엇이 건물인지 읽을 방법이 없다.
                        leading: Icon(
                          candidate.buildingId == null
                              ? Icons.place
                              : Icons.apartment_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          candidate.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(candidate.subtitle),
                        onTap: () => onPicked(candidate),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
