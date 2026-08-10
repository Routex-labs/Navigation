import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// 사진 탭. 대표 사진들을 두 칸 격자로 늘어놓는다.
///
/// 위 캐러셀과 **같은 사진들**이다. 캐러셀은 한 장씩 넘겨야 해서 몇 장이 있는지·어떤
/// 것이 있는지가 한눈에 안 들어오고, 격자는 그 반대다. 둘 중 하나만 두지 않는 이유는
/// 역할이 달라서다 — 캐러셀은 "무슨 매장인지"를 알려 주고, 격자는 "사진을 보러 온"
/// 사람을 위한 자리다.
class PlacePhotoGrid extends StatelessWidget {
  const PlacePhotoGrid({super.key, required this.assetPaths});

  final List<String> assetPaths;

  @override
  Widget build(BuildContext context) {
    if (assetPaths.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
      child: GridView.builder(
        // 시트 본문이 이미 스크롤이라 격자는 스스로 스크롤하지 않는다.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: assetPaths.length,
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          // 매장 사진은 크기가 제각각이라 비율을 맞출 수 없다. 격자는 칸이 정사각으로
          // 고정되므로 여기서는 `cover`로 채운다 — 메뉴 사진과 달리 잘려도 무엇을
          // 찍은 사진인지 알아볼 수 있다.
          child: Image.asset(assetPaths[index], fit: BoxFit.cover),
        ),
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
    this.group,
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
  final String? group;
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

/// 등장 순서대로 값을 뽑는다. 나눌 것이 없으면 빈 목록.
///
/// **한 항목이라도 값이 없으면 나누지 않는다.** 가진 것만 탭에 넣으면 나머지 항목은
/// 어느 탭에서도 보이지 않는데, 화면에는 아무 이상이 없어 보인다. 메뉴가 조용히
/// 사라지는 쪽이 한 줄로 길게 늘어놓는 것보다 나쁘다.
///
/// 값이 한 종류뿐일 때도 만들지 않는다. 누를 곳이 하나뿐인 탭은 아무것도 나누지
/// 않으면서 자리만 차지한다.
List<String> _distinctInOrder(
  List<PlaceMenuItem> items,
  String? Function(PlaceMenuItem) pick,
) {
  final values = <String>[];
  for (final item in items) {
    final value = pick(item);
    if (value == null || value.isEmpty) return const <String>[];
    if (!values.contains(value)) values.add(value);
  }
  return values.length > 1 ? values : const <String>[];
}

/// 탭으로 쓸 카테고리. 화면·테스트가 함께 쓴다.
List<String> menuCategoryTabs(List<PlaceMenuItem> items) =>
    _distinctInOrder(items, (item) => item.category);

/// 위쪽 갈래(음료·푸드).
List<String> menuGroupTabs(List<PlaceMenuItem> items) =>
    _distinctInOrder(items, (item) => item.group);

class _PlaceMenuSectionState extends State<PlaceMenuSection> {
  String? _activeGroup;
  String? _activeTab;
  String _query = '';

  /// 더보기를 눌러 전부 펼친 상태. 갈래·탭을 옮기거나 검색어를 바꾸면 다시 접는다 —
  /// 자리마다 펼침 상태를 따로 들고 있으면, 돌아왔을 때 어디까지 펼쳤는지 기억나지
  /// 않는 목록이 열려 있다.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final groups = menuGroupTabs(widget.items);
    final activeGroup = groups.contains(_activeGroup)
        ? _activeGroup
        : groups.firstOrNull;
    final inGroup = activeGroup == null
        ? widget.items
        : widget.items.where((item) => item.group == activeGroup).toList(growable: false);

    // 검색은 갈래 안에서만 한다. 음료를 보다가 친 검색어에 푸드가 섞여 나오면
    // 갈래를 고른 일이 무효가 된다.
    final searching = _query.trim().isNotEmpty;
    final matched = searching ? _search(inGroup, _query) : inGroup;

    // 검색 중에는 카테고리 탭을 숨긴다. 검색 결과가 여러 카테고리에 걸치는데 탭이
    // 남아 있으면 "지금 뭘 보고 있는지"가 두 곳에서 다르게 말해진다.
    final tabs = searching ? const <String>[] : menuCategoryTabs(matched);
    final active = tabs.contains(_activeTab) ? _activeTab : tabs.firstOrNull;
    final visible = active == null
        ? matched
        : matched.where((item) => item.category == active).toList(growable: false);

    final capped = !_expanded && visible.length > _menuVisibleCap;
    final shown = capped ? visible.take(_menuVisibleCap).toList(growable: false) : visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: placeSectionGutter),
          child: PlaceSectionTitle('메뉴'),
        ),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MenuGroupTabs(
            tabs: groups,
            active: activeGroup!,
            onSelect: (group) => setState(() {
              _activeGroup = group;
              _activeTab = null;
              _expanded = false;
            }),
          ),
        ],
        // 검색창은 메뉴가 한 화면에 안 들어올 때만 의미가 있다. 열 줄도 안 되는
        // 목록에서는 눈으로 훑는 편이 빠르고, 입력창만 자리를 차지한다.
        if (widget.items.length >= _menuSearchThreshold) ...[
          const SizedBox(height: 12),
          _MenuSearchField(
            value: _query,
            onChanged: (value) => setState(() {
              _query = value;
              _expanded = false;
            }),
          ),
        ],
        if (tabs.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MenuCategoryTabs(
            tabs: tabs,
            active: active!,
            onSelect: (tab) => setState(() {
              _activeTab = tab;
              _expanded = false;
            }),
          ),
        ],
        const SizedBox(height: 6),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(placeSectionGutter, 14, placeSectionGutter, 6),
            child: Text(
              '찾는 메뉴가 없습니다',
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ),
        // 세로 목록이라 스크롤을 따로 갖지 않는다. 시트 본문이 이미 스크롤이고,
        // 그 안에 또 스크롤을 넣으면 어느 쪽이 움직일지가 손끝에서 갈린다.
        for (final item in shown) _MenuRow(item: item),
        if (capped)
          _MenuMoreRow(onTap: () => setState(() => _expanded = true)),
      ],
    );
  }
}

