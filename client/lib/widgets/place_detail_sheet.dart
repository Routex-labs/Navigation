import 'dart:async';

import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../domain/dijkstra.dart';
import '../domain/nearby_stores.dart';
import '../models/favorite_place.dart';
import '../models/place_detail.dart';
import '../models/store_index_entry.dart';
import '../repositories/place_detail_repository.dart';
import '../theme/app_theme.dart';
import 'place_detail/place_detail_hours_section.dart';
import 'place_detail/place_detail_nearby_section.dart';
import 'place_detail/place_detail_rich_sections.dart';
import 'place_detail/place_detail_sections.dart';
import 'category_icon.dart';
import 'reach_label.dart';
import 'sheet_grab_handle.dart';
import 'sheet_header.dart';

import 'map_overlay_guard.dart';
import 'map_pass_through_sheet_route.dart';

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

/// 매장 선택 시 시트가 바닥에서 화면 절반까지 한 번에 이동하므로 Material 기본
/// 250ms는 실기기에서 튀어 오르는 것처럼 보인다. 시작과 끝의 속도를 모두 낮춘
/// 곡선으로 늘려 카메라 포커스와 한 동작으로 읽히게 한다.
const kPlaceDetailSheetAnimationStyle = AnimationStyle(
  duration: Duration(milliseconds: 380),
  reverseDuration: Duration(milliseconds: 260),
  curve: Curves.easeInOutCubic,
  reverseCurve: Curves.easeInCubic,
);

