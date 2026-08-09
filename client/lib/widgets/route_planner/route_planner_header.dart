import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'route_plan_mode.dart';

/// 길찾기 화면에서 지금 글자를 치고 있는 칸.
enum RoutePlanField { origin, destination }

/// 길찾기 화면 맨 위의 파란 머리. **수단 → 출발/도착** 순서로 쌓는다.
///
/// 순서가 중요하다. 예전에는 도착지를 먼저 정하게 하고 수단은 그 뒤에 물었는데,
/// 그러면 10 km 떨어진 곳에 도보 안내가 먼저 뜨고 사용자가 그 화면을 지나쳐
/// 다시 눌러야 했다. 수단을 위에 두면 "어떻게 갈지"를 정한 상태에서 목적지를
/// 넣게 되고, 도중에 수단을 바꿔도 입력한 두 칸은 그대로 남는다.
///
/// 이 위젯은 **표시와 입력 전달만** 한다. 무엇이 출발지인지, 경로가 있는지는
/// 전부 상위([RoutePlannerView])가 들고 있다 — 머리와 본문이 각자 상태를 쥐면
/// 수단을 바꿀 때 한쪽만 갱신되어 두 영역이 다른 경로를 말하게 된다.
class RoutePlannerHeader extends StatelessWidget {
  const RoutePlannerHeader({
    super.key,
    required this.mode,
    required this.modes,
    required this.onModeChanged,
    required this.originController,
    required this.destinationController,
    required this.originFocus,
    required this.destinationFocus,
    required this.onOriginChanged,
    required this.onDestinationChanged,
    required this.onSwap,
    required this.onClose,
  });

  final RoutePlanMode mode;

  /// 실제로 고를 수 있는 수단만 담는다. TMAP 키가 없으면 대중교통이 빠진다 —
  /// 눌러서 "쓸 수 없습니다"를 보는 것보다 없는 편이 낫다.
  final List<RoutePlanMode> modes;

  final ValueChanged<RoutePlanMode> onModeChanged;

  final TextEditingController originController;
  final TextEditingController destinationController;
  final FocusNode originFocus;
  final FocusNode destinationFocus;
  final ValueChanged<String> onOriginChanged;
  final ValueChanged<String> onDestinationChanged;

  /// 출발지와 도착지를 맞바꾼다. "왔던 길 되돌아가기"는 길찾기에서 가장 흔한
  /// 두 번째 조회라, 이게 없으면 두 칸을 다시 입력하게 된다.
  final VoidCallback onSwap;

  /// 길찾기 화면을 닫고 지도로 돌아간다.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final value in modes)
                    Expanded(
                      child: _ModeTab(
                        mode: value,
                        selected: value == mode,
                        onTap: () => onModeChanged(value),
                      ),
                    ),
                  IconButton(
                    key: const Key('route-planner-close'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '길찾기 닫기',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _EndpointField(
                          key: const Key('route-planner-origin-field'),
                          controller: originController,
                          focusNode: originFocus,
                          onChanged: onOriginChanged,
                          // 비워 두면 "현재 위치"가 출발지다. 그래서 안내문으로
                          // 적고 실제 글자로는 채우지 않는다 — 글자로 채우면
                          // 사용자가 다른 곳을 치기 전에 먼저 지워야 하고,
                          // 그 글자가 검색어로도 쓰여 결과가 비어 버린다.
                          hintText: '현재 위치',
                        ),
                        const SizedBox(height: 4),
                        _EndpointField(
                          key: const Key('route-planner-destination-field'),
                          controller: destinationController,
                          focusNode: destinationFocus,
                          onChanged: onDestinationChanged,
                          hintText: '도착지를 입력하세요',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('route-planner-swap'),
                    onPressed: onSwap,
                    icon: const Icon(Icons.swap_vert, color: Colors.white),
                    tooltip: '출발지와 도착지 바꾸기',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final RoutePlanMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // 아이콘만 있는 탭이라 화면 낭독기에는 아무것도 안 읽힌다. 라벨을 붙여
      // 두면 "자동차, 선택됨"까지 읽힌다.
      label: mode.label,
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('route-plan-mode-${mode.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Icon(
            mode.icon,
            size: 24,
            color: selected ? AppColors.primary : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 출발/도착 입력 한 칸. 파란 머리 위에 놓이므로 전역 입력 테마(연파랑 채움)를
/// 그대로 쓰면 배경과 구분이 안 된다 — 여기서 흰 반투명으로 덮어쓴다.
class _EndpointField extends StatelessWidget {
  const _EndpointField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15, color: AppColors.text),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        hintText: hintText,
        hintStyle: const TextStyle(fontSize: 15, color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        // 글자가 있을 때만 지우기 버튼. 없을 때도 자리를 잡아 두면 좁은 칸에서
        // 입력 폭이 그만큼 줄어든다.
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
              tooltip: '입력 지우기',
            );
          },
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}
