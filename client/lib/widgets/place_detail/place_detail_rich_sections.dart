import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'korean_line_break.dart';

/// 매장 대표 사진의 로컬 asset 정보다. 네트워크 모델과 분리해 화면에 필요한
/// 최소 표시 정보만 가진다.
class PlaceHeroImage {
  const PlaceHeroImage({required this.assetPath, this.semanticLabel});

  final String assetPath;
  final String? semanticLabel;
}

/// 사진 asset을 가로로 넘겨 볼 수 있는 대표 이미지 영역.
class PlaceHeroCarousel extends StatefulWidget {
  const PlaceHeroCarousel({super.key, required this.images});

  final List<PlaceHeroImage> images;

  @override
  State<PlaceHeroCarousel> createState() => _PlaceHeroCarouselState();
}

class _PlaceHeroCarouselState extends State<PlaceHeroCarousel> {
  var _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();

    // 본문과 같은 좌우 여백에 맞추고 모서리를 깎는다. 끝까지 채우면 사진이 시트
    // 밖으로 이어지는 것처럼 보여서 다음 섹션과의 경계가 흐려진다.
    return SizedBox(
      height: 210,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _activeIndex = index),
            itemBuilder: (context, index) {
              final image = widget.images[index];
              // PageView는 시트 폭 전체를 쓰고 여백은 페이지 안쪽에 준다. 그래야
              // 넘길 때 두 장 사이가 좌우 여백만큼 벌어진다.
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: placeSectionGutter),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    image.assetPath,
                    fit: BoxFit.cover,
                    semanticLabel: image.semanticLabel,
                    width: double.infinity,
                  ),
                ),
              );
            },
          ),
          if (widget.images.length > 1)
            Positioned(
              right: placeSectionGutter + 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    '${_activeIndex + 1} / ${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 메뉴 카드에 필요한 로컬 표시 데이터다. 메뉴의 판매 여부나 가격 갱신은
/// 상위 데이터 공급자가 책임지고 이 위젯은 값을 그대로 렌더링한다.
///
/// 이름과 사진 말고는 전부 없을 수 있다. 출처마다 가진 것이 달라서다 — 공식 사이트가
/// 가격을 안 주는 대신 용량·칼로리·카페인을 주기도 하고, 푸드처럼 영양정보가 아예 없는
/// 것도 있다. 없는 값을 어떻게 메울지는 카드가 정한다([specLine]).
class PlaceMenuItem {
  const PlaceMenuItem({
    required this.name,
    this.category,
    this.nameEn,
    this.price,
    this.description,
    this.volume,
    this.calories,
    this.caffeine,
    this.imageAssetPath,
  });

  final String name;
  final String? category;
  final String? nameEn;
  final String? price;
  final String? description;
  final String? volume;
  final String? calories;
  final String? caffeine;
  final String? imageAssetPath;

  /// 가격 자리를 대신 채울 한 줄(`355ml · 5kcal · 190mg`).
  ///
  /// 셋 다 없으면 `null`이라 카드가 줄 자체를 그리지 않는다. 빈 문자열을 반환하면
  /// 보이지 않는 한 줄만큼 카드 높이가 달라져서, 푸드 카드와 음료 카드가 같은 줄에서
  /// 어긋난다.
  String? get specLine {
    final parts = [
      volume,
      calories,
      caffeine,
    ].where((part) => part != null && part.isNotEmpty).cast<String>();
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// 메뉴를 좁은 가로 카드 목록으로 보여 준다. 카테고리가 있으면 위에 탭을 붙인다.
class PlaceMenuSection extends StatefulWidget {
  const PlaceMenuSection({super.key, required this.items});

  final List<PlaceMenuItem> items;

  @override
  State<PlaceMenuSection> createState() => _PlaceMenuSectionState();
}

/// 탭으로 쓸 카테고리를 등장 순서대로 뽑는다. 탭을 만들지 않을 때는 빈 목록.
///
/// **한 항목이라도 카테고리가 없으면 탭을 만들지 않는다.** 가진 것만 탭에 넣으면 나머지
/// 항목은 어느 탭에서도 보이지 않는데, 화면에는 아무 이상이 없어 보인다. 메뉴가 조용히
/// 사라지는 쪽이 30개를 한 줄로 미는 것보다 나쁘다.
///
/// 카테고리가 한 종류뿐일 때도 만들지 않는다. 누를 곳이 하나뿐인 탭은 아무것도 나누지
/// 않으면서 자리만 차지한다.
List<String> menuCategoryTabs(List<PlaceMenuItem> items) {
  final tabs = <String>[];
  for (final item in items) {
    final category = item.category;
    if (category == null || category.isEmpty) return const <String>[];
    if (!tabs.contains(category)) tabs.add(category);
  }
  return tabs.length > 1 ? tabs : const <String>[];
}

class _PlaceMenuSectionState extends State<PlaceMenuSection> {
  String? _activeTab;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final tabs = menuCategoryTabs(widget.items);
    // 선택한 탭이 사라졌으면(데이터가 바뀌었으면) 첫 탭으로 되돌린다. 없어진
    // 카테고리를 붙들고 있으면 빈 목록이 뜬다.
    final active = tabs.contains(_activeTab) ? _activeTab : tabs.firstOrNull;
    final visible = active == null
        ? widget.items
        : widget.items.where((item) => item.category == active).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: placeSectionGutter),
          child: PlaceSectionTitle('메뉴'),
        ),
        if (tabs.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MenuCategoryTabs(
            tabs: tabs,
            active: active!,
            onSelect: (tab) => setState(() => _activeTab = tab),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // 탭을 바꾸면 가로 스크롤을 처음으로 되돌린다. key가 없으면 같은
            // ListView가 재사용돼, 5개짜리 탭으로 옮겼는데 오른쪽 끝에 가 있다.
            key: ValueKey(active),
            // 가로 리스트는 본문 거터를 스스로 갖는다. 그래야 첫 카드가 시트
            // 가장자리에서 시작하면서도 끝까지 스크롤된다.
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _PlaceMenuCard(item: visible[index]),
          ),
        ),
      ],
    );
  }
}