/// 장소 상세 시트에서 호출자에게 돌려주는 다음 동작.
///
/// 예전에는 `viewCategory`가 하나 더 있었는데, 대분류 칩을 시트에서 걷어낸 뒤로
/// **아무도 그 값을 만들지 않았다.** 호출부에는 그 값을 받는 분기만 남아 있어,
/// 카테고리 시트가 매장 시트를 거쳐 자기 자신을 다시 여는 것처럼 읽혔다. 실제로
/// 도달할 수 없는 경로라 지운다.
enum StoreInfoAction { setOrigin, setDestination }

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
    this.nearbyStoresLoader,
    this.onSelectNearbyStore,
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

  /// 이 매장에서 가까운 다른 매장을 찾아 온다. 인자는 **이 매장의 입구 노드**다.
  ///
  /// [reach]와 **기준이 다르다** — 이쪽은 사용자가 아니라 이 매장에서 잰 거리다.
  /// 같은 기준으로 두 번 적으면 두 번째 줄이 알려 주는 게 없다.
  ///
  /// 시트가 그래프·매장 색인을 직접 들고 오지 않는 이유는, 둘 다 상위(지도 화면)가
  /// 이미 캐시해 두고 검색·경로에 쓰는 것이기 때문이다. 여기서 다시 받아 오면 같은
  /// 데이터가 두 벌이 되고, 무엇보다 시트를 테스트하려면 그래프를 만들어야 한다.
  final Future<List<NearbyStore>> Function(String entranceNodeId)?
  nearbyStoresLoader;

  /// 근처 매장 줄을 눌렀을 때. null이면 누를 수 없는 목록으로 그린다.
  final void Function(StoreIndexEntry store)? onSelectNearbyStore;

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
    Future<List<NearbyStore>> Function(String entranceNodeId)?
    nearbyStoresLoader,
    void Function(StoreIndexEntry store)? onSelectNearbyStore,
    PlaceDetailRepository? repository,
    required VoidCallback onCloseAll,
  }) {
    final navigator = Navigator.of(context);
    return navigator.push<StoreInfoAction>(
      MapPassThroughSheetRoute<StoreInfoAction>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        isScrollControlled: true,
        isDismissible: true,
        sheetAnimationStyle: kPlaceDetailSheetAnimationStyle,
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
            category: category,
            subcategory: subcategory,
            reach: reach,
            nearbyStoresLoader: nearbyStoresLoader,
            onSelectNearbyStore: onSelectNearbyStore,
            repository: repository,
            onCloseAll: onCloseAll,
          ),
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

  /// 근처 매장. 비어 있으면 섹션을 통째로 그리지 않는다.
  List<NearbyStore> _nearbyStores = const [];

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
        // 상세가 온 **뒤에** 시작한다. 근처 매장은 이 매장의 입구 노드에서 재는데,
        // 그 값이 상세 응답에 들어 있기 때문이다.
        unawaited(_loadNearbyStores(detail));
      }
    } catch (_) {
      // 상세 조회는 부가 정보다. 실패를 다이얼로그로 승격하면 길찾기를 막는다.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 근처 매장. **본문 로딩을 붙잡지 않는다** — 그래프를 받아 다익스트라를 한 번
  /// 도는 일이라, 이걸 기다리면 이미 받아 둔 소개·메뉴까지 늦게 뜬다. 목록이
  /// 준비되면 아래에 조용히 붙는다.
  Future<void> _loadNearbyStores(PlaceDetail detail) async {
    final loader = widget.nearbyStoresLoader;
    final entranceNodeId = detail.location.entranceNodeId;
    // 입구 노드가 없으면 잴 출발점이 없다. 이 매장은 길찾기 버튼도 안 나온다.
    if (loader == null || entranceNodeId == null) return;

    try {
      final nearby = await loader(entranceNodeId);
      if (mounted) setState(() => _nearbyStores = nearby);
    } catch (_) {
      // 그래프를 못 받았거나 끊겼다. 목록만 빠지고 상세는 그대로 뜬다.
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
      // **여기에 전체 화면 `GestureDetector(opaque)`를 두면 안 된다.**
      //
      // 예전에는 `DraggableScrollableSheet`를 `GestureDetector(onTap: maybePop,
      // behavior: opaque)`로 감싸 "바깥을 눌러 닫기"를 처리했다. 그런데 이 시트는
      // `isScrollControlled: true`라 라우트의 child가 **화면 전체 높이**를 차지한다.
      // 시트는 아래 절반만 그려지지만 위쪽 투명한 영역도 `opaque` 탓에 히트
      // 테스트에 걸려서, 지도가 보이는 자리의 탭·드래그가 전부 그 GestureDetector로
      // 빨려 들어갔다 — 지도는 보이는데 만질 수 없었다([MapPassThroughSheetRoute]
      // 주석의 세 겹 중 두 번째).
      //
      // 지금은 감싸지 않는다. `DraggableScrollableSheet`는 `expand: false`라
      // 시트가 실제로 그려지는 영역만 히트 테스트에 잡히고, 그 위 빈 자리는
      // 포인터를 지도로 그대로 흘린다. 시트 본문 자체는 아래 builder 안쪽의
      // `GestureDetector(onTap: () {})`가 계속 막고 있어 시트를 눌렀을 때 지도가
      // 함께 반응하는 일은 없다.
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
                // 키보드(`viewInsets`)만큼 아래를 더 비운다. 이 시트는 화면 높이의
                // 비율로 크기가 정해져서 키보드가 올라와도 **줄어들지 않는다** —
                // 아래쪽이 키보드에 덮인 채로 남는다. 그 자리에 있는 입력칸은
                // 가려지고, 스크롤로 끌어올리려 해도 스크롤할 길이가 없어서 꺼낼
                // 수가 없다. 여기서 길이를 만들어 줘야 [_MenuSearchField]가
                // 자기를 보이는 자리로 올릴 수 있다.
                padding: EdgeInsets.only(
                  bottom:
                      20 +
                      MediaQuery.paddingOf(context).bottom +
                      MediaQuery.viewInsetsOf(context).bottom,
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
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                      child: _PlaceCore(
                        title: widget.title,
                        subtitle: widget.subtitle,
                        category: widget.category,
                        subcategory: subcategory,
                        reach: widget.reach,
                      ),
                    ),
                    // 이름을 읽은 직후가 길찾기를 누르는 자리다. 사진·메뉴를
                    // 지나 하단까지 내려가야 한다면 흐름이 한 번 끊긴다.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                        padding: const EdgeInsets.only(top: 24),
                        child: PlaceDetailSections(
                          sections: sections,
                          floorLabel: _detail?.location.floorLabel,
                          homeFooter: _nearbyStores.isEmpty
                              ? null
                              : PlaceNearbySection(
                                  stores: _nearbyStores,
                                  onSelect: widget.onSelectNearbyStore,
                                ),
                        ),
                      ),
                  ],
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
  });

  final String title;
  final String subtitle;
  final String? category;
  final String? subcategory;
  final NodeReach? reach;

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
                  fontSize: 21,
                  height: 1.2,
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
                          style: TextStyle(color: AppColors.blue300),
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
class PlaceDetailSections extends StatefulWidget {
  const PlaceDetailSections({
    super.key,
    required this.sections,
    required this.floorLabel,
    this.now,
    this.homeFooter,
  });

