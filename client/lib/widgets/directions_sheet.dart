import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../domain/dijkstra.dart';
import '../domain/nearest_store.dart';
import '../domain/store_suggestions.dart';
import '../models/discovery_result.dart';
import '../models/store_index_entry.dart';
import '../theme/app_theme.dart';
import 'reach_label.dart';
import 'sheet_grab_handle.dart';

import 'map_overlay_guard.dart';

/// 길찾기 시트에서 고를 수 있는 출발지/도착지 후보. 야외 모드에서는 [Building],
/// 실내 모드에서는 [PoiSearchResult]를 이 공통 형태로 변환해 검색·선택
/// 로직을 하나의 시트 위젯으로 공유한다.
class DirectionsCandidate {
  const DirectionsCandidate({
    required this.title,
    required this.subtitle,
    required this.point,
    this.nodeId,
    this.floor,
    this.reason,
  });

  final String title;
  final String subtitle;
  final LatLng point;

  /// 실내 경로탐색(다익스트라)에 필요한 노드 ID. 야외 후보에는 없다.
  final String? nodeId;

  /// 실내 후보가 속한 층. 야외 후보에는 없다.
  final String? floor;

  /// 의미 검색(`/query/ai`)이 준 추천 이유. 값이 있으면 [subtitle] 대신
  /// 보여준다 — "왜 이 매장이 나왔는지"가 층 라벨보다 중요한 정보다.
  /// 경량 검색 후보에는 없다.
  final String? reason;
}

/// "지도에서 선택"으로 정할 대상. 출발지·도착지 양쪽 모두 지도에서 고를 수
/// 있으므로, 어느 칸을 채우려는 것인지 호출자에게 알려야 한다. bool 하나로는
/// 표현할 수 없어 열거형으로 둔다.
enum DirectionsMapPickTarget { origin, destination }

/// 길찾기 시트가 닫힐 때 돌려주는 결과. [origin]이 null이면 "현재 위치"를
/// 출발지로 쓴다는 뜻이다.
class DirectionsResult {
  /// 도착지까지 정해져서 바로 경로를 그릴 수 있는 경우.
  const DirectionsResult({
    this.origin,
    required DirectionsCandidate this.destination,
  }) : pickOnMap = null;

  /// 도착지 칸에서 "지도에서 선택"을 누른 경우. 도착지는 아직 없고, 호출자가
  /// 지도에서 매장을 고르는 모드로 넘어가야 한다. 출발지는 시트에서 정한 값을
  /// 그대로 이어받는다.
  const DirectionsResult.pickDestinationOnMap({this.origin})
    : destination = null,
      pickOnMap = DirectionsMapPickTarget.destination;

  /// 출발지 칸에서 "지도에서 선택"을 누른 경우. 대칭으로, 출발지는 아직 없고
  /// **이미 고른 도착지를 되돌려준다** — 안 돌려주면 지도에서 출발지를 찍은
  /// 순간 도착지가 사라져 사용자가 처음부터 다시 입력하게 된다.
  const DirectionsResult.pickOriginOnMap({this.destination})
    : origin = null,
      pickOnMap = DirectionsMapPickTarget.origin;

  final DirectionsCandidate? origin;

  /// [pickOnMap]이 [DirectionsMapPickTarget.destination]이면 null이다.
  /// 그 경우 도착지는 지도 탭으로 정해진다.
  final DirectionsCandidate? destination;

  /// null이 아니면 시트는 "이 칸을 지도에서 고르겠다"는 의사만 전달한 것이다.
  final DirectionsMapPickTarget? pickOnMap;
}

enum _ActiveField { origin, destination }

/// [DirectionsSheet]가 부모(MapShellScreen)에 검색을 위임할 때 쓰는 콜백.
///
/// 길찾기 검색은 **항상 건물 전체**를 뒤진다. 예전에는 현재 층으로 좁히고
/// "전체 층에서 찾기" 토글로 넓히게 했는데, 길찾기는 원래 다른 층으로 가려고
/// 여는 기능이라 기본값이 반대였다 — 찾는 매장이 대부분 다른 층에 있어서
/// 사용자가 매번 토글을 켜야 결과가 나왔다.
/// [floorId]는 **목록에서 고른 후보의 층**이다. 사용자가 직접 친 질의에는 절대
/// 넘기지 않는다 — 위 「항상 건물 전체」 규칙 그대로다. 후보를 콕 집은 행동에만
/// 그 후보의 층을 실어 보내, 같은 이름이 층마다 있는 시설(화장실 19곳)에서
/// 화면에 적힌 층과 실제로 가는 층이 어긋나지 않게 한다(설계:
/// `docs/client/search-result-list-ux.md` T절).
typedef DirectionsSearchCallback =
    Future<List<DirectionsCandidate>> Function(String query, {String? floorId});

/// 의미 검색(`/query/ai`) 응답을 시트가 쓰는 형태로 옮긴 것. 후보를
/// [DirectionsCandidate]로만 받으면 mode·질문·선택지를 잃어 상단 검색 패널과
/// 같은 화면을 만들 수 없어서, 계약 전체를 이 타입으로 넘겨받는다.
class DirectionsDiscovery {
  const DirectionsDiscovery({
    required this.mode,
    this.source = DiscoverySource.unknown,
    this.question,
    this.options = const [],
    this.candidates = const [],
  });

  /// 화면 분기의 유일한 근거. 서버가 모르는 값을 보내면
  /// [DiscoveryMode.unknown]으로 내려오고, 시트는 그걸 "결과 없음"과 같이
  /// 안전하게 처리한다 — 임의의 후보를 목적지로 밀지 않는다.
  final DiscoveryMode mode;

  /// 후보를 어휘로 잡았는지 임베딩으로 잡았는지. 온디바이스 이름 후보를 이
  /// 응답으로 대체할지 판단하는 데 쓴다([DiscoverySource]).
  final DiscoverySource source;
  final String? question;
  final List<DiscoveryOption> options;
  final List<DirectionsCandidate> candidates;
}

/// 경량 검색이 빈손일 때 이어 붙이는 **의미 검색** 콜백.
///
/// null이면 이 시트에서는 의미 검색을 쓰지 않는다는 뜻이다 — 야외(건물 입구를
/// 고르는) 모드가 그렇다. `/query/ai`는 건물 **안의 매장**을 찾는 계약이라,
/// 건물을 고르는 자리에서 승격시키면 눌러도 갈 수 없는 목록이 된다.
typedef DirectionsSemanticSearchCallback =
    Future<DirectionsDiscovery> Function(
      String query, {
      Map<String, List<String>>? selectedFacets,
      required bool showAll,
    });