/// 검색창을 붙이는 최소 메뉴 수.
const _menuSearchThreshold = 20;

/// 이름·영문명으로 찾는다. 공백을 지우고 대소문자를 무시한다.
///
/// 설명까지 뒤지지 않는 이유는 결과가 설명 안의 흔한 낱말에 끌려다니기 때문이다 —
/// "커피"를 치면 설명에 커피가 들어간 거의 모든 음료가 나와서 걸러 주는 게 없다.
List<PlaceMenuItem> _search(List<PlaceMenuItem> items, String query) {
  String norm(String value) => value.replaceAll(' ', '').toLowerCase();
  final needle = norm(query);
  return items
      .where(
        (item) =>
            norm(item.name).contains(needle) ||
            norm(item.nameEn ?? '').contains(needle),
      )
      .toList(growable: false);
}

/// 메뉴 한 줄. 왼쪽에 이름·설명·가격, 오른쪽에 사진.
///
/// 글을 왼쪽에 둔 이유는 **읽는 순서** 때문이다. 사람은 왼쪽부터 읽는데 사진이 앞에
/// 있으면 이름을 보려고 눈이 한 번 건너뛴다. 사진은 이름을 확인한 뒤 "그래서 뭐가
/// 나오는데"에 답하는 자리라 오른쪽이 맞다.
///
/// **영문명은 줄에서 뺐다.** 한 줄에 이름·영문명·설명·가격이 다 오면 무엇이 제목인지
/// 흐려진다. 영문명은 골라서 팝업을 연 사람에게만 필요하다.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final PlaceMenuItem item;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: placeSectionGutter,
        vertical: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: AppColors.text,
                  ),
                ),
                if (item.description != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                // 가격이 있으면 설명 아래. 지금 데이터에는 없어서 그려지지 않는다 —
                // 공식 사이트가 가격을 공개하지 않아 지어내는 대신 비워 뒀다.
                if (item.price != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.price!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.imageAssetPath != null) ...[
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                item.imageAssetPath!,
                width: _menuThumbWidth,
                height: _menuThumbHeight,
                // 카드와 같은 이유로 원본 비율을 지킨다(설계 7-A-2).
                fit: BoxFit.contain,
              ),
            ),
          ],
        ],
      ),
    );

    if (!item.hasDetail) return row;

    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _MenuDetailDialog(item: item),
      ),
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}

/// 목록 끝의 "더보기". 누르면 그 자리에서 나머지가 펼쳐진다.
///
/// 개수를 적지 않는 이유는 그 숫자가 판단에 쓰이지 않기 때문이다. "6종"을 보고 누를지
/// 말지를 정하는 사람은 없고, 눌러서 나온 목록에 이미 전부 있다.
class _MenuMoreRow extends StatelessWidget {
  const _MenuMoreRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: placeSectionGutter,
        vertical: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '더보기',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.expand_more, size: 20, color: AppColors.primary),
        ],
      ),
    ),
  );
}

