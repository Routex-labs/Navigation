import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 지도 화면(야외/실내) 공통 상단 바. 실내 모드에서만 햄버거 버튼이 보인다.
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
    required this.showHamburger,
    required this.onHamburgerTap,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.searchActive,
    required this.onCancelSearch,
    required this.onDirectionsTap,
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
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          child: Row(
            children: [
              if (searchActive)
                IconButton(
                  onPressed: onCancelSearch,
                  icon: const Icon(Icons.arrow_back, color: AppColors.muted),
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
                  child: Icon(Icons.search, size: 18, color: AppColors.muted),
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
      ),
    );
  }
}
