import 'dart:async';

import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/building.dart';
import '../models/discovery_result.dart';
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
/// - **타이핑이 300ms 멎으면**: 경량 매칭(`/query/destination`). 형태소
///   정규화(Kiwi)가 이 경로에 들어 있어 "MLB" 같은 이름은 즉시 걸린다.
/// - **경량이 빈손이면**: 400ms를 더 기다렸다가 의미 검색(`/query/ai`)까지
///   자동으로 이어 붙인다. "밥 먹을 곳"처럼 사전에 없는 표현이 여기서 걸린다.
/// - **엔터로 확정**([submitTick] 증가): 두 대기를 모두 건너뛰고 같은 경로를
///   즉시 탄다.
///
/// 두 요청 모두 [currentFloorId]가 있으면 함께 보낸다 — "화장실"처럼 층
/// 시설을 가리키는 질의가 지금 보고 있는 층으로 확정되게 하기 위해서다.
/// 매장 이름 검색이 다른 층에 있어 이 때문에 1차가 빈손이 되더라도, 2차
/// 의미 검색은 층을 무시하고 건물 전체를 보므로 그대로 찾아낸다.
///
/// ### 왜 엔터를 트리거에서 뺐나
///
/// 예전에는 의미 검색을 엔터에만 붙였다. 비용 때문이었는데 두 가지가 깨졌다.
///
/// 1. 한글 IME에서 첫 엔터가 조합 확정에 쓰이면 `onSubmitted`가 실행되지 않아
///    [submitTick]이 오르지 않는다. 그러면 의미 검색은 **아예 시작되지 않는다.**
/// 2. 그때까지 화면에는 경량이 빈손이라는 이유만으로 "찾지 못했어요"가 최종
///    결론처럼 떠 있었다. "신발"·"밥집"은 어떤 매장명·카테고리와도 정확히
///    일치하지 않으므로 타이핑만으로는 **항상** 이 화면이었다. 아직 AI를 부르지도
///    않았는데 사용자는 "이 앱은 못 찾는구나"로 읽는다.
///
/// 그래서 트리거를 엔터가 아니라 **타이핑이 멎었다는 사실**로 바꾸고, 비용은
/// 디바운스를 두 단으로 나눠 막는다. 경량은 300ms로 예전처럼 빠르게 두고, 의미
/// 검색만 그 위에 400ms를 더 얹어 사용자가 실제로 손을 뗀 뒤에 한 번 돈다.
/// 글자마다 태우지 않는 게 핵심이다 — 백엔드가 임베딩 모델을 처음 올리는 호출은
/// HF 캐시가 있어도 6초대이고(`NAV_WARM_EMBEDDING=1`이 그 비용을 서버 기동
/// 시점으로 옮기지만, 워밍이 끝나기 전에 들어온 첫 사용자는 여전히 맞는다),
/// 그렇다고 경량까지 700ms로 늦추면 매장 이름을 정확히 아는 흔한 검색이 같이
/// 느려진다. 두 단으로 나누면 흔한 경로는 안 건드리고 비싼 경로만 늦출 수 있다.
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
    required this.onStorePicked,
    required this.onBuildingPicked,
    this.currentFloorId,
  });

  final String buildingId;

  /// 상단 검색창에 지금 들어 있는 글자.
  final String query;

  /// 지금 보고 있는 층. 실내 지도가 열려 있을 때만 값이 있고, 야외 모드거나
  /// 층이 아직 안 잡혔으면 null이다. 시설 질의("화장실")가 건물 전체에서
  /// 정렬 순서상 우연히 걸리는 층(예: B6)이 아니라 실제로 보고 있는 층으로
  /// 확정되도록 요청에 실어 보낸다.
  final String? currentFloorId;

  /// 엔터로 확정할 때마다 상위가 1씩 올린다. 값이 바뀐 순간에만 의미 검색을
  /// 붙인다 — 같은 글자로 다시 엔터를 눌러도 재검색되게 하려고 bool이 아닌
  /// 카운터로 받는다.
  final int submitTick;

  final ValueChanged<PoiSearchResult> onStorePicked;
  final ValueChanged<Building> onBuildingPicked;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

