import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 지도 화면(야외/실내) 공통 상단 바. 왼쪽 햄버거 버튼은 앱 메뉴를 연다.
///
/// 햄버거는 **모드와 무관하게 항상 보인다.** 한동안 실내 모드에서만 띄웠는데,
/// 그때는 버튼이 곧 "건물 선택"이라 야외에서는 누를 이유가 없었기 때문이다.
/// 지금은 저장한 장소·길찾기·위치 보정·디버그 설정을 모은 앱 메뉴라, 야외에서
/// 숨기면 야외 화면에서만 닿지 않는 항목이 생긴다.
///
/// 검색창은 장소의 "일반 정보"만 보여주는 용도이고, 실제 경로 안내는
/// 오른쪽 길찾기 아이콘이 여는 별도 입력 시트를 통해서만 시작된다 —
/// 이 둘을 분리해야 검색이 곧바로 내비게이션을 시작하지 않는다는 기획을 지킬 수 있다.
///
/// **여기서 직접 입력받는다.** 탭하면 이 창에 커서가 잡히고, 결과는 상위가
/// 바로 아래에 붙이는 `SearchPanel`이 보여준다. 한동안은 탭하면 아래에서
/// 입력창이 하나 더 있는 시트가 올라왔는데, 방금 누른 창과 실제로 치는 창이
/// 달라 검색창이 두 개인 것처럼 보였다. 다만 결과를 놓을 자리는 반드시
/// 있어야 한다 — 결과 표시 없이 상단에서만 검색하면 예전처럼 스낵바로만
/// 알리게 되어 "쳤는데 아무것도 안 나온다"가 된다.
class MapTopBar extends StatelessWidget {
  const MapTopBar({
    super.key,
    required this.onMenuTap,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.searchActive,
    required this.onCancelSearch,
    required this.onDirectionsTap,
    required this.onSearchRequested,
    this.routeOriginLabel,
    this.routeDestinationLabel,
    this.onRouteOriginTap,
    this.onRouteDestinationTap,
    this.onClearRouteDraft,
    this.hintText = '건물, 장소를 검색하세요',
  });

  /// 왼쪽 햄버거 버튼. 앱 메뉴 시트를 여는 것이 유일한 역할이다.
  final VoidCallback onMenuTap;

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  /// 엔터로 확정. 의미 검색은 타이핑이 멎어도 알아서 이어지므로 이 콜백은
  /// **유일한 트리거가 아니라 지름길**이다 — 한글 IME에서 첫 엔터가 조합 확정에
  /// 쓰여 여기까지 오지 않아도 검색은 끝까지 간다.
  final ValueChanged<String> onSubmitted;

  /// 검색이 활성(포커스 또는 입력 중)인지. true면 왼쪽 버튼이 메뉴 대신
  /// "검색 종료"로 바뀐다.
  final bool searchActive;
  final VoidCallback onCancelSearch;

  final VoidCallback onDirectionsTap;

  /// 도착지를 먼저 고른 길찾기 초안이다. 실제 후보 객체는 상위 화면이
  /// 소유하고, 이 위젯은 표시와 탭 전달만 맡아 검색 취소·시트 닫힘으로
  /// 초안이 사라지지 않게 한다.
  final String? routeOriginLabel;
  final String? routeDestinationLabel;
  final VoidCallback? onRouteOriginTap;
  final VoidCallback? onRouteDestinationTap;
  final VoidCallback? onClearRouteDraft;