  final List<PlaceDetailSection> sections;
  final String? floorLabel;

  /// 영업시간 판정의 기준 시각. 테스트가 넘기고 앱에서는 null이라
  /// [DateTime.now]가 쓰인다 — 시각에 의존하는 화면을 고정할 수 있어야 한다.
  final DateTime? now;

  /// 홈 탭 **맨 아래**에 붙는 블록. 근처 매장이 여기 온다.
  ///
  /// 서버 섹션 배열이 아니라 별도 인자인 이유는, 이 내용이 서버가 내려보내는 값이
  /// 아니라 **클라이언트가 그래프로 계산한 것**이기 때문이다. 섹션 배열에 섞으면
  /// "순서는 서버가 정한다"는 계약(4-2 규칙 3)이 반만 참이 된다.
  ///
  /// 메뉴·사진 탭에는 붙이지 않는다. 그쪽은 이 매장 안의 것을 보러 들어간 자리라,
  /// 옆 매장 목록이 끼면 탭을 나눈 이유가 흐려진다.
  final Widget? homeFooter;

  @override
  State<PlaceDetailSections> createState() => _PlaceDetailSectionsState();
}

/// 상단 탭 이름.
const _homeTab = '홈';
const _menuTab = '메뉴';
const _photoTab = '사진';

class _PlaceDetailSectionsState extends State<PlaceDetailSections> {
  String _activeTab = _homeTab;

