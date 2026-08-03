import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../domain/dijkstra.dart';
import '../domain/nearby_facilities.dart';
import '../models/favorite_place.dart';
import '../models/place_detail.dart';
import '../repositories/place_detail_repository.dart';
import '../theme/app_theme.dart';
import 'place_detail/place_detail_rich_sections.dart';
import 'place_detail/place_detail_sections.dart';
import 'category_icon.dart';
import 'reach_label.dart';
import 'sheet_grab_handle.dart';
import 'sheet_header.dart';

import 'map_overlay_guard.dart';

/// 매장 상세 시트가 처음 올라오는 높이(화면 비율).
///
/// 이름·업종·길찾기 버튼에 **사진과 소개 앞부분까지**가 들어오는 선이다. 더
/// 올리면 정보는 많이 보이지만 지도가 거의 안 남아, 방금 고른 매장이 건물
/// 어디쯤인지 확인할 수 없다. 나머지는 시트를 끌어올려 본다.
///
/// **이 값은 지도 카메라와 짝을 이룬다.** 목록에서 매장을 고르면 지도가 그
/// 매장으로 이동하는데, 시트가 덮는 만큼 위로 밀어 올려야 매장이 시트 뒤에
/// 숨지 않는다. 그래서 상수를 공개해 `MapShellScreen`이 그대로 지도에 넘긴다 —
/// 여기만 바꾸면 카메라도 따라온다.
const double kPlaceDetailSheetInitialSize = 0.5;

/// 장소 상세 시트에서 호출자에게 돌려주는 다음 동작.
///
/// 호출부의 출발·도착·카테고리 시트 chain 계약은 기존과 동일하게 유지한다.
enum StoreInfoAction { setOrigin, setDestination, viewCategory }

