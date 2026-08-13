import 'package:flutter/material.dart';

import '../models/floor_plan.dart';
import 'category_icon.dart';
import 'sheet_grab_handle.dart';

/// 한 자리를 세 곳 이상이 나눠 쓸 때 뜨는 **매장 고르기 시트**.
///
/// 그런 자리를 칸으로 나눠 라벨을 전부 박으면 도면이 줄무늬 표처럼 보인다
/// (실기기 확인 — B1 푸드트럭 8곳·공차 골목 4곳). 지도에는 「첫 매장 외 N」
/// 라벨 하나만 두고, 누르면 이 시트가 매장 목록을 펼친다. 항목을 고르면 그
/// [StorePolygon]으로 pop하고, 호출자가 상세 시트를 잇는다. 밖을 눌러 닫으면
/// null이다.
///
/// 상세·카테고리 시트와 달리 barrier를 그대로 둔다 — 이 시트는 "이 자리에서
/// 하나를 고르는" 짧은 분기라, 열린 채 지도를 만질 이유가 없다.
Future<StorePolygon?> showStoreClusterSheet(
  BuildContext context,
  List<StorePolygon> stores,
) {
  return showModalBottomSheet<StorePolygon>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetGrabHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '이 자리의 매장 ${stores.length}곳',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: stores.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
              itemBuilder: (context, index) {
                final store = stores[index];
                final category = store.category;
                return ListTile(
                  onTap: () => Navigator.of(context).pop(store),
                  leading: Icon(
                    category != null ? categoryIconFor(category) : Icons.store,
                    size: 20,
                    color: category != null
                        ? categoryColorFor(category)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(store.name),
                  subtitle: store.subcategory != null
                      ? Text(store.subcategory!)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