/// 패널이 지금 어느 단계에 있는지. 예전에는 `_searching`·`_searchingSemantic`
/// 불리언 두 개로 표현했는데, "경량은 끝났지만 의미 검색은 아직"이라는 단계가
/// 생기면서 조합만으로는 화면을 정할 수 없게 됐다. 특히 [noMatch]는 **의미
/// 검색까지 끝났을 때만** 들어갈 수 있어야 하는데, 불리언으로는 "검색 안 하는
/// 중 + 결과 없음"과 구분이 안 된다.
///
enum _SearchPhase {
  /// 아직 아무것도 치지 않았다. 안내 문구만 보여준다.
  idle,

  /// 경량 매칭이 도는 중. 의미 검색으로 넘어가기 전 대기 시간도 여기 포함된다
  /// — 사용자 입장에서는 둘 다 "찾는 중"이고, 아직 결론이 아니다.
  typingLightSearch,

  /// 의미 검색이 도는 중. 모델 로드로 오래 걸릴 수 있어 경량과 다른 문구를
  /// 띄운다 — 같은 스피너만 돌면 멈춘 것처럼 보인다.
  semanticSearching,

  /// 후보가 넓어서 선택지를 먼저 보여 주는 탐색 응답이다.
  clarify,

  /// 보여줄 매장·건물이 있다.
  results,

  /// 경량과 의미 검색을 **둘 다** 끝냈는데 없다. 최종 "결과 없음" 문구는 오직
  /// 이 단계에서만 나온다.
  noMatch,

  /// 의미 모델은 쓸 수 없지만 경량/태그 후보는 남아 있을 수 있다.
  degraded,

  /// 서버·네트워크가 끊겨 검색을 끝내지 못했다. 없는 것과 못 찾은 것은 사용자가
  /// 할 행동이 다르다 — 전자는 다른 말로 바꿔야 하고, 후자는 기다려야 한다.
  error,
}

/// 의미 검색 결과가 사실상 정확한 이름 일치인지 휴리스틱으로 판정한다. 서버가
/// 어느 tier(정확 일치·동의어·의미)로 매칭했는지는 클라이언트로 내려오지
/// 않으므로, 질의와 결과 이름을 직접 비교해 추정한다.
///
/// 최근 층 스코프 적용(ea315b8)으로 상단 검색이 현재 층을 함께 보내면서,
/// 사용자가 타 층 매장을 정확한 이름으로 검색해도 1차 경량 검색(현재 층
/// 한정)이 빈손이 되어 2차 의미 검색으로 넘어오는 경우가 생겼다. 이때도
/// [SearchPanel._fromSemantic] 배너("뜻이 비슷한 매장을 찾았어요")가 그대로
/// 붙으면, 정확한 이름을 쳤는데 "뜻으로 찾았다"고 말하는 셈이라 부정확하다.
///
/// 대소문자·앞뒤 공백만 정규화하고 그 밖의 정규화(형태소 분석 등)는 하지
/// 않는다. 서버의 Kiwi 정규화까지 흉내내려 하면 휴리스틱이 오히려 서버 판정과
/// 어긋나는 경우가 늘어난다 — 여기서는 "누가 봐도 같은 이름"만 걸러낸다.
bool _isExactNameMatch(String query, List<PoiSearchResult> results) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return false;
  return results.any((result) {
    final name = result.name.trim().toLowerCase();
    return name == normalizedQuery || name.startsWith(normalizedQuery);
  });
}

class _SearchPanelState extends State<SearchPanel> {
  /// 경량 검색용 디바운스. 글자마다 서버를 때리지 않게 잠깐 모았다 보낸다.
  static const _lightDebounce = Duration(milliseconds: 300);

