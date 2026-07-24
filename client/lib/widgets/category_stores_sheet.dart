import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/floor_plan.dart';
import '../models/poi_search_result.dart';
import '../theme/app_theme.dart';
import 'category_icon.dart';
import 'sheet_header.dart';

/// 매장 정보 시트에서 카테고리 chip을 누르면 뜨는, 같은 대분류에 속하는
/// 매장을 층별로 훑어볼 수 있는 목록 시트. 사용자가 항목을 탭하면 그 매장의
/// [PoiSearchResult]로 pop해서 호출자가 다시 매장 정보 시트를 띄우게 한다.
///
/// 건물 전체 층을 순회하며 stores를 모아야 해서 첫 로드는 층 수만큼의 API
/// 호출이 필요하다 — HttpBuildingRepository가 이 응답을 이미 캐시하므로
/// 같은 건물 안에서는 두 번째부터 즉시 뜬다.
class CategoryStoresSheet extends StatefulWidget {
  const CategoryStoresSheet({
    super.key,
    required this.buildingId,
    required this.category,
    required this.onCloseAll,
    this.currentFloor,
  });

  final String buildingId;
  final String category;

  /// 실내 모드에서 지도가 지금 보여주고 있는 층 라벨. 시트 상단의
  /// "현재 층만 보기" 토글에 노출된다. null(야외 모드 등)이면 토글 자체를
  /// 숨기고 전 층 목록만 보여준다.
  final String? currentFloor;

  /// X 버튼이 눌리면 호출. 부모(MapShellScreen)가 chain-close 플래그를 세팅해
  /// 위쪽 시트들(예: 매장 정보 시트, 저장한 장소)이 다시 열리지 않게 한다.
  final VoidCallback onCloseAll;

  static Future<PoiSearchResult?> show(
    BuildContext context, {
    required String buildingId,
    required String category,
    required VoidCallback onCloseAll,
    String? currentFloor,
  }) {
    return showModalBottomSheet<PoiSearchResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => CategoryStoresSheet(
        buildingId: buildingId,
        category: category,
        onCloseAll: onCloseAll,
        currentFloor: currentFloor,
      ),
    );
  }

  @override
  State<CategoryStoresSheet> createState() => _CategoryStoresSheetState();
}

class _CategoryStoresSheetState extends State<CategoryStoresSheet> {
  late final Future<List<_CategoryStoreEntry>> _entriesFuture = _load();
  late final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showCurrentFloorOnly = false;

