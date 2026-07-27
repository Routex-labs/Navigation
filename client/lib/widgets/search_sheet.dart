import 'dart:async';

import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/building.dart';
import '../models/poi_search_result.dart';
import '../theme/app_theme.dart';

/// 검색 시트가 닫히면서 상위에 넘기는 결과.
sealed class SearchSheetOutcome {
  const SearchSheetOutcome();
}

/// 사용자가 결과 목록에서 매장을 골랐다.
class SearchSheetStorePicked extends SearchSheetOutcome {
  const SearchSheetStorePicked(this.store);

  final PoiSearchResult store;
}

/// 사용자가 건물 자체를 골랐다. 상위가 건물 정보 카드를 띄운다.
class SearchSheetBuildingPicked extends SearchSheetOutcome {
  const SearchSheetBuildingPicked(this.building);

  final Building building;
}

/// 결과가 없어 "AI 검색으로 찾기"를 눌렀다. 상위가 AI 검색 패널을 연다.
class SearchSheetAiRequested extends SearchSheetOutcome {
  const SearchSheetAiRequested(this.query);

  final String query;
}

/// 상단 검색창을 탭하면 아래에서 올라오는 검색 시트.
///
/// 예전에는 상단 바의 TextField에서 곧바로 검색하고 결과를 스낵바로만
/// 알렸다. 결과 목록을 놓을 자리가 없어 "쳤는데 아무것도 안 보인다"는 인상을
/// 줬기 때문에, 입력과 결과를 한 화면에 묶어 시트로 올린다.
///
/// 여기서 쓰는 검색은 **경량 매칭(`/query/destination`)** 이다. 형태소 정규화
/// (Kiwi)까지는 이 경로에 들어 있고, 의미 검색(FAISS)은 사용자가 명시적으로
/// 고르는 AI 검색 쪽에 둔다 — 매 검색마다 임베딩 모델을 태우지 않기 위해서.
class SearchSheet extends StatefulWidget {
  const SearchSheet({
    super.key,
    required this.buildingId,
    this.currentFloorId,
  });

  final String buildingId;

  /// 실내를 보고 있으면 그 층으로 스코프. null이면 건물 전체를 뒤진다.
  final String? currentFloorId;

  static Future<SearchSheetOutcome?> show(
    BuildContext context, {
    required String buildingId,
    String? currentFloorId,
  }) {
    return showModalBottomSheet<SearchSheetOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SearchSheet(
        buildingId: buildingId,
        currentFloorId: currentFloorId,
      ),
    );
  }

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  /// 마지막으로 결과를 확정한 질의. 빈 문자열이면 아직 아무것도 안 쳤다.
  String _submittedQuery = '';
  List<PoiSearchResult> _results = const [];

  /// 이름이 걸린 건물. 매장과 함께 목록 맨 위에 한 줄로 얹는다 — 예전 상단
  /// 검색이 하던 "건물 이름 검색"을 여기로 옮겨 온 것이다.
  Building? _building;
  bool _searching = false;

  /// 늦게 도착한 응답이 최신 결과를 덮어쓰지 않게 하는 순번.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 타이핑마다 서버를 때리지 않도록 잠깐 모았다 보낸다.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(value),
    );
  }

  Future<void> _search(String raw) async {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _submittedQuery = '';
        _results = const [];
        _building = null;
        _searching = false;
      });
      return;
    }

    final requestId = ++_requestId;
    setState(() => _searching = true);
    List<PoiSearchResult> results;
    Building? building;
    try {
      results = await destinationRepository.searchDestinations(
        widget.buildingId,
        query,
        currentFloorId: widget.currentFloorId,
      );
      final buildings = await buildingRepository.getAllBuildings();
      building = buildings
          .where((b) => b.name.toLowerCase().contains(query.toLowerCase()))
          .firstOrNull;
    } on Object {
      // 서버 장애·네트워크 끊김. 시트를 닫지 않고 "결과 없음"으로 둔다.
      results = const [];
      building = null;
    }
    // 이 응답을 기다리는 사이 사용자가 더 쳤다면 버린다.
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _submittedQuery = query;
      _results = results;
      _building = building;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _grabber(),
            _field(context),
            const Divider(height: 1),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _grabber() => Container(
    width: 40,
    height: 4,
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    decoration: BoxDecoration(
      color: AppColors.muted.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _field(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                isDense: true,
                hintText: '건물, 장소를 검색하세요',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: AppColors.muted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.muted,
                ),
                filled: true,
                fillColor: AppColors.blue50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_submittedQuery.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Text(
          '매장 이름을 입력해 보세요.\n찾는 게 안 나오면 AI 검색으로 다시 찾을 수 있어요.',
          style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
        ),
      );
    }
    final building = _building;
    if (_results.isEmpty && building == null) return _emptyState(context);

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _results.length + (building == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        if (building != null && index == 0) {
          return ListTile(
            leading: const Icon(
              Icons.apartment_outlined,
              color: AppColors.primary,
            ),
            title: Text(
              building.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              '건물 · ${building.floors.length}개 층',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            onTap: () => Navigator.of(
              context,
            ).pop(SearchSheetBuildingPicked(building)),
          );
        }
        final store = _results[index - (building == null ? 0 : 1)];
        return ListTile(
          leading: const Icon(Icons.place_outlined, color: AppColors.primary),
          title: Text(
            store.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            // 입구 노드가 없으면(status=ok_no_route) 경로 계산이 불가능하다.
            store.nodeId == null ? '${store.floor} · 경로 안내 불가' : store.floor,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          onTap: () => Navigator.of(
            context,
          ).pop(SearchSheetStorePicked(store)),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"$_submittedQuery"에 맞는 매장을 찾지 못했어요.',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '"밥 먹을 곳"처럼 뜻으로 찾으려면 AI 검색을 써 보세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).pop(SearchSheetAiRequested(_submittedQuery)),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI 검색으로 찾기'),
          ),
        ],
      ),
    );
  }
}