  @override
  Widget build(BuildContext context) {
    final hero = widget.sections.whereType<HeroSection>().toList(
      growable: false,
    );
    final menu = widget.sections.whereType<MenuSection>().toList(
      growable: false,
    );
    final home = widget.sections
        .where((section) => section is! HeroSection && section is! MenuSection)
        .toList(growable: false);

    // 대표 사진은 탭 위에 남긴다. 어느 탭을 보고 있든 "무슨 매장인지"는 계속
    // 보여야 하고, 사진 탭은 그 사진들을 한눈에 늘어놓는 자리다.
    final photos = [
      for (final section in hero)
        for (final item in section.items) item.localAsset,
    ];

    // 있는 탭만 만든다. 탭 하나짜리 탭 바는 아무것도 나누지 않으면서 자리만
    // 차지한다(메뉴 카테고리 탭과 같은 규칙).
    final tabs = [
      if (home.isNotEmpty) _homeTab,
      if (menu.isNotEmpty) _menuTab,
      // 사진이 한 장뿐이면 위 캐러셀이 이미 다 보여 준 것이다.
      if (photos.length > 1) _photoTab,
    ];
    final tabbed = tabs.length > 1;
    final active = tabs.contains(_activeTab) ? _activeTab : tabs.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hero.isNotEmpty) ...[_render(hero), const SizedBox(height: 16)],
        if (tabbed) ...[
          _SectionTabs(
            tabs: tabs,
            active: active!,
            onSelect: (tab) => setState(() => _activeTab = tab),
          ),
          const SizedBox(height: 18),
        ],
        if (!tabbed)
          _render([...home, ...menu])
        else if (active == _menuTab)
          _render(menu)
        else if (active == _photoTab)
          PlacePhotoGrid(assetPaths: photos)
        else
          _render(home),
        // 탭이 없으면 본문이 곧 홈이므로 그때도 붙인다.
        if (widget.homeFooter != null && (!tabbed || active == _homeTab)) ...[
          const _SectionBreak(),
          widget.homeFooter!,
        ],
      ],
    );
  }

  Widget _render(List<PlaceDetailSection> sections) {
    final widgets = <Widget>[];
    for (final section in sections) {
      final rendered = switch (section) {
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
        MapSection() => PlaceMapSection(floorLabel: widget.floorLabel),
        MenuSection(:final items) => PlaceMenuSection(
          items: [
            for (final item in items)
              PlaceMenuItem(
                name: item.name,
                // group을 빠뜨리면 음료·푸드 갈래 탭이 통째로 사라진다. 화면에는
                // 아무 이상이 없어 보이고 316종이 한 목록에 이어 붙을 뿐이라,
                // 빠진 것을 알아채기 어려운 자리다.
                group: item.group,
                category: item.category,
                nameEn: item.nameEn,
                price: item.price,
                description: item.description,
                volume: item.volume,
                calories: item.calories,
                caffeine: item.caffeine,
                allergens: item.allergens,
                badges: item.badges,
                imageAssetPath: item.imageAsset,
              ),
          ],
        ),
        // 영업시간만 렌더러가 시각을 넘긴다. "지금 영업 중"은 저장된 값이 아니라
        // 그릴 때마다 계산되는 값이라, 계산의 기준 시각이 화면 밖에서 들어와야
        // 테스트가 시각에 매이지 않는다.
        HoursSection() => PlaceHoursSection(
          hours: section,
          now: widget.now ?? DateTime.now(),
        ),
        DemoInfoSection(:final items) => PlaceDemoInfoSection(
          items: [
            for (final item in items)
              PlaceDemoInfo(
                label: item.label,
                value: item.value,
                confirmedAt: item.confirmedAt,
              ),
          ],
        ),
        LinksSection(:final items) => PlaceLinksSection(
          items: [
            for (final item in items)
              PlaceLinkItem(label: item.label, url: item.url),
          ],
        ),
        BusinessInfoSection(:final items) => PlaceBusinessInfoSection(
          items: [
            for (final item in items)
              PlaceBusinessInfo(label: item.label, value: item.value),
          ],
        ),
      };
      // 사진은 시트 끝까지, 메뉴는 줄 전체가 눌리도록 스스로 여백을 갖는다.
      // 나머지 섹션만 여기서 본문 거터를 씌운다.
      final fullBleed = section is HeroSection || section is MenuSection;
      final padded = fullBleed
          ? rendered
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: placeSectionGutter,
              ),
              child: rendered,
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

/// 시트 본문을 가르는 상단 탭.
///
/// 메뉴가 30종까지 늘면서 한 줄로 이어 붙인 본문이 너무 길어졌다. 상세를 열었을 때
/// 영업시간이 보이려면 메뉴를 한참 지나쳐야 했고, 반대로 메뉴를 보려면 소개를 지나야
/// 했다. **어느 쪽을 보러 왔는지는 사람마다 다르므로** 둘을 나란히 두고 고르게 한다.
///
/// 섹션 순서는 그대로 서버가 정한다(계약 4-2 규칙 3). 클라이언트가 하는 것은 **묶는
/// 일**뿐이고, 한 탭 안에서는 서버가 보낸 순서대로 쌓는다.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
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
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(tab),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tab == active
                          ? AppColors.primary
                          : AppColors.blue100,
                      width: tab == active ? 2.5 : 1,
                    ),
                  ),
                ),
                child: Text(
                  tab,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tab == active ? AppColors.primary : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// 섹션과 섹션 사이의 경계. 여백 + 시트 폭을 가로지르는 선 한 줄이다.
class _SectionBreak extends StatelessWidget {
  const _SectionBreak();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: Divider(height: 1, thickness: 1, color: AppColors.hairline),
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
    children: [PlaceSectionTitle(title), const SizedBox(height: 8), child],
  );
}