/// 위쪽 갈래(음료·푸드) 선택. 카테고리 탭보다 굵게 두어 위계를 드러낸다.
class _MenuGroupTabs extends StatelessWidget {
  const _MenuGroupTabs({
    required this.tabs,
    required this.active,
    required this.onSelect,
  });

  final List<String> tabs;
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
    child: Row(
      children: [
        for (final tab in tabs)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: GestureDetector(
              onTap: () => onSelect(tab),
              behavior: HitTestBehavior.opaque,
              child: Text(
                tab,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: tab == active ? FontWeight.w800 : FontWeight.w500,
                  color: tab == active ? AppColors.text : AppColors.muted,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// 메뉴 이름으로 좁히는 검색창.
class _MenuSearchField extends StatefulWidget {
  const _MenuSearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends State<_MenuSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.blue50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.search, size: 19, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: widget.onChanged,
                style: const TextStyle(fontSize: 14, color: AppColors.text),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '메뉴 검색',
                  hintStyle: TextStyle(fontSize: 14, color: AppColors.muted),
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (widget.value.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _controller.clear();
                  widget.onChanged('');
                },
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 18, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    ),
  );
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

/// 메뉴 사진의 가로÷세로. 번들에 든 30장이 전부 402×420이라 그 값을 그대로 씁니다.
///
/// **썸네일을 이 비율로 잡는 이유는 자르지 않기 위해서다.** 정사각으로 넣으면 비율이
/// 0.96인 사진의 위아래가 잘려 컵이 뭉툭해진다. 배경색으로 여백을 채우는 방식은 못 쓴다 —
/// 사진 배경이 다크그린 18장, 크림색 12장으로 갈리고 그중 4장은 단색도 아니다.
const _menuImageAspect = 402 / 420;

/// 목록 썸네일 크기. 한 줄에 사진·이름·설명이 같이 들어가야 해서 작게 잡는다.
const _menuThumbWidth = 76.0;
final _menuThumbHeight = (_menuThumbWidth / _menuImageAspect).ceilToDouble();

/// 한 카테고리에서 접힌 상태로 보여 주는 줄 수. 넘는 만큼은 "더보기" 뒤로 보낸다.
///
/// 세로 목록이라 줄이 늘어날수록 다른 섹션(영업 정보·매장 정보)이 화면 밖으로 밀린다.
/// 상한을 두면 상세를 처음 열었을 때 어떤 섹션들이 있는지가 한눈에 들어오고, 메뉴를
/// 더 볼 사람만 펼치면 된다.
const _menuVisibleCap = 4;

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
                  // 카드와 같은 이유로 비율을 사진에 맞춘다. 높이를 200으로 박아
                  // 두면 폭이 340이라 세로를 60% 넘게 잘라냈다 — 메뉴를 자세히
                  // 보려고 연 팝업에서 정작 사진이 제일 많이 잘렸다.
                  child: AspectRatio(
                    aspectRatio: _menuImageAspect,
                    child: Image.asset(item.imageAssetPath!, fit: BoxFit.contain),
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

/// 매장 운영 정보를 아이콘-값 행으로 보여 준다.
///
/// 카드 테두리 없이 여백만 쓴다. 위쪽 summary·hero가 이미 시각적으로 묶여 있어서
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
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: infoRowGap),
          PlaceInfoRow(label: items[index].label, value: items[index].value),
        ],
      ],
    );
  }
}

/// 공식 채널 링크 하나.
class PlaceLinkItem {
  const PlaceLinkItem({required this.label, required this.url});

  final String label;
  final String url;
}

/// 라벨을 대신하는 링크 아이콘. 매핑에 없으면 `null`이고, 그때는 일반 링크 아이콘을 쓴다.
///
/// 정보 행([infoIconFor])과 달리 여기서는 모르는 라벨에도 아이콘을 준다. 라벨 글자가
/// 항상 함께 보이기 때문에 아이콘이 뜻을 혼자 짊어지지 않는다.
IconData linkIconFor(String label) => switch (label.replaceAll(' ', '')) {
  '공식사이트' || '홈페이지' || '웹사이트' => Icons.language_outlined,
  '페이스북' => Icons.facebook_outlined,
  '인스타그램' => Icons.camera_alt_outlined,
  '스마트스토어' || '네이버' || '스토어' => Icons.storefront_outlined,
  _ => Icons.link_outlined,
};