  /// 길찾기 초안을 보고 있는 중에도 일반 장소 검색으로 돌아갈 수 있는
  /// 진입점이다. 검색을 닫으면 상위가 같은 초안을 다시 넘겨준다.
  final VoidCallback onSearchRequested;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final showRouteDraft = !searchActive && routeDestinationLabel != null;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(showRouteDraft ? 18 : 28),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          child: showRouteDraft
              ? _RouteDraftBar(
                  originLabel: routeOriginLabel ?? '출발지를 선택하세요',
                  destinationLabel: routeDestinationLabel!,
                  onOriginTap: onRouteOriginTap ?? onDirectionsTap,
                  onDestinationTap: onRouteDestinationTap ?? onDirectionsTap,
                  onSearchRequested: onSearchRequested,
                  onClear: onClearRouteDraft,
                )
              : Row(
            children: [
              if (searchActive)
                IconButton(
                  onPressed: onCancelSearch,
                  icon: const Icon(Icons.arrow_back, color: AppColors.muted),
                  tooltip: '검색 닫기',
                )
              else
                IconButton(
                  key: const Key('map-top-bar-menu'),
                  onPressed: onMenuTap,
                  icon: const Icon(Icons.menu, color: AppColors.muted),
                  tooltip: '메뉴',
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.text,
                    ),
                    // 상단 바 자체가 이미 흰 카드다. 전역 inputDecorationTheme의
                    // 채움색(blue50)과 포커스 테두리(파란 1.5px)를 그대로 두면
                    // 카드 안에 파란 알약이 하나 더 생긴다 — 셋 다 여기서 끈다.
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: hintText,
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              // 글자가 있으면 지우기, 없으면 길찾기. 둘을 나란히 두면 좁은
              // 화면에서 입력 폭이 더 줄어든다.
              //
              // 이 자리가 앱 안 모든 검색창 지우기 X의 기준 패턴이다 — 글자가
              // 있을 때만 나타나고, 글자만 지우는 게 아니라 `onChanged('')`로
              // 그 입력이 걸어 둔 결과 상태까지 함께 되돌린다. 길찾기 시트와
              // 카테고리 매장 목록 시트도 같은 규칙을 따른다.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  if (value.text.isEmpty) {
                    return IconButton(
                      key: const Key('map-top-bar-directions'),
                      onPressed: onDirectionsTap,
                      icon: const Icon(
                        Icons.directions,
                        color: AppColors.primary,
                      ),
                      tooltip: '길찾기',
                    );
                  }
                  return IconButton(
                    key: const Key('map-top-bar-clear'),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(Icons.close, color: AppColors.muted),
                    tooltip: '입력 지우기',
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 네이버·카카오 지도처럼 도착지를 먼저 고른 뒤에도 출발/도착을 한눈에
/// 확인하는 상단 경로 초안 바. 행을 누르면 상위의 기존 길찾기 선택 시트로
/// 연결한다. X만 초안을 지우는 명시적 초기화다.
class _RouteDraftBar extends StatelessWidget {
  const _RouteDraftBar({
    required this.originLabel,
    required this.destinationLabel,
    required this.onOriginTap,
    required this.onDestinationTap,
    required this.onSearchRequested,
    required this.onClear,
  });

  final String originLabel;
  final String destinationLabel;
  final VoidCallback onOriginTap;
  final VoidCallback onDestinationTap;
  final VoidCallback onSearchRequested;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RouteDraftField(
                  key: const Key('route-draft-origin'),
                  icon: Icons.my_location,
                  label: originLabel,
                  isPlaceholder: originLabel == '출발지를 선택하세요',
                  onTap: onOriginTap,
                ),
                const Divider(height: 1, indent: 34),
                _RouteDraftField(
                  key: const Key('route-draft-destination'),
                  icon: Icons.place_outlined,
                  label: destinationLabel,
                  onTap: onDestinationTap,
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('route-draft-search'),
            onPressed: onSearchRequested,
            icon: const Icon(Icons.search, color: AppColors.muted),
            tooltip: '장소 검색',
          ),
          if (onClear != null)
            IconButton(
              key: const Key('route-draft-clear'),
              onPressed: onClear,
              icon: const Icon(Icons.close, color: AppColors.muted),
              tooltip: '길찾기 초기화',
            ),
        ],
      ),
    );
  }
}

class _RouteDraftField extends StatelessWidget {
  const _RouteDraftField({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPlaceholder = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.w700,
                  color: isPlaceholder ? AppColors.muted : AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
