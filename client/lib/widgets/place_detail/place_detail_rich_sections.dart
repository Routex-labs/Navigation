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

  /// 팝업에 보여 줄 영양정보 목록. 없는 값은 빠진다.
  ///
  /// 푸드에는 이 정보가 아예 없어서 빈 목록이 된다. 그때 팝업은 이 블록을 통째로
  /// 생략한다 — 라벨만 있고 값이 빈 표를 그리면 "정보가 없다"가 아니라 "불러오지
  /// 못했다"로 읽힌다.
  List<(String, String)> get nutritionFacts => [
    if (price != null && price!.isNotEmpty) ('가격', price!),
    if (volume != null && volume!.isNotEmpty) ('용량', volume!),
    if (calories != null && calories!.isNotEmpty) ('칼로리', calories!),
    if (caffeine != null && caffeine!.isNotEmpty) ('카페인', caffeine!),
  ];

  /// 팝업을 열 만한 내용이 있는가.
  ///
  /// 없으면 카드를 누를 수 없게 만든다. 눌렀는데 카드에 이미 있는 이름만 다시
  /// 나오는 팝업은 막다른 길이고, 한 번 겪으면 다음 카드도 안 누르게 된다.
  bool get hasDetail => nutritionFacts.isNotEmpty || (description?.isNotEmpty ?? false);
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
          height: _menuListHeight(context),
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

const _menuCardWidth = 172.0;
const _menuImageHeight = 104.0;
const _menuCardPadding = 12.0;
const _menuNameSize = 14.0;
const _menuNameEnSize = 11.0;
const _menuNameGap = 2.0;

/// 카드 글자의 줄 높이. **두 곳에서 같은 값을 써야 해서 상수로 뽑는다** — 아래
/// [_menuListHeight]가 이 값으로 카드 높이를 계산하고, 카드가 이 값으로 글자를
/// 그린다. 둘이 어긋나면 그 차이가 그대로 넘침이 된다.
///
/// `TextStyle.height`를 비워 두면 줄 높이가 글꼴 메트릭에서 나와 기기·글꼴마다
/// 달라진다. 계산과 실제가 어긋나는 원인이 여기였다.
const _menuTextLineHeight = 1.25;

/// 카드 목록의 높이. **상수로 박지 않고 글자 배율에서 계산한다.**
///
/// 예전에는 230으로 박아 뒀는데, 기기의 글자 크기 설정이 커지면 안쪽 텍스트가 그
/// 높이를 넘어 `BOTTOM OVERFLOWED BY N PIXELS`가 떴다. 여백을 넉넉히 주는 것으로
/// 넘어가면 배율을 더 키운 기기에서 같은 일이 다시 생긴다 — 배율을 실제로 읽어서
/// 필요한 만큼 잡는 쪽이 이 실패를 없앤다.
double _menuListHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  // 글자는 이름·영문명 두 줄뿐이다. 줄 높이를 위에서 못 박아 뒀으므로 이 계산은
  // 추정이 아니라 실제 값이다. 소수점은 올려서 반올림 차이로 1px 넘치는 것을 막는다.
  final textBlock =
      scaler.scale(_menuNameSize) * _menuTextLineHeight +
      _menuNameGap +
      scaler.scale(_menuNameEnSize) * _menuTextLineHeight;
  return (_menuImageHeight + _menuCardPadding * 2 + textBlock).ceilToDouble();
}

/// 메뉴 카드 한 장. 사진 + 이름 + 영문명까지만 싣는다.
///
/// 용량·칼로리·카페인을 카드에서 뺀 이유는 **카드가 고르는 자리이기 때문**이다.
/// 30장을 옆으로 넘기면서 읽는 화면에서 숫자 세 개는 이름을 가리는 노이즈였고,
/// 정작 그 숫자가 궁금해지는 건 하나를 고른 다음이다. 그래서 나머지는 팝업으로
/// 옮겼다([_MenuDetailDialog]).
class _PlaceMenuCard extends StatelessWidget {
  const _PlaceMenuCard({required this.item});

  final PlaceMenuItem item;

  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageAssetPath != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: Image.asset(
                    item.imageAssetPath!,
                    height: _menuImageHeight,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                // 누를 수 있다는 표시. 줄을 하나 더 쓰지 않으려고 사진 위에 얹는다 —
                // 표시가 없으면 팝업이 있다는 걸 아무도 모른다.
                if (item.hasDetail)
                  const Positioned(
                    right: 6,
                    top: 6,
                    child: _MenuDetailBadge(),
                  ),
              ],
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(_menuCardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: _menuNameSize,
                      height: _menuTextLineHeight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.nameEn != null) ...[
                    const SizedBox(height: _menuNameGap),
                    Text(
                      item.nameEn!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: _menuNameEnSize,
                        height: _menuTextLineHeight,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: _menuCardWidth,
      child: item.hasDetail
          ? GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _MenuDetailDialog(item: item),
              ),
              child: card,
            )
          : card,
    );
  }
}

class _MenuDetailBadge extends StatelessWidget {
  const _MenuDetailBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      shape: BoxShape.circle,
    ),
    child: const Padding(
      padding: EdgeInsets.all(3),
      child: Icon(Icons.info_outline, size: 14, color: Colors.white),
    ),
  );
}

/// 메뉴 하나의 상세. 카드에서 뺀 설명과 영양정보가 여기 모인다.
///
/// 시트가 아니라 다이얼로그인 이유는 **뒤로가기 규약**(설계 F5) 때문이다. 상세 시트는
/// 자기 라우트가 pop되면 `onCloseAll`로 시트 묶음 전체를 닫는데, 그 위에 시트를 하나
/// 더 쌓으면 뒤로가기 한 번이 어디까지 닫는지가 흐려진다. 다이얼로그는 별도 라우트라
/// 뒤로가기가 팝업만 닫고 상세 시트는 그대로 남는다.
class _MenuDetailDialog extends StatelessWidget {
  const _MenuDetailDialog({required this.item});

  final PlaceMenuItem item;

  @override
  Widget build(BuildContext context) {
    final facts = item.nutritionFacts;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageAssetPath != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: Image.asset(
                    item.imageAssetPath!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    if (item.nameEn != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.nameEn!,
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                    if (item.description != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        keepWordsWhole(item.description!),
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                    // 푸드에는 영양정보가 없다. 라벨만 남은 빈 표를 그리면 "정보가
                    // 없다"가 아니라 "못 불러왔다"로 읽히므로 블록째 생략한다.
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      for (var index = 0; index < facts.length; index++) ...[
                        if (index > 0) const Divider(height: 17),
                        _NutritionRow(label: facts[index].$1, value: facts[index].$2),
                      ],
                    ],
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
    ],
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
