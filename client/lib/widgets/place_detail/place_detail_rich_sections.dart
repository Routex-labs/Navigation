import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                padding: const EdgeInsets.symmetric(
                  horizontal: placeSectionGutter,
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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
    this.allergens,
    this.badges = const <String>[],
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

  /// 알레르기 유발 성분. 공식 사이트 문구 그대로인 한 줄(`대두 / 우유`)이다.
  final String? allergens;

  /// NEW·시즌 한정처럼 줄에 붙는 표시. 없으면 빈 목록이다.
  final List<String> badges;

  final String? imageAssetPath;

  /// 팝업에 보여 줄 영양정보 목록. 없는 값은 빠진다.
  ///
  /// 푸드에는 이 정보가 아예 없어서 빈 목록이 된다. 그때 팝업은 이 블록을 통째로
  /// 생략한다 — 라벨만 있고 값이 빈 표를 그리면 "정보가 없다"가 아니라 "불러오지
  /// 못했다"로 읽힌다.
  ///
  /// **알레르기가 이 목록의 맨 아래다.** 용량·칼로리와 같은 표에 두는 이유는 값이
  /// 같은 성격(라벨-값 한 줄)이라서고, 맨 아래인 이유는 이 값만 없는 항목이 많아
  /// (음료 122/198, 푸드 0) 중간에 끼면 표의 줄 수가 항목마다 들쭉날쭉해지기
  /// 때문이다.
  List<(String, String)> get nutritionFacts => [
    if (price != null && price!.isNotEmpty) ('가격', price!),
    if (volume != null && volume!.isNotEmpty) ('용량', volume!),
    if (calories != null && calories!.isNotEmpty) ('칼로리', calories!),
    if (caffeine != null && caffeine!.isNotEmpty) ('카페인', caffeine!),
    if (allergens != null && allergens!.isNotEmpty) ('알레르기', allergens!),
  ];

  /// 팝업을 열 만한 내용이 있는가.
  ///
  /// 없으면 카드를 누를 수 없게 만든다. 눌렀는데 카드에 이미 있는 이름만 다시
  /// 나오는 팝업은 막다른 길이고, 한 번 겪으면 다음 카드도 안 누르게 된다.
  ///
  /// 배지는 세지 않는다. 배지는 이미 줄에 그려져 있어서, 그것만 있는 항목의 팝업은
  /// 여는 사람이 이미 본 것만 다시 보여 준다 — 상세를 못 받은 4종이 정확히 그렇다.
  bool get hasDetail =>
      nutritionFacts.isNotEmpty || (description?.isNotEmpty ?? false);
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
        : widget.items
              .where((item) => item.group == activeGroup)
              .toList(growable: false);

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
        : matched
              .where((item) => item.category == active)
              .toList(growable: false);

    final capped = !_expanded && visible.length > _menuVisibleCap;
    final shown = capped
        ? visible.take(_menuVisibleCap).toList(growable: false)
        : visible;

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
            padding: EdgeInsets.fromLTRB(
              placeSectionGutter,
              14,
              placeSectionGutter,
              6,
            ),
            child: Text(
              '찾는 메뉴가 없습니다',
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ),
        // 세로 목록이라 스크롤을 따로 갖지 않는다. 시트 본문이 이미 스크롤이고,
        // 그 안에 또 스크롤을 넣으면 어느 쪽이 움직일지가 손끝에서 갈린다.
        for (final item in shown) _MenuRow(item: item),
        if (capped) _MenuMoreRow(onTap: () => setState(() => _expanded = true)),
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
                // 배지는 이름 **아래** 줄이다. 옆에 붙이면 이름이 그만큼 짧게
                // 잘리는데, 316종 중 배지가 붙는 건 32종뿐이라 나머지 284종의
                // 이름 자리를 소수를 위해 내주는 셈이 된다.
                if (item.badges.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final badge in item.badges) _MenuBadge(label: badge),
                    ],
                  ),
                ],
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