/// "출발지 → 도착지" 입력 바텀시트. 두 입력 모두 탭하면 그 아래 검색 결과
/// 목록이 그 필드 기준으로 바뀐다. 출발지 목록의 맨 위에는 "현재 위치"가
/// 항상 고정으로 있어, 별도로 고르지 않으면 출발지는 현재 위치로 간주된다.
///
/// ## 검색은 상단 검색창과 같은 두 단계다
///
/// 사용자는 상단 검색창과 이 시트를 "검색하는 곳"으로 똑같이 본다. 그런데
/// 예전에는 이 시트만 경량 매칭(`/query/destination`) 한 번으로 끝나서,
/// "밥 먹을 곳"처럼 이름이 아닌 말은 **항상** "검색 결과가 없습니다"였다.
/// 상단에서는 찾아 주는 말이 길찾기에서는 안 되니, 사용자에게는 같은 앱이
/// 자리에 따라 다른 검색을 하는 셈이었다. 그래서 `SearchPanel`과 같은 흐름을
/// 여기에도 둔다.
///
/// - **타이핑이 300ms 멎으면**: 경량 매칭. 매장 이름·동의어는 여기서 걸린다.
/// - **경량이 빈손이면**: 400ms를 더 기다렸다가 의미 검색([semanticSearch])
///   까지 자동으로 이어 붙인다. 엔터를 누르면 두 대기를 모두 건너뛴다.
/// - **[semanticSearch]가 null이면**(야외 모드) 예전처럼 경량 한 번으로 끝난다.
///
/// 디바운스가 없던 예전 코드는 글자마다 서버를 때렸다. 의미 검색은 비용이
/// 자릿수로 다르므로(첫 호출은 임베딩 모델 로드로 수 초) 그대로 두면 "밥"·
/// "밥 먹"·"밥 먹을"이 전부 모델을 태운다 — 두 단으로 나눠 흔한 이름 검색은
/// 빠르게 두고 비싼 경로만 늦춘다.
///
/// ## 두 칸을 뒤집는 교체 버튼
///
/// 입력창 오른쪽의 상하 화살표가 출발지와 도착지를 맞바꾼다. 규칙과 근거는
/// `_DirectionsSheetState._canSwap`·`_swapOriginDestination` 주석에 있다.
/// 요약하면 **출발지가 실제 후보일 때만 눌리고, 누르면 곧바로 시트가 닫히며
/// 경로가 다시 그려진다.**
class DirectionsSheet extends StatefulWidget {
  const DirectionsSheet({
    super.key,
    required this.originLabel,
    required this.search,
    this.semanticSearch,
    this.initialOrigin,
    this.initialDestination,
    this.storeIndex,
    this.reachByNodeId,
    this.currentFloorId,
    this.focusOrigin = false,
  });

  /// 출발지를 따로 고르지 않았을 때 보여줄 문구("현재 위치").
  final String originLabel;
  final DirectionsSearchCallback search;

  /// 경량이 빈손일 때 이어 붙일 의미 검색. null이면 승격하지 않는다.
  final DirectionsSemanticSearchCallback? semanticSearch;

  /// 매장 정보 시트의 "출발지로 설정"에서 넘어올 때처럼, 출발지가 이미
  /// 정해진 채로 시트를 열 때 채워둔다.
  final DirectionsCandidate? initialOrigin;

  /// 매장 정보 시트의 "도착지로 설정"에서 넘어올 때처럼, 도착지가 이미
  /// 정해진 채로 시트를 열 때 채워둔다. 검색창에 그 이름을 미리 채우고
  /// 검색 결과 목록에서 그대로 골라도 되고, 다른 검색어로 바꿔도 된다.
  final DirectionsCandidate? initialDestination;

  /// 온디바이스 자동완성의 원본. 상위가 이미 받아 둔 Future를 그대로 받는다
  /// (리포지토리가 같은 Future를 공유하므로 두 번 받지 않는다).
  ///
  /// **없어도 검색은 그대로 돈다.** 후보만 조용히 사라진다 — 상단 검색 패널과
  /// 같은 계약이다(`docs/client/search-input-assist.md` K절 실패 조건).
  final Future<List<StoreIndexEntry>?>? storeIndex;

  /// 현재 위치에서 각 그래프 노드까지의 거리·비용. 상위(MapShellScreen)가 이미
  /// 한 번 계산해 들고 있는 맵을 그대로 받는다 — **여기서 경로를 새로 계산하지
  /// 않는다.**
  ///
  /// 길찾기 후보 목록이 상단 검색 결과와 같은 판단 재료를 갖게 하려고 넣었다.
  /// 같은 앱에서 같은 매장을 고르는데 한쪽에만 거리가 있으면, 사용자는 두 화면이
  /// 다른 것을 뜻한다고 읽는다(설계: `docs/client/map-ui-redesign-plan.md`
  /// 「7+E 합동 설계」의 2단계).
  final Map<String, NodeReach>? reachByNodeId;

  /// 지금 보고 있는 층. **검색 범위를 좁히는 데 쓰지 않는다** — 길찾기는 항상
  /// 건물 전체를 본다(`_semanticDirectionsCandidates` 주석). 묶인 시설에서 거리를
  /// 모를 때 **어느 층을 대표로 적을지**에만 쓴다. 상단 검색 패널과 같은 규칙이라야
  /// 같은 매장이 두 화면에서 다른 층으로 보이지 않는다.
  final String? currentFloorId;

  /// 출발지 칸을 활성으로 열지. 상단 초안 바의 **출발 행**을 눌러 들어올 때 켠다 —
  /// 출발지를 바꾸려고 누른 것이므로 커서와 후보 목록이 그 칸에 맞아야 한다.
  /// 기본은 false로, 도착지를 고르는 기존 흐름이 그대로 유지된다.
  final bool focusOrigin;

  static Future<DirectionsResult?> show(
    BuildContext context, {
    required String originLabel,
    required DirectionsSearchCallback search,
    DirectionsSemanticSearchCallback? semanticSearch,
    DirectionsCandidate? initialOrigin,
    DirectionsCandidate? initialDestination,
    Future<List<StoreIndexEntry>?>? storeIndex,
    Map<String, NodeReach>? reachByNodeId,
    String? currentFloorId,
    bool focusOrigin = false,
  }) {
    return showModalBottomSheet<DirectionsResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => MapOverlayGuard(
        child: DirectionsSheet(
          originLabel: originLabel,
          search: search,
          semanticSearch: semanticSearch,
          initialOrigin: initialOrigin,
          initialDestination: initialDestination,
          storeIndex: storeIndex,
          reachByNodeId: reachByNodeId,
          currentFloorId: currentFloorId,
          focusOrigin: focusOrigin,
        ),
      ),
    );
  }

  @override
  State<DirectionsSheet> createState() => _DirectionsSheetState();
}

/// 검색창 바로 아래 줄. 목적지를 이름으로 찾지 않고 지도에서 직접 누르고 싶은
/// 사용자를 위한 지름길이다.
///
/// 이 줄이 필요한 이유: 지도에서 매장을 눌러 "출발지로 설정"하면 이 시트가
/// 곧바로 열리는데, 그 사용자는 방금 지도를 보고 있었으므로 나머지 한 쪽도
/// 지도에서 고르려 한다. 그런데 시트가 지도를 덮고 있어 시트를 닫는 방법밖에
/// 없었고, 닫으면 방금 지정한 값이 어디로 갔는지 알 수 없었다.
///
/// **출발지·도착지 양쪽에 똑같이 필요하다.** 지금 활성인 칸이 어느 쪽이냐에
/// 따라 [target]만 달라지고 자리와 생김새는 같다 — 두 칸의 조작 방법이 다르면
/// 사용자는 한쪽에만 있는 기능을 없는 것으로 여긴다.
class _PickOnMapTile extends StatelessWidget {
  const _PickOnMapTile({required this.target, required this.onTap});

