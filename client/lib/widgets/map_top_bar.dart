import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 지도 화면(야외/실내) 공통 상단 바. 실내 모드에서만 햄버거 버튼이 보인다.
///
/// **두 얼굴을 가진다.** 평소에는 검색창 한 줄이고, 길찾기 중에는([routeMode])
/// 출발/도착 두 칸이 된다. 검색창은 장소의 "일반 정보"만 보여주는 용도이고
/// 경로 안내는 오른쪽 길찾기 아이콘에서 시작된다 — 이 둘을 분리해야 검색이
/// 곧바로 내비게이션을 시작하지 않는다는 기획을 지킬 수 있다.
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
    required this.showHamburger,
    required this.onHamburgerTap,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.searchActive,
    required this.onCancelSearch,
    required this.onDirectionsTap,
    this.routeMode = false,
    this.originController,
    this.destinationController,
    this.originFocus,
    this.destinationFocus,
    this.onOriginChanged,
    this.onDestinationChanged,
    this.onClearRouteDraft,
    this.hintText = '건물, 장소를 검색하세요',
  });

  final bool showHamburger;
  final VoidCallback onHamburgerTap;

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  /// 엔터로 확정. 의미 검색은 타이핑이 멎어도 알아서 이어지므로 이 콜백은
  /// **유일한 트리거가 아니라 지름길**이다 — 한글 IME에서 첫 엔터가 조합 확정에
  /// 쓰여 여기까지 오지 않아도 검색은 끝까지 간다.
  final ValueChanged<String> onSubmitted;

  /// 검색이 활성(포커스 또는 입력 중)인지. true면 왼쪽 버튼이 햄버거 대신
  /// "검색 종료"로 바뀐다.
  final bool searchActive;
  final VoidCallback onCancelSearch;

  final VoidCallback onDirectionsTap;

  /// 지금 길찾기 중인지. 참이면 이 바가 검색창 하나 대신 **출발/도착 두 칸**이
  /// 된다.
  ///
  /// 한때는 길찾기가 전체 화면(`screens/route_planner/`)이었고 이 바에는 값만
  /// 적힌 요약 행이 떴다. 그래서 목적지를 고치려면 화면을 한 번 더 열어야 했고,
  /// 방금 누른 칸과 실제로 치는 칸이 서로 다른 화면에 있었다. 지금은 여기서
  /// 곧바로 친다 — 아래에 붙는 후보 목록도 상위가 이 바 바로 밑에 놓는다.
  final bool routeMode;

  /// [routeMode]일 때 두 칸의 입력 상태. 값(어느 매장을 골랐는지)은 상위가
  /// 들고 있고, 이 위젯은 표시와 입력 전달만 맡는다.
  final TextEditingController? originController;
  final TextEditingController? destinationController;
  final FocusNode? originFocus;
  final FocusNode? destinationFocus;
  final ValueChanged<String>? onOriginChanged;
  final ValueChanged<String>? onDestinationChanged;

  /// X — 길찾기를 통째로 끝낸다(그려진 경로까지).
  final VoidCallback? onClearRouteDraft;

  final String hintText;

  @override
  Widget build(BuildContext context) {
    final showRouteDraft = routeMode && originController != null;
    // 상태 표시줄 여백은 여기서 먹지 않는다. 길찾기 중에는 이 바 **위에** 이동
    // 수단 줄이 오는데, 둘이 각자 SafeArea를 두면 여백이 두 번 들어가 상단이
    // 뚝 떨어진다. 그 여백은 상위가 Column 전체에 한 번만 준다.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(showRouteDraft ? 18 : 28),
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        child: showRouteDraft
            ? _RouteDraftBar(
                originController: originController!,
                destinationController: destinationController!,
                originFocus: originFocus,
                destinationFocus: destinationFocus,
                onOriginChanged: onOriginChanged,
                onDestinationChanged: onDestinationChanged,
                onClear: onClearRouteDraft,
              )
            : Row(
                children: [
                  if (searchActive)
                    IconButton(
                      onPressed: onCancelSearch,
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.muted,
                      ),
                      tooltip: '검색 닫기',
                    )
                  else if (showHamburger)
                    IconButton(
                      onPressed: onHamburgerTap,
                      icon: const Icon(Icons.menu, color: AppColors.muted),
                      tooltip: '건물 선택',
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Icon(
                        Icons.search,
                        size: 18,
                        color: AppColors.muted,
                      ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 글자가 있으면 지우기, 없으면 길찾기. 둘을 나란히 두면 좁은
                  // 화면에서 입력 폭이 더 줄어든다.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) {
                        return IconButton(
                          onPressed: onDirectionsTap,
                          icon: const Icon(
                            Icons.directions,
                            color: AppColors.primary,
                          ),
                          tooltip: '길찾기',
                        );
                      }
                      return IconButton(
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
    );
  }
}

/// 길찾기 중일 때 상단 바가 되는 **출발/도착 두 칸**.
///
/// 네이버·카카오 지도의 길찾기 머리와 같은 자리다. 두 칸 모두 진짜 입력창이라
/// 여기서 바로 고쳐 칠 수 있고, 결과 목록은 상위가 이 바 바로 아래에 붙인다 —
/// 방금 누른 칸과 실제로 치는 칸이 같아야 한다.
///
/// X는 길찾기를 통째로 끝내는 유일한 명시적 조작이다(지도에 그려진 경로까지).
class _RouteDraftBar extends StatelessWidget {
  const _RouteDraftBar({
    required this.originController,
    required this.destinationController,
    required this.originFocus,
    required this.destinationFocus,
    required this.onOriginChanged,
    required this.onDestinationChanged,
    required this.onClear,
  });

  final TextEditingController originController;
  final TextEditingController destinationController;
  final FocusNode? originFocus;
  final FocusNode? destinationFocus;
  final ValueChanged<String>? onOriginChanged;
  final ValueChanged<String>? onDestinationChanged;
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
                  controller: originController,
                  focusNode: originFocus,
                  onChanged: onOriginChanged,
                  // 비워 두면 "현재 위치"가 출발지다. 그래서 안내문으로 적고
                  // 실제 글자로는 채우지 않는다 — 글자로 채우면 사용자가 다른
                  // 곳을 치기 전에 먼저 지워야 하고, 그 글자가 검색어로도 쓰여
                  // 결과가 비어 버린다.
                  hintText: '현재 위치',
                ),
                const Divider(height: 1, indent: 34),
                _RouteDraftField(
                  key: const Key('route-draft-destination'),
                  icon: Icons.place_outlined,
                  controller: destinationController,
                  focusNode: destinationFocus,
                  onChanged: onDestinationChanged,
                  hintText: '도착지를 입력하세요',
                ),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              key: const Key('route-draft-clear'),
              onPressed: onClear,
              icon: const Icon(Icons.close, color: AppColors.muted),
              tooltip: '길찾기 종료',
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
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hintText,
  });

  final IconData icon;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
              // 상단 바 자체가 흰 카드다. 전역 inputDecorationTheme의 채움색과
              // 포커스 테두리를 그대로 두면 카드 안에 파란 알약이 하나 더 생긴다.
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hintText,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
