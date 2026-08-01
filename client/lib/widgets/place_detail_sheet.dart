import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/favorite_place.dart';
import '../models/place_detail.dart';
import '../repositories/place_detail_repository.dart';
import '../theme/app_theme.dart';
import 'place_detail/place_detail_rich_sections.dart';
import 'place_detail/place_detail_sections.dart';
import 'sheet_grab_handle.dart';
import 'sheet_header.dart';

import 'map_overlay_guard.dart';

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
    this.subcategory,
    this.repository,
    required this.onCloseAll,
  });

  final String title;
  final String subtitle;
  final String buildingId;
  final String? placeId;
  final FavoritePlace? favorite;
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
    String? subcategory,
    PlaceDetailRepository? repository,
    required VoidCallback onCloseAll,
  }) {
    return showModalBottomSheet<StoreInfoAction>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
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
          subcategory: subcategory,
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
  List<PlaceDetailSection> get _visibleSections =>
      _isExcluded ? const [] : (_detail?.sections ?? const []);

  /// 길찾기 버튼은 하단 고정 바 한 곳에만 있다. chain 규약을 타지 않도록
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
    final saved = favorite != null && favoritesController.contains(favorite.key);
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
          initialChildSize: 0.58,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SheetGrabHandle(),
                          SheetHeader(
                            onCloseAll: widget.onCloseAll,
                            onIntentionalPop: _markIntentional,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                            child: _PlaceCore(
                              title: widget.title,
                              subtitle: widget.subtitle,
                              subcategory: subcategory,
                              favorite: favorite,
                              isSaved: saved,
                              onToggleFavorite: _onToggleFavorite,
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
                  // 상세가 아무리 길어도 길찾기는 한 번에 눌러야 한다(F5). 스크롤에
                  // 따라 나타났다 사라지는 대신 처음부터 하단에 고정해 둔다.
                  _StickyActionBar(
                    onOrigin: () => _pop(StoreInfoAction.setOrigin),
                    onDestination: () => _pop(StoreInfoAction.setDestination),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 시트 최상단의 이름·층·업종 블록.
///
/// 길찾기 버튼을 하단으로 내렸기 때문에 제목이 가로폭을 거의 다 쓴다. 대분류
/// 칩(`category`)은 층 아래 `subcategory`와 같은 축의 정보라 중복이어서 뺐다.
class _PlaceCore extends StatelessWidget {
  const _PlaceCore({
    required this.title,
    required this.subtitle,
    required this.subcategory,
    required this.favorite,
    required this.isSaved,
    required this.onToggleFavorite,
  });

  final String title;
  final String subtitle;
  final String? subcategory;
  final FavoritePlace? favorite;
  final bool isSaved;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final hasSubcategory = subcategory != null && subcategory!.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.blue50,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.storefront, color: AppColors.primary, size: 22),
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
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasSubcategory ? '$subtitle · $subcategory' : subtitle,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (favorite != null) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onToggleFavorite,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            tooltip: isSaved ? '저장 취소' : '장소로 저장',
            icon: Icon(
              isSaved ? Icons.check_circle : Icons.add_circle_outline,
              color: isSaved ? AppColors.success : AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// 시트 하단에 항상 붙어 있는 출발·도착 바.
///
/// 본문이 비쳐 보이면 안 되므로 불투명 배경과 상단 경계선을 둔다. 홈 인디케이터
/// 위로 겹치지 않도록 하단 safe area를 패딩에 더한다.
class _StickyActionBar extends StatelessWidget {
  const _StickyActionBar({required this.onOrigin, required this.onDestination});

  final VoidCallback onOrigin;
  final VoidCallback onDestination;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const ValueKey('place-detail-actions'),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.blue100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: onOrigin,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue50,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('출발'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: onDestination,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('도착'),
            ),
          ),
        ],
      ),
    );
  }
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
    // 소개와 매장 정보는 둘 다 "이 매장이 뭔지" 설명하는 글이라 한 덩어리로 묶는다.
    // 서버가 summary를 businessInfo 바로 앞에 놓아 주므로, 여기서는 제목을
    // 소개 쪽에 한 번만 붙이고 businessInfo의 제목을 끈다.
    final hasSummary = sections.any((section) => section is SummarySection);
    final hasBusinessInfo =
        sections.any((section) => section is BusinessInfoSection);
    final groupSummary = hasSummary && hasBusinessInfo;

    final widgets = <Widget>[];
    PlaceDetailSection? previous;
    for (final section in sections) {
      final widget = switch (section) {
        SummarySection(:final text) => _TitledSection(
            // 매장 정보가 없으면 소개 문단만 제목 없이 떠 버리므로 제 이름을 준다.
            title: groupSummary ? '매장 정보' : '소개',
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
        NoticeSection(:final text, :final until) =>
          PlaceNoticeSection(text: text, until: until),
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
            showTitle: !groupSummary,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: placeSectionGutter),
              child: widget,
            );
      if (widgets.isNotEmpty) {
        // 같은 묶음 안(소개 → 매장 정보)은 좁게, 다른 섹션 사이는 넓게. 테두리를
        // 걷어낸 뒤로는 섹션을 나누는 게 여백뿐이라 이 차이가 곧 그룹핑이다.
        final sameGroup = groupSummary &&
            previous is SummarySection &&
            section is BusinessInfoSection;
        widgets.add(SizedBox(height: sameGroup ? 12 : 24));
      }
      widgets.add(padded);
      previous = section;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

/// 제목 + 본문 한 쌍. 섹션 위젯 자체가 제목을 갖지 않는 경우(소개)에 씌운다.
class _TitledSection extends StatelessWidget {
  const _TitledSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PlaceSectionTitle(title),
      const SizedBox(height: 8),
      child,
    ],
  );
}