  final DirectionsMapPickTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOrigin = target == DirectionsMapPickTarget.origin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          onTap: onTap,
          dense: true,
          leading: const Icon(
            Icons.touch_app_outlined,
            size: 20,
            color: AppColors.primary,
          ),
          title: const Text(
            '지도에서 선택',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          // 제목은 같아도 부제는 갈라야 한다. 출발지 칸에서 눌렀는데 "도착지로
          // 지정합니다"라고 적혀 있으면 사용자는 잘못 눌렀다고 판단해 되돌린다.
          //
          // **매장만 말하면 안 된다.** 지도에서는 복도도 고를 수 있는데(하단 바의
          // "위치 지정"과 같은 조작이다), 부제가 매장만 말하면 아무도 그걸 모른다.
          // 매장이 없는 자리를 눌러 본 사용자는 앱이 반응하지 않는다고 읽는다.
          subtitle: Text(
            isOrigin
                ? '지도에서 매장이나 복도를 눌러 출발지로 지정합니다'
                : '지도에서 매장이나 복도를 눌러 도착지로 지정합니다',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.muted,
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// 시트가 지금 어느 단계에 있는지. 상단 검색 패널(`SearchPanel._SearchPhase`)과
/// 같은 구분을 쓴다. 예전의 `_loading` 불리언 하나로는 [noMatch]를 표현할 수
/// 없다 — "검색 결과가 없습니다"는 **의미 검색까지 끝난 뒤에만** 최종 결론으로
/// 쓸 수 있는데, 불리언으로는 "경량만 끝난 상태"와 구분되지 않는다.
enum _SearchPhase {
  /// 검색어가 비어 있고 보여줄 후보도 없다. 실내에서는 빈 질의를 서버로 보내지
  /// 않아(경량 리포지토리가 빈 목록으로 짧게 끊는다) 항상 이 상태가 된다.
  /// 예전에는 이 자리에도 "검색 결과가 없습니다"가 떠서, 아무것도 치지 않았는데
  /// 못 찾았다고 말했다.
  idle,

  /// 경량 매칭이 도는 중. 의미 검색으로 넘어가기 전 대기도 여기 포함된다 —
  /// 사용자 입장에서는 둘 다 "찾는 중"이고 아직 결론이 아니다.
  lightSearching,

  /// 의미 검색이 도는 중. 모델 로드로 오래 걸릴 수 있어 문구를 따로 붙인다.
  semanticSearching,

  /// 후보가 넓어서 선택지를 먼저 보여 주는 탐색 응답이다.
  clarify,

  /// 보여줄 후보가 있다.
  results,

  /// **온디바이스 후보로 답했다.** 서버 경량 매칭은 빈손이었지만 기기 안 인덱스가
  /// 이름으로 매장을 찾은 상태다. 이때는 의미 검색으로 넘어가지 않는다 — 근거는
  /// 상단 검색 패널과 같다(search-input-assist.md K절 실기기 검증 2번).
  suggestions,

  /// 쓸 수 있는 검색을 **모두** 끝냈는데 없다.
  noMatch,

  /// 의미 검색은 못 쓰지만 경량/태그 후보는 남아 있을 수 있다.
  degraded,

  /// 서버·네트워크가 끊겨 검색을 끝내지 못했다. 없는 것과 못 찾은 것은 사용자가
  /// 할 행동이 다르다 — 전자는 말을 바꿔야 하고, 후자는 기다려야 한다.
  error,
}

class _DirectionsSheetState extends State<DirectionsSheet> {
  /// 경량 검색용 디바운스. 예전에는 글자마다 곧바로 서버를 때렸다.
  static const _lightDebounce = Duration(milliseconds: 300);

  /// 경량이 빈손일 때 의미 검색으로 넘어가기 전에 한 번 더 기다리는 시간.
  /// "타이핑이 잠깐 멈췄다"가 아니라 "손을 뗐다"에 가까운 신호에서만 비싼
  /// 경로를 태우기 위해 경량보다 길게 잡는다.
  static const _semanticGrace = Duration(milliseconds: 400);

  late final _originController = TextEditingController(
    text: widget.initialOrigin?.title ?? widget.originLabel,
  );
  late final _destinationController = TextEditingController(
    text: widget.initialDestination?.title ?? '',
  );
  final _originFocusNode = FocusNode();
  final _destinationFocusNode = FocusNode();

  DirectionsCandidate? _selectedOrigin;
  DirectionsCandidate? _selectedDestination;
  late _ActiveField _activeField;
  List<DirectionsCandidate> _results = const [];
  _SearchPhase _phase = _SearchPhase.idle;

  /// 두 단계의 대기를 한 필드로 돌린다. 한 시점에 살아 있을 수 있는 대기는
  /// 하나뿐이고(경량을 기다리거나, 경량이 끝나 의미 검색을 기다리거나) 취소
  /// 지점도 같다 — 새 글자가 오면 둘 다 죽어야 한다.
  Timer? _debounce;

  /// 마지막으로 결과를 확정한 질의. "…을(를) 찾지 못했어요" 문구에 쓴다.
  String _submittedQuery = '';

  /// 이번 결과가 의미 검색에서 나왔는지. 단계가 아니라 결과의 성질이라
  /// [_SearchPhase]에 합치지 않는다.
  bool _fromSemantic = false;

  DiscoveryMode? _discoveryMode;
  String? _discoveryQuestion;
  List<DiscoveryOption> _discoveryOptions = const [];

  /// stateless API에 매번 실어 보내는 facet 선택. 이 맵 하나가 화면 chip과
  /// 다음 요청의 공통 원본이라, 화면은 선택됐는데 요청에는 빠지는 상태를
  /// 만들지 않는다.
  Map<String, List<String>> _selectedFacets = const {};

  /// 최근 선택 순서. "다시 선택"은 마지막 답 하나만 되돌린다.
  final List<(String facet, String value)> _facetSelectionOrder = [];

  int _searchSeq = 0;

  bool get _isOriginActive => _activeField == _ActiveField.origin;

  String get _activeQuery =>
      _isOriginActive ? _originController.text : _destinationController.text;

  TextEditingController get _activeController =>
      _isOriginActive ? _originController : _destinationController;

  /// 온디바이스 자동완성의 원본. null은 "아직 못 받았거나 받기에 실패했다"는
  /// 뜻이고, **그 상태가 정상 경로에 포함된다.**
  List<StoreIndexEntry>? _storeIndex;

  /// 지금 질의에 대한 후보. 질의가 바뀔 때만 다시 계산한다 — build에서 매번
  /// 계산하면 한 프레임에 여러 번 1640건을 훑는다.
  List<StoreSuggestion> _suggestions = const [];

  /// 다음 검색 한 번만 이 층으로 좁힌다. 후보를 **탭한 경우**에 선다.
  /// null이면 평소대로 건물 전체를 본다(위 [DirectionsSearchCallback] 주석).
  String? _floorScopeOnce;

  /// 후보 원본을 받아 둔다. 실패는 삼킨다 — 자동완성만 포기하고 검색은 막지 않는다.
  Future<void> _loadStoreIndex() async {
    final source = widget.storeIndex;
    if (source == null) return;
    try {
      final index = await source;
      if (!mounted || index == null) return;
      setState(() {
        _storeIndex = index;
        // 목록이 늦게 도착하는 동안 사용자가 이미 치고 있었을 수 있다.
        _suggestions = _computeSuggestions(_activeQuery);
      });
    } on Object {
      // 자동완성만 포기한다.
    }
  }

  List<StoreSuggestion> _computeSuggestions(String query) {
    final index = _storeIndex;
    if (index == null) return const [];
    return suggestStores(stores: index, query: query);
  }

  @override
  void initState() {
    super.initState();
    _selectedOrigin = widget.initialOrigin;
    _selectedDestination = widget.initialDestination;
    unawaited(_loadStoreIndex());
    if (widget.focusOrigin) {
      // 출발 행을 눌러 열렸다. 후보 목록도 출발지 기준(맨 위 "현재 위치" 고정 행)
      // 이어야 한다. 명시적 출발지가 없으면 칸에 적힌 "현재 위치"는 값이 아니라
      // 안내문이므로 지운다 — 그대로 두면 사용자가 먼저 지워야 하고, 검색어로도
      // 쓰여서 결과가 비어 버린다([_onOriginTap]과 같은 규칙).
      _activeField = _ActiveField.origin;
      if (widget.initialOrigin == null) _originController.clear();
      _search(_originController.text);
      return;
    }
    _activeField = _ActiveField.destination;
    _search(_destinationController.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _originFocusNode.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  /// 타이핑마다 서버를 때리지 않도록 잠깐 모았다 보낸다. 여기서 시작한 검색도
  /// 경량이 빈손이면 의미 검색까지 이어진다 — 엔터를 안 눌러도 된다.
  void _scheduleSearch(String query) {
    _debounce?.cancel();
    // 디바운스가 끝나기 전이라도 이전 요청은 무효화한다. 늦게 도착한 응답이
    // 화면을 덮으면 검색창의 글자와 목록이 어긋난다.
    _searchSeq++;
    _debounce = Timer(_lightDebounce, () => _search(query));
  }

  /// [immediate]가 참이면 의미 검색으로 넘어가기 전 [_semanticGrace] 대기를
  /// 건너뛴다. 엔터로 확정한 경우다.
  Future<void> _search(String raw, {bool immediate = false}) async {
    _debounce?.cancel();
    final query = raw.trim();
    // 여러 검색이 겹쳐 뜰 수 있어(빠른 타이핑 등) 마지막 요청 결과만 반영하도록
    // 시퀀스로 스테일 응답을 버린다.
    final seq = ++_searchSeq;
    setState(() {
      // 새 원문 검색은 이전 clarify 선택의 연장이 아니다. 선택을 남기면 다른
      // 문장에 이전 facet이 섞여 stateless 계약의 의미가 깨진다.
      _selectedFacets = const {};
      _facetSelectionOrder.clear();
      _phase = _SearchPhase.lightSearching;
    });

    // 서버 응답을 기다리지 않는다. 이게 후보가 즉시 뜨는 이유다.
    _suggestions = _computeSuggestions(query);

    List<DirectionsCandidate> results;
    try {
      // 층을 좁히는 경우는 둘뿐이다.
      //  1. 목록에서 후보를 **탭한** 경우 — 그 후보의 층(한 번 쓰고 지운다).
      //  2. 질의가 **층마다 있는 시설**을 가리키는 경우 — 가장 가까운 층.
      // 그 밖에는 null이라 「길찾기는 항상 건물 전체」 규칙이 그대로 유지된다.
      final floorId =
          _floorScopeOnce ??
          nearestFloorForGroupedFacility(
            suggestions: _suggestions,
            reachByNodeId: widget.reachByNodeId,
          );
      _floorScopeOnce = null;
      results = await widget.search(query, floorId: floorId);
    } on Object {
      _finishFailed(query, seq);
      return;
    }
    if (!mounted || seq != _searchSeq) return;

    if (results.isNotEmpty) {
      setState(() {
        _submittedQuery = query;
        _results = results;
        _fromSemantic = false;
        _clearDiscovery();
        _phase = _SearchPhase.results;
      });
      return;
    }

    // 아직 아무것도 치지 않았다. 의미 검색은 빈 질의로 부를 수 없고(서버가
    // text.min_length=1을 강제한다) 부를 이유도 없다.
    if (query.isEmpty) {
      setState(() {
        _submittedQuery = '';
        _results = const [];
        _fromSemantic = false;
        _clearDiscovery();
        _phase = _SearchPhase.idle;
      });
      return;
    }

    // **이름 후보는 임베딩에는 이기고 어휘에는 진다.**
    //
    // 서버 경량 매칭은 `name LIKE`라 구두점이 든 `A.P.C.`를 못 잡고, 초성
    // (`ㄴㅇㅋ`)은 아예 못 잡는다. 그런데 온디바이스 인덱스는 이미 그 매장을
    // 찾아 둔 상태다. 그 정답이 임계값을 겨우 넘긴 의미 검색에 덮이면 안 된다
    // (search-input-assist.md K절 실기기 검증 2번).
    //
    // 그렇다고 `/query/ai` 호출 자체를 막지는 않는다 — 그 엔드포인트의 1차는
    // 임베딩이 아니라 서버 어휘(동의어·intent·카테고리)라, 이름 후보와 같은
    // 등급의 결정적 매칭이다. 막으면 `커피`가 상호에 그 글자가 든 몇 곳으로
    // 끝나고 카페 카테고리 전체가 가려진다. 그래서 후보를 먼저 확정해 보여준
    // 뒤, 응답의 `source`로 교체 여부를 정한다.
    //
    // 교정 후보만 있을 때는 추측이라 2차에 온전히 기회를 준다.
    final hasNameSuggestions = _suggestions.any((s) => !s.kind.isCorrection);
    if (hasNameSuggestions) {
      setState(() {
        _submittedQuery = query;
        _results = const [];
        _fromSemantic = false;
        _clearDiscovery();
        _phase = _SearchPhase.suggestions;
      });
    }

    final semantic = widget.semanticSearch;
    if (semantic == null) {
      // 야외 모드 — 여기가 마지막 단계라 그대로 결론을 낸다.
      setState(() {
        _submittedQuery = query;
        _results = const [];
        _fromSemantic = false;
        _clearDiscovery();
        _phase = _SearchPhase.noMatch;
      });
      return;
    }

    if (immediate) {
      await _semanticSearch(
        query,
        seq,
        keepSuggestionsUnlessLight: hasNameSuggestions,
      );
      return;
    }
    // 대기를 `Future.delayed`가 아니라 Timer로 두는 이유는 취소 때문이다.
    // 시트가 닫히면 dispose가, 사용자가 더 치면 _scheduleSearch가 이 타이머를
    // 끈다. `await Future.delayed`는 취소할 방법이 없다.
    _debounce = Timer(
      _semanticGrace,
      () => _semanticSearch(
        query,
        seq,
        keepSuggestionsUnlessLight: hasNameSuggestions,
      ),
    );
  }

  /// 2단계. 여기까지 왔다는 건 경량이 확실히 빈손이라는 뜻이고, 이 함수가
  /// 끝나야 비로소 [_SearchPhase.noMatch]를 최종 결론으로 쓸 수 있다.
  ///
  /// [keepSuggestionsUnlessLight]가 참이면 화면에 온디바이스 이름 후보가 이미
  /// 떠 있다. 그때는 스피너로 덮지 않고, 어휘(`light`)로 잡은 응답일 때만
  /// 교체한다. 상단 검색 패널의 같은 이름 인자와 규칙이 동일하다.
  Future<void> _semanticSearch(
    String query,
    int seq, {
    bool keepSuggestionsUnlessLight = false,
  }) async {
    final semantic = widget.semanticSearch;
    if (semantic == null || !mounted || seq != _searchSeq) return;
    if (!keepSuggestionsUnlessLight) {
      setState(() => _phase = _SearchPhase.semanticSearching);
    }

    DirectionsDiscovery discovery;
    try {
      discovery = await semantic(query, showAll: false);
    } on Object {
      if (keepSuggestionsUnlessLight) return; // 후보 화면을 오류로 덮지 않는다
      _finishFailed(query, seq);
      return;
    }
    if (!mounted || seq != _searchSeq) return;
    if (keepSuggestionsUnlessLight &&
        (!discovery.source.canReplaceNameSuggestions ||
            discovery.candidates.isEmpty)) {
      return;
    }
    setState(() => _applyDiscovery(query, discovery));
  }

  /// facet 동작은 새 의미 검색 요청이다. 서버 세션이 없으므로 원문·선택 전체를
  /// 항상 다시 보내고, 요청 번호도 올려 과거 응답을 무효화한다.
  Future<void> _requestDiscovery({required bool showAll}) async {
    final semantic = widget.semanticSearch;
    if (semantic == null) return;
    _debounce?.cancel();
    final query = _activeQuery.trim();
    if (query.isEmpty) return;

    final seq = ++_searchSeq;
    setState(() => _phase = _SearchPhase.semanticSearching);
    try {
      final discovery = await semantic(
        query,
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
      if (!mounted || seq != _searchSeq) return;
      setState(() => _applyDiscovery(query, discovery));
    } on Object {
      _finishFailed(query, seq);
    }
  }

  /// [setState] 안에서만 부른다. mode를 화면 상태로 옮기는 유일한 자리다 —
  /// 서버가 새 mode를 추가하거나 계약을 어기면 후보를 임의로 추천하지 않고
  /// 사용자가 다른 표현으로 다시 찾을 수 있는 noMatch로 보낸다.
  void _applyDiscovery(String query, DirectionsDiscovery discovery) {
    _submittedQuery = query;
    _results = discovery.candidates;
    // "뜻이 비슷한 곳"은 임베딩으로 찾았을 때만 맞는 말이다. 서버 어휘로 잡은
    // 결과에까지 붙이면 정확히 찾아 준 것을 추측이라고 말하는 셈이다. 상단
    // 검색 패널과 같은 규칙이다(search_panel.dart의 같은 자리).
    _fromSemantic =
        discovery.candidates.isNotEmpty &&
        !discovery.source.canReplaceNameSuggestions &&
        !isExactNameMatch(query, discovery.candidates.map((c) => c.title));
    _discoveryMode = discovery.mode;
    _discoveryQuestion = discovery.question;
    _discoveryOptions = discovery.options;
    _phase = switch (discovery.mode) {
      DiscoveryMode.direct || DiscoveryMode.results =>
        discovery.candidates.isEmpty
            ? _SearchPhase.noMatch
            : _SearchPhase.results,
      DiscoveryMode.clarify => _SearchPhase.clarify,
      DiscoveryMode.noMatch || DiscoveryMode.unknown => _SearchPhase.noMatch,
      DiscoveryMode.degraded => _SearchPhase.degraded,
    };
  }

  void _clearDiscovery() {
    _discoveryMode = null;
    _discoveryQuestion = null;
    _discoveryOptions = const [];
  }

  /// 서버 장애·네트워크 끊김. 시트를 닫지 않고 안내만 바꾼다. 이걸 "결과 없음"과
  /// 같이 처리하면 백엔드가 죽었을 뿐인데 "그런 매장은 없다"고 말하는 셈이라,
  /// 사용자는 말을 바꿔 가며 계속 헛수고를 하게 된다.
  void _finishFailed(String query, int seq) {
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _submittedQuery = query;
      _results = const [];
      _fromSemantic = false;
      _selectedFacets = const {};
      _facetSelectionOrder.clear();
      _clearDiscovery();
      _phase = _SearchPhase.error;
    });
  }

  void _selectFacet(DiscoveryOption option) {
    final next = Map<String, List<String>>.fromEntries(
      _selectedFacets.entries.map(
        (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
      ),
    );
    // 한 질문은 한 축을 가리키므로 같은 축의 이전 선택은 교체한다.
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

  /// 출발지 입력창을 처음 탭해 활성화할 때만 호출된다. 아직 명시적 출발지가
  /// 없을 때(=필드에 "현재 위치" placeholder만 있음)는 지워서 사용자가 바로
  /// 검색어를 칠 수 있게 하고, 지도에서 "출발지로 설정"으로 매장이 이미 채워진
  /// 경우처럼 실제 출발지가 있을 때는 그대로 남겨 사용자가 다시 입력하지 않아도
  /// 되게 한다(입력을 바꾸고 싶으면 그때 직접 지우거나 덮어쓰면 된다).
  /// 이미 출발지 입력 중일 때(커서 위치만 바꾸는 탭 등)는 타이핑한 내용을
  /// 지우면 안 되므로 다시 호출하지 않는다.
  void _onOriginTap() {
    if (_activeField == _ActiveField.origin) return;
    final hasExplicitOrigin = _selectedOrigin != null;
    setState(() {
      _activeField = _ActiveField.origin;
      if (!hasExplicitOrigin) _originController.clear();
    });
    _search(hasExplicitOrigin ? _originController.text : '');
  }

  /// 도착지 칸으로 넘어올 때도 다시 검색한다. 활성 칸만 바꾸고 목록을 그대로
  /// 두면, 출발지로 찾아 둔 후보가 도착지 후보인 것처럼 남는다.
  void _onDestinationTap() {
    if (_activeField == _ActiveField.destination) return;
    setState(() => _activeField = _ActiveField.destination);
    _search(_destinationController.text);
  }

  void _onOriginChanged(String query) {
    setState(() => _activeField = _ActiveField.origin);
    _scheduleSearch(query);
  }

  void _onDestinationChanged(String query) {
    setState(() => _activeField = _ActiveField.destination);
    _scheduleSearch(query);
  }

  /// 출발지 칸의 지우기 X.
  ///
  /// **글자만 지우면 안 된다.** 칸은 비었는데 [_selectedOrigin]에 방금 지운
  /// 매장이 그대로 남으면, 도착지를 고르는 순간 사용자가 지웠다고 믿는 곳에서
  /// 출발하는 경로가 그려진다. 화면과 확정 상태가 갈라지는 자리라 둘을 같이
  /// 비운다.
  ///
  /// 비운 뒤 칸에 [DirectionsSheet.originLabel]("현재 위치")을 다시 채우지
  /// 않는다. 그건 값이 아니라 안내문이고([_onOriginTap] 주석), X를 눌렀는데
  /// 글자가 남아 있으면 아무 일도 안 일어난 것처럼 보인다. 게다가 그 글자는
  /// 검색어로도 쓰여서 결과가 통째로 비어 버린다. "현재 위치로 되돌리기"는
  /// 목록 맨 위 고정 행([_currentLocationTile])이 담당하고, 비어 있는 상태의
  /// 뜻도 그것과 같다 — `_selectedOrigin == null`이 곧 현재 위치다.
  void _clearOrigin() {
    setState(() {
      _selectedOrigin = null;
      _originController.clear();
      _activeField = _ActiveField.origin;
    });
    // 빈 질의로 다시 검색한다. [_search]가 대기 중인 디바운스를 끊고 요청
    // 번호를 올려, 지우기 직전 글자의 응답이 늦게 도착해 빈 칸 아래에 목록을
    // 깔아 놓는 일을 막는다.
    _search('');
  }

  /// 도착지 칸의 지우기 X. 출발지와 같은 이유로 [_selectedDestination]도 함께
  /// 비운다. 이쪽은 결과가 더 즉각적이다 — 도착지가 남아 있으면
  /// [_afterOriginPicked]가 "도착지는 이미 있다"고 보고, 사용자가 출발지를
  /// 고르는 순간 지워진 줄 알았던 도착지로 시트를 닫아 버린다.
  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destinationController.clear();
      _activeField = _ActiveField.destination;
    });
    _search('');
  }

  /// 교체 버튼을 누를 수 있는지. **출발지가 실제 후보일 때만** 참이다.
  ///
  /// 교체하면 지금 출발지가 도착지가 되는데, 도착지는 [DirectionsResult]가
  /// non-null을 요구하고 경로를 그리려면 point·nodeId가 있어야 한다. "현재
  /// 위치"는 그런 후보 객체가 아예 없다 — 출발지 칸에서만 `null`이라는 뜻으로
  /// 표현되는 특수값이라 도착지 자리로 옮길 수 없다. 그래서 출발지가 현재
  /// 위치인 동안에는 아예 못 누르게 막는다. 눌리게 두고 안에서 되돌리면
  /// 사용자는 버튼이 고장났다고 읽는다.
  ///
  /// 반대로 **도착지가 비어 있어도 교체는 성립한다.** "A에서 출발"을 뒤집으면
  /// "현재 위치에서 출발해 A로 도착"이고, 양쪽 모두 유효한 값이다. 그래서
  /// 조건은 "양쪽 모두 후보"가 아니라 "출발지가 후보" 하나로 충분하다.
  bool get _canSwap => _selectedOrigin != null;

  /// 출발지 ↔ 도착지 교체.
  ///
  /// **확정된 후보만 뒤집는다.** 아직 고르지 않고 타이핑 중인 글자는 후보가
  /// 아니라 검색어라 뒤집을 대상이 없다. 검색어를 반대 칸으로 옮기면 그 칸의
  /// 검색이 처음부터 다시 돌기만 하고, 사용자가 고른 적 없는 값이 확정된
  /// 것처럼 칸에 앉는다.
  ///
  /// **교체 즉시 시트를 닫고 경로를 다시 그린다.** 이 시트에는 확정 버튼이
  /// 없어서 확정 지점은 목록에서 후보를 고르는 순간뿐이다([_selectCandidate]).
  /// 교체만 하고 열어 두면 방금 만든 조합을 제출할 방법이 없어, 사용자는 이미
  /// 칸에 적혀 있는 값을 목록에서 한 번 더 골라야 한다. "빠진 칸이 채워지는
  /// 순간 닫는다"는 [_afterOriginPicked]의 기존 규칙과도 같은 결이다.
  /// [_canSwap] 덕분에 교체 결과의 도착지는 항상 non-null이라 여기서 바로
  /// 결과를 만들 수 있다. 잘못 눌렀더라도 상위가 출발·도착을 모두 기억했다가
  /// 시트를 다시 열 때 되돌려주므로, 한 번 더 누르면 원래대로 돌아간다.
  void _swapOriginDestination() {
    final origin = _selectedOrigin;
    // 버튼이 비활성이라 여기까지 오지 않지만, 상태가 바뀐 뒤 늦게 도착한 탭까지
    // 막아 도착지가 null이 되는 경로를 원천 차단한다.
    if (origin == null) return;
    final destination = _selectedDestination;

    // 다섯 조각을 한 setState에서 함께 뒤집는다. 하나라도 남으면 칸에 적힌
    // 글자와 확정된 후보가 어긋나고, 그 어긋남은 시트를 닫는 순간 경로로 굳는다.
    setState(() {
      _selectedOrigin = destination;
      _selectedDestination = origin;
      // 도착지가 비어 있었다면 출발지는 "현재 위치"로 돌아간다. 값이 아니라
      // 안내문이므로 컨트롤러에는 라벨만 넣고 [_selectedOrigin]은 null로 둔다.
      _originController.text = destination?.title ?? widget.originLabel;
      _destinationController.text = origin.title;
      _activeField = _ActiveField.destination;
    });

    // 교체 직전에 걸려 있던 디바운스와 이미 날아간 요청을 함께 무효화한다.
    // 검색이 도는 중에 교체를 누르면 늦게 도착한 응답이 반대 칸의 목록을
    // 덮는데, `_searchSeq`를 올려 두면 [_search]가 그 응답을 버린다.
    //
    // 무효화만 하고 **새 검색을 걸지는 않는다.** 시트는 바로 아래 줄에서
    // 닫히므로 다시 그릴 목록이 없고, 걸어 두면 아무도 보지 않을 요청 하나가
    // 서버로 더 나간다(닫히는 타이밍에 따라 나갈 때도 안 나갈 때도 있어
    // 재현조차 들쭉날쭉하다).
    _debounce?.cancel();
    _searchSeq++;

    Navigator.of(
      context,
    ).pop(DirectionsResult(origin: destination, destination: origin));
  }

  /// 엔터로 확정. 사용자가 이미 "다 쳤다"고 말한 셈이라 두 대기를 모두
  /// 건너뛴다. 한글 IME에서는 첫 엔터가 조합 확정에 쓰여 여기까지 오지 않을 수
  /// 있으므로 **유일한 트리거가 아니라 지름길**이다 — 그래도 검색은 디바운스로
  /// 끝까지 간다.
  void _onSubmitted(String query) {
    _search(query, immediate: true);
  }

  void _selectCurrentLocationAsOrigin() {
    setState(() {
      _selectedOrigin = null;
      _originController.text = widget.originLabel;
      _activeField = _ActiveField.destination;
    });
    _afterOriginPicked();
  }

  void _selectCandidate(DirectionsCandidate candidate) {
    if (_activeField == _ActiveField.origin) {
      setState(() {
        _selectedOrigin = candidate;
        _originController.text = candidate.title;
        _activeField = _ActiveField.destination;
      });
      _afterOriginPicked();
      return;
    }
    _selectedDestination = candidate;
    Navigator.of(
      context,
    ).pop(DirectionsResult(origin: _selectedOrigin, destination: candidate));
  }

  /// "지도에서 선택" — 도착지를 검색으로 찾지 않고 지도에서 직접 누르겠다는 뜻.
  ///
  /// 시트가 지도를 덮고 있는 동안에는 매장을 누를 수 없으므로 여기서 닫고,
  /// 실제 선택은 호출자(MapShellScreen)가 지도 위에서 이어받는다. 지금까지 고른
  /// 출발지는 함께 돌려줘서 사용자가 다시 입력하지 않게 한다.
  void _pickDestinationOnMap() {
    Navigator.of(
      context,
    ).pop(DirectionsResult.pickDestinationOnMap(origin: _selectedOrigin));
  }

  /// "지도에서 선택" — 출발지 쪽. 도착지 쪽과 대칭이며, 이번에는 **이미 고른
  /// 도착지**를 돌려준다. 안 돌려주면 지도에서 출발지를 찍는 순간 도착지가
  /// 사라져, 방금까지 채워두었던 칸을 다시 입력하게 된다.
  void _pickOriginOnMap() {
    Navigator.of(
      context,
    ).pop(DirectionsResult.pickOriginOnMap(destination: _selectedDestination));
  }

  /// 출발지를 고른 뒤 호출한다. 도착지가 이미 정해져 있으면(예: "도착지로
  /// 설정"에서 넘어와 미리 채워진 경우) 다시 도착지를 고르게 하지 않고
  /// 바로 시트를 닫아 길찾기 경로를 보여준다. 아직 도착지가 없으면 기존처럼
  /// 도착지 입력으로 포커스만 넘긴다.
  void _afterOriginPicked() {
    final destination = _selectedDestination;
    if (destination != null) {
      Navigator.of(context).pop(
        DirectionsResult(origin: _selectedOrigin, destination: destination),
      );
      return;
    }
    _destinationFocusNode.requestFocus();
    _search(_destinationController.text);
  }

  /// 출발지·도착지 입력 칸을 만든다. 두 칸의 유일한 차이는 아이콘·안내문·콜백
  /// 뿐이라, 생김새를 한 곳에 모아 둬야 한쪽에만 X가 붙는 상태가 생기지 않는다.
  ///
  /// 지우기 X는 상단 검색창(`map_top_bar.dart`)과 같은 규칙이다 — **글자가
  /// 있을 때만** 나타난다. 없을 때 `suffixIcon`을 빈 위젯으로 채우면 안 된다:
  /// `InputDecorator`가 아이콘 자리에 최소 48px를 잡아, 보이지도 않는 버튼이
  /// 입력 폭을 계속 갉아먹는다. 그래서 아예 null로 둔다(높이는 prefixIcon이
  /// 이미 잡고 있어 X가 붙고 떨어져도 칸이 흔들리지 않는다).
  ///
  /// 컨트롤러를 직접 구독해 이 칸만 다시 그린다. 부모의 setState에 기대면
  /// 글자가 바깥에서 바뀌는 경로(교체 버튼 등)에서 X가 한 프레임 늦는다.
  Widget _inputField({
    required Key clearKey,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool autofocus,
    required VoidCallback onTap,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
    required Widget prefixIcon,
    required String hintText,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onTap: onTap,
        onChanged: onChanged,
        onSubmitted: _onSubmitted,
        decoration: InputDecoration(
          prefixIcon: prefixIcon,
          hintText: hintText,
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: clearKey,
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  tooltip: '입력 지우기',
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOriginActive = _isOriginActive;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 이 시트는 헤더(제목·입력창)가 스크롤 밖에 있어서 손잡이를 끌면
              // 크기 조절이 아니라 시트 자체가 끌린다(끌어서 닫기). 표시의
              // 의미는 같으므로 다른 시트와 같은 자리에 같은 모양으로 둔다.
              const SheetGrabHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '길찾기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 교체 버튼은 두 입력창 **오른쪽 세로 가운데**에 둔다. 지도
                    // 앱에서 통용되는 자리이기도 하고, 두 칸 사이에 걸쳐 있어야
                    // "무엇과 무엇을 바꾸는지"가 그림으로 읽힌다. 칸 안에 넣으면
                    // 지우기 X와 자리를 다투고, 아래에 따로 두면 어느 칸에
                    // 걸리는 버튼인지 알 수 없다.
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _inputField(
                                clearKey: const Key('directions-clear-origin'),
                                controller: _originController,
                                focusNode: _originFocusNode,
                                autofocus: widget.focusOrigin,
                                onTap: _onOriginTap,
                                onChanged: _onOriginChanged,
                                onClear: _clearOrigin,
                                prefixIcon: const Icon(
                                  Icons.my_location,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                hintText: '출발지를 입력하세요',
                              ),
                              const SizedBox(height: 8),
                              _inputField(
                                clearKey: const Key(
                                  'directions-clear-destination',
                                ),
                                controller: _destinationController,
                                focusNode: _destinationFocusNode,
                                autofocus: !widget.focusOrigin,
                                onTap: _onDestinationTap,
                                onChanged: _onDestinationChanged,
                                onClear: _clearDestination,
                                prefixIcon: const Icon(
                                  Icons.place_outlined,
                                  size: 20,
                                  color: AppColors.dest,
                                ),
                                hintText: '도착지를 입력하세요',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          key: const Key('directions-swap'),
                          // 못 누르는 상태에서도 **숨기지 않는다.** 버튼이
                          // 사라지면 사용자는 기능이 없다고 결론짓고 다시 찾지
                          // 않는다. 대신 왜 못 누르는지를 툴팁으로 말한다.
                          onPressed: _canSwap ? _swapOriginDestination : null,
                          icon: const Icon(Icons.swap_vert),
                          color: AppColors.primary,
                          tooltip: _canSwap
                              ? '출발지와 도착지 교체'
                              : '현재 위치는 도착지로 지정할 수 없어 교체할 수 없어요',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 검색창 바로 아래. 지금 활성인 칸을 지도에서 채운다 — 출발지
              // 칸이면 출발지를, 도착지 칸이면 도착지를 고르는 모드로 넘어간다.
              _PickOnMapTile(
                target: isOriginActive
                    ? DirectionsMapPickTarget.origin
                    : DirectionsMapPickTarget.destination,
                onTap: isOriginActive
                    ? _pickOriginOnMap
                    : _pickDestinationOnMap,
              ),
              Expanded(child: _resultsArea(scrollController, isOriginActive)),
            ],
          );
        },
      ),
    );
  }

  /// 결과 영역. 단계마다 화면 전체를 갈아 끼우지 않고 **행 목록**으로 조립한다.
  /// 출발지 칸이 활성일 때 맨 위 "현재 위치"는 검색이 돌든 실패하든 항상 눌러야
  /// 하는데, 단계별로 다른 위젯을 통째로 그리면 그 행이 사라진다.
  Widget _resultsArea(ScrollController controller, bool isOriginActive) {
    final rows = <Widget>[];
    if (isOriginActive) rows.add(_currentLocationTile());

    final showResults = switch (_phase) {
      _SearchPhase.results ||
      _SearchPhase.clarify ||
      _SearchPhase.degraded => true,
      // 검색 중인 후보는 직전 질의의 것이라 그리지 않는다. 남겨 두면 방금 지운
      // 글자의 결과를 새 글자의 결과처럼 읽는다.
      _ => false,
    };
    if (showResults) {
      if (_discoveryMode != null) rows.add(_discoveryHeader());
      if (_fromSemantic) rows.add(_semanticBanner());
      for (final candidate in _results) {
        rows.add(_candidateTile(candidate));
      }
    }
    rows.addAll(_suggestionRows());

    final status = _statusRow(showResults);
    if (status != null) rows.add(status);

    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => rows[index],
    );
  }

  ListTile _currentLocationTile() => ListTile(
    leading: const Icon(Icons.my_location, color: AppColors.primary),
    title: const Text(
      '현재 위치',
      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    ),
    onTap: _selectCurrentLocationAsOrigin,
  );

  /// 온디바이스 후보 줄. 서버가 못 잡는 초성(`ㄴㅇㅋ`)·구두점(`A.P.C.`)·오타
  /// (`샤낼 뷰티`)가 여기서 걸린다.
  ///
  /// **탭하면 그 이름으로 검색을 다시 돌린다.** 후보에는 좌표가 없어서 곧바로
  /// 목적지로 확정할 수 없기 때문이다([StoreIndexEntry] 주석). 대신 **그 후보의
  /// 층**을 함께 실어 보내 화면에 적힌 층과 실제로 가는 층이 어긋나지 않게 한다.
  List<Widget> _suggestionRows() {
    final showAsAnswer =
        _phase == _SearchPhase.suggestions || _phase == _SearchPhase.noMatch;
    if (!showAsAnswer || _suggestions.isEmpty) return const [];
    final allCorrections = _suggestions.every((s) => s.kind.isCorrection);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
        child: Text(
          allCorrections ? '이걸 찾으셨나요?' : '검색어 제안',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      ),
      for (final suggestion in _suggestions) _suggestionTile(suggestion),
    ];
  }

