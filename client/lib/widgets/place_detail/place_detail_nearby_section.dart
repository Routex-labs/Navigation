/// 상세 하단의 "근처 매장" 목록.
///
/// 비교하기 쉽도록 한 줄에 한 매장을 놓되, 본문이 불필요하게 길어지지 않도록
/// 처음에는 3개만 보여 준다. 후보가 더 있으면 사용자가 명시적으로 펼친다.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/nearby_stores.dart';
import '../../models/store_index_entry.dart';
import '../../theme/app_theme.dart';
import '../category_icon.dart';
import '../reach_label.dart';
import 'place_detail_rich_sections.dart';

const _collapsedStoreCount = 3;
const _expandDuration = Duration(milliseconds: 240);

class PlaceNearbySection extends StatefulWidget {
  const PlaceNearbySection({
    super.key,
    required this.stores,
    required this.onSelect,
  });

  final List<NearbyStore> stores;
  final void Function(StoreIndexEntry store)? onSelect;

  @override
  State<PlaceNearbySection> createState() => _PlaceNearbySectionState();
}

class _PlaceNearbySectionState extends State<PlaceNearbySection> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant PlaceNearbySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.stores.map((item) => item.store.id).toList();
    final newIds = widget.stores.map((item) => item.store.id).toList();
    if (!listEquals(oldIds, newIds)) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stores.isEmpty) return const SizedBox.shrink();

    final visibleCount = _expanded
        ? widget.stores.length
        : math.min(_collapsedStoreCount, widget.stores.length);
    final hiddenCount = widget.stores.length - _collapsedStoreCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: placeSectionGutter),
          child: PlaceSectionTitle('근처 매장'),
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: _expandDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            child: Column(
              children: [
                for (var index = 0; index < visibleCount; index++) ...[
                  _NearbyRow(
                    nearby: widget.stores[index],
                    onTap: widget.onSelect == null
                        ? null
                        : () => widget.onSelect!(widget.stores[index].store),
                  ),
                  if (index < visibleCount - 1)
                    const Divider(height: 1, color: AppColors.hairline),
                ],
              ],
            ),
          ),
        ),
        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              placeSectionGutter,
              4,
              placeSectionGutter,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                iconAlignment: IconAlignment.end,
                icon: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: _expandDuration,
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 19,
                  ),
                ),
                label: Text(_expanded ? '접기' : '$hiddenCount개 더보기'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.nearby, required this.onTap});

  final NearbyStore nearby;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final store = nearby.store;
    final category = subcategoryLabelFor(store.subcategory) ?? store.category;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.blue50,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  storeIconFor(
                    name: store.name,
                    subcategory: store.subcategory,
                    category: store.category,
                  ),
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        store.floorName,
                        reachLabel(nearby.reach),
                        if (category != null && category.isNotEmpty) category,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.blue300,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