/// 공식 채널 링크 목록. 누르면 외부 브라우저로 연다.
class PlaceLinksSection extends StatelessWidget {
  const PlaceLinksSection({super.key, required this.items});

  final List<PlaceLinkItem> items;

  // 열기에 실패하면 조용히 넘기지 않는다. 눌렀는데 아무 일도 일어나지 않으면
  // 사용자는 앱이 멈춘 줄 안다 — 실패했다는 사실만이라도 알려 준다.
  Future<void> _open(BuildContext context, PlaceLinkItem item) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(item.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.label}을(를) 열지 못했습니다'),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlaceSectionTitle('링크'),
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: infoRowGap),
          GestureDetector(
            onTap: () => _open(context, items[index]),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  linkIconFor(items[index].label),
                  size: 19,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[index].label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.text,
                    ),
                  ),
                ),
                // 이 줄이 앱 밖으로 나간다는 표시. 화살표(>)를 쓰면 앱 안의 다음
                // 화면으로 읽힌다.
                const Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 정보 행 사이 간격. 행마다 구분선을 긋지 않는 이유는 6줄짜리 목록이 표처럼
/// 보이면서 시트 전체가 글 덩어리로 읽히기 때문이다. 섹션 경계는 이미
/// `_SectionBreak`가 긋고 있어서 행 사이까지 그을 필요가 없다.
const infoRowGap = 14.0;

/// 라벨을 대신하는 아이콘. 없으면 `null`이고, 그때는 라벨을 글자로 남긴다.
///
/// **모르는 라벨에 기본 아이콘을 물리지 않는다.** 아이콘이 라벨을 대신할 수 있는
/// 것은 그 아이콘이 라벨을 정확히 가리킬 때뿐이고, 아무 아이콘이나 붙이면 값이
/// 무슨 뜻인지가 화면에서 사라진다. 데이터는 사람이 쓰는 자유 문자열이라
/// 언제든 새 라벨이 들어온다.
IconData? infoIconFor(String label) => switch (label.replaceAll(' ', '')) {
  '영업시간' || '운영시간' => Icons.schedule_outlined,
  '대표번호' || '전화번호' || '연락처' || '문의' => Icons.call_outlined,
  '매장타입' || '매장유형' => Icons.storefront_outlined,
  '주차' => Icons.local_parking_outlined,
  '위생등급' => Icons.verified_outlined,
  '주소' || '위치' => Icons.place_outlined,
  '홈페이지' || '웹사이트' => Icons.language_outlined,
  _ => null,
};

/// 아이콘 + 값 한 줄. 아이콘이 라벨을 대신하므로 라벨 글자가 사라진다.
///
/// 라벨을 값 위 캡션으로 올렸던 이전 배치는 한 항목이 두 줄을 썼다. 항목이 여섯
/// 개면 열두 줄이라 시트가 글 덩어리로 읽혔다. 아이콘은 가로 24px만 쓰고 값이
/// 본문 폭을 그대로 받으므로, 같은 내용이 절반 높이에 들어간다.
class PlaceInfoRow extends StatelessWidget {
  const PlaceInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.caption,
  });

  final String label;
  final String value;

  /// 값 아래 작은 글씨(확인일 등). 없으면 그리지 않는다.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final icon = infoIconFor(label);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 아이콘은 첫 줄 글자의 중앙에 맞춘다. 위쪽 정렬만 하면 값이 두 줄일 때
        // 아이콘이 글자보다 살짝 떠 보인다.
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon ?? Icons.circle,
            size: icon == null ? 5 : 19,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 아이콘이 라벨을 대신하지 못할 때만 라벨을 글자로 남긴다.
              if (icon == null) ...[
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                keepWordsWhole(value),
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.text,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  caption!,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
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
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: infoRowGap),
          PlaceInfoRow(
            label: items[index].label,
            value: items[index].value,
            // 확인일이 제각각일 때만 항목마다 붙인다. 묶을 수 없기 때문이다.
            caption: sharedDate == null ? '${items[index].confirmedAt} 확인' : null,
          ),
        ],
        if (sharedDate != null) ...[
          const SizedBox(height: 12),
          Text(
            '$sharedDate 확인',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ],
    );
  }
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
