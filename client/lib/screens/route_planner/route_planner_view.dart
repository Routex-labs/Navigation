import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/service_locator.dart';
import '../../models/directions_route.dart';
import '../../models/transit_route.dart';
import '../../theme/app_theme.dart';
import '../../widgets/directions_candidate.dart';
import '../../widgets/route_planner/road_route_summary_card.dart';
import '../../widgets/route_planner/route_plan_mode.dart';
import '../../widgets/route_planner/route_planner_header.dart';
import '../../widgets/route_planner/transit_route_detail_sheet.dart';
import '../../widgets/transit_itinerary_tile.dart';

/// 길찾기 화면이 **지도에게** 시키는 일들.
///
/// 지도를 이 화면 안에 새로 만들지 않는 이유가 여기 있다. MapLibre 지도는
/// 플랫폼 뷰라 하나 더 띄우면 타일·GPS·실내 도면을 통째로 다시 로드하고, 방금
/// 보던 카메라와 위치 앵커가 날아간다. 그래서 그리는 일은 이미 떠 있는 야외
/// 지도에 맡기고, 이 화면은 그 위에 얹혀 **무엇을 그릴지만** 정한다.
abstract interface class RoutePlannerMap {
  /// 출발지를 따로 고르지 않았을 때 쓸 "현재 위치" 좌표. GPS를 아직 못 잡았고
  /// 지도에서 찍은 출발점도 없으면 null이다.
  LatLng? get currentOriginPoint;

  /// 도로 경로(자동차·도보)의 끝점 보정. [point]가 우리 실내 도면이 있는 건물
  /// **안**이면 그 건물의 지상 출입구로 바꾼다.
  ///
  /// 건물 내부 좌표를 그대로 끝점으로 주면 TMAP이 가장 가까운 도로로 스냅해,
  /// 실제로 들어갈 수 있는 문과 다른 면에 사용자를 내려놓는다.
  LatLng resolveRoadEndpoint(LatLng point);

  /// 자동차·도보 경로선을 지도에 그린다.
  Future<void> showRoadRoute(
    DirectionsRoute route, {
    required LatLng origin,
    required LatLng destination,
    required String label,
  });

  /// 고른 대중교통 경로를 지도에 그린다.
  Future<void> showTransitItinerary(
    TransitItinerary itinerary, {
    required LatLng origin,
    required LatLng destination,
    required String label,
  });

  /// 지금 그려 둔 경로를 지운다. 길찾기를 취소하거나 조건이 바뀌어 다시
  /// 계산하기 직전에 부른다 — 안 지우면 새 경로가 나올 때까지 옛 선이 남아
  /// 화면과 카드가 서로 다른 경로를 말한다.
  void clearPlannedRoute();
}

/// 아래에서 시트가 올라오는 대신 **화면이 통째로 바뀌는** 길찾기.
///
/// 예전에는 길찾기 버튼이 바텀시트를 올렸다. 시트가 지도를 덮으니 경로를 보려면
/// 시트를 닫아야 했고, 닫으면 방금 넣은 출발/도착이 어디로 갔는지 알 수 없었다.
/// 게다가 수단은 시트를 닫은 **뒤에** 지도 위 작은 줄에서 고르게 되어, 입력과
/// 선택이 서로 다른 화면에 흩어져 있었다.
///
/// 이 화면은 그 셋을 한 자리에 모은다 — 맨 위에 수단, 그 아래 출발/도착, 그
/// 아래에 결과. 결과의 모양만 수단에 따라 갈린다.
///
/// - **자동차·도보**: 고르는 즉시 지도에 경로 하나를 그리고 아래에 요약 카드.
/// - **대중교통**: 후보 목록을 먼저 보여 주고, 하나를 고르면 지도 + 끌 수 있는
///   상세 시트. 그 시트의 X는 목록으로 되돌아간다(지도로 닫지 않는다).
class RoutePlannerView extends StatefulWidget {
  const RoutePlannerView({
    super.key,
    required this.map,
    required this.search,
    required this.onClose,
    required this.onEndpointsChanged,
    required this.onPickOnMap,
    required this.onIndoorWalkRoute,
    this.onModeChanged,
    this.initialOrigin,
    this.initialDestination,
    this.initialMode,
    this.initialField,
    this.transitEnabled = true,
  });