  /// 경량이 빈손일 때 의미 검색으로 넘어가기 전에 한 번 더 기다리는 시간.
  /// 300ms를 그대로 쓰지 않는 이유는 클래스 주석에 적었다 — 의미 검색은 경량과
  /// 비용이 자릿수로 다르므로 "타이핑이 잠깐 멈췄다"가 아니라 "손을 뗐다"에
  /// 가까운 신호에서만 태운다. 이 값을 0으로 두면 "밥"·"밥 먹"·"밥 먹을"이 전부
  /// 모델을 태운다.
  static const _semanticGrace = Duration(milliseconds: 400);

  /// 두 단계의 대기를 **한 필드로** 돌린다. 한 시점에 살아 있을 수 있는 대기는
  /// 하나뿐이고(경량을 기다리는 중이거나, 경량이 끝나 의미 검색을 기다리는
  /// 중이거나), 취소 지점도 같다 — 새 글자가 오면 둘 다 죽어야 한다. 필드를
  /// 나누면 "경량 타이머는 껐는데 의미 타이머는 살아 있는" 조합이 생긴다.
  Timer? _debounce;

  /// 마지막으로 결과를 확정한 질의. "…에 맞는 매장을 찾지 못했어요" 문구에 쓴다.
  String _submittedQuery = '';
  List<PoiSearchResult> _results = const [];

  /// 이름이 걸린 건물. 매장과 함께 목록 맨 위에 한 줄로 얹는다 — 예전 상단
  /// 검색이 하던 "건물 이름 검색"을 여기로 옮겨 온 것이다.
  Building? _building;

  _SearchPhase _phase = _SearchPhase.idle;

  /// 이번 결과가 의미 검색에서 나왔는지. 목록에 "뜻으로 찾은 결과"라고 표시해
  /// 사용자가 왜 다른 이름이 나왔는지 납득할 수 있게 한다. 단계가 아니라 결과의
  /// 성질이라 [_SearchPhase]에 합치지 않고 따로 둔다.
  bool _fromSemantic = false;

  /// 마지막 탐색 응답의 원본 후보. [PoiSearchResult]로만 바꾸면 storeId와
  /// reason을 잃어 추천 이유·선택 후 추적을 할 수 없으므로 별도로 보존한다.
  List<DiscoveryMatch> _discoveryMatches = const [];

  /// 마지막 `/query/ai` 응답의 mode. 화면 상태는 이 값을 안전하게 명시 분기한다.
  DiscoveryMode? _discoveryMode;

  /// clarify일 때의 질문 문장.
  String? _discoveryQuestion;

  /// clarify일 때의 선택지.
  List<DiscoveryOption> _discoveryOptions = const [];

  /// stateless API에 매번 실어 보내는 facet 선택. 이 맵 하나가 화면 chip과
  /// 다음 요청 body의 공통 원본이라, 화면은 선택됐는데 요청에는 빠지는 상태를
  /// 만들지 않는다.
  Map<String, List<String>> _selectedFacets = const {};

