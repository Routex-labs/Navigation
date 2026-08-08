import 'dart:async';

import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../domain/dijkstra.dart';
import '../domain/name_siblings.dart';
import '../domain/nearest_store.dart';
import '../domain/reason_text.dart';
import '../domain/search_result_order.dart';
import '../domain/store_suggestions.dart';
import '../models/building.dart';
import '../models/category_count.dart';
import '../models/discovery_result.dart';
import '../models/poi_search_result.dart';
import '../models/store_index_entry.dart';
import '../theme/app_theme.dart';
import 'category_icon.dart';
import 'category_label_order.dart';
import 'filter_pill.dart';
import 'reach_label.dart';

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
    required this.onQueryPicked,
    required this.indoorContextActive,
    this.currentFloorId,
    this.reachByNodeId,
    this.categoryEntries,
    this.onCategoryPicked,
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

  final ValueChanged<PoiSearchResult> onStorePicked;
  final ValueChanged<Building> onBuildingPicked;

  /// 최근 검색어를 골랐을 때. 패널이 입력창을 갖고 있지 않으므로(클래스 주석
  /// 참고) 검색을 스스로 다시 돌릴 수 없다 — 상위가 검색창 글자를 그 값으로
  /// 바꾸고 [query]·[submitTick]을 새로 내려줘야 한 바퀴가 돈다.
  final ValueChanged<String> onQueryPicked;

  /// 지금 건물 안을 보고 있는가(실내 모드이거나, 야외 지도 위에서 실내 도면을
  /// 훑는 중). 상위의 `_indoorContextActive`를 그대로 받는다.
  ///
  /// **자동완성은 이 값이 참일 때만 동작한다.** 후보의 원본이 건물 하나의 매장
  /// 목록이라, 야외에서 쓰면 지금 서 있는 곳과 무관한 매장을 제안하게 된다.
  /// 실제로 시청 앞 야외 지도에서 `apc`를 치니 더현대서울 3층 매장이 후보로
  /// 떴다 — 사용자가 야외에서 찾는 것은 그게 아니다.
  ///
  /// 야외 장소 검색은 외부 검색 API(Tmap 등)로 별도로 채울 예정이며, 그때
  /// 이 패널이 어느 원본을 쓸지는 이 값으로 갈린다.
  final bool indoorContextActive;

  /// 건물의 (층·대분류·소분류)별 매장 수. **상위가 이미 들고 있는 Future를 그대로
  /// 받는다** — 여기서 다시 요청하면 같은 정보를 두 번 받게 되고, 두 화면의
  /// 카테고리 목록이 어긋날 수 있다.
  ///
  /// "찾지 못했어요" 화면에서 **둘러볼 곳**을 제안하는 데만 쓴다(설계:
  /// `docs/client/search-result-list-ux.md` R절). null이거나 로드가 실패하면
  /// 그 줄만 조용히 사라진다.
  final Future<List<CategoryCount>>? categoryEntries;

  /// 위 대분류를 골랐을 때. 상위가 검색을 닫고 그 카테고리의 매장 목록 시트를
  /// 연다. null이면 제안 줄을 그리지 않는다.
  final ValueChanged<String>? onCategoryPicked;

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

  /// **온디바이스 후보로 답했다.** 서버 경량 매칭은 빈손이었지만 기기 안 인덱스가
  /// 이름으로 매장을 찾은 상태다. 이때는 의미 검색으로 넘어가지 않는다 — 근거는
  /// [_SearchPanelState._search]의 분기 주석에 있다.
  suggestions,

  /// 경량과 의미 검색을 **둘 다** 끝냈는데 없다. 최종 "결과 없음" 문구는 오직
  /// 이 단계에서만 나온다.
  noMatch,

  /// 의미 모델은 쓸 수 없지만 경량/태그 후보는 남아 있을 수 있다.
  degraded,

  /// 서버·네트워크가 끊겨 검색을 끝내지 못했다. 없는 것과 못 찾은 것은 사용자가
  /// 할 행동이 다르다 — 전자는 다른 말로 바꿔야 하고, 후자는 기다려야 한다.
  error,
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
/// [isExactNameMatch]와 같은 이유다. 그 결과 "더현대 서울"로 검색하면 띄어쓰기가
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