  final RoutePlannerMap map;
  final DirectionsSearchCallback search;

  /// 길찾기를 끝내고 지도로 돌아간다. X로 취소했을 때는 그리던 경로도 함께
  /// 지운 뒤에, "안내시작"으로 넘어갈 때는 경로를 남긴 채로 불린다.
  final VoidCallback onClose;

  /// 두 칸이 바뀔 때마다 상위에 알린다. 상위(지도 화면)가 같은 값을 상단 초안
  /// 바에 쓰고 있어서, 안 알리면 길찾기를 닫는 순간 방금 넣은 목적지가 사라진다.
  final void Function(
    DirectionsCandidate? origin,
    DirectionsCandidate? destination,
  )
  onEndpointsChanged;

  /// "지도에서 선택". 이 화면이 지도를 덮고 있으므로 상위가 화면을 접고 지도
  /// 탭을 받아야 한다 — 고른 뒤에 상위가 이 화면을 다시 연다.
  final ValueChanged<DirectionsMapPickTarget> onPickOnMap;

  /// 사용자가 수단을 **직접** 바꿨을 때. 상위가 이 값을 기억해 두었다가 "지도에서
  /// 선택"으로 화면을 접었다 다시 열 때 되살린다 — 안 그러면 자동차를 골라 둔
  /// 사용자가 출발지를 지도에서 찍고 돌아왔을 때 거리로 다시 정해진 수단을 본다.
  ///
  /// 자동으로 정한 첫 수단은 알리지 않는다. 그것은 선택이 아니라 기본값이고,
  /// 상위가 그것까지 기억하면 조건이 바뀌어도 옛 기본값이 계속 따라다닌다.
  final ValueChanged<RoutePlanMode>? onModeChanged;

  /// 도보 + **건물 안 매장**이 목적지인 경우. 이 조합만 상위의 기존 흐름으로
  /// 넘긴다.
  ///
  /// 그 안내는 "문을 경유해 매장까지"라 야외 도보 구간과 실내 구간이 한 몸이고,
  /// 층 이동까지 포함한다. 여기서 도로 경로 하나로 그리면 건물 외벽에서 안내가
  /// 끝나 정작 목적지인 매장에 닿지 못한다.
  final void Function(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  )
  onIndoorWalkRoute;

  final DirectionsCandidate? initialOrigin;
  final DirectionsCandidate? initialDestination;

  /// 처음 고를 수단. 없으면 거리를 보고 정한다([_pickInitialMode]).
  final RoutePlanMode? initialMode;

  /// 열자마자 커서를 둘 칸. 없으면 도착지가 비었을 때만 도착지 칸이 열린다.
  final RoutePlanField? initialField;

  final bool transitEnabled;

  @override
  State<RoutePlannerView> createState() => _RoutePlannerViewState();
}

/// 걸어갈 만한 거리의 상한(m).
///
/// 1.5 km는 보통 걸음으로 20분쯤이다. 그보다 멀면 대중교통을 먼저 보여 주는
/// 편이 맞다 — 도보 안내를 지나쳐 다시 누르게 하는 것보다 낫고, 반대로 이 값을
/// 더 낮추면 두 정거장 거리를 굳이 버스로 안내하게 된다.
const _walkableMeters = 1500.0;