  ListTile _suggestionTile(StoreSuggestion suggestion) {
    // 묶인 시설(화장실 19곳)에서 어느 매장의 층을 적을지는 거리를 아는 쪽만
    // 정할 수 있다. 상단 검색 패널과 같은 함수를 쓴다.
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: widget.reachByNodeId,
      currentFloorId: widget.currentFloorId,
    );
    final store = nearest.store;
    final reach = nearest.reach;
    final count = suggestion.stores.length;
    final floorLine = count > 1
        ? '${store.floorName} 등 $count곳'
        : store.floorName;
    return ListTile(
      key: Key('directions-suggestion-${store.id}'),
      leading: Icon(
        suggestion.kind.isCorrection ? Icons.auto_fix_high : Icons.search,
        color: AppColors.muted,
      ),
      title: Text(
        store.name,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(floorLine, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (reach != null)
            Text(
              reachLabel(reach),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        _floorScopeOnce = store.floorId;
        _activeController.text = store.name;
        _search(store.name, immediate: true);
      },
    );
  }

  ListTile _candidateTile(DirectionsCandidate candidate) {
    // 실내 후보(floor가 있는 것)인데 입구 노드가 없으면 경로를 계산할 수 없다.
    // 고를 수는 있게 두되(위치는 지도에 보여줄 수 있다) 미리 알린다.
    final unroutable = candidate.floor != null && candidate.nodeId == null;
    final subtitle =
        candidate.reason ??
        (unroutable ? '${candidate.subtitle} · 경로 안내 불가' : candidate.subtitle);
    // 상단 검색 결과와 **같은 규칙**이다 — 거리를 모르면 줄을 아예 그리지 않는다.
    // 줄마다 "거리 알 수 없음"을 반복하면 목록이 읽히지 않는다.
    final nodeId = candidate.nodeId;
    final reach = nodeId == null ? null : widget.reachByNodeId?[nodeId];
    return ListTile(
      leading: const Icon(Icons.place, color: AppColors.primary),
      title: Text(
        candidate.title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (reach != null)
            Text(
              reachLabel(reach),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 검색 결과 행과 같은 무게. 두 화면이 같은 값을 다르게 그리면
              // 사용자는 둘이 다른 것을 뜻한다고 읽는다.
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      isThreeLine: reach != null,
      onTap: () => _selectCandidate(candidate),
    );
  }

  /// 왜 치지도 않은 이름이 나왔는지 설명하는 줄. 이게 없으면 사용자는 검색이
  /// 엉뚱한 결과를 냈다고 읽는다.
  Widget _semanticBanner() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '뜻이 비슷한 곳을 찾았어요',
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

  /// clarify 질문 + 선택 chip. 상단 검색 패널과 같은 계약(축 하나에 값 하나,
  /// 매 요청에 선택 전체 재전송)을 그대로 쓴다.
  Widget _discoveryHeader() {
    final isClarify = _discoveryMode == DiscoveryMode.clarify;
    final selectedChips = <Widget>[];
    for (final entry in _selectedFacets.entries) {
      for (final value in entry.value) {
        selectedChips.add(
          InputChip(
            key: Key('directions-selected-facet-${entry.key}-$value'),
            label: Text('$value 선택됨'),
            onDeleted: () => _removeFacet(entry.key, value),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
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
                          'directions-facet-option-'
                          '${option.facet}-${option.value}',
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
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: const Key('directions-show-all'),
                onPressed: () => _requestDiscovery(showAll: true),
                child: const Text('전체 보기'),
              ),
              TextButton(
                key: const Key('directions-choose-again'),
                onPressed: _chooseAgain,
                child: const Text('다시 선택'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 후보 목록 아래(또는 대신) 붙는 안내 한 줄. 보여줄 후보가 있으면 안내는
  /// 필요 없다.
  Widget? _statusRow(bool showResults) {
    if (showResults && _results.isNotEmpty) return null;
    return switch (_phase) {
      _SearchPhase.idle => _message(
        widget.semanticSearch != null
            ? '이름을 입력하면 바로 찾아드려요.\n"밥 먹을 곳"처럼 뜻으로 물어도 됩니다.'
            : '이름을 입력해 목적지를 찾아보세요.',
      ),
      _SearchPhase.lightSearching ||
      _SearchPhase.semanticSearching => _searchingRow(),
      // 의미 검색까지 끝난 뒤에만 도달한다(야외 모드는 경량이 마지막 단계다).
      _SearchPhase.noMatch => _message(
        _submittedQuery.isEmpty
            ? '검색 결과가 없습니다'
            : '"$_submittedQuery"에 맞는 곳을 찾지 못했어요.\n다른 말로 바꿔서 다시 찾아보세요.',
      ),
      _SearchPhase.degraded => _message(
        '추천 기능을 지금은 제한적으로만 사용할 수 있어요.\n'
        '잠시 후 다시 검색하거나 다른 표현으로 찾아보세요.',
      ),
      _SearchPhase.error => _message(
        '지금은 검색할 수 없어요.\n연결 상태를 확인하고 잠시 후 다시 시도해 주세요.',
      ),
      // clarify·results인데 후보가 비었다면 질문 chip만 남은 상태다.
      // suggestions는 온디바이스 후보 줄이 이미 답을 그리고 있으므로 안내가 없다.
      _SearchPhase.clarify ||
      _SearchPhase.results ||
      _SearchPhase.suggestions => null,
    };
  }

  /// 아직 결론이 아니라는 표시. 의미 검색 단계에서는 문구를 덧붙인다 — 여기서
  /// 갑자기 오래 걸리기 시작하므로, 같은 스피너만 돌면 멈춘 것처럼 보인다.
  Widget _searchingRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (_phase == _SearchPhase.semanticSearching) ...[
            const SizedBox(height: 14),
            const Text(
              '취향에 맞는 곳을 찾는 중…',
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

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
    ),
  );
}
