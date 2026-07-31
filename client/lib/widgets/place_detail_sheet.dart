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
    this.repository,
    required this.onCloseAll,
  });

  final String title;
  final String subtitle;
  final String buildingId;
  final String? placeId;
  final FavoritePlace? favorite;
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
      builder: (context) => PlaceDetailSheet(
        title: title,
        subtitle: subtitle,
        buildingId: buildingId,
        placeId: placeId,
        favorite: favorite,
        category: category,
        subcategory: subcategory,
        repository: repository,
        onCloseAll: onCloseAll,
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

  /// 코어 행이 스크롤로 가려졌는지. 이 높이를 넘어가면 이름 옆 길찾기 버튼이
  /// 화면 밖으로 나간다.
  static const _coreRowExtent = 92.0;
  static const _floatingBarHeight = 60.0;

  bool _showFloatingActions = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final shouldShow = notification.metrics.pixels > _coreRowExtent;
    if (shouldShow != _showFloatingActions) {
      setState(() => _showFloatingActions = shouldShow);
    }
    return false;
  }

  /// 길찾기 버튼은 시트 위·아래 두 곳에 있지만 반환 계약은 하나다. chain 규약을
  /// 타지 않도록 두 경로 모두 `_markIntentional`을 거친다(F5).
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
    final category = widget.category;
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
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(
                        8,
                        4,
                        8,
                        // 떠 있는 액션 바가 마지막 섹션을 가리지 않도록 그만큼 비운다.
                        _showFloatingActions ? _floatingBarHeight + 12 : 20,
                      ),
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
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                            child: _PlaceCore(
                              title: widget.title,
                              subtitle: widget.subtitle,
                              category: category,
                              subcategory: subcategory,
                              favorite: favorite,
                              isSaved: saved,
                              onToggleFavorite: _onToggleFavorite,
                              actions: _PlaceActions(
                                onOrigin: () => _pop(StoreInfoAction.setOrigin),
                                onDestination: () =>
                                    _pop(StoreInfoAction.setDestination),
                              ),
                            ),
                          ),
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(12, 24, 12, 8),
                              child: _DetailLoadingPlaceholder(),
                            )
                          else if (sections.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                              child: PlaceDetailSections(
                                sections: sections,
                                floorLabel: _detail?.location.floorLabel,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 코어 행이 위로 밀려 올라가면 길찾기 버튼이 화면에서 사라진다.
                  // 상세가 길어도 길찾기는 언제나 한 번에 눌러야 하므로(F5) 그때만
                  // 같은 버튼을 하단에 띄운다.
                  if (_showFloatingActions)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _FloatingActionBar(
                        onOrigin: () => _pop(StoreInfoAction.setOrigin),
                        onDestination: () => _pop(StoreInfoAction.setDestination),
                      ),
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

class _PlaceCore extends StatelessWidget {
  const _PlaceCore({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.subcategory,
    required this.favorite,
    required this.isSaved,
    required this.onToggleFavorite,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final String? category;
  final String? subcategory;
  final FavoritePlace? favorite;
  final bool isSaved;
  final VoidCallback onToggleFavorite;

  /// 이름 바로 오른쪽에 붙는 길찾기 버튼. 상세 로딩·실패와 무관하게 항상 그린다.
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Row(
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
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (category != null) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(label: category!),
                  ],
                  if (favorite != null) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: onToggleFavorite,
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: isSaved ? '저장 취소' : '장소로 저장',
                      icon: Icon(
                        isSaved ? Icons.check_circle : Icons.add_circle_outline,
                        color: isSaved ? Colors.green : AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                subcategory != null && category != null && subcategory != category
                    ? '$subtitle · $subcategory'
                    : subtitle,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        actions,
      ],
    );
  }
}

/// 출발·도착 한 쌍. 시트 상단(이름 옆)과 하단 고정 바가 같은 위젯을 쓴다.
class _PlaceActions extends StatelessWidget {
  const _PlaceActions({required this.onOrigin, required this.onDestination});

  final VoidCallback onOrigin;
  final VoidCallback onDestination;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CompactFilledButton(label: '출발', onPressed: onOrigin),
      const SizedBox(width: 6),
      _CompactFilledButton(label: '도착', onPressed: onDestination),
    ],
  );
}

/// 이름 옆에 두 개가 들어가야 하므로 기본 FilledButton보다 좁게 만든다.
class _CompactFilledButton extends StatelessWidget {
  const _CompactFilledButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}

/// 스크롤로 이름 옆 버튼이 가려졌을 때 시트 하단에 뜨는 같은 액션.
///
/// 본문이 비쳐 보이면 안 되므로 불투명 배경과 상단 경계선을 둔다.
class _FloatingActionBar extends StatelessWidget {
  const _FloatingActionBar({required this.onOrigin, required this.onDestination});

  final VoidCallback onOrigin;
  final VoidCallback onDestination;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('place-detail-floating-actions'),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.blue100)),
    ),
    child: Align(
      alignment: Alignment.centerRight,
      child: _PlaceActions(onOrigin: onOrigin, onDestination: onDestination),
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
        SummarySection(:final text) => PlaceSummarySection(text: text),
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
            items: [
              for (final item in items)
                PlaceBusinessInfo(label: item.label, value: item.value),
            ],
          ),
      };
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 12));
      widgets.add(widget);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: ShapeDecoration(
          color: AppColors.blue50,
          shape: StadiumBorder(
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.28)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      );
}
