import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/favorite_place.dart';
import '../state/favorites_controller.dart';
import '../theme/app_theme.dart';
import 'sheet_header.dart';

/// 매장 정보 시트에서 사용자가 고를 수 있는 다음 동작.
///
/// [viewCategory]는 매장 이름 옆 카테고리 chip을 눌렀을 때, 같은 카테고리의
/// 다른 매장들을 훑어볼 수 있는 목록 시트로 넘기라는 신호다. 호출자는 시트에
/// 이미 넘긴 카테고리 값을 그대로 다시 활용하면 되므로 별도 데이터가 필요 없다.
enum StoreInfoAction { setOrigin, setDestination, viewCategory }

/// 실내 검색에서 매장을 고르면 뜨는 정보 시트. 길찾기 시트와 같은 형태로
/// 아래에서 올라온다. 매장 상세 정보(사진·설명 등)는 아직 백엔드에 없어
/// 비워두고, 우하단의 출발지/도착지 버튼으로 바로 길찾기 시트로 넘어갈 수
/// 있게만 한다.
///
/// [favorite]이 주어지면 매장 이름 옆에 즐겨찾기 토글(+/체크) 버튼이 붙는다.
/// 저장되지 않은 상태에서 누르면 [FavoritesController]에 추가, 이미 저장된
/// 상태에서 누르면 삭제한다.
///
/// [category]가 주어지면 이름 아래에 카테고리 chip이 붙고, 누르면
/// [StoreInfoAction.viewCategory]로 시트가 닫혀 호출자가 카테고리 매장 목록
/// 시트로 이어갈 수 있다.
class StoreInfoSheet extends StatefulWidget {
  const StoreInfoSheet({
    super.key,
    required this.title,
    required this.subtitle,
    this.favorite,
    this.category,
    this.subcategory,
    required this.onCloseAll,
  });

  final String title;
  final String subtitle;

  /// null이면 즐겨찾기 버튼을 숨긴다(예: 건물 자체 정보처럼 매장이 아닌 경우).
  final FavoritePlace? favorite;

  /// 매장 대분류. 지도에서 매장 폴리곤을 탭한 경우에만 채워지고, 텍스트 검색
  /// 결과나 저장한 장소에서 온 경우엔 null이라 chip이 뜨지 않는다.
  final String? category;

  /// 카테고리 chip 아래 작게 표시할 소분류. category가 null이면 무시된다.
  final String? subcategory;

  /// X 버튼이 눌리면 호출. 부모(MapShellScreen)가 chain-close 플래그를
  /// set해서 열려 있는 위쪽 시트들도 다시 열리지 않게 한다.
  final VoidCallback onCloseAll;

  static Future<StoreInfoAction?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    FavoritePlace? favorite,
    String? category,
    String? subcategory,
    required VoidCallback onCloseAll,
  }) {
    return showModalBottomSheet<StoreInfoAction>(
      context: context,
      isScrollControlled: true,
      // 사용자가 시트 밖(어두운 barrier 영역) 및 시트 프레임 내부의 빈 상단
      // 여백을 누르면 닫힌다. barrier tap은 flutter가 기본으로 처리하지만,
      // DraggableScrollableSheet가 프레임 세로 전체를 차지하면서 상단 절반이
      // 투명이라 그 부분 탭은 barrier로 전달되지 않는다 — 그래서 시트 안쪽
      // 상단을 별도 GestureDetector로 소비한다.
      isDismissible: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StoreInfoSheet(
        title: title,
        subtitle: subtitle,
        favorite: favorite,
        category: category,
        subcategory: subcategory,
        onCloseAll: onCloseAll,
      ),
    );
  }

  @override
  State<StoreInfoSheet> createState() => _StoreInfoSheetState();
}

class _StoreInfoSheetState extends State<StoreInfoSheet> {
  /// 시트가 back/X/카테고리 chip/출발·도착 버튼처럼 명시적 조작으로 pop될 때
  /// true로 세팅된다. PopScope가 pop 이벤트를 받아 이 값이 false면 barrier 탭·
  /// drag-down으로 dismiss된 것으로 간주해 chain 전체를 닫는다.
  bool _intentionalPop = false;

  void _markIntentional() => _intentionalPop = true;

  @override
  void initState() {
    super.initState();
    favoritesController.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    favoritesController.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
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
    // 바깥 탭(barrier/투명 상단/drag-down)은 back과 달리 chain 전체를 닫는
    // 다는 요구사항 → PopScope로 pop 이벤트를 인터셉트해서, 명시적 조작으로
    // pop된 게 아니면 onCloseAll을 호출한다. GestureDetector는 여전히 시트
    // 프레임 내부의 투명 상단 탭을 잡아주는데, 여기서도 곧장 pop하면 그
    // pop이 PopScope에 걸려 자동으로 closeAll 처리된다.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
        initialChildSize: 0.42,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          return GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Material(
              color: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SheetHeader(
                      onCloseAll: widget.onCloseAll,
                      onIntentionalPop: _markIntentional,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Row(
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
                                      widget.title,
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
                                    _CategoryChip(
                                      label: category,
                                      onTap: () {
                                        _markIntentional();
                                        Navigator.of(context)
                                            .pop(StoreInfoAction.viewCategory);
                                      },
                                    ),
                                  ],
                                  if (favorite != null) ...[
                                    const SizedBox(width: 6),
                                    IconButton(
                                      onPressed: _onToggleFavorite,
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      tooltip: saved ? '저장 취소' : '장소로 저장',
                                      icon: Icon(
                                        saved ? Icons.check_circle : Icons.add_circle_outline,
                                        color: saved ? Colors.green : AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                subcategory != null && category != null && subcategory != category
                                    ? '${widget.subtitle} · $subcategory'
                                    : widget.subtitle,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ),
                    ),
                    // 매장 상세 정보(사진·설명 등)는 아직 준비되지 않아 비워둔다.
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () {
                                _markIntentional();
                                Navigator.of(context).pop(StoreInfoAction.setOrigin);
                              },
                              child: const Text('출발'),
                            ),
                            FilledButton(
                              onPressed: () {
                                _markIntentional();
                                Navigator.of(context).pop(StoreInfoAction.setDestination);
                              },
                              child: const Text('도착'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// 매장 이름 옆에 붙는 대분류 chip. 누르면 시트가 닫히면서 같은 카테고리의
/// 매장 목록으로 넘어간다. 가벼운 톤(연한 파스텔)으로 이름과 시각적 무게가
/// 겹치지 않게 한다.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blue50,
      shape: StadiumBorder(
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right, size: 14, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
