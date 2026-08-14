/// 상세 아래에 붙는 "근처 매장" 목록.
///
/// **기준은 사용자가 아니라 이 매장이다.** 사용자 기준 거리는 시트 헤더에 이미 있고,
/// 같은 기준으로 두 번 적으면 두 번째 줄이 알려 주는 것이 없다. 고르는 규칙과 그
/// 실패 조건은 `domain/nearby_stores.dart`가 단일 출처다.
///
/// ## 세로 목록이 아니라 가로 슬라이드인 이유
///
/// 이 목록에는 **사진이 없다.** 매장 사진은 스타벅스 한 곳에만 있고 나머지 1,639건은
/// 오버레이가 비어 있다. 사진 없는 줄을 세로로 다섯 개 쌓으면 글자만 다섯 줄이 되어,
/// 바로 위의 메뉴·영업정보와 무게가 같아진다 — 본문이 끝났다는 신호가 사라진다.
/// 가로로 밀면 "곁다리로 더 있다"가 모양만으로 전해지고, 세로 자리도 한 칸만 쓴다.
///
/// 사진 대신 업종 아이콘을 카드 머리에 둔다. `storeIconFor`는 검색 결과·시트 헤더가
/// 쓰는 것과 같은 함수라, 같은 매장이 화면마다 다른 그림으로 보이지 않는다.
library;

import 'package:flutter/material.dart';

import '../../../../domain/nearby_stores.dart';
import '../../../../models/store_index_entry.dart';
import '../../../../theme/app_theme.dart';
import '../../../../core/map/category_icon.dart';
import '../../../../domain/reach_label.dart';
import './place_detail_rich_sections.dart';

/// 카드 한 장의 너비. 화면 폭과 무관하게 **다음 카드가 일부 보이도록** 고정한다 —
/// 잘린 카드가 보이는 것이 "옆으로 더 있다"를 말하는 가장 싼 방법이다. 화면 폭에
/// 맞춰 나누면 기기에 따라 딱 떨어져서 그 신호가 사라진다.
const _cardWidth = 132.0;

class PlaceNearbySection extends StatelessWidget {
  const PlaceNearbySection({
    super.key,
    required this.stores,
    required this.onSelect,
  });

  final List<NearbyStore> stores;

  /// 카드를 눌렀을 때. null이면 누를 수 없는 목록으로 그린다.
  final void Function(StoreIndexEntry store)? onSelect;

  @override
  Widget build(BuildContext context) {
    // 빈 목록이면 제목까지 통째로 없앤다. "근처 매장 (없음)"은 정보가 아니라
    // 고장으로 읽힌다 — 섹션 계약 4-2 규칙 1과 같은 이유다.
    if (stores.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: placeSectionGutter),
          child: PlaceSectionTitle('근처 매장'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // 좌우 여백을 목록 **안쪽**에 준다. 바깥에서 Padding으로 감싸면 스크롤
            // 영역까지 좁아져 첫 카드와 마지막 카드가 여백에서 잘린다.
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            itemCount: stores.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final nearby = stores[index];
              return _NearbyCard(
                nearby: nearby,
                onTap: onSelect == null ? null : () => onSelect!(nearby.store),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.nearby, required this.onTap});

  final NearbyStore nearby;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final store = nearby.store;
    final label = subcategoryLabelFor(store.subcategory) ?? store.category;

    return SizedBox(
      width: _cardWidth,
      child: Material(
        color: AppColors.blue50,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  storeIconFor(
                    name: store.name,
                    subcategory: store.subcategory,
                    category: store.category,
                  ),
                  size: 22,
                  color: AppColors.primary,
                ),
                const Spacer(),
                Text(
                  store.name,
                  // 두 줄까지 편다. 이 건물의 매장명은 `LISTENING ROOM BY ODE`처럼
                  // 긴 것이 흔해서, 한 줄로 자르면 카드가 무슨 매장인지 못 말한다.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // 층을 항상 적는다. 그래프가 층을 넘어 이어져 있어 다른 층 매장이
                  // 섞일 수 있고, 그때 층이 없으면 "몇 걸음"으로 읽힌다.
                  [
                    store.floorName,
                    // 거리 문구는 검색 결과 목록과 **같은 함수**로 만든다. 두 화면이
                    // 같은 거리를 다르게 적으면 사용자는 둘이 다른 것을 뜻한다고 읽는다.
                    reachLabel(nearby.reach),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                if (label != null && label.isNotEmpty)
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
