import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../models/building/category_count.dart';
import '../../../../theme/app_theme.dart';
import '../../../../map/icon/category_icon.dart';
import '../../../../domain/category/category_label_order.dart';
import '../../../../map/style/category_map_filter.dart';

/// 검색창 바로 아래에 붙는 카테고리 chip 열.
/// 건물에 실제 존재하는 대분류만 골라 각각 하나의 chip으로 노출한다.
/// chip 탭 → 해당 카테고리 매장 목록 시트가 바로 열린다 (예전에는 카테고리
/// pill → 카테고리 목록 시트 → 매장 목록 시트로 두 단계였음).
///
/// 카테고리 enumeration은 건물 전 층의 `stores[].category`를 unique하게 뽑아
/// 사용자에게 보이는 label 기준 가나다 순으로 정렬한다. HttpBuildingRepository가 층별 응답을
/// 캐시하므로 첫 로드 이후엔 즉시.
class CategoryChipsRow extends StatelessWidget {
  const CategoryChipsRow({
    super.key,
    required this.entriesFuture,
    required this.selection,
    required this.onSelectionChanged,
    required this.onRetry,
  });

  final Future<List<CategoryCount>> entriesFuture;
  final CategorySelection? selection;
  final ValueChanged<CategorySelection?> onSelectionChanged;

  /// 목록 로드가 실패했을 때 다시 읽기.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CategoryCount>>(
      future: entriesFuture,
      builder: (context, snapshot) {
        // 실패를 빈 목록과 같이 취급하면 안 된다. 둘 다 `data == null`이지만
        // 화면에서 아무것도 안 그리면 사용자에게는 "이 앱엔 원래 카테고리가
        // 없다"로 보이고, 다시 시도할 방법도 없다. 실패는 눌러서 재시도할 수
        // 있는 칩으로 드러낸다.
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError) {
          return _CategoryRetryChip(onTap: onRetry);
        }
        final entries = snapshot.data ?? const <CategoryCount>[];
        if (entries.isEmpty) return const SizedBox.shrink();
        final categories = sortedCategoryLabels(
          entries.map((entry) => entry.category),
        );
        if (categories.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _CategoryChip(
                name: categories[i],
                selected: selection?.category == categories[i],
                // 이미 고른 대분류를 다시 누르면 해제한다. 해제 수단이 따로
                // 없으면 사용자는 필터를 걸고 나서 원래 화면으로 못 돌아온다.
                onTap: () => onSelectionChanged(
                  selection?.category == categories[i]
                      ? null
                      : CategorySelection(category: categories[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;

  /// 지금 이 대분류로 지도가 필터돼 있는지. 선택 상태를 카테고리 고유색으로
  /// 칠해, 어떤 카테고리가 걸려 있는지 pill 줄만 보고도 알 수 있게 한다.
  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = categoryIconFor(name);
    final color = categoryColorFor(name);
    return Material(
      color: selected ? color : Colors.white,
      elevation: AppElevation.onMap,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        // 선택된 chip은 카테고리 고유색으로 채워지므로 경계선이 필요 없다.
        side: BorderSide(
          color: selected ? Colors.transparent : AppColors.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 카테고리 목록을 못 읽었을 때 칩 자리에 대신 뜨는 재시도 버튼.
///
/// 칩과 같은 모양·같은 자리에 둔다. 별도 배너로 띄우면 지도 위 오버레이가
/// 한 줄 더 늘어나 검색창·안내 카드와 자리를 다투게 된다.
class _CategoryRetryChip extends StatelessWidget {
  const _CategoryRetryChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      // 지도에 붙은 조작 줄이다. 그림자를 줄이고 경계는 hairline이 맡는다
      // (AppElevation.onMap).
      elevation: AppElevation.onMap,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 16, color: AppColors.muted),
              SizedBox(width: 6),
              Text(
                '카테고리 다시 불러오기',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
