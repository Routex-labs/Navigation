import 'dart:async';

import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/building.dart';
import '../models/poi_search_result.dart';
import '../theme/app_theme.dart';

/// 상단 검색창 바로 아래에 붙는 결과 패널.
///
/// **입력창을 가지고 있지 않다.** 사용자는 상단 바의 검색창에 그대로 치고,
/// 이 패널은 그 글자를 받아 결과만 그린다. 예전에는 검색창을 탭하면 아래에서
/// 입력창이 하나 더 있는 시트가 올라왔는데, 방금 누른 창과 실제로 입력하는
/// 창이 달라 "왜 검색창이 두 개냐"는 인상을 줬다.
///
/// ## 검색 한 곳, 두 단계
///
/// 사용자는 "일반 검색"과 "AI 검색"을 구분하지 않는다. 매장 이름을 치든
/// 자연어를 치든 상단 검색창 한 곳에 치면 되고, 어느 경로로 찾을지는 이
/// 패널이 정한다.
///
/// - **타이핑 중**([query] 변경): 경량 매칭(`/query/destination`)만 돌린다.
///   형태소 정규화(Kiwi)가 이 경로에 들어 있어 "MLB" 같은 이름은 즉시 걸린다.
/// - **엔터로 확정**([submitTick] 증가): 경량이 빈손이면 의미 검색
///   (`/query/ai`)까지 자동으로 이어 붙인다. "밥 먹을 곳"처럼 사전에 없는
///   표현이 여기서 걸린다.
///
/// 의미 검색을 타이핑 중이 아니라 **확정 시점에만** 붙이는 이유는 비용이다.
/// 백엔드가 임베딩 모델을 로드하면 첫 호출이 20초대까지 가므로, 글자마다
/// 던지면 "밥"·"밥 먹"·"밥 먹을"이 전부 모델을 태운다. 사용자가 다 치고
/// 엔터를 누른 순간에만 한 번 태운다.
///
/// 상태를 상위에서 명령형으로 밀어 넣지 않고 [query]·[submitTick] 두 값으로만
/// 받는 이유는 순서 문제 때문이다. 패널은 검색이 활성화될 때 비로소 트리에
/// 들어오므로, 상위가 GlobalKey로 메서드를 부르면 첫 글자가 패널이 생기기
/// 전에 도착해 조용히 사라질 수 있다.
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.buildingId,
    required this.query,
    required this.submitTick,
    required this.currentFloorId,
    required this.onStorePicked,
    required this.onBuildingPicked,
  });

  final String buildingId;

  /// 상단 검색창에 지금 들어 있는 글자.
  final String query;

  /// 엔터로 확정할 때마다 상위가 1씩 올린다. 값이 바뀐 순간에만 의미 검색을
  /// 붙인다 — 같은 글자로 다시 엔터를 눌러도 재검색되게 하려고 bool이 아닌
  /// 카운터로 받는다.
  final int submitTick;

  /// 검색 시점의 층을 그때그때 물어본다. 값으로 받으면 사용자가 층을 바꾼 뒤
  /// 상위가 리빌드되기 전까지 옛 층으로 검색하게 된다.
  final String? Function() currentFloorId;

  final ValueChanged<PoiSearchResult> onStorePicked;
  final ValueChanged<Building> onBuildingPicked;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
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
  void initState() {
    super.initState();
    // 검색창에 글자가 남아 있는 채로 패널이 다시 열릴 수 있다.
    if (widget.query.trim().isNotEmpty) _scheduleSearch(widget.query);
  }

  @override
  void didUpdateWidget(covariant SearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.submitTick != oldWidget.submitTick) {
      // 엔터로 확정. 디바운스를 기다리지 않고 즉시, 의미 검색까지 허용해서.
      _search(widget.query, allowSemantic: true);
    } else if (widget.query != oldWidget.query) {
      _scheduleSearch(widget.query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// 타이핑마다 서버를 때리지 않도록 잠깐 모았다 보낸다. 타이핑 중에는 경량
  /// 검색만 — 의미 검색은 엔터로 확정했을 때만 붙는다(클래스 주석 참고).
  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
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

    final floorId = widget.currentFloorId();
    List<PoiSearchResult> results;
    Building? building;
    var fromSemantic = false;
    try {
      // 1단계: 경량 매칭. 매장 이름·동의어는 여기서 즉시 걸린다.
      results = await destinationRepository.searchDestinations(
        widget.buildingId,
        query,
        currentFloorId: floorId,
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
          currentFloorId: floorId,
        );
        fromSemantic = results.isNotEmpty;
      }
    } on Object {
      // 서버 장애·네트워크 끊김. 패널을 닫지 않고 "결과 없음"으로 둔다.
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
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
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
        padding: EdgeInsets.fromLTRB(16, 20, 16, 22),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
        final offset = (building == null ? 0 : 1) + (_fromSemantic ? 1 : 0);
        if (building != null && index == (_fromSemantic ? 1 : 0)) {
          return ListTile(
            leading: const Icon(
              Icons.apartment_outlined,
              color: AppColors.primary,
            ),
            title: Text(
              building.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '건물 · ${building.floors.length}개 층',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            onTap: () => widget.onBuildingPicked(building),
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
          onTap: () => widget.onStorePicked(store),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