/// `NEW`·`시즌 한정` 같은 표시 하나.
///
/// **아이콘이 아니라 글자다.** 공식 사이트가 이미지 배지로 주는 값이지만, 그 이미지를
/// 그대로 번들에 넣으면 상표를 한 벌 더 들여오는 셈이고 배지 종류가 늘 때마다 사진을
/// 다시 받아야 한다. 글자면 값이 무엇이 오든 그려진다.
///
/// 색은 종류로 갈리지 않는다. 지금 데이터의 배지는 `NEW` 31건·`시즌 한정` 5건 둘뿐인데,
/// 여기서 이름으로 색을 나누면 처음 보는 배지가 왔을 때 그릴 색이 없어진다.
/// 배지 한 종류의 색. 배경·테두리·글자를 함께 들고 다닌다 — 셋을 따로 고르면
/// 대비가 어긋난 조합이 조용히 만들어진다.
class BadgeTone {
  const BadgeTone({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

/// 모르는 배지가 왔을 때의 색. **이 값이 있어야 색을 종류별로 나눌 수 있다** —
/// 스타벅스가 새 배지를 만들면(예: "한정 판매") 그리지 못하는 것이 아니라 무채색으로
/// 떨어진다. 색은 정보를 더하는 장치이지 그리기 위한 조건이 아니다.
const _badgeToneDefault = BadgeTone(
  background: Color(0xFFF3F4F6),
  border: Color(0xFFE0E3E7),
  foreground: AppColors.muted,
);

/// 배지 이름 → 색. 둘 다 연한 배경 + 진한 글자(tonal)라 사진 옆에서 튀지 않는다.
///
/// 갈라 놓는 이유는 **한 줄에 둘이 나란히 뜨는 항목이 있기 때문이다.** 같은 색이면
/// 두 배지가 한 덩어리로 읽힌다. 초록은 새로 나온 것, 주황은 기간이 정해진 것으로
/// 쓴다 — 빨강을 쓰지 않는 것은 앱에서 이미 오류·목적지에 배정된 색이라 뜻이
/// 겹치기 때문이다.
/// 키는 아래 [badgeToneFor]가 쓰는 정규화된 형태(공백 제거·대문자)로 적는다.
const _badgeTones = <String, BadgeTone>{
  'NEW': BadgeTone(
    background: Color(0xFFE8F5EC),
    border: Color(0xFFC6E6D0),
    foreground: Color(0xFF1E7B45),
  ),
  '시즌한정': BadgeTone(
    background: Color(0xFFFDF0E7),
    border: Color(0xFFF7D9C2),
    foreground: Color(0xFFB4600F),
  ),
};

/// 배지 색을 고른다. 공백을 지우고 대문자로 맞춰 찾는 이유는 수집 원본이 `NEW`와
/// `New`, `시즌 한정`과 `시즌한정`을 섞어 쓸 수 있어서다 — 표기 하나가 달라졌다고
/// 색이 조용히 사라지면 원인을 찾기 어렵다. 화면에 그리는 글자는 원본 그대로다.
BadgeTone badgeToneFor(String label) =>
    _badgeTones[label.replaceAll(' ', '').toUpperCase()] ?? _badgeToneDefault;

class _MenuBadge extends StatelessWidget {
  const _MenuBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = badgeToneFor(label);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tone.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: tone.foreground,
          ),
        ),
      ),
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

class _MenuSearchFieldState extends State<_MenuSearchField>
    with WidgetsBindingObserver {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final _focusNode = FocusNode();

  /// 포커스는 받았는데 키보드가 아직 안 올라온 상태. 이때 스크롤하면 **지금 비어
  /// 있는 자리**를 기준으로 계산해서, 키보드가 올라온 뒤 다시 가려진다.
  var _revealPending = false;

  /// 마지막 빌드에서 본 키보드 높이. [build]가 기록한다.
  var _keyboardInset = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) return;
    // 이미 다른 입력칸을 쓰다 넘어온 경우라 키보드가 떠 있다. 기다릴 것이 없다.
    if (_keyboardInset > 0) {
      _reveal();
    } else {
      _revealPending = true;
    }
  }

  /// 키보드가 실제로 올라온 순간을 여기서 잡는다.
  ///
  /// 고정 지연(`Future.delayed`)으로 맞추지 않는 이유는 그 값이 기기·키보드마다 다른
  /// 애니메이션 길이를 추측한 숫자이기 때문이다 — 느린 기기에서 먼저 스크롤해 버리면
  /// 아무 일도 없어 보인다.
  ///
  /// 키보드는 **화면(view)의 메트릭**이라 이 콜백으로 온다. `didChangeDependencies`로
  /// 잡으려다 실패했는데, 이 위젯을 감싸는 MediaQuery가 바뀌지 않기 때문이다 —
  /// 바뀌는 것은 그 위의 화면이고 MediaQuery는 그 값을 옮겨 담을 뿐이다.
  @override
  void didChangeMetrics() {
    if (!_revealPending) return;
    // 메트릭 콜백은 프레임 밖에서 오고 MediaQuery는 다음 빌드에 갱신되므로,
    // 값을 보는 것도 스크롤하는 것도 다음 프레임에 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_revealPending) return;
      if (MediaQuery.viewInsetsOf(context).bottom <= 0) return;
      _revealPending = false;
      _reveal();
    });
  }

  /// 검색창을 화면 위쪽으로 올린다. 끝에 붙이지 않고 조금 띄우는(0.08) 이유는
  /// 검색이 결과를 보려고 하는 일이라, 입력칸만 보이고 아래가 키보드면 친 보람이
  /// 없기 때문이다.
  void _reveal() {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.08,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // **여기서 읽어야 한다.** MediaQuery 의존은 빌드마다 새로 등록되고 리빌드 직전에
    // 비워지므로, 포커스 리스너 안에서만 읽으면 그 등록이 다음 리빌드에 지워져
    // 키보드가 올라와도 [didChangeDependencies]가 오지 않는다. 화면에 쓰지 않는
    // 값을 굳이 빌드에서 읽는 이유가 이것이다.
    _keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
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
                  focusNode: _focusNode,
                  onChanged: widget.onChanged,
                  style: const TextStyle(fontSize: 14, color: AppColors.text),
                  // 상태별 테두리를 **전부** 끈다. `border`만 끄면 포커스됐을 때
                  // 테마의 focusedBorder(파랑 1.5px)가 살아나 알약 테두리가 뜬다 —
                  // `border`는 기본 상태의 테두리일 뿐이고 상태별 값이 우선한다.
                  // 이 칸은 이미 바깥 상자가 배경·모서리를 갖고 있어서, 안쪽에 또
                  // 테두리가 그려지면 상자 안에 상자가 생긴다. `filled`도 같은
                  // 이유로 끈다(테마가 채우면 바깥 상자 위에 한 겹 더 칠한다).
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
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

/// 메뉴 사진의 가로÷세로. 번들에 든 316장이 전부 300×313이라 그 값을 그대로 쓴다.
///
/// **썸네일을 이 비율로 잡는 이유는 자르지 않기 위해서다.** 정사각으로 넣으면 비율이
/// 0.96인 사진의 위아래가 잘려 컵이 뭉툭해진다. 배경색으로 여백을 채우는 방식은 못 쓴다 —
/// 사진 배경이 제품마다 다크그린·크림색으로 갈리고 단색이 아닌 것도 있다.
///
/// 30종일 때는 402×420이었다. 전량 316종은 공식 목록 페이지의 같은 사진을 받은 것이라
/// 해상도가 300×313으로 바뀌었고, 비율은 0.957 → 0.958로 사실상 같다. **비율이 다른
/// 사진이 섞여 들어오면 `BoxFit.contain`이 남는 쪽을 여백으로 남긴다** — 잘리지는
/// 않지만 줄마다 사진 크기가 달라 보인다. 그때는 이 상수가 아니라 사진을 맞춘다.
const _menuImageAspect = 300 / 313;

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
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  // 카드와 같은 이유로 비율을 사진에 맞춘다. 높이를 200으로 박아
                  // 두면 폭이 340이라 세로를 60% 넘게 잘라냈다 — 메뉴를 자세히
                  // 보려고 연 팝업에서 정작 사진이 제일 많이 잘렸다.
                  child: AspectRatio(
                    aspectRatio: _menuImageAspect,
                    child: Image.asset(
                      item.imageAssetPath!,
                      fit: BoxFit.contain,
                    ),
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
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
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
                        _NutritionRow(
                          label: facts[index].$1,
                          value: facts[index].$2,
                        ),
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
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      // **값을 Flexible로 감싼다.** 용량·칼로리는 `355ml`처럼 짧아서 한 줄에 남지만
      // 알레르기는 `땅콩 / 대두 / 우유 / 알류 / 밀 / 오징어`처럼 27자까지 온다.
      // 감싸지 않으면 팝업 폭(340)을 넘겨 RenderFlex 오버플로가 난다.
      Flexible(
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: AppColors.text,
            ),
          ),
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

/// 링크 줄 왼쪽 배지의 모양.
///
/// **브랜드 favicon을 번들에 넣지 않는다.** 로고 파일을 담는 순간 저작권 정리 대상이
/// 메뉴 사진과 같아지고, 원격 favicon URL은 시트 첫 프레임이 네트워크를 기다리게 해서
/// 설계 9-1 D1′이 금지한 것과 같은 문제가 된다. 그래서 Material 아이콘을 그대로 쓰되
/// **브랜드 색만** 입힌다 — 색은 로고가 아니라서 담을 것이 없다.
class PlaceLinkBrand {
  const PlaceLinkBrand({required this.icon, required this.colors});

  final IconData icon;

  /// 배지 바탕색. 한 색이면 단색, 여러 색이면 좌상→우하 그라데이션이다.
  /// 인스타그램처럼 브랜드 자체가 그라데이션인 곳이 있어 목록으로 받는다.
  final List<Color> colors;
}

/// 라벨로 고른 브랜드 배지. 모르는 라벨에도 배지를 준다 — 라벨 글자가 항상 옆에
/// 있어서 아이콘이 뜻을 혼자 짊어지지 않는다([infoIconFor]와 다른 점).
PlaceLinkBrand linkBrandFor(String label) =>
    switch (label.replaceAll(' ', '')) {
      '공식사이트' || '홈페이지' || '웹사이트' => const PlaceLinkBrand(
        icon: Icons.public,
        colors: [Color(0xFF3C4043)],
      ),
      '페이스북' => const PlaceLinkBrand(
        icon: Icons.facebook,
        colors: [Color(0xFF1877F2)],
      ),
      '인스타그램' => const PlaceLinkBrand(
        icon: Icons.camera_alt,
        colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
      ),
      '스마트스토어' || '네이버' || '스토어' => const PlaceLinkBrand(
        icon: Icons.storefront,
        colors: [Color(0xFF03C75A)],
      ),
      _ => const PlaceLinkBrand(icon: Icons.link, colors: [AppColors.muted]),
    };

/// 라벨 대신 주소를 보여 줄 줄인가.
///
/// **차례가 아니라 라벨로 판단한다.** 참고 화면에서 주소가 보이는 것은 그 줄이 첫
/// 줄이어서가 아니라 웹사이트 줄이어서다 — `공식 사이트`라는 라벨은 어느 사이트인지를
/// 말해 주지 않지만 `페이스북`·`인스타그램`은 라벨이 곧 정체다. 순서로 정하면 배열
/// 순서를 바꿨을 때 뜻 없이 화면이 따라 바뀐다.
bool isWebsiteLabel(String label) => switch (label.replaceAll(' ', '')) {
  '공식사이트' || '홈페이지' || '웹사이트' => true,
  _ => false,
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
        const PlaceSectionTitle('SNS'),
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: infoRowGap),
          _LinkRow(
            item: items[index],
            onTap: () => _open(context, items[index]),
          ),
        ],
      ],
    );
  }
}

