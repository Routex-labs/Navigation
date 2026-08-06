import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/service_locator.dart';
import '../domain/dijkstra.dart';
import '../models/building.dart';
import '../models/discovery_result.dart';
import '../models/outdoor_poi.dart';
import '../models/poi_search_result.dart';
import '../theme/app_theme.dart';
import 'category_icon.dart';
import 'reach_label.dart';
import 'transit_style.dart';

/// 상단 검색창 바로 아래에 붙는 결과 패널.
///
/// **입력창을 가지고 있지 않다.** 사용자는 상단 바의 검색창에 그대로 치고,
/// 이 패널은 그 글자를 받아 결과만 그린다. 예전에는 검색창을 탭하면 아래에서
/// 입력창이 하나 더 있는 시트가 올라왔는데, 방금 누른 창과 실제로 입력하는
/// 창이 달라 "왜 검색창이 두 개냐"는 인상을 줬다.
///
/// ## 어디에 서 있느냐가 무엇을 찾을지 정한다
///
/// 아래의 경량·의미 두 단계는 **건물 안을 보고 있을 때만** 돈다
/// ([indoorContextActive]). 밖에서는 건물 이름과 주변 장소만 찾고 건물 안
/// 매장은 조회조차 하지 않는다 — 이유는 그 필드 주석에 적었다.
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
    this.reachByNodeId,
    this.outdoorSearchCenter,
    this.onOutdoorPoiPicked,
    this.indoorContextActive = true,
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

  /// 현재 위치에서 각 그래프 노드까지의 거리·비용. 상위(MapShellScreen)가
  /// 검색을 시작할 때 한 번 계산해 내려준다.
  ///
  /// null이거나 매장의 노드가 여기 없으면 **거리 줄을 그리지 않는다.** 위치를
  /// 아직 안 잡았을 때 줄마다 "거리 알 수 없음"이 반복되면 목록이 읽히지 않고,
  /// 그 상태에서 사용자가 할 수 있는 일도 "위치 지정" 하나뿐이라 매 줄에
  /// 알릴 이유가 없다.
  final Map<String, NodeReach>? reachByNodeId;

  /// 건물 **밖** 장소를 함께 찾을 기준점. 야외를 보고 있을 때만 값이 있고,
  /// 실내 도면을 보고 있으면(또는 위치를 아직 못 잡았으면) null이다.
  ///
  /// null이면 바깥 검색을 아예 하지 않는다. 실내에서 "화장실"을 찾는 사람에게
  /// 길 건너 편의점 화장실을 섞어 주면, 지금 서 있는 층의 결과가 뒤로 밀린다.
  final LatLng? outdoorSearchCenter;

  /// 야외 장소를 골랐을 때. null이면 바깥 결과 줄을 눌러도 아무 일이 없으므로,
  /// [outdoorSearchCenter]가 있어도 이 콜백이 없으면 섹션을 그리지 않는다.
  final ValueChanged<OutdoorPoi>? onOutdoorPoiPicked;

  /// 지금 화면이 **건물 안**을 보고 있는지. 실내 탭이거나, 야외 탭이어도 실내
  /// 진입 오버레이가 켜져 있으면 참이다.
  ///
  /// 이 값이 **건물 안 매장을 찾을지 말지**를 정한다. 밖에 서 있는 사람이
  /// 정하는 것은 "어느 건물로 갈지"이지 그 안의 어느 매장인지가 아니다. 매장을
  /// 섞으면 "더현대"를 쳤을 때 목록이 그 안의 매장으로 채워져, 정작 고르려던
  /// 건물 줄이 뒤로 밀리거나 화면 밖으로 나간다.
  ///
  /// 건물 안 매장으로 가는 길이 막히는 것은 아니다. 건물 줄을 누르면 시트가
  /// "건물 안에서 매장 고르기"를 함께 묻고, 그쪽으로 들어가면 도면 위에서
  /// 매장을 직접 누를 수 있다.
  final bool indoorContextActive;

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