  /// back/X/항목 선택처럼 명시적 조작으로 pop될 때 true. PopScope가 pop을
  /// 받았을 때 이 값이 false면 barrier·drag-down으로 dismiss된 것으로 보고
  /// chain 전체를 닫는다.
  bool _intentionalPop = false;
  void _markIntentional() => _intentionalPop = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_CategoryStoreEntry> _applyFilters(List<_CategoryStoreEntry> all) {
    final query = _searchQuery.trim().toLowerCase();
    final current = widget.currentFloor;
    return all.where((entry) {
      if (_showCurrentFloorOnly && current != null && entry.floor != current) {
        return false;
      }
      if (query.isNotEmpty && !entry.store.name.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// 편의시설 카테고리에서 목록에 노출하지 않을 하위 카테고리.
  /// - `주차`: 매장이 아니라 주차 구획이라 매장 검색 흐름에 노출할 필요가 없음.
  /// - `교통`: 지하철 등 건물 외부 시설이라 실내 매장 탐색과 무관.
  /// - `escalator`·`elevator` (및 한글 표기): 개별 도착지로 안내할 대상이
  ///   아니므로 제외 — 경로 안내가 필요할 때는 다익스트라가 자동으로 층 이동
  ///   수단으로 이 노드들을 사용한다.
  ///
  /// 실제 층 데이터의 subcategory는 영어 소문자이므로 그 표기를 우선으로 넣고,
  /// 다른 seed 경로에서 한글로 들어올 가능성에 대비해 대응되는 한글 표기도 함께 둔다.
  static const _hiddenSubcategoriesByCategory = <String, Set<String>>{
    '편의시설': {
      '주차',
      '교통',
      'escalator',
      '에스컬레이터',
      'elevator',
      '엘리베이터',
    },
  };

  Future<List<_CategoryStoreEntry>> _load() async {
    final building = await buildingRepository.getBuilding(widget.buildingId);
    if (building == null) return const [];
    final hiddenSubs =
        _hiddenSubcategoriesByCategory[widget.category] ?? const <String>{};
    final entries = <_CategoryStoreEntry>[];
    for (final floor in building.floors) {
      final json = await buildingRepository.getFloorGeoJson(
        widget.buildingId,
        floor,
      );
      if (json == null) continue;
      final plan = FloorPlan.fromJson(json);
      for (final store in plan.stores) {
        if (store.category != widget.category) continue;
        if (hiddenSubs.contains(store.subcategory)) continue;
        entries.add(_CategoryStoreEntry(store: store, floor: floor));
      }
    }
    // 층수 낮은 순(지하 최하층 → 지상 최상층)으로 정렬. 백엔드가 floors를
    // 층 level 내림차순으로 내려주므로 여기서 오름차순으로 다시 뒤집는다.
    // 같은 층 안에서는 매장 이름 순으로 보조 정렬해 화면상 순서를 안정화.
    entries.sort((a, b) {
      final la = _floorLevel(a.floor);
      final lb = _floorLevel(b.floor);
      if (la != lb) return la.compareTo(lb);
      return a.store.name.compareTo(b.store.name);
    });
    return entries;
  }

  /// "B6", "1F" 같은 층 라벨을 정렬용 정수 level로 바꾼다. `B<n>=-n`, `<n>F=n`.
  /// 알 수 없는 형태의 라벨은 0으로 두어 지상·지하 사이에 놓는다.
  static int _floorLevel(String label) {
    final upper = label.toUpperCase();
    final basement = RegExp(r'^B(\d+)$').firstMatch(upper);
    if (basement != null) return -int.parse(basement.group(1)!);
    final above = RegExp(r'^(\d+)F$').firstMatch(upper);
    if (above != null) return int.parse(above.group(1)!);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // 바깥(투명 상단·barrier·drag-down) 탭으로 닫히면 PopScope가 잡아 chain
    // 전체를 닫는다(back 버튼과 구분됨). 내부 콘텐츠는 inner GestureDetector가
    // dismiss 전파를 막는다.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
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
              child: FutureBuilder<List<_CategoryStoreEntry>>(
                future: _entriesFuture,
                builder: (context, snapshot) {
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: SheetHeader(
                          title: widget.category,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: categoryColorFor(widget.category)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              categoryIconFor(widget.category),
                              size: 16,
                              color: categoryColorFor(widget.category),
                            ),
                          ),
                          onCloseAll: widget.onCloseAll,
                          onIntentionalPop: _markIntentional,
                        ),
                      ),
                      SliverToBoxAdapter(child: _buildFilterBar()),
                      ..._buildBody(snapshot),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  List<Widget> _buildBody(AsyncSnapshot<List<_CategoryStoreEntry>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (snapshot.hasError) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('매장 목록을 불러오지 못했습니다. 서버 연결을 확인해주세요.'),
          ),
        ),
      ];
    }
    final all = snapshot.data ?? const <_CategoryStoreEntry>[];
    if (all.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('이 카테고리에 해당하는 매장이 없습니다.'),
          ),
        ),
      ];
    }
    final entries = _applyFilters(all);
    if (entries.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('조건에 맞는 매장이 없습니다.'),
          ),
        ),
      ];
    }
    return [
      SliverList.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 20, endIndent: 20),
        itemBuilder: (context, index) => _StoreTile(
          entry: entries[index],
          onTap: () {
            _markIntentional();
            Navigator.of(context).pop(entries[index].toPoiSearchResult());
          },
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  Widget _buildFilterBar() {
    final currentFloor = widget.currentFloor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          if (currentFloor != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '현재 층만 보기 ($currentFloor)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _showCurrentFloorOnly,
                  onChanged: (v) => setState(() => _showCurrentFloorOnly = v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.muted),
        hintText: '매장 이름 검색',
        hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.muted),
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.entry, required this.onTap});

  final _CategoryStoreEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = entry.store;
    final subcategory = store.subcategory;
    final subtitle = subcategory != null && subcategory != store.category
        ? '${entry.floor} · $subcategory'
        : entry.floor;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        storeIconFor(name: store.name, subcategory: store.subcategory),
        size: 20,
        color: AppColors.primary,
      ),
      title: Text(
        store.name,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
    );
  }
}

class _CategoryStoreEntry {
  const _CategoryStoreEntry({required this.store, required this.floor});

  final StorePolygon store;
  final String floor;

  PoiSearchResult toPoiSearchResult() => PoiSearchResult(
        name: store.name,
        floor: floor,
        point: store.centroid,
        nodeId: store.entranceNodeId,
        category: store.category,
        subcategory: store.subcategory,
      );
}