/// 링크 한 줄 — 브랜드 배지 · 라벨(또는 주소) · 오른쪽 `>`.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.item, required this.onTap});

  final PlaceLinkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 라벨이 비어 있어도 줄이 빈 채로 남지 않게 주소로 대신한다. 라벨은 사람이
    // 쓰는 자유 문자열이라 언제든 빠질 수 있다.
    final showUrl = isWebsiteLabel(item.label) || item.label.trim().isEmpty;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          _LinkBadge(brand: linkBrandFor(item.label)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              showUrl ? item.url : item.label,
              // **한 줄 말줄임이고, 자르는 곳은 뒤다.** 주소는 앞쪽(호스트)이 어디로
              // 가는지를 말하고 뒤쪽(경로)은 그렇지 않다. 두 줄로 흘리면 줄 높이가
              // 항목마다 달라져 목록이 아니라 글 덩어리로 읽힌다.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                // 주소만 링크 색이다. 이 줄이 글자가 아니라 주소라는 표시.
                color: showUrl ? AppColors.primary : AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 참고 화면을 따라 `>`를 쓴다. 앱 밖으로 나간다는 사실은 브랜드 배지와
          // (웹사이트 줄에서는) 주소가 대신 알려 준다.
          const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// 브랜드 색 원 안에 Material 아이콘 하나.
class _LinkBadge extends StatelessWidget {
  const _LinkBadge({required this.brand});

  final PlaceLinkBrand brand;

  @override
  Widget build(BuildContext context) {
    final colors = brand.colors;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // LinearGradient는 색이 두 개 이상이어야 해서 단색이면 같은 색을 겹친다.
        gradient: LinearGradient(
          colors: colors.length == 1 ? [colors.first, colors.first] : colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(brand.icon, size: 17, color: Colors.white),
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
  // 고객센터는 수화기가 아니라 상담원 아이콘이다. 같은 전화번호라도 "이 매장에
  // 건다"와 "본사 콜센터에 건다"는 다른 일이고, 둘을 같은 글리프로 그리면 화면이
  // 그 차이를 지운다. 아이콘만으로는 부족해서 이 줄은 라벨 글자도 함께 남긴다
  // ([PlaceInfoRow.keepLabel]).
  '고객센터' => Icons.support_agent_outlined,
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
    this.keepLabel = false,
    this.copyText,
  });

  final String label;
  final String value;

  /// 값 아래 작은 글씨(확인일 등). 없으면 그리지 않는다.
  final String? caption;

  /// 아이콘이 있어도 라벨 글자를 남긴다.
  ///
  /// 기본은 아이콘이 라벨을 대신하는 것이고, 그 전제는 "아이콘이 라벨을 정확히
  /// 가리킨다"였다. 라벨 자체가 **값의 뜻을 바꾸는** 줄에서는 그 전제가 깨진다 —
  /// `고객센터 1522-3232`에서 `고객센터`를 지우면 남은 것은 매장 직통 번호처럼
  /// 읽히고, 그건 정보가 줄어든 게 아니라 틀린 정보가 된 것이다.
  final bool keepLabel;

  /// 값 옆 '복사' 버튼이 클립보드에 담을 문자열. null이면 버튼을 그리지 않는다.
  ///
  /// 값 전체가 아니라 **복사할 만한 토막**만 받는다. `1522-3232 (평일 09:00–18:00)`을
  /// 통째로 복사하면 전화 앱에 붙여 넣을 수 없다.
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    final icon = infoIconFor(label);
    final copyText = this.copyText;

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
              if (icon == null || keepLabel) ...[
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 3),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      keepWordsWhole(value),
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  // 복사 버튼은 값 **바로 옆**이다. 줄 오른쪽 끝에 붙이면 값이 짧을
                  // 때 무엇을 복사하는 버튼인지가 멀어진다.
                  if (copyText != null) _CopyButton(text: copyText),
                ],
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

/// 값 옆에 붙는 '복사' 버튼.
///
/// 아이콘 대신 글자를 쓴다. 전화번호 옆의 겹친 사각형 글리프는 "저장"·"공유"로도
/// 읽히는데, 잘못 눌러도 잃는 게 없는 동작이라 아이콘 수수께끼를 낼 이유가 없다.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});

  final String text;

  // 클립보드는 실패할 수 있다. 웹은 브라우저 권한을, 리눅스는 클립보드 매니저를
  // 타고, 둘 다 없으면 플랫폼 채널이 예외를 던진다. 조용히 삼키면 사용자는
  // 복사된 줄 알고 붙여 넣기를 시도하므로, 실패를 실패라고 말한다.
  Future<void> _copy(BuildContext context) async {
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      copied = false;
    }
    if (!context.mounted) return;
    showPlaceToast(context, copied ? '복사했습니다' : '복사하지 못했습니다');
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _copy(context),
    behavior: HitTestBehavior.opaque,
    child: Semantics(
      button: true,
      label: '$text 복사',
      child: const Padding(
        // 글자만으로는 손가락이 닿을 자리가 안 나온다. 여백으로 세로 26·가로 42를
        // 만든다.
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          '복사',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    ),
  );
}

