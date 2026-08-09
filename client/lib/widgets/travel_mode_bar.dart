import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 목적지까지 **어떻게 갈지**.
///
/// 자동차·자전거는 넣지 않는다. 우리가 부르는 TMAP API에 그 경로가 없어서,
/// 탭만 만들어 두면 눌러도 아무 일이 없는 죽은 버튼이 된다 — 사용자는 그것을
/// "고장"으로 읽지 "지원 안 함"으로 읽지 않는다.
enum TravelMode {
  walk,
  transit;

  String get label => this == TravelMode.walk ? '도보' : '대중교통';

  IconData get icon => this == TravelMode.walk
      ? Icons.directions_walk_rounded
      : Icons.directions_transit_rounded;
}

/// 상단 경로 초안 바 아래에 붙는 이동 수단 선택 줄.
///
/// **왜 필요한가** — 예전에는 목적지를 정하면 무조건 도보 경로부터 그렸고,
/// 대중교통은 하단 카드의 버튼을 눌러야 나왔다. 그래서 10 km 떨어진 목적지에
/// "약 147분 / 10649m" 도보 안내가 먼저 떴다. 걸어서 두 시간 반 걸리는 길을
/// 기본 답으로 내미는 셈이라, 사용자는 매번 그 화면을 지나쳐 다시 눌러야 했다.
///
/// 수단을 **먼저 고르게** 하면 그 왕복이 사라진다. 처음 뜨는 수단도 거리에
/// 따라 정하므로(가까우면 도보, 멀면 대중교통) 대개는 고를 필요조차 없다.
class TravelModeBar extends StatelessWidget {
  const TravelModeBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.transitEnabled = true,
  });

  final TravelMode selected;
  final ValueChanged<TravelMode> onSelected;

  /// TMAP 키가 없어 대중교통을 쓸 수 없으면 false. 그 탭을 **감춘다** —
  /// 눌러서 "쓸 수 없습니다"를 보는 것보다 없는 편이 낫다.
  final bool transitEnabled;

  @override
  Widget build(BuildContext context) {
    final modes = transitEnabled ? TravelMode.values : [TravelMode.walk];
    // 수단이 하나뿐이면 고를 것이 없다. 선택지가 없는 선택 줄은 자리만 먹는다.
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

  final TravelMode mode;
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
            const SizedBox(width: 6),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
