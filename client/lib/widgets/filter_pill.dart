import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 목록을 좁히는 가로 줄에 쓰는 pill. **시트·패널 안 필터 줄의 단일 출처다.**
///
/// 카테고리 시트의 소분류 줄과 검색 패널의 되물음(clarify) 선택지는 하는 일이 같다 —
/// "지금 보이는 목록을 이 값으로 좁혀라". 같은 일을 하는 것이 화면마다 다르게 생기면
/// 사용자는 둘을 다른 기능으로 읽는다. 그래서 한 곳에 두고 양쪽이 함께 쓴다.
///
/// **그림자를 쓰지 않는다.** 흰 시트·패널 위에 뜬 카드처럼 보이면 목록과 같은 평면에
/// 있다는 게 읽히지 않는다. 지도 위에 떠 있는 pill과 구분되는 지점이기도 하다.
///
/// Material의 `ActionChip`·`FilterChip`을 쓰지 않는 이유는 크기다. 기본 chip은 높이가
/// 32~40이고 좌우 여백도 넉넉해서, 선택지가 다섯이면 두 줄로 접히며 정작 결과 목록을
/// 화면 밖으로 밀어낸다. 이 pill은 높이 30에 맞춰 한 줄에서 가로로 스크롤된다.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 라벨 뒤에 붙는 아이콘. 선택을 해제하는 `×`처럼 pill 자체가 무엇을 하는지
  /// 바꾸는 경우에만 쓴다. 없으면 라벨만 그린다.
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.text;
    return Material(
      color: selected ? AppColors.primary : const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                Icon(trailing, size: 14, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