/// 화면 아래쪽에 잠깐 떠 있다 사라지는 알림.
///
/// **`ScaffoldMessenger`의 SnackBar를 쓰지 않는다.** 상세 시트는 `Navigator`에 얹힌
/// 모달 라우트라 화면 아래 절반을 덮는데, SnackBar를 그리는 `Scaffold`는 그 **아래**에
/// 있다. 즉 시트 안에서 띄운 SnackBar는 시트에 가려 보이지 않는다. 여기서는 루트
/// `Overlay` 맨 위에 직접 끼워 시트보다 앞에 그린다.
///
/// 포인터는 [IgnorePointer]로 통과시킨다. 1.6초짜리 알림이 그동안 시트의 탭을
/// 가로채면 안 된다.
///
/// **토스트는 화면에 한 개만 둔다.** 엔트리와 타이머를 모듈 수준에서 들고
/// 있다가, 새 토스트가 뜨는 순간 이전 것을 즉시 걷어낸다. 예전에는 취소
/// 불가능한 `Future.delayed`가 해제를 맡았는데, 그 시점에 `entry.mounted`가
/// false면 remove를 다시 시도하지 않아 토스트가 오버레이에 영원히 남았고,
/// 연속 호출은 엔트리를 겹겹이 쌓기만 했다.
OverlayEntry? _placeToastEntry;
Timer? _placeToastTimer;

void showPlaceToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _dismissPlaceToast();

  final entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 40,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  _placeToastEntry = entry;
  overlay.insert(entry);
  _placeToastTimer = Timer(
    const Duration(milliseconds: 1600),
    _dismissPlaceToast,
  );
}

/// 떠 있는 토스트를 확실히 걷어낸다. 실패 경로가 없다 — 여기 들어오는 엔트리는
/// 전부 [showPlaceToast]가 insert한 것이고, [OverlayEntry.remove]는 Overlay가
/// 이미 dispose된 뒤에도 안전하게 no-op으로 끝난다. 제거 후 참조를 비우므로
/// 같은 엔트리를 두 번 remove할 일도 없다.
void _dismissPlaceToast() {
  _placeToastTimer?.cancel();
  _placeToastTimer = null;
  final entry = _placeToastEntry;
  _placeToastEntry = null;
  entry?.remove();
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

/// 전화번호가 들어 있는 줄인가.
///
/// **값이 아니라 라벨로 먼저 거른다.** 값만 보고 판단하면 영업시간 줄의
/// `2026-08-10`이나 층 안내의 `B2-1` 같은 토막에 복사 버튼이 붙는다.
bool isPhoneLabel(String label) => switch (label.replaceAll(' ', '')) {
  '고객센터' || '대표번호' || '전화번호' || '연락처' || '문의' => true,
  _ => false,
};

/// 값에서 전화번호로 보이는 첫 토막. 없으면 null이고, 그때는 복사 버튼도 없다.
///
/// 값은 `1522-3232 (평일 09:00–18:00)`처럼 번호 뒤에 부연이 붙는다. 통째로 복사하면
/// 전화 앱에 붙여 넣을 수 없으므로 번호만 떼어 낸다.
String? phoneNumberIn(String value) =>
    _phonePattern.firstMatch(value)?.group(0);

final _phonePattern = RegExp(r'\d{2,4}-\d{3,4}(?:-\d{4})?');

/// 확인일이 붙은 운영 정보를 라벨-값 행으로 보여 준다.
class PlaceDemoInfoSection extends StatelessWidget {
  const PlaceDemoInfoSection({super.key, required this.items});

  final List<PlaceDemoInfo> items;

  Widget _row(PlaceDemoInfo item, String? sharedDate) {
    final isPhone = isPhoneLabel(item.label);
    return PlaceInfoRow(
      label: item.label,
      value: item.value,
      // 전화 줄만 라벨을 남긴다. 누가 받는 번호인지는 아이콘이 말해 주지 못하고,
      // 그 한 단어가 빠지면 값의 뜻이 달라진다.
      keepLabel: isPhone,
      copyText: isPhone ? phoneNumberIn(item.value) : null,
      // 확인일이 제각각일 때만 항목마다 붙인다. 묶을 수 없기 때문이다.
      caption: sharedDate == null ? '${item.confirmedAt} 확인' : null,
    );
  }

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
          _row(items[index], sharedDate),
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
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
  );
}
