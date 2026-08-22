import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';

/// 화면 맨 아래에 **고정**된 탭 줄. 다른 것들이 뜨고 지고 끌려 올라가도 이 줄만은
/// 늘 같은 자리에 있다 — 여기가 바닥이라는 것을 알려 주는 것이 이 줄의 첫 일이다.
///
/// **탭이 화면을 갈아 끼우지는 않는다.** 이 앱은 지도 한 화면이고, 나머지는 그
/// 위에 뜨는 시트·모드다. 그래서 [MapTab.map]만 "돌아오는 자리"이고 나머지는 각자
/// 자기 것을 연다. 대신 지금 켜져 있는 것은 [selected]로 표시해, 누른 것이 어디에
/// 남아 있는지 보이게 한다.
enum MapTab {
  map('지도', Icons.map_outlined, Icons.map),
  directions('길찾기', Icons.alt_route_outlined, Icons.alt_route),
  events('이벤트', Icons.local_activity_outlined, Icons.local_activity),
  saved('저장', Icons.bookmark_border, Icons.bookmark);

  const MapTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// 탭 줄의 높이. **안전영역은 여기에 포함되지 않는다** — 위에 얹히는 것들이
/// 띄워야 할 거리를 재려면 두 값을 따로 더해야 한다.
const double kMapTabBarHeight = 56;

class MapTabBar extends StatelessWidget {
  const MapTabBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.disabled = const {},
  });

  final MapTab selected;
  final ValueChanged<MapTab> onSelected;

  /// 지금 여기서는 열 것이 없는 탭. **빼지 않고 흐리게 둔다** — 자리가 뜨고 지면
  /// 바닥이라는 약속이 깨지고, 사용자는 방금 누른 자리를 다시 찾아야 한다. 흐린
  /// 채로 남아 있으면 "여기서는 못 쓴다"가 그대로 읽힌다.
  final Set<MapTab> disabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      // 그림자가 아니라 실선으로 가른다. 위에 붙는 판도 흰 면이라, 그림자를 쓰면
      // 두 흰 면 사이에 그림자가 끼어 판이 떠 있는 것처럼 보인다.
      shape: const Border(top: BorderSide(color: AppColors.hairline)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kMapTabBarHeight,
          child: Row(
            children: [
              for (final tab in MapTab.values)
                Expanded(
                  child: _TabItem(
                    key: Key('map-tab-${tab.name}'),
                    tab: tab,
                    selected: tab == selected,
                    onTap: disabled.contains(tab)
                        ? null
                        : () => onSelected(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final MapTab tab;
  final bool selected;

  /// null이면 여기서 열 것이 없는 탭이다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = switch ((enabled, selected)) {
      (false, _) => AppColors.muted.withValues(alpha: 0.38),
      (_, true) => AppColors.primary,
      _ => AppColors.muted,
    };
    return InkWell(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        enabled: enabled,
        button: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                // 고른 것은 색과 굵기 **둘 다**로 가른다. 색만으로 가르면 색을
                // 구분하기 어려운 사람에게는 아무 표시도 없는 줄이 된다.
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
