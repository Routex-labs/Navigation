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

/// 상단 검색창을 탭하면 아래에서 올라오는 검색 시트.
///
/// 예전에는 상단 바의 TextField에서 곧바로 검색하고 결과를 스낵바로만
/// 알렸다. 결과 목록을 놓을 자리가 없어 "쳤는데 아무것도 안 보인다"는 인상을
/// 줬기 때문에, 입력과 결과를 한 화면에 묶어 시트로 올린다.
///
/// ## 검색 한 곳, 두 단계
///
/// 사용자는 "일반 검색"과 "AI 검색"을 구분하지 않는다. 매장 이름을 치든
/// 자연어를 치든 여기 한 곳에 치면 되고, 어느 경로로 찾을지는 이 시트가
/// 정한다.
///
/// - **타이핑 중**: 경량 매칭(`/query/destination`)만 돌린다. 형태소 정규화
///   (Kiwi)가 이 경로에 들어 있어 "MLB" 같은 이름은 즉시 걸린다.
/// - **엔터로 확정**: 경량이 빈손이면 의미 검색(`/query/ai`)까지 자동으로
///   이어 붙인다. "밥 먹을 곳"처럼 사전에 없는 표현이 여기서 걸린다.
///
/// 의미 검색을 타이핑 중이 아니라 **확정 시점에만** 붙이는 이유는 비용이다.
/// 백엔드가 임베딩 모델을 로드하면 첫 호출이 20초대까지 가므로, 글자마다
/// 던지면 "밥"·"밥 먹"·"밥 먹을"이 전부 모델을 태운다. 사용자가 다 치고
/// 엔터를 누른 순간에만 한 번 태운다.
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

  /// 의미 검색(2단계)이 도는 중. 모델 로드로 오래 걸릴 수 있어 경량 검색과
  /// 다른 문구를 띄운다 — 같은 스피너만 돌면 멈춘 것처럼 보인다.
  bool _searchingSemantic = false;

  /// 이번 결과가 의미 검색에서 나왔는지. 목록에 "뜻으로 찾은 결과"라고 표시해
  /// 사용자가 왜 다른 이름이 나왔는지 납득할 수 있게 한다.
  bool _fromSemantic = false;

  /// 늦게 도착한 응답이 최신 결과를 덮어쓰지 않게 하는 순번.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 타이핑마다 서버를 때리지 않도록 잠깐 모았다 보낸다. 타이핑 중에는 경량
  /// 검색만 — 의미 검색은 엔터로 확정했을 때만 붙는다(클래스 주석 참고).
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(value),
    );
  }

  Future<void> _search(String raw, {bool allowSemantic = false}) async {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _submittedQuery = '';
        _results = const [];
        _building = null;
        _searching = false;
        _searchingSemantic = false;
        _fromSemantic = false;
      });
      return;
    }

    final requestId = ++_requestId;
    setState(() {
      _searching = true;
      _searchingSemantic = false;
    });

    List<PoiSearchResult> results;
    Building? building;
    var fromSemantic = false;
    try {
      // 1단계: 경량 매칭. 매장 이름·동의어는 여기서 즉시 걸린다.
      results = await destinationRepository.searchDestinations(
        widget.buildingId,
        query,
        currentFloorId: widget.currentFloorId,
      );
      final buildings = await buildingRepository.getAllBuildings();
      building = buildings
          .where((b) => b.name.toLowerCase().contains(query.toLowerCase()))
          .firstOrNull;

      // 2단계: 엔터로 확정했는데 아무것도 못 찾았으면 의미 검색까지 이어 붙인다.
      // 사용자가 "결과 없음"을 볼 상황에서만 타므로, 잘 되던 검색은 그대로 빠르다.
      if (allowSemantic && results.isEmpty && building == null) {
        if (!mounted || requestId != _requestId) return;
        setState(() => _searchingSemantic = true);
        results = await destinationRepository.searchDestinationsAi(
          widget.buildingId,
          query,
          currentFloorId: widget.currentFloorId,
        );
        fromSemantic = results.isNotEmpty;
      }
    } on Object {
      // 서버 장애·네트워크 끊김. 시트를 닫지 않고 "결과 없음"으로 둔다.
      results = const [];
      building = null;
      fromSemantic = false;
    }
    // 이 응답을 기다리는 사이 사용자가 더 쳤다면 버린다.
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _submittedQuery = query;
      _results = results;
      _building = building;
      _fromSemantic = fromSemantic;
      _searching = false;
      _searchingSemantic = false;
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
              // 엔터로 확정한 순간에만 의미 검색까지 이어 붙인다.
              onSubmitted: (value) => _search(value, allowSemantic: true),
              decoration: InputDecoration(
                isDense: true,
                hintText: '매장 이름이나 "밥 먹을 곳"처럼 입력하세요',
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_searchingSemantic) ...[
              const SizedBox(height: 14),
              const Text(
                '뜻이 비슷한 매장을 찾는 중…',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              const Text(
                '처음 한 번은 조금 오래 걸릴 수 있어요',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ],
          ],
        ),
      );
    }
    if (_submittedQuery.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Text(
          '매장 이름을 입력하면 바로 찾아드려요.\n'
          '"밥 먹을 곳"처럼 뜻으로 물어도 됩니다.',
          style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
        ),
      );
    }
    final building = _building;
    if (_results.isEmpty && building == null) return _emptyState(context);

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount:
          _results.length + (building == null ? 0 : 1) + (_fromSemantic ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        // 의미 검색으로 찾은 결과는 입력한 말과 이름이 전혀 다를 수 있다.
        // 왜 이게 나왔는지 한 줄로 알려 준다.
        if (_fromSemantic && index == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '뜻이 비슷한 매장을 찾았어요',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final offset =
            (building == null ? 0 : 1) + (_fromSemantic ? 1 : 0);
        if (building != null && index == (_fromSemantic ? 1 : 0)) {
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
        final store = _results[index - offset];
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
          // 엔터로 확정했다면 의미 검색까지 이미 돌린 뒤다. 사용자가 더 눌러 볼
          // 수단이 남아 있는 것처럼 보이면 안 되므로, 다른 말로 바꿔 보라고만 한다.
          const Text(
            '다른 말로 바꿔서 다시 찾아보세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