class _RoutePlannerViewState extends State<RoutePlannerView> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _originFocus = FocusNode();
  final _destinationFocus = FocusNode();

  late RoutePlanMode _mode;
  DirectionsCandidate? _origin;
  DirectionsCandidate? _destination;

  /// 지금 글자를 치고 있는 칸. null이면 결과(지도·목록)를 보는 중이다.
  RoutePlanField? _editing;

  List<DirectionsCandidate> _results = const [];
  bool _searching = false;
  int _searchSeq = 0;

  /// 경로 계산 순번. 수단을 빠르게 바꾸면 요청이 겹치는데, 늦게 도착한 옛
  /// 응답이 새 경로를 덮으면 화면과 지도가 서로 다른 수단을 말하게 된다.
  int _computeSeq = 0;
  bool _computing = false;
  String? _error;

  /// 실패했을 때 사용자가 할 수 있는 일. 재조회로 풀리는 실패에만 채운다.
  VoidCallback? _errorAction;
  String? _errorActionLabel;

  DirectionsRoute? _roadRoute;
  TransitRoutes? _transitRoutes;
  TransitItinerary? _selectedItinerary;

  /// 후보를 조회한 시각. 상세 시트의 "오후 9:53 - 11:01"이 이 값을 기준으로
  /// 계산된다 — 매 프레임 now()를 읽으면 시트를 열어 둔 채 숫자가 저 혼자 바뀐다.
  DateTime? _transitQueriedAt;

  List<RoutePlanMode> get _modes => [
    for (final mode in RoutePlanMode.values)
      if (mode != RoutePlanMode.transit || widget.transitEnabled) mode,
  ];

  @override
  void initState() {
    super.initState();
    _origin = widget.initialOrigin;
    _destination = widget.initialDestination;
    _originController.text = _origin?.title ?? '';
    _destinationController.text = _destination?.title ?? '';
    _mode = widget.initialMode ?? _pickInitialMode();
    _originFocus.addListener(_onOriginFocusChanged);
    _destinationFocus.addListener(_onDestinationFocusChanged);

    final field =
        widget.initialField ??
        (_destination == null ? RoutePlanField.destination : null);
    if (field != null) {
      _editing = field;
      // 입력 칸에 커서를 넣는 것과 후보 목록을 그 칸 기준으로 여는 것은 같이
      // 가야 한다. 하나만 하면 커서는 출발 칸에 있는데 목록은 도착지 후보인
      // 상태가 된다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (field == RoutePlanField.origin ? _originFocus : _destinationFocus)
            .requestFocus();
      });
      _search('');
      return;
    }
    // 두 칸이 이미 채워진 채 열렸다(매장 시트에서 "도착지로 설정" 등).
    // 물어볼 것이 없으므로 곧바로 계산해서 결과부터 보여 준다.
    //
    // **다음 프레임으로 미룬다.** 계산을 시작하면 지도(이미 이 프레임에서
    // 그려진 위젯)의 경로를 지우게 되는데, 그 setState를 build 도중에 부르면
    // "setState() called during build"로 터진다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_compute());
    });
  }

  @override
  void dispose() {
    _originFocus.removeListener(_onOriginFocusChanged);
    _destinationFocus.removeListener(_onDestinationFocusChanged);
    _originController.dispose();
    _destinationController.dispose();
    _originFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  /// 거리를 보고 처음 보여 줄 수단을 정한다.
  ///
  /// 출발점이나 도착지를 모르면 도보로 둔다. 모르는 채로 대중교통을 부르면
  /// "현재 위치를 아직 못 잡았습니다"만 뜨고 끝나, 사용자는 수단을 고른 적도
  /// 없는데 실패 안내를 본다.
  RoutePlanMode _pickInitialMode() {
    final destination = _destination;
    final from = _origin?.point ?? widget.map.currentOriginPoint;
    if (destination == null || from == null || !widget.transitEnabled) {
      return RoutePlanMode.walk;
    }
    final meters = const Distance().as(
      LengthUnit.Meter,
      from,
      destination.point,
    );
    return meters > _walkableMeters
        ? RoutePlanMode.transit
        : RoutePlanMode.walk;
  }

  void _onOriginFocusChanged() {
    if (!_originFocus.hasFocus || _editing == RoutePlanField.origin) return;
    setState(() => _editing = RoutePlanField.origin);
    _search(_originController.text);
  }

  void _onDestinationFocusChanged() {
    if (!_destinationFocus.hasFocus || _editing == RoutePlanField.destination) {
      return;
    }
    setState(() => _editing = RoutePlanField.destination);
    _search(_destinationController.text);
  }

  Future<void> _search(String query) async {
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    final results = await widget.search(query);
    // 여러 검색이 겹쳐 뜰 수 있어(빠른 타이핑 등) 마지막 요청 결과만 반영한다.
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _onOriginChanged(String query) {
    setState(() {
      _editing = RoutePlanField.origin;
      // 글자를 지우거나 고쳤다는 것은 지금 잡혀 있는 출발지를 버렸다는 뜻이다.
      // 안 버리면 "강남역"을 지우고 다른 곳을 쳐도 계산은 강남역에서 시작한다.
      _origin = null;
    });
    _search(query);
  }

  void _onDestinationChanged(String query) {
    setState(() {
      _editing = RoutePlanField.destination;
      _destination = null;
    });
    _search(query);
  }

  void _swap() {
    setState(() {
      final origin = _origin;
      _origin = _destination;
      _destination = origin;
      _originController.text = _origin?.title ?? '';
      _destinationController.text = _destination?.title ?? '';
      _editing = null;
    });
    _unfocusFields();
    widget.onEndpointsChanged(_origin, _destination);
    _compute();
  }

  void _selectCurrentLocationAsOrigin() {
    setState(() {
      _origin = null;
      _originController.clear();
    });
    _afterPicked(RoutePlanField.origin);
  }

  void _selectCandidate(DirectionsCandidate candidate) {
    final field = _editing ?? RoutePlanField.destination;
    setState(() {
      if (field == RoutePlanField.origin) {
        _origin = candidate;
        _originController.text = candidate.title;
      } else {
        _destination = candidate;
        _destinationController.text = candidate.title;
      }
    });
    _afterPicked(field);
  }

  /// 한 칸을 채운 뒤. 아직 도착지가 없으면 도착지 칸으로 넘겨 주고, 둘 다
  /// 준비됐으면 입력을 닫고 경로를 계산한다.
  void _afterPicked(RoutePlanField field) {
    widget.onEndpointsChanged(_origin, _destination);
    if (_destination == null) {
      setState(() => _editing = RoutePlanField.destination);
      _destinationFocus.requestFocus();
      _search(_destinationController.text);
      return;
    }
    setState(() => _editing = null);
    _unfocusFields();
    _compute();
  }

  void _unfocusFields() {
    _originFocus.unfocus();
    _destinationFocus.unfocus();
  }

  void _onModeChanged(RoutePlanMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    widget.onModeChanged?.call(mode);
    // 수단을 바꾼 것은 "다시 계산해 달라"는 뜻이다. 입력 중이었더라도 두 칸이
    // 이미 채워져 있으면 결과부터 보여 준다.
    if (_destination != null) {
      setState(() => _editing = null);
      _unfocusFields();
    }
    _compute();
  }

  /// 도로 경로의 출발 좌표.
  ///
  /// 실내 지점이 출발지면 건물 문으로 바꾼다. 건물 안 좌표를 그대로 보내면
  /// TMAP이 건물 반대편 도로에 스냅해, 실제로 나가는 문과 다른 곳에서 경로가
  /// 시작한다. 출발지를 안 골랐으면 현재 위치(GPS 또는 지도에서 찍은 지점)다.
  LatLng? _originPoint() {
    final origin = _origin;
    if (origin == null) return widget.map.currentOriginPoint;
    return widget.map.resolveRoadEndpoint(origin.point);
  }

  Future<void> _compute() async {
    final destination = _destination;
    if (destination == null) return;

    // 도보 + 건물 안 매장은 이 화면이 그릴 수 없는 유일한 조합이다. 상위의
    // "문을 경유해 매장까지" 흐름으로 넘긴다([RoutePlannerView.onIndoorWalkRoute]).
    if (_mode == RoutePlanMode.walk && destination.isIndoorPoint) {
      widget.onIndoorWalkRoute(_origin, destination);
      return;
    }

    final seq = ++_computeSeq;
    widget.map.clearPlannedRoute();
    setState(() {
      _computing = true;
      _error = null;
      _errorAction = null;
      _errorActionLabel = null;
      _roadRoute = null;
      _transitRoutes = null;
      _selectedItinerary = null;
    });

    final origin = _originPoint();
    if (origin == null) {
      _finishWithError(seq, '현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }
    final endpoint = widget.map.resolveRoadEndpoint(destination.point);

    if (_mode == RoutePlanMode.transit) {
      await _computeTransit(seq, origin: origin, endpoint: endpoint);
      return;
    }
    await _computeRoad(seq, origin: origin, endpoint: endpoint);
  }

  Future<void> _computeRoad(
    int seq, {
    required LatLng origin,
    required LatLng endpoint,
  }) async {
    final route = _mode == RoutePlanMode.car
        ? await directionsRepository.getDrivingRoute(
            origin: origin,
            destination: endpoint,
          )
        : await directionsRepository.getWalkingRoute(
            origin: origin,
            destination: endpoint,
          );
    if (!mounted || seq != _computeSeq) return;
    if (route == null) {
      _finishWithError(
        seq,
        _mode == RoutePlanMode.car
            ? '자동차 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.'
            : '도보 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
        actionLabel: '다시 시도',
        action: _compute,
      );
      return;
    }
    setState(() {
      _computing = false;
      _roadRoute = route;
    });
    await widget.map.showRoadRoute(
      route,
      origin: origin,
      destination: endpoint,
      // 도로 경로 라벨은 **이름 그대로**다. "안내시작"으로 넘어가면 지도 위
      // ETA 카드가 이 값을 그대로 적는데, 다른 진입점(검색에서 바로 도착 선택)이
      // 이미 이름만 넘기고 있어서 여기서 "까지"를 붙이면 같은 목적지가 어떻게
      // 골랐느냐에 따라 다르게 적힌다. 대중교통 요약 카드는 반대로 문장형이라
      // "OO까지"를 받는다.
      label: _destination?.title ?? '목적지',
    );
  }

  Future<void> _computeTransit(
    int seq, {
    required LatLng origin,
    required LatLng endpoint,
  }) async {
    final routes = await transitRepository.getTransitRoutes(
      origin: origin,
      destination: endpoint,
    );
    if (!mounted || seq != _computeSeq) return;

    // 결말마다 사용자가 할 행동이 다르다. 한 문구로 묶으면 700m 앞 목적지를
    // 두고 계속 재시도하게 된다([TransitRoutesStatus] 주석).
    switch (routes.status) {
      case TransitRoutesStatus.unavailable:
        _finishWithError(seq, '대중교통 안내를 쓸 수 없습니다. TMAP 키 설정을 확인해주세요.');
      case TransitRoutesStatus.failed:
        _finishWithError(
          seq,
          '대중교통 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
          actionLabel: '다시 시도',
          action: _compute,
        );
      case TransitRoutesStatus.tooClose:
        // 걸어갈 수 있는 거리다. 여기서 끝내지 않고 도보로 넘어갈 길을 준다 —
        // 사용자가 원한 것은 "저기까지 가는 방법"이지 "대중교통 그 자체"가 아니다.
        _finishWithError(
          seq,
          '가까운 거리라 대중교통 경로가 없습니다.',
          actionLabel: '도보로 보기',
          action: () => _onModeChanged(RoutePlanMode.walk),
        );
      case TransitRoutesStatus.noRoute:
        _finishWithError(seq, '이 구간의 대중교통 경로를 찾지 못했습니다.');
      case TransitRoutesStatus.ok:
        setState(() {
          _computing = false;
          _transitRoutes = routes;
          _transitQueriedAt = DateTime.now();
        });
    }
  }

  void _finishWithError(
    int seq,
    String message, {
    String? actionLabel,
    VoidCallback? action,
  }) {
    if (!mounted || seq != _computeSeq) return;
    setState(() {
      _computing = false;
      _error = message;
      _errorActionLabel = actionLabel;
      _errorAction = action;
    });
  }

  Future<void> _pickItinerary(TransitItinerary itinerary) async {
    final destination = _destination;
    final origin = _originPoint();
    if (destination == null || origin == null) return;
    setState(() => _selectedItinerary = itinerary);
    await widget.map.showTransitItinerary(
      itinerary,
      origin: origin,
      destination: widget.map.resolveRoadEndpoint(destination.point),
      label: '${destination.title}까지',
    );
  }

  /// 상세 시트의 X. 지도의 선을 걷고 후보 목록으로 되돌아간다.
  void _backToTransitList() {
    widget.map.clearPlannedRoute();
    setState(() => _selectedItinerary = null);
  }

  /// 머리의 X. 그리던 경로까지 지우고 지도로 돌아간다 — 남겨 두면 취소했는데
  /// 화면에는 경로가 그대로인 상태가 된다.
  void _cancel() {
    widget.map.clearPlannedRoute();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 뒤로가기는 앱을 끄는 대신 길찾기만 닫는다. 상세를 보는 중이면 한 단계
      // 위(목록)로만 올라간다 — X와 같은 규칙이라 둘 중 무엇을 눌러도 같은 곳에
      // 도착한다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectedItinerary != null) {
          _backToTransitList();
          return;
        }
        _cancel();
      },
      child: Column(
        children: [
          RoutePlannerHeader(
            mode: _mode,
            modes: _modes,
            onModeChanged: _onModeChanged,
            originController: _originController,
            destinationController: _destinationController,
            originFocus: _originFocus,
            destinationFocus: _destinationFocus,
            onOriginChanged: _onOriginChanged,
            onDestinationChanged: _onDestinationChanged,
            onSwap: _swap,
            onClose: _cancel,
          ),
          // 머리 아래는 상황에 따라 지도를 **덮거나 비운다.** 비어 있는 자리는
          // 아무 위젯도 그리지 않아 그대로 지도 탭이 통과한다 — 투명한 막을
          // 깔면 지도를 못 움직이게 된다.
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_editing != null) return _buildSearchResults();
    if (_mode == RoutePlanMode.transit) return _buildTransitBody();
    return _buildRoadBody();
  }

  /// 후보 목록. 검색 중에는 지도를 완전히 덮는다 — 이 순간 사용자가 보는 것은
  /// 지도가 아니라 "어디로 갈지"의 선택지다.
  Widget _buildSearchResults() {
    final isOrigin = _editing == RoutePlanField.origin;
    final target = isOrigin
        ? DirectionsMapPickTarget.origin
        : DirectionsMapPickTarget.destination;
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          _PickOnMapTile(
            target: target,
            onTap: () => widget.onPickOnMap(target),
          ),
          const Divider(height: 1),
          Expanded(
            child: _searching && _results.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    // 출발지 칸에서는 맨 위에 "현재 위치"를 고정으로 둔다.
                    // 따로 고르지 않으면 그게 기본값이므로, 되돌아올 길이
                    // 목록 안에 있어야 한다.
                    itemCount: _results.length + (isOrigin ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (isOrigin && index == 0) {
                        return ListTile(
                          key: const Key('route-planner-current-location'),
                          leading: const Icon(
                            Icons.my_location,
                            color: AppColors.primary,
                          ),
                          title: const Text(
                            '현재 위치',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          onTap: _selectCurrentLocationAsOrigin,
                        );
                      }
                      final candidate = _results[index - (isOrigin ? 1 : 0)];
                      return ListTile(
                        // 건물과 건물 안 매장을 아이콘으로 가른다. 같은 핀으로
                        // 두면 목록에서 무엇이 건물인지 읽을 방법이 없다.
                        leading: Icon(
                          candidate.buildingId == null
                              ? Icons.place
                              : Icons.apartment_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          candidate.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(candidate.subtitle),
                        onTap: () => _selectCandidate(candidate),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadBody() {
    final route = _roadRoute;
    if (route == null) return _bottomSlot(_buildStatusCard());
    return _bottomSlot(
      RoadRouteSummaryCard(
        mode: _mode,
        route: route,
        // "안내시작"은 경로를 **남긴 채** 화면만 닫는다. 그래야 지도 위 ETA
        // 카드가 그 경로를 이어받아 걷는 동안 안내를 계속한다.
        onStart: widget.onClose,
      ),
    );
  }

  Widget _buildTransitBody() {
    final selected = _selectedItinerary;
    if (selected != null) {
      return TransitRouteDetailSheet(
        itinerary: selected,
        originLabel: _origin?.title ?? '현재 위치',
        destinationLabel: _destination?.title ?? '목적지',
        departAt: _transitQueriedAt,
        onBackToList: _backToTransitList,
        onStart: widget.onClose,
      );
    }
    final routes = _transitRoutes;
    if (routes == null || !routes.hasRoutes) {
      // 목록이 없을 때는 지도를 덮지 않는다. 진행 중·실패 안내는 한 장이면
      // 충분하고, 그 뒤로 지도가 보이면 사용자가 어디를 조회 중인지 안다.
      return _bottomSlot(_buildStatusCard());
    }
    final itineraries = routes.itineraries;
    return Material(
      color: Colors.white,
      child: ListView.separated(
        padding: EdgeInsets.only(
          top: 4,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: itineraries.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 20, endIndent: 20),
        itemBuilder: (context, index) => TransitItineraryTile(
          itinerary: itineraries[index],
          // 첫 줄은 정렬상 가장 빠른 경로다. 그 사실을 배지로 밝히지 않으면
          // 사용자는 순서의 의미를 추측해야 한다.
          fastest: index == 0 && itineraries.length > 1,
          onTap: () => _pickItinerary(itineraries[index]),
        ),
      ),
    );
  }

  /// 진행 중·실패를 알리는 한 장짜리 카드. 둘을 한 자리에 모아 두면 "계산
  /// 중"과 "실패"가 같은 위치에서 바뀌어, 사용자가 눈을 옮기지 않아도 된다.
  Widget? _buildStatusCard() {
    final error = _error;
    if (error != null) {
      final actionLabel = _errorActionLabel;
      final action = _errorAction;
      return Card(
        key: const Key('route-planner-error'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                style: const TextStyle(fontSize: 14, color: AppColors.text),
              ),
              if (actionLabel != null && action != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: action,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(actionLabel),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (!_computing) return null;
    return const Card(
      key: Key('route-planner-loading'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('경로를 계산하는 중…', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  /// 지도를 가리지 않고 화면 아래에만 카드를 놓는다. [child]가 null이면 아무것도
  /// 그리지 않아 그 자리가 통째로 지도가 된다.
  Widget _bottomSlot(Widget? child) {
    if (child == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: child,
        ),
      ),
    );
  }
}

/// 검색 결과 맨 위 줄. 목적지를 이름으로 찾지 않고 지도에서 직접 누르고 싶은
/// 사용자를 위한 지름길이다.
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
    return ListTile(
      key: const Key('route-planner-pick-on-map'),
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
      subtitle: Text(
        isOrigin ? '지도에서 매장을 눌러 출발지로 지정합니다' : '지도에서 매장을 눌러 도착지로 지정합니다',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: AppColors.muted,
      ),
    );
  }
}