/// 이름에서 검색어와 일치하는 구간만 강조한 span 목록을 만든다.
///
/// **왜 강조하나** — 이 결과가 왜 나왔는지를 색으로 설명하기 위해서다. 예전에는
/// 이름 전체가 같은 굵기의 검정이라, 검색어와 한 글자도 안 겹쳐 보이는 결과가
/// 섞여 있어도 어디가 걸린 것인지 읽을 방법이 없었다.
///
/// **강조가 하나도 안 걸리는 것이 정상 상태다.** 의미 검색("밥 먹을 곳")은 이름에
/// 검색어가 없는 결과를 돌려주는 게 목적이고, 그 화면은 [SearchPanel._fromSemantic]
/// 배너가 대신 설명한다. 그래서 여기서는 못 찾았을 때 원문을 그대로 돌려줄 뿐
/// 실패로 다루지 않는다.
///
/// 대소문자·앞뒤 공백만 정규화하고 그 밖의 정규화(형태소 분석 등)는 하지 않는다.
/// 서버의 Kiwi 정규화까지 흉내내면 강조 구간이 오히려 서버 판정과 어긋난다 —
/// [_isExactNameMatch]와 같은 이유다. 그 결과 "더현대 서울"로 검색하면 띄어쓰기가
/// 다른 "더현대서울점"에는 강조가 걸리지 않는데, 이건 강조가 빠질 뿐 결과 자체는
/// 그대로 나오므로 손실이 없는 쪽으로 둔 선택이다.
List<TextSpan> highlightedNameSpans(String name, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return [TextSpan(text: name)];

  final haystack = name.toLowerCase();
  final spans = <TextSpan>[];
  var cursor = 0;
  while (true) {
    final index = haystack.indexOf(needle, cursor);
    if (index < 0) break;
    if (index > cursor) {
      spans.add(TextSpan(text: name.substring(cursor, index)));
    }
    spans.add(
      TextSpan(
        text: name.substring(index, index + needle.length),
        style: const TextStyle(color: AppColors.primary),
      ),
    );
    cursor = index + needle.length;
  }

  if (spans.isEmpty) return [TextSpan(text: name)];
  if (cursor < name.length) spans.add(TextSpan(text: name.substring(cursor)));
  return spans;
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

  /// 건물 밖 장소(TMAP POI). 실내 결과와 **따로** 들고 있는 이유는 두 목록의
  /// 수명이 다르기 때문이다 — 바깥 검색은 실내 검색보다 늦게 끝날 수 있고,
  /// 실내가 빈손이어도 여기 결과가 있으면 "찾지 못했어요"를 띄우면 안 된다.
  List<OutdoorPoi> _pois = const [];

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

  /// 직전 요청이 "전체 보기"였는가. 선택(facet) 없이 질문만 건너뛴 상태를
  /// 가리키므로 `_selectedFacets`로는 표현되지 않는다. 이 상태에서만 "다시 선택"이
  /// 질문으로 돌아가는 유일한 길이라, 헤더 버튼 노출 조건에 필요하다.
  bool _showingAll = false;

  /// 늦게 도착한 응답이 최신 결과를 덮어쓰지 않게 하는 순번.
  int _requestId = 0;

  /// 이번 검색의 두 다리가 각각 끝났는지. 밖에서 보고 있을 때 "찾지 못했어요"를
  /// 언제 띄울지 정하는 데만 쓴다([_concludeOutdoorOnly]).
  bool _lightSearchDone = false;
  bool _outdoorSearchDone = false;

  /// 결과 목록의 스크롤. Scrollbar와 스크롤뷰가 같은 컨트롤러를 봐야 막대가
  /// 실제 위치를 따라간다.
  final _resultScrollController = ScrollController();

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
    _resultScrollController.dispose();
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
        _pois = const [];
        _fromSemantic = false;
        _discoveryMatches = const [];
        _discoveryMode = null;
        _discoveryQuestion = null;
        _discoveryOptions = const [];
        _selectedFacets = const {};
        _facetSelectionOrder.clear();
        _showingAll = false;
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
      _showingAll = false;
      _pois = const [];
      _phase = _SearchPhase.typingLightSearch;
    });
    _lightSearchDone = false;
    _outdoorSearchDone = false;

    // 건물 밖 검색은 **기다리지 않는다.** 실내 검색과 나란히 출발시켜 두고,
    // 먼저 끝나는 쪽부터 화면에 붙인다. 순서대로 하면 실내 결과가 이미 나온
    // 화면에서 바깥 응답을 기다리느라 목록이 늦게 뜬다.
    unawaited(_searchOutdoorPois(query, requestId));

    var results = const <PoiSearchResult>[];
    Building? building;
    try {
      // 1단계: 경량 매칭. 매장 이름·동의어는 여기서 즉시 걸린다.
      // 현재 층을 함께 보낸다 — "화장실"처럼 시설을 가리키는 질의는 이래야
      // 지금 보고 있는 층으로 확정된다(안 보내면 건물 전체에서 정렬 순서상
      // 우연히 걸리는 층이 나온다). 매장을 이름으로 아는 검색이 다른 층에
      // 있어 여기서 빈손이 되더라도, 빈손이면 아래에서 층 제한이 없는 의미
      // 검색으로 자동으로 넘어가 그 매장을 여전히 찾아낸다.
      //
      // **밖에서는 이 요청을 아예 보내지 않는다**([indoorContextActive]).
      // 밖에 선 사람이 고르는 것은 건물이고, 매장은 건물에 닿아서 고른다.
      if (widget.indoorContextActive) {
        results = await destinationRepository.searchDestinations(
          widget.buildingId,
          query,
          currentFloorId: widget.currentFloorId,
        );
      }
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
    _lightSearchDone = true;

    // 2단계로 넘길지 판단한다. 예전에는 여기에 `allowSemantic`(=엔터를 눌렀다)
    // 조건이 하나 더 있었다. 그 조건이 빠지면서 "찾지 못했어요"는 의미 검색을
    // 지난 뒤에만 나올 수 있게 된다. 경량이 한 건이라도 잡으면 그대로 보여준다
    // — 잘 되던 검색은 여전히 빠르다.
    if (results.isEmpty && building == null) {
      // 밖에서는 의미 검색으로 넘어가지 않는다. 그 경로가 돌려주는 것도 결국
      // 건물 안 매장이라, 여기서 태우면 방금 뺀 결과가 뒷문으로 다시 들어온다.
      // 결론은 바깥 검색과 함께 [_concludeOutdoorOnly]가 낸다.
      if (!widget.indoorContextActive) {
        setState(() {
          _submittedQuery = query;
          _results = const [];
          _building = null;
          _fromSemantic = false;
          _discoveryMatches = const [];
          _discoveryMode = null;
          _discoveryQuestion = null;
          _discoveryOptions = const [];
        });
        _concludeOutdoorOnly(query, requestId);
        return;
      }
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

  /// 건물 밖 장소 검색(TMAP POI). 실내 검색과 **독립적으로** 돈다.
  ///
  /// 실패해도 화면 단계([_phase])를 건드리지 않는다. 이 검색은 곁들이는
  /// 정보라, 바깥 조회가 실패했다고 실내 결과까지 오류 화면으로 덮으면 원래
  /// 되던 검색이 같이 죽는다.
  Future<void> _searchOutdoorPois(String query, int requestId) async {
    final center = widget.outdoorSearchCenter;
    // **건너뛰는 이유를 반드시 남긴다.** 이 세 조건 중 하나만 걸려도 화면에는
    // "바깥 결과가 없다"와 똑같이 보인다. 실제로 기준점이 null이라 한 번도 안
    // 돌던 시기를 로그 없이 지나쳤다.
    if (center == null) {
      debugPrint('[tmap-poi] 건너뜀: 검색 기준점 없음(위치·카메라 모두 미확보)');
      _finishOutdoorLeg(query, requestId, const []);
      return;
    }
    if (widget.onOutdoorPoiPicked == null) {
      debugPrint('[tmap-poi] 건너뜀: 선택 콜백 없음');
      _finishOutdoorLeg(query, requestId, const []);
      return;
    }
    if (!outdoorPoiRepository.isAvailable) {
      debugPrint('[tmap-poi] 건너뜀: TMAP_APP_KEY 미주입');
      _finishOutdoorLeg(query, requestId, const []);
      return;
    }
    final pois = await outdoorPoiRepository.searchNearby(query, center: center);
    _finishOutdoorLeg(query, requestId, pois);
  }

  /// 바깥 조회가 끝났다(건너뛴 경우 포함). 결과를 반영하고 결론을 시도한다.
  void _finishOutdoorLeg(String query, int requestId, List<OutdoorPoi> pois) {
    // 늦게 도착한 응답이 다음 검색어의 화면을 덮지 않게 한다(실내와 같은 규칙).
    if (!mounted || requestId != _requestId) return;
    _outdoorSearchDone = true;
    if (pois.isNotEmpty) {
      setState(() {
        _pois = pois;
        // 이름 강조가 쓰는 질의어. 실내 검색이 아직 안 끝났을 수 있어 여기서도
        // 채운다 — 안 채우면 이전 검색어 기준으로 강조가 걸린다.
        _submittedQuery = query;
      });
    }
    _concludeOutdoorOnly(query, requestId);
  }

  /// 밖에서 보고 있을 때 화면을 결론짓는다.
  ///
  /// 밖에서는 실내 검색도 의미 검색도 돌리지 않으므로(그 결과를 일부러 뺐다)
  /// 결론을 낼 사람이 이 함수뿐이다. 여기서 아무 것도 안 하면 스피너가 영원히
  /// 돈다 — 사용자에게는 "검색이 멈춘 앱"으로 보인다.
  ///
  /// **두 다리가 모두 끝났을 때만 결론을 낸다.** 바깥 조회는 기준점이 없거나
  /// TMAP 키가 없으면 그 자리에서 즉시 끝나는데, 그때는 건물 이름 조회가 아직
  /// 돌고 있다. 한쪽만 보고 결론지으면 "찾지 못했어요"가 한 번 번쩍인 뒤 곧바로
  /// 건물 줄로 바뀌는 화면이 된다.
  ///
  /// 건물 안을 보고 있을 때는 아무 것도 하지 않는다 — 그쪽은 실내 검색이 결론을
  /// 갖고 있고, 여기서 손대면 아직 도는 중인 화면을 덮어쓴다.
  void _concludeOutdoorOnly(String query, int requestId) {
    if (!mounted || requestId != _requestId) return;
    if (widget.indoorContextActive) return;
    if (!_lightSearchDone || !_outdoorSearchDone) return;
    setState(() {
      _submittedQuery = query;
      _phase = (_building == null && _pois.isEmpty)
          ? _SearchPhase.noMatch
          : _SearchPhase.results;
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
      DiscoveryMode.direct =>
        discovery.matches.isEmpty ? _SearchPhase.noMatch : _SearchPhase.results,
      DiscoveryMode.clarify => _SearchPhase.clarify,
      DiscoveryMode.results =>
        discovery.matches.isEmpty ? _SearchPhase.noMatch : _SearchPhase.results,
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
                  (entry) =>
                      MapEntry(entry.key, List<String>.from(entry.value)),
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
        _showingAll = showAll;
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
      _showingAll = false;
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
    // 건물 밖 결과가 하나라도 있으면 **어떤 단계에서도** 목록을 보여준다.
    //
    // 실내 검색이 아직 돌고 있거나(스피너) 빈손으로 끝났거나(결과 없음)
    // 실패했더라도(오류), 사용자가 찾던 곳이 바깥에 이미 잡혀 있는데 그
    // 화면들을 띄우면 답을 손에 쥐고도 못 보여 주는 셈이 된다. 실내가 아직
    // 도는 중이라는 사실은 목록 안의 진행 줄이 대신 알린다.
    final hasOutdoor = _pois.isNotEmpty;
    switch (_phase) {
      case _SearchPhase.idle:
        // 안내 문구는 지금 실제로 찾아 줄 수 있는 것만 말한다. 밖에서
        // "매장 이름을 입력하면 바로 찾아드려요"라고 해 놓고 매장을 안 찾아
        // 주면, 사용자는 앱이 고장 났다고 읽는다.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
          child: Text(
            widget.indoorContextActive
                ? '매장 이름을 입력하면 바로 찾아드려요.\n'
                      '"밥 먹을 곳"처럼 뜻으로 물어도 됩니다.'
                : '건물 이름이나 주변 장소를 입력해 보세요.\n'
                      '건물을 고르면 그 안의 매장까지 이어서 안내해요.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              height: 1.5,
            ),
          ),
        );
      case _SearchPhase.typingLightSearch:
      case _SearchPhase.semanticSearching:
        return hasOutdoor ? _resultList() : _searchingState();
      case _SearchPhase.clarify:
      case _SearchPhase.results:
        return _resultList();
      case _SearchPhase.degraded:
        return _results.isEmpty && !hasOutdoor
            ? _degradedState()
            : _resultList();
      case _SearchPhase.error:
        return hasOutdoor ? _resultList() : _errorState();
      case _SearchPhase.noMatch:
        return hasOutdoor ? _resultList() : _emptyState(context);
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
    // 바깥 결과 덕분에 목록이 먼저 떴을 뿐, 건물 안 검색은 아직 돌고 있을 수
    // 있다. 그 사실을 안 밝히면 사용자는 이게 최종 목록이라고 읽는다.
    //
    // 밖에서는 건물 안을 뒤지지 않으므로 이 줄도 뜨지 않는다 — 돌지도 않는
    // 검색을 "찾는 중"이라고 말하면 오지 않을 결과를 기다리게 된다.
    if (widget.indoorContextActive &&
        (_phase == _SearchPhase.typingLightSearch ||
            _phase == _SearchPhase.semanticSearching)) {
      rows.add(const _IndoorSearchingRow());
    }
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
          leading: const Icon(
            Icons.apartment_outlined,
            color: AppColors.primary,
          ),
          title: Text.rich(
            TextSpan(
              children: highlightedNameSpans(building.name, _submittedQuery),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

    // 건물 밖 결과는 **항상 실내 아래**에 둔다. 이 앱의 본업은 건물 안 길찾기라,
    // 같은 이름이 안팎에 다 있으면 사용자가 지금 서 있는 건물 안 매장을 먼저
    // 보는 것이 맞다. 대신 어디까지가 우리 건물이고 어디부터 바깥인지 헤더로
    // 명확히 가른다 — 안 가르면 다른 건물 매장을 우리 매장으로 오해한다.
    final onPoiPicked = widget.onOutdoorPoiPicked;
    final pois = _poisExcludingBuilding(building);
    if (pois.isNotEmpty && onPoiPicked != null) {
      rows.add(_outdoorHeader());
      for (final poi in pois) {
        rows.add(_poiTile(poi, onPoiPicked));
      }
    }

    // 왜 ListView(shrinkWrap)가 아니라 SingleChildScrollView + Column인가.
    //
    // 이 패널은 결과가 적으면 내용만큼만 높고, 많으면 상위가 준 maxHeight 안에서
    // 스크롤돼야 한다. `ListView(shrinkWrap: true)`가 그 두 가지를 다 해줄 것 같지만,
    // 느슨한 제약(maxHeight만 있고 tight가 아닌) 안에서는 스크롤 범위를 실제 내용보다
    // 짧게 잡아 **목록의 마지막 항목에 영영 도달하지 못했다.** 30건을 받아 끝까지
    // 내려도 29번째에서 멈췄다(스크롤 위치는 최대값인데 마지막 타일이 안 나온다).
    //
    // Column은 자식을 전부 즉시 만들지만, 이 목록의 상한은 서버 쪽
    // MAX_SHOW_ALL_MATCHES(30)이라 지연 생성으로 아낄 것이 없다. 상한이 크게 늘면
    // 그때 다시 볼 문제다.
    final children = <Widget>[];
    for (var index = 0; index < rows.length; index++) {
      if (index > 0) {
        children.add(const Divider(height: 1, indent: 16));
      }
      children.add(rows[index]);
    }

    return Scrollbar(
      controller: _resultScrollController,
      child: SingleChildScrollView(
        controller: _resultScrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  /// 이미 위에 "건물" 줄로 올라간 곳과 같은 장소를 가리키는 바깥 결과를 뺀다.
  ///
  /// TMAP도 "더현대서울"을 POI 한 건으로 돌려주므로, 그냥 두면 같은 건물이
  /// 목록에 두 번 뜬다. 헷갈리는 것으로 끝나지 않고 **둘이 하는 일이 다르다** —
  /// 위쪽 건물 줄은 시트를 열어 건물 안 매장까지 이어 주지만, 아래쪽은 좌표
  /// 하나짜리 야외 장소라 건물 앞에서 안내가 끝난다. 아래를 누른 사용자는
  /// 기능이 반쯤 죽은 쪽으로 새는 셈이라 아예 지운다.
  ///
  /// 공백을 지우고 대소문자를 맞춘 뒤 **완전 일치**로만 판정한다("더현대 서울"
  /// = "더현대서울"). contains로 넓히면 "더현대서울 스타벅스"처럼 건물 이름을
  /// 앞에 달고 있는 진짜 결과까지 함께 사라진다 — 중복 한 줄을 지우려다 찾던
  /// 매장을 지우는 쪽이 훨씬 나쁘다.
  List<OutdoorPoi> _poisExcludingBuilding(Building? building) {
    if (building == null || _pois.isEmpty) return _pois;
    final key = _collapse(building.name);
    return _pois.where((poi) => _collapse(poi.name) != key).toList();
  }

  static String _collapse(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  Widget _discoveryHeader() {
    final isClarify = _discoveryMode == DiscoveryMode.clarify;
    final hasSelection = _selectedFacets.isNotEmpty;

    // 두 버튼은 clarify 흐름의 조작 수단이라, 되물음이 없는 화면에 두면 누를 대상이
    // 없는 버튼이 된다. 예전에는 이 Wrap이 조건 없이 렌더돼 direct("커피" 1건)·
    // no_match에서도 떴다. mode가 화면 분기의 유일한 근거라는 계약(DiscoveryResponse
    // 주석)을 헤더에서도 지킨다.
    //
    // "전체 보기"는 아직 안 본 후보가 남아 있을 때만 뜻이 있다 — 질문이 서 있거나
    // (clarify) 선택으로 좁혀진 상태다. 이미 전체를 보고 있으면 다시 눌러야 그대로다.
    final canShowAll = (isClarify || hasSelection) && !_showingAll;
    // "다시 선택"은 되돌릴 답이 있을 때다. 선택 없이 전체 보기로 질문을 건너뛴
    // 상태도 포함한다 — 그 화면에서는 이 버튼이 질문으로 돌아가는 유일한 길이다.
    final canChooseAgain = hasSelection || _showingAll;

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
                        key: Key(
                          'facet-option-${option.facet}-${option.value}',
                        ),
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
          if (canShowAll || canChooseAgain) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                if (canShowAll)
                  TextButton(
                    key: const Key('show-all'),
                    onPressed: () => _requestDiscovery(showAll: true),
                    child: const Text('전체 보기'),
                  ),
                if (canChooseAgain)
                  TextButton(
                    key: const Key('choose-again'),
                    onPressed: _chooseAgain,
                    child: const Text('다시 선택'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 결과 한 줄. 이름(검색어 강조) + 업종을 한 줄에 두고, 그 아래 층 또는 추천 이유.
  ///
  /// 업종을 왼쪽 아이콘이 아니라 **이름 오른쪽 회색 글자**로 두는 이유는, 매장마다
  /// 다른 글리프를 만들지 않고도 소분류까지 그대로 읽히기 때문이다. 왼쪽 아이콘은
  /// "이건 장소다"만 말하면 되므로 한 종류로 충분하다.
  Widget _storeTile(PoiSearchResult store, DiscoveryMatch? match) {
    // 소분류가 없는 장소에서 업종이 통째로 사라지지 않도록 대분류로 떨어뜨린다 —
    // 상세 시트를 여는 호출부(MapShellScreen._showStoreInfo)와 같은 규칙이다.
    final categoryLabel =
        subcategoryLabelFor(store.subcategory) ?? store.category;
    // 노드가 없는 매장은 애초에 경로를 못 그리므로 거리도 없다. 그 사실은
    // 아래 첫 줄의 "경로 안내 불가"가 이미 말한다.
    final nodeId = store.nodeId;
    final reach = nodeId == null ? null : widget.reachByNodeId?[nodeId];
    final firstLine =
        match?.reason ??
        (nodeId == null ? '${store.floor} · 경로 안내 불가' : store.floor);
    return ListTile(
      leading: const Icon(Icons.place_outlined, color: AppColors.primary),
      title: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: highlightedNameSpans(store.name, _submittedQuery),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          if (categoryLabel != null) ...[
            const SizedBox(width: 8),
            // 업종이 길어도 이름 자리를 먹지 않도록 상한을 둔다. 이름이 먼저
            // 읽혀야 하는 줄이라 남는 폭은 이름 쪽에 준다.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 84),
              child: Text(
                categoryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            firstLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (reach != null)
            Text(
              reachLabel(reach),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 거리는 "지금 갈지"를 정하는 값이라 층보다 한 단계 진하게 둔다.
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      // 두 줄짜리 subtitle은 ListTile에 알려야 세로 정렬이 맞는다.
      isThreeLine: reach != null,
      onTap: () => widget.onStorePicked(store),
    );
  }

  /// "건물 밖" 구분선. 여기부터는 우리 백엔드가 아니라 외부 지도(TMAP)에서 온
  /// 결과라는 것도 함께 밝힌다 — 정보의 깊이가 다른 이유이고, 실제와 다를 때
  /// 사용자가 어디를 의심할지 알려 준다.
  Widget _outdoorHeader() {
    // "건물 밖"은 **건물 안에서 볼 때** 뜻이 있는 말이다. 밖에 서서 보는
    // 목록에서는 여기가 바깥인 게 당연하므로 그냥 "주변 장소"다.
    final label = widget.indoorContextActive ? '건물 밖 주변 장소' : '주변 장소';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.explore_outlined, size: 14, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
          const Text(
            'TMAP',
            style: TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// 건물 밖 장소 한 줄. 실내 줄과 모양을 맞추되, **층 대신 주소와 직선 거리**를
  /// 적는다. 밖에서는 같은 이름의 지점이 여럿이라, 어느 지점인지 가르는 단서가
  /// 층이 아니라 주소다.
  Widget _poiTile(OutdoorPoi poi, ValueChanged<OutdoorPoi> onPicked) {
    final distance = poi.distanceMeters;
    final subtitleParts = [
      if (distance != null) '약 ${formatTransitDistance(distance)}',
      if (poi.address != null) poi.address!,
    ];
    return ListTile(
      leading: const Icon(Icons.storefront_outlined, color: AppColors.muted),
      title: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: highlightedNameSpans(poi.name, _submittedQuery),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          if (poi.category != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 84),
              child: Text(
                poi.category!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
      onTap: () => onPicked(poi),
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
            widget.indoorContextActive
                ? '"$_submittedQuery"에 맞는 매장을 찾지 못했어요.'
                : '"$_submittedQuery"에 맞는 건물이나 장소를 찾지 못했어요.',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          // 이 문구가 나오는 시점에는 (건물 안이면) 경량과 의미 검색을 모두
          // 돌린 뒤이고, 밖이면 건물 이름과 주변 장소를 모두 훑은 뒤다. 사용자가
          // 더 눌러 볼 수단이 남아 있는 것처럼 보이면 안 되므로, 다른 말로 바꿔
          // 보라고만 한다.
          Text(
            widget.indoorContextActive
                ? '다른 말로 바꿔서 다시 찾아보세요.'
                : '건물 이름으로 찾은 뒤, 건물 안에서 매장을 골라도 됩니다.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
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

/// 목록 맨 위에 붙는 "건물 안은 아직 찾는 중" 줄.
///
/// 바깥 결과가 먼저 도착해 목록이 뜬 상태를 위한 것이다. 이 줄이 없으면
/// 사용자는 지금 보이는 것이 전부라고 읽고, 잠시 뒤 실내 결과가 위에 끼어들며
/// 목록이 통째로 밀린다.
class _IndoorSearchingRow extends StatelessWidget {
  const _IndoorSearchingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            '건물 안에서도 찾는 중…',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
