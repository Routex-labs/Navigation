import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/favorite_place.dart';
import '../theme/app_theme.dart';
import 'sheet_header.dart';

/// 사용자가 저장해둔 매장 목록을 보여주는 바텀시트.
///
/// 각 항목은 탭하면 [FavoritePlace]를 반환하며(호출자가 매장 정보 시트로
/// 넘겨준다), 오른쪽 점 세개 메뉴로 삭제할 수 있고, 드래그로 순서 조정도
/// 지원한다. 저장·삭제·순서 조정은 전부 [FavoritesController]에 위임한다.
///
/// 리스트 재빌드는 [ListenableBuilder]로 처리한다 — 수동으로 addListener
/// 후 setState를 부르면 ReorderableListView의 드롭 애니메이션 중간에
/// 재빌드가 끼어들어 `_elements.contains(element)` assertion이 터진다.
class FavoritesSheet extends StatefulWidget {
  const FavoritesSheet({super.key, required this.onCloseAll});

  /// X 버튼이 눌리면 호출. 부모(MapShellScreen)가 chain-close 플래그를 세팅
  /// 해 위쪽 시트들도 다시 열리지 않게 한다.
  final VoidCallback onCloseAll;

  static Future<FavoritePlace?> show(
    BuildContext context, {
    required VoidCallback onCloseAll,
  }) {
    return showModalBottomSheet<FavoritePlace>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => FavoritesSheet(onCloseAll: onCloseAll),
    );
  }

  @override
  State<FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<FavoritesSheet> {
  /// back/X/항목 선택으로 명시적 pop될 때 true. PopScope가 이 값이 false인
  /// pop(=barrier/drag)을 잡아 chain 전체를 닫는다.
  bool _intentionalPop = false;
  void _markIntentional() => _intentionalPop = true;

  @override
  Widget build(BuildContext context) {
    // 화면 높이의 최대 80%까지만 잡는다. DraggableScrollableSheet를 쓰지 않는
    // 이유는 그쪽의 scrollController를 ReorderableListView에 물릴 때 드래그
    // 리오더와 시트 스크롤이 같은 컨트롤러를 공유해 element 트리가 꼬이는
    // `_elements.contains(element)` assertion이 발생하기 때문이다.
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: '저장한 장소',
              onCloseAll: widget.onCloseAll,
              onIntentionalPop: _markIntentional,
            ),
            Flexible(
              child: ListenableBuilder(
                listenable: favoritesController,
                builder: (context, _) {
                  final places = favoritesController.places;
                  if (places.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(20, 40, 20, 40),
                      child: Center(
                        child: Text(
                          '아직 저장한 장소가 없어요.\n매장 정보에서 + 버튼으로 추가할 수 있어요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.muted),
                        ),
                      ),
                    );
                  }
                  return ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: places.length,
                    // 오른쪽 기본 드래그 핸들(≡ 아이콘) 제거. 아이템 아무 데나
                    // 꾹 누르면 살짝 떠오르며 이동한다.
                    buildDefaultDragHandles: false,
                    // ignore: deprecated_member_use -- onReorderItem은 최신 SDK 전용.
                    onReorder: favoritesController.reorder,
                    itemBuilder: (context, index) {
                      final place = places[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(place.key),
                        index: index,
                        child: _FavoriteTile(
                          place: place,
                          onTap: () {
                            _markIntentional();
                            Navigator.of(context).pop(place);
                          },
                          onDelete: () =>
                              favoritesController.removeByKey(place.key),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.place,
    required this.onTap,
    required this.onDelete,
  });

  final FavoritePlace place;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.blue50,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.storefront, color: AppColors.primary, size: 18),
      ),
      title: Text(
        place.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        place.floor,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      trailing: PopupMenuButton<_FavoriteMenu>(
        icon: const Icon(Icons.more_vert, color: AppColors.muted),
        onSelected: (value) {
          if (value == _FavoriteMenu.delete) onDelete();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _FavoriteMenu.delete,
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('삭제'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _FavoriteMenu { delete }