/// 다음 검색 한 번에만 적용할 층 스코프.
///
/// **예전에는 "층으로 좁히지 마라"는 bool 하나였다.** 1F에서 `apc` 후보로 뜬 3F의
/// `A.P.C.`를 탭하면 층 스코프 때문에 1차가 빈손이 되어 후보 화면으로 되돌아오던
/// 문제를 그렇게 막았다. 그런데 스코프를 아예 빼면 **어느 매장을 고를지는 서버가
/// 자기 순서로 정한다.**
///
/// 실기기에서 그 대가가 드러났다. 1F에서 후보 `화장실 · 1F 등 19곳 · 57m`를 탭했더니
/// **`화장실 · B6 · 219m`** 로 갔다. 화면이 1F라고 적어 놓고 네 배 먼 지하 6층으로
/// 보낸 것이다. 같은 이름이 19곳이니 서버는 그중 하나를 고를 수밖에 없는데, 그
/// 기준에 사용자 위치가 들어갈 자리가 없다.
///
/// **고른 후보의 층을 실어 보내면 둘 다 풀린다.** `A.P.C.`는 3F로 좁혀 확정되고,
/// `화장실`은 화면에 적힌 그 1F로 확정된다. 추가 요청도, 계약 변경도 없다.
///
/// [floorId]가 null인 경우는 **층을 모르는 선택**이다 — 최근 검색어는 문자열
/// 하나뿐이라 어느 층 매장이었는지 알 방법이 없다. 그때만 예전처럼 스코프를 뺀다.
///
/// 설계 근거와 검증 기준은 `docs/client/search-result-list-ux.md` T절이 단일
/// 출처다.
class _FloorScopeOverride {
  const _FloorScopeOverride(this.floorId);

  /// 이 층으로 좁힌다. null이면 좁히지 않는다.
  final String? floorId;
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

  /// 직전 요청이 "전체 보기"였는가. 선택(facet) 없이 질문만 건너뛴 상태를
  /// 가리키므로 `_selectedFacets`로는 표현되지 않는다. 이 상태에서만 "다시 선택"이
  /// 질문으로 돌아가는 유일한 길이라, 헤더 버튼 노출 조건에 필요하다.
  bool _showingAll = false;

  /// 늦게 도착한 응답이 최신 결과를 덮어쓰지 않게 하는 순번.
  int _requestId = 0;

  /// 결과 목록의 스크롤. Scrollbar와 스크롤뷰가 같은 컨트롤러를 봐야 막대가
  /// 실제 위치를 따라간다.
  final _resultScrollController = ScrollController();

  /// 온디바이스 자동완성의 원본. 건물당 1회 받아 둔다.
  ///
  /// null은 "아직 못 받았거나 받기에 실패했다"는 뜻이고, **그 상태가 정상 경로에
  /// 포함된다.** 자동완성은 부가 기능이라 목록이 없으면 후보만 조용히 사라지고
  /// 서버 검색은 그대로 돈다(설계: search-input-assist.md K절 실패 조건).
  List<StoreIndexEntry>? _storeIndex;

  /// 지금 질의에 대한 후보. **질의가 바뀔 때만** 다시 계산한다 — build에서 매번
  /// 계산하면 한 프레임에 여러 번 1640건을 훑는다.
  List<StoreSuggestion> _suggestions = const [];

  /// 사용자가 직접 고른 정렬. null이면 아직 안 골랐다는 뜻이고, 그때는
  /// [defaultSortOrder]가 위치 유무를 보고 정한다.
  ///
  /// **검색어가 바뀌면 지운다**(didUpdateWidget). 세션에 저장하면 다음 검색이
  /// 사용자가 기억하지 못하는 순서로 시작한다. 반대로 같은 검색어로 다시 엔터를
  /// 누르는 경우에는 유지한다 — 방금 한 조작이 사라지면 안 된다.
  SearchSortOrder? _sortOverride;

  /// 다음 검색 **한 번만** 층 스코프를 이 값으로 바꾼다. null이면 재정의 없이
  /// [SearchPanel.currentFloorId]를 그대로 쓴다.
  ///
  /// 목록에서 무언가를 **탭한 경우**에 선다. 층 스코프는 "화장실"처럼 사용자가
  /// 직접 친 시설 질의를 지금 보는 층으로 확정하려고 있는 것이지, 목록에서 특정
  /// 대상을 콕 집은 행동에 그대로 적용할 것이 아니다.
  ///
  /// 왜 bool이 아니라 층 값인지는 [_FloorScopeOverride] 주석에 있다.
  _FloorScopeOverride? _floorScopeOnce;

  @override
  void initState() {
    super.initState();
    if (widget.indoorContextActive) _loadStoreIndex();
    // 검색창에 글자가 남아 있는 채로 패널이 다시 열릴 수 있다.
    if (widget.query.trim().isNotEmpty) _scheduleSearch(widget.query);
  }

  /// 후보 원본을 받아 둔다. 실패는 삼킨다 — 위 [_storeIndex] 주석 참고.
  Future<void> _loadStoreIndex() async {
    try {
      final index = await buildingRepository.getStoreIndex(widget.buildingId);
      if (!mounted || index == null) return;
      setState(() {
        _storeIndex = index;
        // 목록이 늦게 도착하는 동안 사용자가 이미 치고 있었을 수 있다.
        _suggestions = _computeSuggestions(widget.query);
      });
    } on Object {
      // 자동완성만 포기한다. 검색을 막지 않는다.
    }
  }

  List<StoreSuggestion> _computeSuggestions(String query) {
    // 야외에서는 후보를 만들지 않는다 — 이유는 [SearchPanel.indoorContextActive].
    if (!widget.indoorContextActive) return const [];
    final index = _storeIndex;
    if (index == null) return const [];
    return suggestStores(stores: index, query: query);
  }