/// 매장 상세 시트.
///
/// 이름·층·카테고리와 길찾기 버튼은 이미 검색 결과에 있으므로 즉시 표시한다.
/// 실패하거나 [placeId]가 없는 기존 저장 장소에서는 조용히 본문만 비운다.
class PlaceDetailSheet extends StatefulWidget {
  const PlaceDetailSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buildingId,
    required this.placeId,
    this.favorite,
    this.category,
    this.subcategory,
    this.reach,
    this.facilities = const [],
    this.repository,
    required this.onCloseAll,
  });

  final String title;
  final String subtitle;
  final String buildingId;
  final String? placeId;
  final FavoritePlace? favorite;

  /// 현재 위치에서 이 매장까지의 거리·비용. 상위(MapShellScreen)가 검색 결과
  /// 목록과 **같은 계산 결과**를 그대로 넘긴다 — 목록에 74m라고 적혀 있는데
  /// 눌러 들어온 상세가 다른 값을 말하면 어느 쪽도 못 믿게 된다.
  ///
  /// null이면 줄을 그리지 않는다. 위치를 아직 안 잡았거나 그래프가 끊긴
  /// 경우이고, 그 상태에서 "거리 알 수 없음"을 적어 봐야 사용자가 할 수 있는
  /// 일은 "위치 지정" 하나뿐이라 이 자리에서 알릴 이유가 없다.
  final NodeReach? reach;

  /// 이 매장에서 가장 가까운 화장실·엘리베이터. 비어 있으면 줄을 그리지 않는다.
  ///
  /// [reach]와 **기준이 다르다** — 이쪽은 사용자가 아니라 이 매장에서 잰 거리다.
  /// 같은 기준으로 두 번 적으면 두 번째 줄이 알려 주는 게 없다.
  final List<NearbyFacility> facilities;

  /// 헤더 아이콘의 대분류 폴백·강조색. 세부 규칙(`카페·베이커리` 등)이 먼저고,
  /// 거기 걸리지 않는 일반 매장이 이 값으로 떨어진다.
  final String? category;
  final String? subcategory;

  /// 테스트에서는 가짜를 넣고, 앱에서는 service locator의 전역 저장소를 쓴다.
  final PlaceDetailRepository? repository;
  final VoidCallback onCloseAll;

  static Future<StoreInfoAction?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String buildingId,
    required String? placeId,
    FavoritePlace? favorite,
    String? category,
    String? subcategory,
    NodeReach? reach,
    List<NearbyFacility> facilities = const [],
    PlaceDetailRepository? repository,
    required VoidCallback onCloseAll,
  }) {
    return showModalBottomSheet<StoreInfoAction>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      // 시트 뒤 지도를 어둡게 덮지 않는다. 목록에서 매장을 고르면 지도가 그
      // 매장으로 이동하는데, 기본 barrier(검정 54%)가 깔리면 정작 확인하러 온
      // 그 매장이 어둠 속에 있다. 바깥을 눌러 닫는 동작은 시트 본문의
      // GestureDetector가 그대로 처리하므로 잃는 기능은 없다.
      barrierColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => MapOverlayGuard(
        child: PlaceDetailSheet(
          title: title,
          subtitle: subtitle,
          buildingId: buildingId,
          placeId: placeId,
          favorite: favorite,
          category: category,
          subcategory: subcategory,
          reach: reach,
          facilities: facilities,
          repository: repository,
          onCloseAll: onCloseAll,
        ),
      ),
    );
  }

  @override
  State<PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<PlaceDetailSheet> {
  bool _intentionalPop = false;
  bool _isLoading = false;

  /// 위젯이 아니라 응답 모델을 들고 있는다. `kind`(excluded 판정)와 `provenance`
  /// (출처 노출)를 build 시점에 봐야 하기 때문이다 — 설계 7-A-3·7-A-4.
  PlaceDetail? _detail;

  /// 주차·에스컬레이터·엘리베이터 1,007건. 서버가 404 대신 `excluded`로 200을
  /// 주고, "시트를 열지 말지"는 클라이언트가 이 값만 보고 정한다(설계 4-1).
  /// 분류 규칙을 클라이언트에 심지 않기 위한 계약이라, 여기서 카테고리 문자열을
  /// 다시 판정하지 않는다.
  bool get _isExcluded => _detail?.kind == PlaceKind.excluded;

  /// 본문에 그릴 섹션. excluded면 비운다.
  ///
  /// `map`은 걸러 낸다. 지도 미리보기가 아직 없어서 층 이름만 적힌 블록인데,
  /// 그 층은 헤더 배지에 이미 있다. 누를 수도 없는 중복이라 자리만 차지했다.
  /// 서버 계약은 그대로 두고 화면에서만 뺀다 — 지도 이동을 붙이는 날 되살린다.
  List<PlaceDetailSection> get _visibleSections => _isExcluded
      ? const []
      : (_detail?.sections ?? const [])
            .where((section) => section is! MapSection)
            .toList();

  /// 길찾기 버튼은 이름 바로 아래 한 곳에만 있다. chain 규약을 타지 않도록
  /// `_markIntentional`을 거친다(F5).
  void _pop(StoreInfoAction action) {
    _markIntentional();
    Navigator.of(context).pop(action);
  }

  @override
  void initState() {
    super.initState();
    favoritesController.addListener(_onFavoritesChanged);
    _loadDetailContent();
  }

  @override
  void dispose() {
    favoritesController.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _markIntentional() => _intentionalPop = true;

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDetailContent() async {
    final placeId = widget.placeId;
    if (placeId == null) return;

    setState(() => _isLoading = true);
    try {
      final detail = await (widget.repository ?? placeDetailRepository)
          .getPlaceDetail(widget.buildingId, placeId);
      if (mounted && detail != null) {
        setState(() => _detail = detail);
      }
    } catch (_) {
      // 상세 조회는 부가 정보다. 실패를 다이얼로그로 승격하면 길찾기를 막는다.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onToggleFavorite() async {
    final favorite = widget.favorite;
    if (favorite == null) return;
    await favoritesController.toggle(favorite);
    if (!mounted) return;
    final saved = favoritesController.contains(favorite.key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? '장소에 저장했습니다' : '저장을 취소했습니다'),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favorite = widget.favorite;
    final saved =
        favorite != null && favoritesController.contains(favorite.key);
    final subcategory = widget.subcategory;
    final sections = _visibleSections;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: DraggableScrollableSheet(
          initialChildSize: kPlaceDetailSheetInitialSize,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) => GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Material(
              color: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ScrollConfiguration(
                behavior: const _NoOverscrollIndicator(),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    bottom: 20 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SheetGrabHandle(),
                      SheetHeader(
                        onCloseAll: widget.onCloseAll,
                        onIntentionalPop: _markIntentional,
                        // 저장은 눌러도 시트가 그대로 남는 유일한 버튼이라 길찾기와
                        // 같은 줄에 두지 않는다([SheetHeader.trailing] 주석).
                        trailing: favorite == null
                            ? null
                            : _SaveToggle(
                                isSaved: saved,
                                onPressed: _onToggleFavorite,
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: _PlaceCore(
                          title: widget.title,
                          subtitle: widget.subtitle,
                          category: widget.category,
                          subcategory: subcategory,
                          reach: widget.reach,
                          facilities: widget.facilities,
                        ),
                      ),
                      // 이름을 읽은 직후가 길찾기를 누르는 자리다. 사진·메뉴를
                      // 지나 하단까지 내려가야 한다면 흐름이 한 번 끊긴다.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: _PlaceActions(
                          onOrigin: () => _pop(StoreInfoAction.setOrigin),
                          onDestination: () =>
                              _pop(StoreInfoAction.setDestination),
                        ),
                      ),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                          child: _DetailLoadingPlaceholder(),
                        )
                      else if (sections.isNotEmpty)
                        Padding(
                          // 좌우 여백은 섹션이 스스로 갖는다. 사진·메뉴는
                          // 시트 끝까지 써야 해서 여기서 일괄로 줄 수 없다.
                          padding: const EdgeInsets.only(top: 20),
                          child: PlaceDetailSections(
                            sections: sections,
                            floorLabel: _detail?.location.floorLabel,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 시트 최상단의 아이콘·이름·층·업종 블록.
///
/// 왼쪽 아이콘은 카테고리 칩·카테고리 매장 목록과 같은 [storeIconFor] 규칙을
/// 쓴다. 목록에서 보던 글리프가 상세에서도 같은 자리에 있어야 "방금 누른 그것"이
/// 이어진다. 한때 이 자리에 있던 건 모든 매장에 똑같이 붙는 storefront 하나라
/// 알려 주는 게 없었는데, 지금은 대분류 폴백이 있어 매장마다 달라진다.
///
/// 층은 배지가 아니라 업종 줄 앞의 pill이다. 44px 정사각형은 로고 자리로 읽혀서
/// 텍스트를 넣으면 브랜드 마크처럼 오독된다.
class _PlaceCore extends StatelessWidget {
  const _PlaceCore({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.subcategory,
    required this.reach,
    required this.facilities,
  });

  final String title;
  final String subtitle;
  final String? category;
  final String? subcategory;
  final NodeReach? reach;
  final List<NearbyFacility> facilities;

  @override
  Widget build(BuildContext context) {
    final label = subcategoryLabelFor(subcategory);
    final reach = this.reach;
    final hasFloor = subtitle.isNotEmpty;
    final accent = category == null
        ? AppColors.primary
        : categoryColorFor(category!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Icon(
            storeIconFor(
              name: title,
              subcategory: subcategory,
              category: category,
            ),
            size: 22,
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                // 긴 이름은 잘라내기 전에 두 줄까지 준다. 그 이상은 헤더 높이가
                // 튀어서 본문 첫 화면을 먹는다.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              // 층도 업종도 없으면 줄 자체를 만들지 않는다 — 빈 줄이 제목 아래
              // 여백만 늘린다.
              if (hasFloor || label != null) ...[
                const SizedBox(height: 5),
                // 층·구분점·업종을 위젯 세 개로 나열하지 않고 한 문장으로 그린다.
                // 위젯으로 나누면 사이 간격을 padding 상수로 찍어야 하는데, 그
                // 값이 글자 사이 자연스러운 간격과 어긋나 층만 동떨어져 보였다.
                // 하나의 텍스트로 두면 간격을 폰트가 정한다.
                Text.rich(
                  TextSpan(
                    children: [
                      if (hasFloor)
                        TextSpan(
                          text: subtitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      if (hasFloor && label != null)
                        const TextSpan(
                          text: ' · ',
                          style: TextStyle(color: AppColors.blue100),
                        ),
                      if (label != null) TextSpan(text: label),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: AppColors.muted,
                  ),
                ),
              ],
              // "어디인가" 다음 줄이 "어떻게 닿는가"다. 목록에서 이미 본 값을
              // 상세에서도 같은 자리에 두어, 눌러 들어온 뒤 다시 찾지 않게 한다.
              if (reach != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.directions_walk,
                      size: 14,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        reachLabel(reach),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // 이 매장에서 가장 가까운 시설. 위 거리 줄과 **기준이 다르므로**
              // ("나 → 매장"과 "매장 → 시설") 아이콘과 문구로 구분한다.
              for (final facility in facilities) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      switch (facility.kind) {
                        FacilityKind.restroom => Icons.wc,
                        FacilityKind.elevator => Icons.elevator,
                      },
                      size: 14,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${facility.kind.label} ${facility.reach.distanceM.round()}m',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 본문 끝에서 내용이 늘어나는 overscroll 표시를 끈다.
///
/// 이 시트는 스크롤 제스처를 이미 두 가지로 쓰고 있다 — 위로 끌면 시트가 커지고,
/// 끝에서 아래로 끌면 닫힌다([DraggableScrollableSheet]). 거기에 끝에서 내용이
/// 늘어나는 표시까지 겹치면 "아직 더 볼 게 남았다"는 잘못된 신호가 된다.
///
/// **표시만 끄고 물리는 건드리지 않는다.** 스크롤 physics를 바꾸면 시트를
/// 끌어 키우고 줄이는 동작 자체가 이 스크롤의 overscroll에 얹혀 있어서 함께 깨진다.
class _NoOverscrollIndicator extends MaterialScrollBehavior {
  const _NoOverscrollIndicator();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// 이름 바로 아래에 놓는 출발·도착 한 줄.
///
/// 길찾기는 이 시트의 목적이라 사진·메뉴보다 먼저 눈에 닿아야 한다. 저장은
/// 여기 없다 — 눌러도 시트가 남는 유일한 버튼이라 헤더로 갔다
/// ([SheetHeader.trailing] 주석).
///
/// **바닥 고정 바로 옮겨 본 적이 있는데 되돌렸다.** 스크롤 위치와 무관하게
/// 닿는다는 이점보다, 두 자짜리 버튼이 늘 화면 바닥을 한 줄 차지하는 부담이
/// 컸다. 같은 이유로 폭도 가로에 맞춰 늘리지 않는다 — 글자가 두 자뿐이라
/// 늘리면 여백만 커진다. 왼쪽에 붙여 한 쌍으로 읽히게 둔다.
class _PlaceActions extends StatelessWidget {
  const _PlaceActions({required this.onOrigin, required this.onDestination});

  final VoidCallback onOrigin;
  final VoidCallback onDestination;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('place-detail-actions'),
    children: [
      FilledButton(
        onPressed: onOrigin,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue50,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        ),
        child: const Text('출발'),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: onDestination,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        ),
        child: const Text('도착'),
      ),
    ],
  );
}

/// 헤더 우측의 저장 토글.
///
/// 예전에는 본문 액션 줄에서 "저장"/"저장됨" 글자를 달고 있었고, 그 주석은
/// 아이콘만으로 짐작하게 두지 않으려는 것이라고 적고 있었다. 헤더는 자리가
/// 아이콘 폭뿐이라 글자를 뗀다. **그 자리를 세 가지로 메운다** — 채움/윤곽으로
/// 저장 여부를 구분하고, tooltip을 달고, 누른 결과를 스낵바가 문장으로 알린다.
/// 셋 중 하나라도 빠지면 글자를 뗀 것이 그냥 후퇴가 된다.
class _SaveToggle extends StatelessWidget {
  const _SaveToggle({required this.isSaved, required this.onPressed});

  final bool isSaved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('place-detail-save'),
    tooltip: isSaved ? '저장 취소' : '장소에 저장',
    onPressed: onPressed,
    icon: Icon(
      isSaved ? Icons.bookmark : Icons.bookmark_border,
      size: 22,
      color: isSaved ? AppColors.primary : AppColors.muted,
    ),
  );
}

class _DetailLoadingPlaceholder extends StatelessWidget {
  const _DetailLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('place-detail-loading'),
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.blue50,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

/// 닫힌 섹션 집합을 화면 위젯으로 바꾼다. 모델 파싱 단계에서 모르는 type은 이미
/// 버려졌지만, 여기서도 타입별로만 분기해 새 서버 섹션이 길찾기 UI를 깨지 않게 한다.
class PlaceDetailSections extends StatelessWidget {
  const PlaceDetailSections({
    super.key,
    required this.sections,
    required this.floorLabel,
  });

  final List<PlaceDetailSection> sections;
  final String? floorLabel;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (final section in sections) {
      final widget = switch (section) {
        SummarySection(:final text) => _TitledSection(
          title: '소개',
          child: PlaceSummarySection(text: text),
        ),
        HeroSection(:final items) => PlaceHeroCarousel(
          images: [
            for (final item in items)
              PlaceHeroImage(assetPath: item.localAsset),
          ],
        ),
        KeyValueSection(:final items) => PlaceKeyValueSection(
          items: [
            for (final item in items)
              PlaceKeyValue(label: item.label, value: item.value),
          ],
        ),
        TagsSection(:final tags) => PlaceTagsSection(tags: tags),
        NoticeSection(:final text, :final until) => PlaceNoticeSection(
          text: text,
          until: until,
        ),
        MapSection() => PlaceMapSection(floorLabel: floorLabel),
        MenuSection(:final items) => PlaceMenuSection(
          items: [
            for (final item in items)
              PlaceMenuItem(
                name: item.name,
                price: item.price,
                description: item.description,
                imageAssetPath: item.imageAsset,
              ),
          ],
        ),
        BusinessInfoSection(:final items) => PlaceBusinessInfoSection(
          items: [
            for (final item in items)
              PlaceBusinessInfo(label: item.label, value: item.value),
          ],
        ),
      };
      // 사진은 시트 끝까지, 메뉴는 가로 스크롤이 끝까지 흐르도록 스스로 여백을
      // 갖는다. 나머지 섹션만 여기서 본문 거터를 씌운다.
      final fullBleed = section is HeroSection || section is MenuSection;
      final padded = fullBleed
          ? widget
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: placeSectionGutter,
              ),
              child: widget,
            );
      // 여백만으로는 섹션이 어디서 끝났는지 읽히지 않는다. 카드로 감싸는 대신
      // 시트 폭을 가로지르는 얇은 선 하나로만 끊는다.
      if (widgets.isNotEmpty) widgets.add(const _SectionBreak());
      widgets.add(padded);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

/// 섹션과 섹션 사이의 경계. 여백 + 시트 폭을 가로지르는 선 한 줄이다.
class _SectionBreak extends StatelessWidget {
  const _SectionBreak();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Divider(height: 1, thickness: 1, color: AppColors.blue100),
  );
}

/// 제목 + 본문 한 쌍. 섹션 위젯 자체가 제목을 갖지 않는 경우(소개)에 씌운다.
class _TitledSection extends StatelessWidget {
  const _TitledSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [PlaceSectionTitle(title), const SizedBox(height: 10), child],
  );
}