class _MenuCategoryTabs extends StatelessWidget {
  const _MenuCategoryTabs({
    required this.tabs,
    required this.active,
    required this.onSelect,
  });

  final List<String> tabs;
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
      itemCount: tabs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final tab = tabs[index];
        final selected = tab == active;
        return GestureDetector(
          onTap: () => onSelect(tab),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? AppColors.blue500 : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.blue500 : AppColors.blue100,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(
                  tab,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// 가격 자리에 넣을 문구. 가격이 우선이고, 없으면 용량·칼로리·카페인이 대신 온다.
String? _metaLine(PlaceMenuItem item) => item.price ?? item.specLine;

class _PlaceMenuCard extends StatelessWidget {
  const _PlaceMenuCard({required this.item});

  final PlaceMenuItem item;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 172,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageAssetPath != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.asset(
                item.imageAssetPath!,
                height: 104,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  if (item.nameEn != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.nameEn!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                  // 가격이 있으면 가격, 없으면 용량·칼로리·카페인. 둘 다 없는 카드도
                  // 있고(가격을 공개하지 않는 푸드), 그때는 이 줄을 통째로 생략한다.
                  if (_metaLine(item) != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _metaLine(item)!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: item.price != null ? 14 : 12,
                        fontWeight: item.price != null ? FontWeight.w700 : FontWeight.w600,
                        color: item.price != null ? AppColors.text : AppColors.blue500,
                      ),
                    ),
                  ],
                  if (item.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 주소·주차처럼 매장을 설명하는 운영 정보다.
///
/// 영업시간·연락처류는 이 자리에 오지 못한다. 시간이 지나면 자동으로 거짓이 되는데
/// 갱신을 보장할 방법이 없어서이고, 서버 검증기의 `forbidden_labels`가 데이터
/// 단계에서 막는다(설계 9-1).
class PlaceBusinessInfo {
  const PlaceBusinessInfo({required this.label, required this.value});

  final String label;
  final String value;
}

/// 매장 운영 정보를 라벨-값 행으로 보여 준다.
///
/// 카드 테두리 없이 구분선만 쓴다. 위쪽 summary·hero가 이미 시각적으로 묶여 있어서
/// 여기에 상자를 하나 더 두면 시트가 카드의 나열처럼 보인다.
class PlaceBusinessInfoSection extends StatelessWidget {
  const PlaceBusinessInfoSection({super.key, required this.items});

  final List<PlaceBusinessInfo> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlaceSectionTitle('매장 정보'),
        const SizedBox(height: 10),
        // 여백은 항목 사이에만 둔다. 첫·마지막 행에 붙이면 섹션 아래위가 다른
        // 섹션보다 더 벌어져서 구분선 간격이 제각각으로 보인다.
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
          ],
          _BusinessInfoRow(item: items[index]),
        ],
      ],
    );
  }
}