  @override
  void didUpdateWidget(covariant SearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 야외 → 실내로 들어오면 그때 원본을 받는다. 야외에서 미리 받아 두면 쓰지도
    // 않을 목록을 내려받는 것이고, 실내로 들어온 뒤에는 후보가 있어야 한다.
    if (widget.indoorContextActive && !oldWidget.indoorContextActive) {
      _loadStoreIndex();
    }
    if (widget.query != oldWidget.query ||
        widget.indoorContextActive != oldWidget.indoorContextActive) {
      // 서버 응답을 기다리지 않는다. 이게 자동완성이 즉시 뜨는 이유다.
      _suggestions = _computeSuggestions(widget.query);
    }
    // 새 검색어면 정렬 선택을 지운다. 엔터 재확정(submitTick만 오름)은 같은
    // 검색어라 유지한다.
    if (widget.query != oldWidget.query) _sortOverride = null;
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
      // 목록에서 고른 검색이면 **고른 그 매장의 층**으로 좁힌다(위
      // [_FloorScopeOverride]). 층을 모르는 선택(최근 검색어)만 스코프를 뺀다.
      final override = _floorScopeOnce;
      final floorScope = override != null
          ? override.floorId
          : widget.currentFloorId;
      _floorScopeOnce = null;
      results = await destinationRepository.searchDestinations(
        widget.buildingId,
        query,
        currentFloorId: floorScope,
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
      // **이름이 실제로 걸렸으면 의미 검색으로 넘어가지 않는다.**
      //
      // 실기기에서 `apc`로 확인한 문제다. 서버 경량 매칭은 `name LIKE %apc%`라
      // 구두점이 든 `A.P.C.`를 못 잡고 `no_match`를 준다. 그런데 온디바이스
      // 인덱스는 정규화 키로 이미 그 매장을 찾아 화면에 띄워 둔 상태다. 여기서
      // 2차로 넘어가면 그 정답이 스피너에 덮이고, 임계값 0.50을 겨우 넘은
      // 의미 검색이 **주차구역(6A·6E)** 을 "뜻이 비슷한 매장"이라며 확정했다.
      // 맞는 답을 보여주다가 틀린 답으로 갈아치운 셈이다.
      //
      // FAISS.md 11절이 정한 역할 분리("정확한 이름은 1차가 확정하고 임베딩은
      // 말로 푸는 질의만 담당")를 그대로 따르는 것이며, 달라진 건 그 1차가
      // 서버뿐 아니라 온디바이스 인덱스이기도 하다는 점이다.
      //
      // 교정 후보만 있을 때는 넘긴다 — 그건 추측이라 의미 검색이 더 나을 수
      // 있고, 2차도 실패하면 noMatch 화면이 그 교정 후보를 되묻는다.
      if (_suggestions.any((s) => !s.kind.isCorrection)) {
        setState(() {
          _submittedQuery = query;
          _results = const [];
          _building = null;
          _fromSemantic = false;
          _discoveryMatches = const [];
          _discoveryMode = null;
          _discoveryQuestion = null;
          _discoveryOptions = const [];
          _phase = _SearchPhase.suggestions;
        });
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
      _fromSemantic =
          results.isNotEmpty &&
          !isExactNameMatch(query, results.map((r) => r.name));
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
            results.isNotEmpty &&
            !isExactNameMatch(query, results.map((r) => r.name));
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
    // **후보를 띄울지는 단계가 아니라 "이번 글자의 답이 있는가"로 정한다.**
    //
    // [_phase]로 판단하면 안 되는 이유가 있다. 디바운스(300ms) 동안에는 아직
    // 요청이 시작조차 안 해서 단계가 그대로 남아 있다 — 첫 글자에는 [idle],
    // 두 번째 검색부터는 **직전 질의의 [results]** 다. 즉 단계만 보면 사용자가
    // 이미 다른 말을 치고 있는데 화면은 이전 결과를 계속 보여준다.
    //
    // [_submittedQuery]는 지금 화면에 그려진 결과가 어느 질의의 것인지를 담고
    // 있으므로, 검색창 글자와 다르면 "아직 이번 글자의 답이 아니다"가 된다.
    // 온디바이스 후보는 0ms에 나오니 그 사이를 후보로 채운다.
    final awaitingAnswer = widget.query.trim() != _submittedQuery;
    if (_suggestions.isNotEmpty &&
        awaitingAnswer &&
        // 의미 검색만 예외다. 여기까지 왔다는 건 이름으로 걸린 후보가 없었다는
        // 뜻이라(위 _search 분기) 후보로 덮을 것도 없고, 여기서만 몇 초가 걸릴 수
        // 있어 "AI가 찾는 중"이라는 사실 자체가 화면에 있어야 한다.
        _phase != _SearchPhase.semanticSearching) {
      return _suggestionList(settled: false);
    }

    switch (_phase) {
      case _SearchPhase.idle:
        return _idleState();
      case _SearchPhase.typingLightSearch:
      case _SearchPhase.semanticSearching:
        return _searchingState();
      case _SearchPhase.suggestions:
        return _suggestionList(settled: true);
      case _SearchPhase.clarify:
      case _SearchPhase.results:
        return _resultList();
      case _SearchPhase.degraded:
        return _results.isEmpty ? _degradedState() : _resultList();
      case _SearchPhase.error:
        return _errorState();
      // **오타 교정이 실제로 값을 내는 자리다.** 서버가 못 찾은 뒤에도 "샤낼 뷰티"
      // 같은 표기 실수나 초성 질의(`ㄴㅇㅋ`)는 온디바이스 후보가 잡는다. 여기서
      // 후보를 안 보여주면 사용자가 볼 수 있는 건 "찾지 못했어요" 하나뿐이다.
      case _SearchPhase.noMatch:
        return _suggestions.isEmpty
            ? _emptyState(context)
            : _suggestionList(settled: true);
    }
  }

  /// 지금 적용 중인 정렬. 사용자가 고른 값이 우선이고, 안 골랐으면 위치 유무로
  /// 정한다.
  SearchSortOrder get _sortOrder =>
      _sortOverride ?? defaultSortOrder(widget.reachByNodeId);

  /// 목록 머리말 — 개수·층 분포(Q)와 정렬 컨트롤(P)이 **한 줄**을 쓴다.
  ///
  /// 줄을 두 개 만들면 그만큼 결과가 아래로 밀린다. 이 패널은 상단 오버레이라
  /// 세로가 가장 귀한 자원이다.
  ///
  /// [floorNames]는 **화면에 그린 줄들의 층**이다. 묶인 시설(화장실 19곳)의
  /// 나머지 층까지 세면 한 줄짜리 목록에 `10개 층`이라고 적히는데, 사용자가 보는
  /// 것과 다른 수를 적는 셈이다. 서버 상한(30)이나 후보 상한(8)에 잘린 목록에서
  /// 전체 개수를 적지 않는 것과 같은 규칙이다.
  ///
  /// 층을 `B2 ~ 3F` 같은 **범위**로 적지 않는다. `StoreIndexEntry`·
  /// `PoiSearchResult` 어느 쪽에도 `Floor.level`이 없어서, 문자열을 사전순으로
  /// 세우면 `1F`가 `B1`보다 앞에 온다. 순서 값이 생기기 전에는 `N개 층`이
  /// 사실만 말하는 유일한 표기다.
  Widget _listHeader({
    required int count,
    required Iterable<String> floorNames,
    required bool canChoose,
  }) {
    final floors = floorNames.toSet();
    final floorText = floors.length == 1 ? floors.first : '${floors.length}개 층';
    final canNearest = canSortByNearest(widget.reachByNodeId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '검색 결과 $count · $floorText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
          if (canChoose)
            // 네이버가 필터를 칩으로 늘어놓지 않고 헤더 우측에 `추천순 ⌄`로
            // 접는 것과 같은 자리다(naver-map-ui-ux-analysis.md 1절).
            PopupMenuButton<SearchSortOrder>(
              key: const Key('sort-order'),
              initialValue: _sortOrder,
              tooltip: '정렬 기준',
              onSelected: (value) => setState(() => _sortOverride = value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: SearchSortOrder.nearest,
                  // 거리를 아무도 모르면 눌러도 순서가 안 바뀐다. 고를 수 있게
                  // 두면 사용자는 정렬이 고장 났다고 읽는다.
                  enabled: canNearest,
                  child: Text(canNearest ? '가까운 순' : '가까운 순 (현재 위치 필요)'),
                ),
                const PopupMenuItem(
                  value: SearchSortOrder.bestMatch,
                  child: Text('이름 맞춤 순'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sortOrder == SearchSortOrder.nearest
                          ? '가까운 순'
                          : '이름 맞춤 순',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const Icon(
                      Icons.expand_more,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 후보 목록. 상위가 [_storeIndex]를 못 받았으면 애초에 여기 오지 않는다.
  ///
  /// 후보를 탭하면 **좌표를 들고 바로 이동하지 않는다.** 그 이름으로 검색을 다시
  /// 돌려(`onQueryPicked`) 기존 경량 매칭이 좌표까지 갖춘 결과를 만들게 한다 —
  /// 이유는 [StoreIndexEntry] 주석에 있다.
  /// [settled]는 **이 화면이 이번 글자의 결론인가**다. 타이핑 중(서버를 기다리는
  /// 중)이면 false다.
  ///
  /// 이 값으로 갈리는 게 둘이다. **타이핑 중에는 정렬을 고르게 하지 않고, 순서도
  /// 매칭 품질순 그대로 둔다.** 글자마다 목록이 거리로 다시 세워지면 아직 무엇을
  /// 찾는지 정하지도 않은 사용자의 눈앞에서 줄이 위아래로 튄다. 그리고 매 글자
  /// 컨트롤이 깜빡이면 아직 결론이 아닌 화면이 결론처럼 보인다.
  Widget _suggestionList({required bool settled}) {
    // 머리말은 호출 자리가 아니라 **후보의 성격**으로 정한다. 전부 교정 후보면
    // "네가 치려던 게 이거냐"는 되물음이고, 하나라도 이름이 실제로 걸렸으면
    // "이런 게 있다"는 제안이다. 자리로 나누면 같은 목록에 다른 말이 붙는다.
    final allCorrections = _suggestions.every((s) => s.kind.isCorrection);
    // 교정 후보는 추측이다. 개수를 세고 거리로 정렬해 주는 건 "이게 답이다"라는
    // 말인데, 여기서 우리가 아는 건 "표기가 비슷한 이름이 있다"뿐이다.
    //
    // **1건짜리 목록에는 머리말을 얹지 않는다.** `검색 결과 1 · 4F`는 바로 아래
    // 한 줄이 이미 말한 것을 되풀이할 뿐이고, 정렬 컨트롤도 누를 대상이 없다.
    // 개수 머리말과 컨트롤이 같은 조건으로 갈리므로 조건도 하나로 둔다.
    final showCount =
        settled &&
        !allCorrections &&
        canChooseSortOrder(itemCount: _suggestions.length, fromSemantic: false);
    final suggestions = showCount
        ? sortedSuggestions(
            suggestions: _suggestions,
            reachByNodeId: widget.reachByNodeId,
            order: _sortOrder,
          )
        : _suggestions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCount)
          _listHeader(
            count: suggestions.length,
            // 묶인 시설은 화면에 그린 대표의 층만 센다(_listHeader 주석).
            floorNames: [
              for (final suggestion in suggestions)
                nearestByWalkingDistance(
                  stores: suggestion.stores,
                  reachByNodeId: widget.reachByNodeId,
                ).store.floorName,
            ],
            canChoose: true,
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              allCorrections ? '이걸 찾으셨나요?' : '검색어 제안',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final suggestion in suggestions)
                  _suggestionTile(suggestion),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _suggestionTile(StoreSuggestion suggestion) {
    // 묶인 시설(화장실 19곳)에서 **어느 매장의 층을 적을지**를 여기서 정한다.
    // 예전에는 인덱스 첫 번째였고, 인덱스가 `Floor.level DESC`라 늘 꼭대기 층이
    // 대표였다 — B2에 서 있어도 `화장실 · 6F 등 19곳`. 규칙과 실패 조건은
    // [nearestByWalkingDistance](../domain/nearest_store.dart)가 단일 출처다.
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: widget.reachByNodeId,
    );
    final store = nearest.store;
    final reach = nearest.reach;
    final categoryLabel =
        subcategoryLabelFor(store.subcategory) ?? store.category;
    // 층마다 있는 시설(화장실 19건)은 한 줄로 묶여 온다. 몇 곳인지 적어 주지
    // 않으면 사용자는 "왜 한 층만 나오지"로 읽는다. **개수는 거리를 아는 곳이
    // 몇인지와 무관하게 묶인 전체다** — 19곳 중 3곳만 도달 가능하다고 `등 3곳`
    // 으로 적으면 없는 사실을 만들어 낸다.
    final count = suggestion.stores.length;
    final floorLine = count > 1
        ? '${store.floorName} 등 $count곳'
        : store.floorName;
    return ListTile(
      key: Key('suggestion-${store.id}'),
      dense: true,
      // 돋보기와 핀 2종만 쓰는 네이버 관례를 따른다. 교정 후보만 다른 아이콘으로
      // "이건 네가 친 말이 아니다"를 알린다 — 검증 기준(L)의 "교정 후보임이
      // 화면에 드러남"이 이 아이콘과 아래 하이라이트 없음으로 충족된다.
      leading: Icon(
        suggestion.kind.isCorrection ? Icons.auto_fix_high : Icons.search,
        size: 20,
        color: AppColors.muted,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text.rich(
              // 교정 후보는 사용자가 친 글자와 이름이 어긋나 있어 하이라이트가
              // 안 걸린다. 그게 정상이다(highlightedNameSpans 주석).
              TextSpan(
                children: highlightedNameSpans(store.name, widget.query),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (categoryLabel != null) ...[
            const SizedBox(width: 8),
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
      // 결과 목록(_storeTile)과 같은 두 줄 구조다. 후보 목록이 사실상 결과
      // 화면으로도 쓰이는데(서버가 한 곳을 지목 못 한 브랜드 질의) 거리만 없어서,
      // 가장 흔한 검색이 가장 빈약한 화면으로 가고 있었다.
      // 설계: docs/client/search-result-list-ux.md O절.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            floorLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (reach != null)
            Text(
              reachLabel(reach),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 결과 행과 같은 무게. 두 목록이 같은 값을 다르게 그리면 사용자는
              // 둘이 다른 것을 뜻한다고 읽는다.
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      isThreeLine: reach != null,
      onTap: () {
        // 화면에 적힌 그 층으로 확정되게 한다. 이름만 넘기면 같은 이름이 19곳인
        // 시설에서 서버가 자기 순서로 아무 층이나 고른다([_FloorScopeOverride]).
        _floorScopeOnce = _FloorScopeOverride(store.floorId);
        widget.onQueryPicked(store.name);
      },
    );
  }

  /// 아직 아무것도 치지 않은 화면. 최근 검색어가 있으면 그걸 보여주고, 없으면
  /// 예전처럼 안내 문구만 남긴다.
  ///
  /// **"인기 매장"은 만들지 않는다.** 방문·클릭 로그가 없어 순위를 만들 근거가
  /// 없다(설계: naver-map-ui-ux-analysis.md J절). 클라이언트가 실제로 아는 것만
  /// 쓴다.
  ///
  /// 첫 실행의 빈 목록은 오류가 아니라 정상 상태다. 그때는 목록 자리에
  /// 빈 박스를 남기지 않고 안내 문구가 그 자리를 그대로 쓴다.
  Widget _idleState() {
    return ListenableBuilder(
      listenable: recentSearchesController,
      builder: (context, _) {
        final queries = recentSearchesController.queries;
        if (queries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 22),
            child: Text(
              '매장 이름을 입력하면 바로 찾아드려요.\n'
              '"밥 먹을 곳"처럼 뜻으로 물어도 됩니다.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '최근 검색어',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: recentSearchesController.clear,
                    child: const Text('전체 삭제', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            // 목록이 상한(컨트롤러의 maxEntries)까지 차도 패널이 화면을 다 먹지
            // 않도록 상위가 준 높이 안에서 스크롤시킨다. 결과 목록과 같은 이유로
            // ListView가 아니라 Column + SingleChildScrollView다(아래 _resultList
            // 주석 참고).
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final query in queries)
                      ListTile(
                        key: Key('recent-$query'),
                        dense: true,
                        leading: const Icon(
                          Icons.history,
                          size: 20,
                          color: AppColors.muted,
                        ),
                        title: Text(
                          query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: AppColors.muted,
                          tooltip: '$query 삭제',
                          onPressed: () =>
                              recentSearchesController.remove(query),
                        ),
                        onTap: () {
                          // 최근 검색어는 문자열 하나뿐이라 어느 층 매장이었는지
                          // 알 방법이 없다. 층을 모르는 선택이므로 스코프를 뺀다.
                          _floorScopeOnce = const _FloorScopeOverride(null);
                          widget.onQueryPicked(query);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
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
    // 가까운 것부터 보여준다. 규칙과 실패 조건은
    // [sortedSearchResults](../domain/search_result_order.dart)가 단일 출처다.
    // 여기(build)에서 세우는 이유는 거리의 출처인 `widget.reachByNodeId`가 위치를
    // 새로 잡을 때마다 바뀌기 때문이다 — 결과를 받는 시점에 한 번만 세우면
    // 화면에 적힌 거리와 순서가 어긋난 목록이 남는다. 상한이 30건이라 매 빌드
    // 정렬 비용은 무시할 수 있다.
    final ordered = sortedSearchResults(
      results: _results,
      reachByNodeId: widget.reachByNodeId,
      fromSemantic: _fromSemantic,
      order: _sortOrder,
    );
    // 개수·층 머리말과 정렬 컨트롤은 **결론인 목록에만** 얹는다. clarify는 아직
    // 질문이 서 있는 화면이라 질문·선택지 줄 위에 개수를 또 적으면 무엇을 먼저
    // 읽어야 할지 흐려지고, 의미 검색 결과는 유사도순이라 고를 수 있는 축이
    // 아니다(`canChooseSortOrder`).
    final canChoose =
        _discoveryMode != DiscoveryMode.clarify &&
        canChooseSortOrder(
          itemCount: ordered.length,
          fromSemantic: _fromSemantic,
        );
    // 건물 행 **아래**에 둔다. "검색 결과 N"의 N은 매장 수이고 건물은 세지
    // 않으므로, 건물 위에 얹으면 그 줄까지 세는 것처럼 읽힌다.
    if (canChoose) {
      rows.add(
        _listHeader(
          count: ordered.length,
          floorNames: [for (final store in ordered) store.floor],
          canChoose: true,
        ),
      );
    }
    // 추천 이유는 **storeId로** 짝짓는다. 예전에는 `_discoveryMatches[index]`로
    // 인덱스를 맞췄는데, 정렬이 들어오면 이유가 엉뚱한 매장에 붙는다. 그리고
    // 이건 가정이 아니다 — `_fromSemantic`은 결과가 정확한 이름 일치로 판정되면
    // false가 되는데(_semanticSearch), 그때도 `_discoveryMatches`는 차 있다.
    // 즉 "정렬은 도는데 인덱스 짝짓기는 깨지는" 조합이 실제 경로로 존재한다.
    final matchByStoreId = {
      for (final match in _discoveryMatches) match.storeId: match,
    };
    // 모든 행에 똑같이 들어 있는 근거 문장은 행에서 빼고 층에 자리를 돌려준다.
    // 규칙과 이유는 [distinctiveReason](../domain/reason_text.dart)이 단일 출처다.
    final sharedReasons = sharedReasonSentences(
      _discoveryMatches.map((match) => match.reason),
    );
    for (final store in ordered) {
      final placeId = store.placeId;
      rows.add(
        _storeTile(
          store,
          placeId == null ? null : matchByStoreId[placeId],
          sharedReasons,
        ),
      );
    }
    rows.addAll(_siblingRows(ordered));

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

  /// 서버가 확정한 1건 **아래에** 같은 계열 매장을 잇는 행들.
  ///
  /// `구찌`를 치면 서버는 `구찌` 한 곳을 자신 있게 확정하고, `구찌 뷰티`·
  /// `구찌 선글라스`는 화면에서 사라진다. 규칙과 실패 조건은
  /// [nameSiblings](../domain/name_siblings.dart)가 단일 출처다.
  ///
  /// **정확 일치 행은 맨 위에 고정한다.** 사용자가 친 그 이름이라 거리로 밀어
  /// 내리면 "이름 맞춤"이라는 말 자체가 무너진다. 그래서 이 화면에는 정렬
  /// 컨트롤을 두지 않는다 — 머리 행이 고정된 목록은 정렬 기준 하나로 설명되지
  /// 않는다. 형제는 실데이터 기준 최대 3건이라 고를 것도 많지 않다.
  List<Widget> _siblingRows(List<PoiSearchResult> ordered) {
    // 경량 경로가 확정한 1건일 때만이다. 의미 검색·discovery 결과는 이름으로
    // 걸린 게 아니라 형제라는 개념 자체가 없다.
    if (_discoveryMode != null || _fromSemantic) return const [];
    if (ordered.length != 1) return const [];

    final siblings = nameSiblings(
      suggestions: _suggestions,
      confirmedName: ordered.single.name,
    );
    if (siblings.isEmpty) return const [];

    final sorted = sortedSuggestions(
      suggestions: siblings,
      reachByNodeId: widget.reachByNodeId,
      order: _sortOrder,
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Text(
          '이름이 비슷한 매장 ${sorted.length}곳',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      ),
      for (final suggestion in sorted) _suggestionTile(suggestion),
    ];
  }

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

    // 선택·되돌리기 줄. 답을 한 번이라도 골랐을 때만 선다.
    final selectedRow = <Widget>[];
    for (final entry in _selectedFacets.entries) {
      for (final value in entry.value) {
        if (selectedRow.isNotEmpty) selectedRow.add(const SizedBox(width: 6));
        selectedRow.add(
          FilterPill(
            key: Key('selected-facet-${entry.key}-$value'),
            label: value,
            selected: true,
            // 고른 값을 다시 누르면 풀린다. 카테고리 시트의 소분류 pill과 같은
            // 규칙이라 같은 모양이 같게 동작한다. `×`는 그 사실을 눈에 보이게 한다.
            trailing: Icons.close,
            onTap: () => _removeFacet(entry.key, value),
          ),
        );
      }
    }
    // 조작 pill(전체 보기·다시 선택)은 **선택 줄 끝에 구분선 뒤로** 붙인다. 예전에는
    // "전체 보기"가 혼자 윗줄에 떠서, 방금 고른 선택보다 위에 있는 탈출구가 됐다.
    // clarify 화면에서는 이미 선택지 줄 끝에 있으므로 여기서는 빼고 중복시키지 않는다.
    final trailingActions = <Widget>[
      if (canShowAll && !isClarify)
        FilterPill(
          key: const Key('show-all'),
          label: '전체 보기',
          selected: false,
          onTap: () => _requestDiscovery(showAll: true),
        ),
      if (canChooseAgain)
        FilterPill(
          key: const Key('choose-again'),
          label: '다시 선택',
          selected: false,
          onTap: _chooseAgain,
        ),
    ];
    if (trailingActions.isNotEmpty) {
      if (selectedRow.isNotEmpty) {
        selectedRow.add(
          const VerticalDivider(width: 10, indent: 6, endIndent: 6),
        );
      }
      for (var index = 0; index < trailingActions.length; index++) {
        if (index > 0) selectedRow.add(const SizedBox(width: 6));
        selectedRow.add(trailingActions[index]);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_discoveryMode == DiscoveryMode.degraded)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                '일부 추천 기능이 준비되지 않아 제한된 결과만 보여드려요.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          if (isClarify) ...[
            // 질문은 이 패널의 다른 머리말(`검색어 제안`·`최근 검색어`)과 같은
            // 크기·색으로 둔다. 예전에는 14/굵게라 질문이 결과보다 커 보였는데,
            // 여기서 물어보는 건 답을 좁히는 보조 수단이지 화면의 주인공이 아니다.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                _discoveryQuestion ?? '어떤 조건을 더 중요하게 보시나요?',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ),
            // **선택지는 한 줄에서 가로로 스크롤한다.** Wrap으로 접으면 다섯 개짜리
            // 축(styles)에서 두 줄이 되고, 질문·전체 보기까지 합쳐 세로 150px가
            // 넘어가 정작 결과 목록이 화면 밖으로 밀린다. 줄을 고정하면 선택지가
            // 몇 개든 패널 높이가 그대로다.
            if (_discoveryOptions.isNotEmpty)
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final option in _discoveryOptions) ...[
                      FilterPill(
                        key: Key(
                          'facet-option-${option.facet}-${option.value}',
                        ),
                        label: '${option.label} (${option.count})',
                        selected: false,
                        onTap: () => _selectFacet(option),
                      ),
                      const SizedBox(width: 6),
                    ],
                    // 성격이 다른 것은 같은 줄에 두되 섞이지 않게 구분선으로
                    // 나눈다(naver-map-ui-ux-analysis.md 5·6절의 필터 줄과 같다).
                    // 위 pill들은 "이 값으로 좁혀라"이고, 이건 "좁히지 말고 다 봐라"다.
                    if (canShowAll) ...[
                      const VerticalDivider(width: 10, indent: 6, endIndent: 6),
                      FilterPill(
                        key: const Key('show-all'),
                        label: '전체 보기',
                        selected: false,
                        onTap: () => _requestDiscovery(showAll: true),
                      ),
                    ],
                  ],
                ),
              ),
          ],
          if (selectedRow.isNotEmpty) ...[
            if (isClarify) const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: selectedRow,
              ),
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
  Widget _storeTile(
    PoiSearchResult store,
    DiscoveryMatch? match,
    Set<String> sharedReasons,
  ) {
    // 소분류가 없는 장소에서 업종이 통째로 사라지지 않도록 대분류로 떨어뜨린다 —
    // 상세 시트를 여는 호출부(MapShellScreen._showStoreInfo)와 같은 규칙이다.
    final categoryLabel =
        subcategoryLabelFor(store.subcategory) ?? store.category;
    // 노드가 없는 매장은 애초에 경로를 못 그리므로 거리도 없다. 그 사실은
    // 아래 첫 줄의 "경로 안내 불가"가 이미 말한다.
    final nodeId = store.nodeId;
    final reach = nodeId == null ? null : widget.reachByNodeId?[nodeId];
    // 층은 **항상** 남긴다. 예전에는 reason이 층을 통째로 대체해서, 다섯 행이 같은
    // 문장을 되풀이하는 동안 정작 몇 층인지가 화면에서 사라졌다.
    final reason = distinctiveReason(match?.reason, sharedReasons);
    final floorLine = nodeId == null
        ? '${store.floor} · 경로 안내 불가'
        : store.floor;
    final firstLine = reason == null ? floorLine : '$floorLine · $reason';
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
          // (_SearchPhase.noMatch에서만 그린다). 말을 바꿔 보라는 것 말고
          // 사용자가 더 눌러 볼 수단이 있는 것처럼 보이면 안 된다.
          const Text(
            '다른 말로 바꿔서 다시 찾아보세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          _browseCategories(),
        ],
      ),
    );
  }

  /// 못 찾았을 때의 탈출구 — 카테고리로 둘러보기(R절).
  ///
  /// **"인기 검색어"는 만들지 않는다.** 방문·클릭 로그가 없어 순위를 만들 근거가
  /// 없다(J절과 같은 이유). 여기 놓는 것은 우리가 실제로 아는 것 — 이 건물에
  /// 어떤 대분류가 있는가 — 뿐이다.
  ///
  /// **야외에서는 그리지 않는다.** 아직 들어가지도 않은 건물의 카테고리를 누르게
  /// 되고, 지도 강조는 도면 위에 그려지므로 결과가 보이지 않는다(지도 위 chip 줄이
  /// `_indoorContextActive`로 갈리는 것과 같은 이유).
  Widget _browseCategories() {
    final entries = widget.categoryEntries;
    final onPicked = widget.onCategoryPicked;
    if (entries == null || onPicked == null || !widget.indoorContextActive) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<CategoryCount>>(
      future: entries,
      builder: (context, snapshot) {
        // 로드 실패·미완료는 **줄만 조용히 사라진다.** 상위 지도 오버레이는 실패를
        // 재시도 칩으로 드러내지만, 여기서는 부가 제안이라 "찾지 못했어요" 화면에
        // 오류를 하나 더 얹을 이유가 없다.
        final categories = sortedCategoryLabels(
          (snapshot.data ?? const <CategoryCount>[]).map((e) => e.category),
        );
        if (categories.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '카테고리로 둘러보기',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              // 대분류가 6~7개라 접으면 두 줄이 된다. 이 화면은 결과가 없어
              // 세로가 남으므로 Wrap으로 두어 한눈에 다 보이게 한다.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in categories)
                    FilterPill(
                      key: Key('browse-category-$category'),
                      label: category,
                      selected: false,
                      onTap: () => onPicked(category),
                    ),
                ],
              ),
            ],
          ),
        );
      },
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
