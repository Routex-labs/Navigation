import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../../../models/route/route_plan_mode.dart';

/// 상단 길찾기 바(출발/도착 두 칸) **바로 아래**에 붙는 이동 수단 선택 줄.
///
/// **왜 입력 아래에 있는가** — 한동안 이 줄은 전용 길찾기 화면 맨 위, 입력보다
/// 위에 있었다. "어떻게 갈지를 먼저 정한다"는 순서였는데, 그 화면을 없애고
/// 길찾기를 상단 바로 되돌리면서 자리도 바뀌었다. 지금 순서는 **어디로 갈지 →
/// 어떻게 갈지**다. 도착지를 정하면 거리를 보고 수단이 자동으로 정해지므로
/// (가까우면 도보, 멀면 대중교통) 이 줄은 대개 "고르는 곳"이 아니라 "지금 무엇으로
/// 안내 중인지 보여주고 바꿀 수 있는 곳"이다.
///
/// 수단이 하나뿐이면(실내 탭·TMAP 키 없음) 줄 자체를 감춘다. 선택지가 없는 선택
/// 줄은 자리만 먹는다.
class TravelModeBar extends StatelessWidget {
  const TravelModeBar({
    super.key,
    required this.selected,
    required this.modes,
    required this.onSelected,
  });

  final RoutePlanMode selected;

  /// 실제로 고를 수 있는 수단만 담는다. 카카오 키가 없으면 대중교통이, 실내
  /// 탭에서는 자동차·대중교통이 빠진다 — 눌러서 "쓸 수 없습니다"를 보는 것보다
  /// 없는 편이 낫다.
  final List<RoutePlanMode> modes;

  final ValueChanged<RoutePlanMode> onSelected;

  @override
  Widget build(BuildContext context) {
    if (modes.length < 2) return const SizedBox.shrink();

    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          key: const ValueKey('travel-mode-bar'),
          children: [
            for (final mode in modes)
              Expanded(
                child: _ModeTab(
                  mode: mode,
                  selected: mode == selected,
                  onTap: () => onSelected(mode),
                ),
              ),
          ],
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
    final color = selected ? Colors.white : AppColors.muted;
    return InkWell(
      key: ValueKey('travel-mode-${mode.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(mode.icon, size: 18, color: color),
            const SizedBox(width: 5),
            // 세 칸이 되면서 한 칸이 좁아졌다. 이름이 잘리면 아이콘만 남아
            // "자동차"와 "대중교통"을 구분할 수 없으므로 줄이지 않고 흘려보낸다.
            Flexible(
              child: Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