class _BusinessInfoRow extends StatelessWidget {
  const _BusinessInfoRow({required this.item});

  final PlaceBusinessInfo item;

  // 라벨을 왼쪽 열로 두면 값이 쓸 수 있는 폭이 72px 줄어, 주소처럼 긴 값이 두
  // 줄로 갈라진다. 라벨을 값 위 캡션으로 올려 값이 본문 폭을 그대로 쓰게 한다.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        item.label,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      const SizedBox(height: 3),
      Text(
        keepWordsWhole(item.value),
        style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.text),
      ),
    ],
  );
}

/// 영업시간·대표번호처럼 **시간이 지나면 저절로 거짓이 되는** 운영 정보다.
///
/// [PlaceBusinessInfo]와 갈라 둔 이유가 여기 있다. 저쪽은 주소처럼 잘 변하지 않는 값만
/// 담고 확인일을 붙이지 않는다 — 정보량 대비 소음만 늘기 때문이다(설계 7-A-3). 이쪽은
/// 반대로 확인일 없이는 값 자체를 믿을 수 없어서, 서버가 항목마다 확인일을 필수로 준다.
class PlaceDemoInfo {
  const PlaceDemoInfo({
    required this.label,
    required this.value,
    required this.confirmedAt,
  });

  final String label;
  final String value;
  final String confirmedAt;
}

/// 확인일이 붙은 운영 정보를 라벨-값 행으로 보여 준다.
class PlaceDemoInfoSection extends StatelessWidget {
  const PlaceDemoInfoSection({super.key, required this.items});

  final List<PlaceDemoInfo> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // 확인일이 전부 같으면 섹션 아래에 한 번만 적는다. 다섯 항목에 같은 날짜를 다섯
    // 번 적으면 읽히지 않는 소음이 되고, **다르면 묶을 수 없다** — 묶는 순간 오래된
    // 항목이 최근에 확인된 것처럼 보인다.
    final dates = {for (final item in items) item.confirmedAt};
    final sharedDate = dates.length == 1 ? dates.single : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlaceSectionTitle('영업 정보'),
        const SizedBox(height: 10),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
          ],
          _DemoInfoRow(
            item: items[index],
            showConfirmedAt: sharedDate == null,
          ),
        ],
        if (sharedDate != null) ...[
          const SizedBox(height: 10),
          Text(
            '$sharedDate 확인',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

class _DemoInfoRow extends StatelessWidget {
  const _DemoInfoRow({required this.item, required this.showConfirmedAt});

  final PlaceDemoInfo item;
  final bool showConfirmedAt;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        showConfirmedAt ? '${item.label} · ${item.confirmedAt} 확인' : item.label,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      const SizedBox(height: 3),
      Text(
        keepWordsWhole(item.value),
        style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.text),
      ),
    ],
  );
}

/// 상세 본문의 좌우 여백. 사진처럼 끝까지 채우는 섹션만 이 값을 쓰지 않는다.
const placeSectionGutter = 20.0;

/// 섹션 제목. 카드 테두리를 걷어낸 뒤로는 이 제목과 여백이 섹션 경계를 만드는
/// 유일한 장치라, 모든 섹션이 같은 굵기·크기를 쓰게 한곳에 둔다.
class PlaceSectionTitle extends StatelessWidget {
  const PlaceSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: AppColors.text,
    ),
  );
}