  /// 최근 선택 순서. "다시 선택"은 마지막 질문의 답 하나만 되돌려 질문으로
  /// 복귀시킨다. 각 축은 현재 한 값을 선택하게 하므로 `(facet, value)`로 둔다.
  final List<(String facet, String value)> _facetSelectionOrder = [];

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
      // 엔터로 확정. 사용자가 이미 "다 쳤다"고 말한 셈이라 두 대기를 모두
      // 건너뛴다. 엔터가 의미 검색의 **유일한** 트리거는 아니지만, 가장 빠른
      // 트리거로는 남는다.
      _search(widget.query, immediate: true);
    } else if (widget.query != oldWidget.query) {
      _scheduleSearch(widget.query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// 타이핑마다 서버를 때리지 않도록 잠깐 모았다 보낸다. 여기서 시작한 검색도
  /// 경량이 빈손이면 의미 검색까지 이어진다 — 엔터를 안 눌러도 된다.
  void _scheduleSearch(String value) {
    _debounce?.cancel();
    // 새 입력이 들어온 순간 기존 요청을 무효화한다. 디바운스가 끝나기 전에도
    // 이전 검색의 늦은 응답이 화면을 덮으면, 화면의 검색어와 후보가 달라진다.
    _requestId++;
    _debounce = Timer(_lightDebounce, () => _search(value));
  }

  /// [immediate]가 참이면 의미 검색으로 넘어가기 전 [_semanticGrace] 대기를
  /// 건너뛴다. 엔터로 확정한 경우다.
  Future<void> _search(String raw, {bool immediate = false}) async {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      // 검색창을 비웠다. 진행 중인 응답이 나중에 도착해 빈 화면을 덮지 않도록
      // 순번도 함께 올린다.
      _requestId++;
      setState(() {
        _submittedQuery = '';
        _results = const [];
        _building = null;
        _fromSemantic = false;
        _discoveryMatches = const [];
        _discoveryMode = null;
        _discoveryQuestion = null;
        _discoveryOptions = const [];
        _selectedFacets = const {};
        _facetSelectionOrder.clear();
        _phase = _SearchPhase.idle;
      });
      return;
    }

    final requestId = ++_requestId;
    setState(() {
      // 새 원문 검색은 이전 clarify 선택의 연장이 아니다. 선택을 남기면 다른
      // 문장에 이전 facet이 섞여 stateless 계약의 의미가 깨진다.
      _selectedFacets = const {};
      _facetSelectionOrder.clear();
      _phase = _SearchPhase.typingLightSearch;
    });

    List<PoiSearchResult> results;
    Building? building;
    try {
      // 1단계: 경량 매칭. 매장 이름·동의어는 여기서 즉시 걸린다.
      // 현재 층을 함께 보낸다 — "화장실"처럼 시설을 가리키는 질의는 이래야
      // 지금 보고 있는 층으로 확정된다(안 보내면 건물 전체에서 정렬 순서상
      // 우연히 걸리는 층이 나온다). 매장을 이름으로 아는 검색이 다른 층에
      // 있어 여기서 빈손이 되더라도, 빈손이면 아래에서 층 제한이 없는 의미
      // 검색으로 자동으로 넘어가 그 매장을 여전히 찾아낸다.
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
      _finishFailed(query, requestId);
      return;
    }
    // 이 응답을 기다리는 사이 사용자가 더 쳤다면 버린다.
    if (!mounted || requestId != _requestId) return;

    // 2단계로 넘길지 판단한다. 예전에는 여기에 `allowSemantic`(=엔터를 눌렀다)
    // 조건이 하나 더 있었다. 그 조건이 빠지면서 "찾지 못했어요"는 의미 검색을
    // 지난 뒤에만 나올 수 있게 된다. 경량이 한 건이라도 잡으면 그대로 보여준다
    // — 잘 되던 검색은 여전히 빠르다.
    if (results.isEmpty && building == null) {
      if (immediate) {
        await _semanticSearch(query, requestId);
      } else {
        // 대기를 `Future.delayed`가 아니라 Timer로 두는 이유는 취소 때문이다.
        // 패널이 닫히면 dispose가 이 타이머를 끄고, 사용자가 글자를 더 치면
        // _scheduleSearch가 같은 필드를 덮어써 끈다. `await Future.delayed`는
        // 취소할 방법이 없어 패널이 사라진 뒤에도 살아 있다.
        _debounce = Timer(
          _semanticGrace,
          () => _semanticSearch(query, requestId),
        );
      }
      return;
    }

    setState(() {
      _submittedQuery = query;
      _results = results;
      _building = building;
      _fromSemantic = false;
      _discoveryMatches = const [];
      // 경량 매칭 결과라 discovery 계약과 무관하다 — 직전 AI 질의의 잔여
      // 질문/선택지가 이번 결과에 얹혀 보이지 않도록 함께 지운다.
      _discoveryMode = null;
      _discoveryQuestion = null;
      _discoveryOptions = const [];
      _phase = _SearchPhase.results;
    });
  }

  /// 2단계. 여기까지 왔다는 건 경량이 확실히 빈손이라는 뜻이고, 이 함수가 끝나야
  /// 비로소 [_SearchPhase.noMatch]를 최종 결론으로 쓸 수 있다.
  ///
  /// 백엔드 응답은 DiscoveryResponse(mode + question/options + matches)다.
  /// mode마다 명시적인 화면 상태로 옮긴다. 추천 후보는 [DiscoveryMatch] 원본을
  /// 별도 보관해 reason/storeId를 잃지 않고 기존 길찾기 콜백에는 변환값만 준다.
  Future<void> _semanticSearch(String query, int requestId) async {
    if (!mounted || requestId != _requestId) return;
    setState(() => _phase = _SearchPhase.semanticSearching);

    DiscoveryResult discovery;
    try {
      // 백엔드의 2차(의미) 단계는 current_floor_id를 받아도 건물 전체를 본다
      // (query_search.match_ai_destination 주석 참고) — 1차만 층으로 좁혀
      // 확정하고, 1차가 실패한 뒤인 여기서는 층을 또 좁히지 않는다. 그대로
      // 넘겨도 회귀가 없다.
      discovery = await destinationRepository.searchDestinationsAi(
        widget.buildingId,
        query,
        currentFloorId: widget.currentFloorId,
      );
    } on Object {
      _finishFailed(query, requestId);
      return;
    }
    if (!mounted || requestId != _requestId) return;

    final results = discovery.matches
        .map((match) => match.toPoiSearchResult())
        .toList();
    // 결과가 사실상 정확한 이름 일치면(예: 타 층 "나이키") "뜻이 비슷한"
    // 배너를 붙이지 않는다 — 실제로는 뜻으로 찾은 게 아니라 층 스코프 때문에
    // 1차가 빈손이 되어 여기로 넘어왔을 뿐이다.
    setState(() {
      _submittedQuery = query;
      _results = results;
      _building = null;
      _fromSemantic = results.isNotEmpty && !_isExactNameMatch(query, results);
      _discoveryMatches = discovery.matches;
      _discoveryMode = discovery.mode;
      _discoveryQuestion = discovery.question;
      _discoveryOptions = discovery.options;
      _phase = _phaseForDiscovery(discovery);
    });
  }

  _SearchPhase _phaseForDiscovery(DiscoveryResult discovery) {
    // 서버가 새 mode를 추가하거나 계약을 어긴 경우에는 후보를 임의로 추천하지
    // 않는다. 사용자가 다른 표현으로 재검색할 수 있는 안전한 noMatch로 보낸다.
    return switch (discovery.mode) {
      DiscoveryMode.direct => discovery.matches.isEmpty
          ? _SearchPhase.noMatch
          : _SearchPhase.results,
      DiscoveryMode.clarify => _SearchPhase.clarify,
      DiscoveryMode.results => discovery.matches.isEmpty
          ? _SearchPhase.noMatch
          : _SearchPhase.results,
      DiscoveryMode.noMatch || DiscoveryMode.unknown => _SearchPhase.noMatch,
      DiscoveryMode.degraded => _SearchPhase.degraded,
    };
  }

  /// facet 동작은 새 `/query/ai` 요청이다. 서버 세션이 없으므로 원문·현재 층·
  /// 선택 전체를 항상 다시 보내고, 요청 번호도 올려 과거 응답을 무효화한다.
  Future<void> _requestDiscovery({required bool showAll}) async {
    _debounce?.cancel();
    final query = widget.query.trim();
    if (query.isEmpty) return;

    final requestId = ++_requestId;
    setState(() => _phase = _SearchPhase.semanticSearching);
    try {
      final discovery = await destinationRepository.searchDestinationsAi(
        widget.buildingId,
        query,
        currentFloorId: widget.currentFloorId,
        selectedFacets: _selectedFacets.isEmpty
            ? null
            : Map<String, List<String>>.fromEntries(
                _selectedFacets.entries.map(
                  (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
                ),
              ),
        showAll: showAll,
      );
      if (!mounted || requestId != _requestId) return;

      final results = discovery.matches
          .map((match) => match.toPoiSearchResult())
          .toList();
      setState(() {
        _submittedQuery = query;
        _results = results;
        _building = null;
        _fromSemantic =
            results.isNotEmpty && !_isExactNameMatch(query, results);
        _discoveryMatches = discovery.matches;
        _discoveryMode = discovery.mode;
        _discoveryQuestion = discovery.question;
        _discoveryOptions = discovery.options;
        _phase = _phaseForDiscovery(discovery);
      });
    } on Object {
      _finishFailed(query, requestId);
    }
  }

  void _selectFacet(DiscoveryOption option) {
    final next = Map<String, List<String>>.fromEntries(
      _selectedFacets.entries.map(
        (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
      ),
    );
    // 한 질문은 한 축을 가리키므로 같은 축의 이전 선택은 교체한다. 다중 축은
    // 그대로 유지되어 다음 요청에 모두 전송된다.
    next[option.facet] = [option.value];
    setState(() {
      _selectedFacets = next;
      _facetSelectionOrder.removeWhere((item) => item.$1 == option.facet);
      _facetSelectionOrder.add((option.facet, option.value));
    });
    _requestDiscovery(showAll: false);
  }

  void _removeFacet(String facet, String value) {
    final next = Map<String, List<String>>.fromEntries(
      _selectedFacets.entries.map(
        (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
      ),
    );
    final values = next[facet];
    if (values == null) return;
    values.remove(value);
    if (values.isEmpty) next.remove(facet);
    setState(() {
      _selectedFacets = next;
      _facetSelectionOrder.removeWhere(
        (item) => item.$1 == facet && item.$2 == value,
      );
    });
    _requestDiscovery(showAll: false);
  }

  void _chooseAgain() {
    if (_facetSelectionOrder.isEmpty) {
      _requestDiscovery(showAll: false);
      return;
    }
    final last = _facetSelectionOrder.last;
    _removeFacet(last.$1, last.$2);
  }

  /// 서버 장애·네트워크 끊김. 패널을 닫지 않고 안내만 바꾼다. 이걸 "결과 없음"과
  /// 같이 처리하면, 백엔드가 죽었을 뿐인데 사용자에게 "그런 매장은 없다"고 말하는
  /// 셈이 된다 — 사용자는 말을 바꿔 가며 계속 헛수고를 하게 된다.
  void _finishFailed(String query, int requestId) {
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _submittedQuery = query;
      _results = const [];
      _building = null;
      _fromSemantic = false;
      _discoveryMatches = const [];
      _discoveryMode = null;
      _discoveryQuestion = null;
      _discoveryOptions = const [];
      _selectedFacets = const {};
      _facetSelectionOrder.clear();
      _phase = _SearchPhase.error;
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
    switch (_phase) {
      case _SearchPhase.idle:
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 22),
          child: Text(
            '매장 이름을 입력하면 바로 찾아드려요.\n'
            '"밥 먹을 곳"처럼 뜻으로 물어도 됩니다.',
            style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
          ),
        );
      case _SearchPhase.typingLightSearch:
      case _SearchPhase.semanticSearching:
        return _searchingState();
      case _SearchPhase.clarify:
      case _SearchPhase.results:
        return _resultList();
      case _SearchPhase.degraded:
        return _results.isEmpty ? _degradedState() : _resultList();
      case _SearchPhase.error:
        return _errorState();
      case _SearchPhase.noMatch:
        return _emptyState(context);
    }
  }

  /// 아직 결론이 아니라는 화면. 경량 단계에서는 스피너만 돌리고, 의미 검색으로
  /// 넘어가면 문구를 덧붙인다 — 여기서 갑자기 오래 걸리기 시작하기 때문에,
  /// 같은 스피너만 계속 돌면 사용자는 앱이 멈췄다고 읽는다.
  Widget _searchingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (_phase == _SearchPhase.semanticSearching) ...[
            const SizedBox(height: 14),
            const Text(
              '취향에 맞는 매장을 찾는 중…',
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

  Widget _resultList() {
    final rows = <Widget>[];
    final isDiscovery = _discoveryMode != null;
    if (isDiscovery) rows.add(_discoveryHeader());
    if (_fromSemantic) {
      rows.add(
        const Padding(
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
        ),
      );
    }
    final building = _building;
    if (building != null) {
      rows.add(
        ListTile(
          leading: const Icon(Icons.apartment_outlined, color: AppColors.primary),
          title: Text(
            building.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '건물 · ${building.floors.length}개 층',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          onTap: () => widget.onBuildingPicked(building),
        ),
      );
    }
    for (var index = 0; index < _results.length; index++) {
      final match = index < _discoveryMatches.length
          ? _discoveryMatches[index]
          : null;
      rows.add(_storeTile(_results[index], match));
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (_, index) => rows[index],
    );
  }

  Widget _discoveryHeader() {
    final isClarify = _discoveryMode == DiscoveryMode.clarify;
    final selectedChips = <Widget>[];
    for (final entry in _selectedFacets.entries) {
      for (final value in entry.value) {
        selectedChips.add(
          InputChip(
            key: Key('selected-facet-${entry.key}-$value'),
            label: Text('$value 선택됨'),
            onDeleted: () => _removeFacet(entry.key, value),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_discoveryMode == DiscoveryMode.degraded)
            const Text(
              '일부 추천 기능이 준비되지 않아 제한된 결과만 보여드려요.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          if (isClarify) ...[
            Text(
              _discoveryQuestion ?? '어떤 조건을 더 중요하게 보시나요?',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            if (_discoveryOptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _discoveryOptions
                    .map(
                      (option) => ActionChip(
                        key: Key('facet-option-${option.facet}-${option.value}'),
                        label: Text('${option.label} (${option.count})'),
                        onPressed: () => _selectFacet(option),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
          if (selectedChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: selectedChips),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: const Key('show-all'),
                onPressed: () => _requestDiscovery(showAll: true),
                child: const Text('전체 보기'),
              ),
              TextButton(
                key: const Key('choose-again'),
                onPressed: _chooseAgain,
                child: const Text('다시 선택'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storeTile(PoiSearchResult store, DiscoveryMatch? match) => ListTile(
    leading: const Icon(Icons.place_outlined, color: AppColors.primary),
    title: Text(
      store.name,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      match?.reason ??
          (store.nodeId == null ? '${store.floor} · 경로 안내 불가' : store.floor),
      style: const TextStyle(fontSize: 12, color: AppColors.muted),
    ),
    onTap: () => widget.onStorePicked(store),
  );

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
          // 이 문구가 나오는 시점에는 경량과 의미 검색을 모두 돌린 뒤다
          // (_SearchPhase.noMatch에서만 그린다). 사용자가 더 눌러 볼 수단이
          // 남아 있는 것처럼 보이면 안 되므로, 다른 말로 바꿔 보라고만 한다.
          const Text(
            '다른 말로 바꿔서 다시 찾아보세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _degradedState() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '추천 기능을 지금은 제한적으로만 사용할 수 있어요.',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            '잠시 후 다시 검색하거나 다른 표현으로 찾아보세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// 검색을 끝내지 못한 화면. "찾지 못했어요"와 문구를 나누는 이유는 사용자가
  /// 할 행동이 다르기 때문이다 — 여기서는 말을 바꿔도 소용이 없다.
  Widget _errorState() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '지금은 검색할 수 없어요.',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            '연결 상태를 확인하고 잠시 후 다시 시도해 주세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
