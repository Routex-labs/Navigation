// ignore_for_file: invalid_use_of_protected_member
//
// 이 파일은 `OutdoorMapBodyState`의 part다. setState는 그 클래스가 State에서
// 물려받은 protected 멤버이고, 여기서 부르는 것은 **같은 클래스의 코드**다 —
// 파일만 갈라져 있을 뿐 바깥에서 남의 protected 멤버를 건드리는 것이 아니다.
// 분석기는 extension을 "서브클래스가 아니다"로 보아 경고하므로 파일 단위로
// 끈다. 본체(생명주기·build)는 클래스 안에 있어 이 해제의 영향을 받지 않는다.
/// `OutdoorMapBodyState`의 **경로·안내·대중교통** 부분.
///
/// [outdoor_map_screen.dart]의 part다. 한 파일이 7,500줄을 넘어 읽을 수
/// 없어져 성격별로 갈랐다 — **옮기기만 했고 동작은 그대로다.**
///
/// extension을 쓰는 이유: 같은 라이브러리(part)라 private 멤버가 그대로
/// 보이고, extension끼리도 서로 부를 수 있다. mixin은 서로의 private
/// 멤버를 못 봐서 이렇게 얽힌 클래스에는 쓸 수 없다.
///
/// 상태 필드와 생명주기(initState/dispose/build), 그리고 셸이 부르는
/// 공개 API 19개는 본체에 남아 있다.
part of 'outdoor_map_screen.dart';

extension OutdoorMapRoute on OutdoorMapBodyState {
  // 실내 진입 오버레이 위에 그리는 실내 경로. 현재 보고 있는 층에 해당하는
  // 세그먼트만 지도에 그려지고, 층 chip으로 다른 층을 훑으면 해당 층 세그먼트로
  // 갈아탄다. 다층 경로일 때는 [_indoorMultiFloorRoute]에 전체가 남아 있어
  // ETA 총 거리도 유지된다.
  /// 지금 이 층에 그려진 실내 경로 세그먼트. 실내 탭과 같은 세션이 소유한다 —
  /// 진행률이 이 값에 투영되므로 두 곳에 두면 남은거리가 갈라진다.
  IndoorRoute? get _indoorRouteSegment => _guidance.routeSegment;

  /// 층 전환 작업을 직렬화한다.
  ///
  /// 겹쳐 돌면 층과 경로가 서로 다른 시점을 가리킨다. 오류가 나도 탑승 상태를
  /// 화면에 남기지 않는다 — 큐가 오류만 찍고 끝나면 걸음이 멈춘 채 배너가
  /// 영구히 남고 사용자가 복구할 방법이 없다.
  void _enqueueFloorTransition(Future<void> Function() action) {
    _floorTransitionQueue = _floorTransitionQueue
        .then((_) => mounted ? action() : Future<void>.value())
        .onError(_recoverFloorTransitionFailure);
  }

  Future<void> _recoverFloorTransitionFailure(
    Object error,
    StackTrace stackTrace,
  ) async {
    debugPrint('floor transition failed: $error\n$stackTrace');
    if (!mounted) return;
    await _endEscalatorRide();
    if (!mounted) return;
    setState(() => _pendingArrivalNode = null);
    _showSnack('층 전환을 완료하지 못했습니다. 현재 층과 위치를 다시 확인해주세요.');
  }

  /// 디버그 전용 — 실제 탑승 없이 층 전환 시퀀스를 태운다.
  ///
  /// **판정기를 흉내 내는 것이지 우회하는 것이 아니다.** 판정기가 확정을 냈을 때
  /// 타는 경로(시작 → 확정, [_beginEscalatorTransition] →
  /// [_completeEscalatorTransition])에 합성 transition을 그대로 넣는다. 도면
  /// 크로스페이드와 마커 활강·카메라 정렬([_swapIndoorFloorForRide]), 새 층
  /// 앵커 복원, 재탐색까지 전부 프로덕션 코드가 돈다 — 여기서 따로 그리는 화면이 없으므로
  /// 이 버튼으로 본 연출이 곧 실기기에서 에스컬레이터를 탔을 때의 연출이다.
  ///
  /// 도착 노드는 경로가 지목한 노드([IndoorRouteSegment.transferToNodeId])를
  /// 그대로 쓴다. 실제 판정도 활성 경로가 있으면 같은 값을 우선한다
  /// ([findEscalatorArrivalNode]의 1단계).
  ///
  /// 판정기 자체([EscalatorTransitionDetector])는 건드리지 않는다 — 수직 전이
  /// 알고리즘은 재작성이 예정돼 있어, 거기 디버그 주입구를 뚫으면 재작성 때
  /// 같이 갈아엎어야 할 표면만 는다.
  void _debugForceFloorTransition() {
    final transfer = _debugForceableTransfer;
    final floor = _activeFloor;
    if (transfer == null || floor == null) return;
    final (:segment, :nextFloorLabel) = transfer;
    // 층 라벨 → 순위 비교는 층 전환 연출 정책과 같은 함수를 쓴다
    // (floor_switch_progress).
    final goingUp = floorSwitchRank(nextFloorLabel) > floorSwitchRank(floor);
    final transition = EscalatorTransition(
      // 도착 노드를 경로 지목으로 찾으므로 그룹 매칭까지 갈 일이 없지만,
      // 진단 JSON에 남는 값이라 강제 전환임을 알아볼 수 있게 적는다.
      group: 'DEBUG',
      direction: goingUp ? EscalatorDirection.up : EscalatorDirection.down,
      fromFloorLabel: floor,
      toFloorLabel: nextFloorLabel,
      deltaM: goingUp ? 5.0 : -5.0,
      durationMs: 0,
      stepsDuring: 0,
      boardingNodeId: segment.transferFromNodeId!,
      boardingNodeName: null,
      boardingDistanceM: 0,
      boardingEvidence: 'debug-forced',
      expectedArrivalNodeId: segment.transferToNodeId,
    );
    _enqueueFloorTransition(() => _beginEscalatorTransition(transition));
    // 시작과 확정 사이를 벌린다. 실제 에스컬레이터는 탑승부터 하차 감지까지
    // 10초를 넘게 타는데, 처음 1.2초로 뒀더니 "이동 중" 상태가 실제보다 훨씬
    // 짧아 보였다 — 이 버튼으로 본 리듬이 곧 실기기 리듬이어야 하므로 실제
    // 탑승 시간에 가깝게 둔다. (실기기에서는 이 대기가 없다 — 판정기가 실제
    // 하차를 기다리므로 몸이 시간을 정한다.)
    _enqueueFloorTransition(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    _enqueueFloorTransition(() => _completeEscalatorTransition(transition));
  }

  /// 이 층 [nodeId]에서 목적지까지 경로를 다시 뽑는다.
  ///
  /// 이미 그 노드에서 시작하는 경로가 그려져 있으면 아무것도 하지 않는다 —
  /// 같은 계산을 두 번 돌리면 진행률 기준점만 다시 흔들린다.
  ///
  /// 연출을 붙이지 않는다. 카메라는 [_swapIndoorFloorForRide]가 하차 지점과
  /// 내리는 방향에 맞춰 뒀고, 이 재계산은 그 자리를 실제 하차 노드 기준으로
  /// 다듬는 것뿐이다. 전환이 끝난 뒤에 또 움직이면 사용자는 방금 자리 잡은
  /// 화면이 한 번 더 흔들리는 것을 본다.
  Future<void> _recomputeRouteFrom({
    required String nodeId,
    required String floor,
  }) async {
    final destination = _preTransferDestination ?? _indoorRouteDestination;
    final destinationNodeId = destination?.nodeId;
    final buildingId = _building?.id;
    if (destination == null ||
        destinationNodeId == null ||
        buildingId == null) {
      return;
    }
    if (_routeStartsAt(nodeId, floor)) return;
    setState(() => _indoorRouteDestination = destination);
    if (destination.floor == floor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: buildingId,
        floor: floor,
        endNodeId: destinationNodeId,
        playOverview: false,
        // 층 전환 후 재계산 — 같은 길안내의 연속이다.
        beginNewRecordingSession: false,
        startNodeId: nodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: buildingId,
        startFloor: floor,
        endFloor: destination.floor,
        endNodeId: destinationNodeId,
        playOverview: false,
        beginNewRecordingSession: false,
        startNodeId: nodeId,
      );
    }
  }

  /// 지금 [floor]에 그려진 경로가 [nodeId]에서 시작하는가.
  bool _routeStartsAt(String nodeId, String floor) {
    final multi = _indoorMultiFloorRoute;
    final route = multi == null
        ? (_activeFloor == floor ? _indoorRouteSegment : null)
        : multi.segmentForFloor(floor)?.route;
    return route != null && route.nodeIds.firstOrNull == nodeId;
  }

  /// 지금 화면이 그려야 하는 층 전환 배너 상태.
  FloorTransitionUiState? get _floorTransitionUiState => floorTransitionUiState(
    arrival: _escalatorArrival,
    ride: _escalatorRide,
    stage: _escalatorStage,
  );

  /// 배너·스크림 상태가 바뀌면 셸에 알린다. 같은 값이면 알리지 않는다.
  ///
  /// 값 비교로 막지 않으면 매 스냅샷마다 부모 setState가 돌아, 지도 전체가
  /// 초당 수 회 다시 그려진다.
  void _reportFloorTransitionUi() {
    final banner = _floorTransitionUiState;
    final scrim = _floorSwapVeil;
    if (banner == _reportedFloorTransition &&
        scrim == _reportedFloorScrimOpacity) {
      return;
    }
    _reportedFloorTransition = banner;
    _reportedFloorScrimOpacity = scrim;
    final notify = widget.onFloorTransitionChanged;
    if (notify == null) return;
    // build 중에는 부모 setState를 호출할 수 없다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify(banner, scrim);
    });
  }

  Future<void> _refreshIndoorDestinationPin() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    try {
      await controller.removeLayer(kOutdoorIndoorDestLayerId);
      await addIndoorDestinationPinLayer(controller);
      await _syncIndoorDestinationLayer();
    } catch (error, stackTrace) {
      // hot reload 편의 기능이라 실패해도 앱을 죽이지 않는다.
      debugPrint('destination pin refresh failed: $error\n$stackTrace');
    }
  }

  /// 건물(입구·footprint·층 목록)을 로드한다.
  ///
  /// **실패를 조용히 삼키면 안 된다.** 이 화면의 실내 기능은 전부 [_building]과
  /// [_buildingFootprint]에 걸려 있다 — 층 선택기, 위치 지정, 확대/탭 실내 진입
  /// 판정, 실내 도면 오버레이 등록이 모두 그렇다. 요청이 던지면 아래 setState가
  /// 아예 실행되지 않아 그 전부가 **아무 표시 없이** 사라진다. 예전에는 이
  /// 호출이 await도 catch도 없이 initState에서 발사돼 예외가 unhandled async
  /// error로만 남았고, 화면에는 "야외 지도는 멀쩡한데 실내 기능만 없는" 상태가
  /// 원인을 짚을 단서 하나 없이 남았다.
  ///
  /// 야외 지도 자체는 건물 없이도 쓸 수 있으므로, 실내 화면([IndoorMapBody])
  /// 처럼 전체 화면 에러로 덮지 않는다. 지도는 그대로 두고 재시도가 달린 배지만
  /// 띄워, 사용자가 왜 실내 기능이 없는지 알고 그 자리에서 복구할 수 있게 한다.
  Future<void> _loadBuildingEntrance() async {
    final Building? building;
    try {
      building = await buildingRepository.getBuilding(demoBuildingId);
    } catch (_) {
      if (!mounted) return;
      if (!_buildingLoadFailed) setState(() => _buildingLoadFailed = true);
      _scheduleBuildingRetry();
      return;
    }
    if (!mounted) return;
    // 성공했으면 예약된 재시도는 필요 없다. 사다리도 되돌려, 나중에 다시
    // 끊겼을 때 짧은 간격부터 새로 시작하게 한다.
    _buildingRetryTimer?.cancel();
    _buildingRetryTimer = null;
    _buildingRetryAttempt = 0;
    setState(() {
      _buildingLoadFailed = false;
      _building = building;
      _entrance = building?.entrance;
      _buildingFootprint = building?.footprintWgs84;
      _activeFloor = building?.initialFloor;
    });
    _notifyActiveFloor();
    _syncDestinationLayer();
    _syncBuildingLayer();
    // 스타일이 이미 로드된 뒤 건물이 늦게 도착한 케이스(테스트/느린 네트워크)를
    // 위해 실내 MVT 소스도 여기서 한 번 더 등록 시도.
    _ensureIndoorTilesRegistered();
    final floor = _activeFloor;
    if (building != null && floor != null) {
      // 지상 출입구는 층 그래프와 **독립적으로** 필요하다. 사용자가 층 chip으로
      // 다른 층을 훑는 순간 [_floorPlan]은 그 층 것으로 갈리는데, 문 목록은
      // 그동안에도 남아 있어야 야외 안내가 끊기지 않는다.
      unawaited(_loadGroundEntrances(building.id, floor));
      await _loadFloorGraph(building.id, floor);
    }
  }

  /// 지상 출입구 목록을 받아 [_groundEntrances]를 채운다.
  ///
  /// 실패는 조용히 넘긴다. 문을 못 받으면 문을 경유하지 않는 예전 안내(목적지
  /// 좌표로 바로 걷기 경로)로 폴백하는 것이 맞고, 여기서 에러를 띄우면 야외
  /// 지도를 쓰던 사용자에게 아무 조치도 못 할 경고만 남는다.
  ///
  /// [floor]는 건물의 기본 층(=출입구가 있는 지상층)이다. 백엔드가
  /// `default_floor`로 "출입구가 있는 지상 1층"을 내려주므로 그 값을 그대로 쓴다.
  Future<void> _loadGroundEntrances(String buildingId, String floor) async {
    final Map<String, dynamic>? geojson;
    try {
      geojson = await buildingRepository.getFloorGeoJson(buildingId, floor);
    } catch (_) {
      return;
    }
    if (!mounted || geojson == null) return;
    final entrances = groundEntrancesFrom(FloorPlan.fromJson(geojson));
    if (entrances.isEmpty) return;
    setState(() {
      _groundEntrances = entrances;
      _groundEntranceFloor = floor;
    });
    _syncSelectedEntrance();
  }

  /// 현재 위치에서 가장 가까운 문을 다시 고르고, 바뀌었으면 상태에 반영한다.
  ///
  /// 여기서 [_entrance]도 함께 갱신한다. 그 값은 이 화면의 **실내 진입/이탈
  /// 판정 전체**가 보는 기준점이다. 백엔드 건물 응답에는 출입구 좌표가 없어
  /// 지금까지 이 값이 계속 null이었고, 그래서 GPS 자동 진입은 조건을 아무리
  /// 만족해도 발화하지 못했다. 문 좌표가 생긴 지금이 그 기준점을 채울 자리다.
  ///
  /// 위치를 아직 못 잡았으면 건물 중심을 대신 쓴다 — 문 하나라도 골라 둬야
  /// 진입 판정이 살아 있고, 실제 위치가 들어오면 곧바로 다시 고른다.
  void _syncSelectedEntrance() {
    if (_groundEntrances.isEmpty) return;
    final position = _position;
    final reference = position != null
        ? ll.LatLng(position.latitude, position.longitude)
        : _buildingCenter(_buildingFootprint ?? const []);
    if (reference == null) return;

    final picked = nearestEntrance(
      _groundEntrances,
      reference,
      current: _selectedEntrance,
    );
    if (picked == null || picked.id == _selectedEntrance?.id) return;
    setState(() {
      _selectedEntrance = picked;
      _entrance = picked.point;
    });
  }

  /// [fromPositionStream]이 true면 **마지막으로 요청한 지점에서 충분히 움직였을
  /// 때만** TMAP을 다시 부른다([shouldRecomputeRouteAfterMove]). 위치 스트림이
  /// 1초에 한 번 오게 된 뒤로, 걸으면서 이 함수를 부를 때마다 요청을 내보내면
  /// 초당 한 번씩 외부 API를 두드린다.
  ///
  /// **사용자가 목적지를 고른 호출(false)은 절대 거르지 않는다.** 제자리에 서서
  /// 도착지를 눌렀을 때 "아무 일도 일어나지 않는" 화면이 되기 때문이다. 문 재선택
  /// ([_retargetJourneyEntrance])은 네트워크를 타지 않으므로 거르는 쪽에 두지
  /// 않는다 — 좌표가 올 때마다 그대로 돈다.
  Future<void> _updateRoute(
    Position position, {
    bool fromPositionStream = false,
  }) async {
    // 문 경유 안내 중이면 이번 위치로 다시 고른 문이 목적지다. 걸어가는 동안
    // 더 가까운 문이 생기면([_syncSelectedEntrance]가 이미 갱신했다) 야외 구간의
    // 도착점과 실내 구간의 시작점을 함께 갈아 끼운다 — 한쪽만 바꾸면 도보 경로는
    // 새 문으로 가는데 실내 경로는 옛 문에서 시작하는 화면이 된다.
    if (_pendingIndoorDestination != null) _retargetJourneyEntrance();

    // 길찾기가 그린 **계획 경로**는 출발점이 못박혀 있다. GPS가 갱신될 때마다
    // 다시 계산하면 사용자가 비교하려고 보고 있는 선이 걸음마다 흔들린다.
    if (_fixedRouteOrigin != null) return;

    // 야외 걷기 경로는 **사용자가 목적지를 고른 경우에만** 그린다.
    //
    // 예전에는 목적지가 없으면 [_entrance]로 폴백했지만, 백엔드가 건물 출입구
    // 좌표를 내려주지 않아 그 값이 늘 null이었고 폴백은 한 번도 실행되지 않았다.
    // 이제 [_syncSelectedEntrance]가 실제 문 좌표로 그 값을 채우므로, 폴백을
    // 그대로 두면 앱을 켜고 GPS가 잡히는 것만으로 아무도 요청하지 않은
    // "가장 가까운 문까지" 경로가 그려지고, 위치가 갱신될 때마다 TMAP 요청이
    // 나간다. [_entrance]는 진입/이탈 판정의 기준점이지 목적지가 아니다.
    final target = _userDestination;
    if (target == null) return;

    final origin = ll.LatLng(position.latitude, position.longitude);
    if (fromPositionStream &&
        !shouldRecomputeRouteAfterMove(
          origin: origin,
          lastRequestedOrigin: _lastRouteRequestOrigin,
        )) {
      return;
    }
    _lastRouteRequestOrigin = origin;

    final route = await directionsRepository.getWalkingRoute(
      origin: origin,
      destination: target,
    );
    if (!mounted) return;
    // 도착점이 문이면 TMAP 선이 문 앞에서 끊기거나, 아예 문에 닿지 못한 채
    // 엉뚱한 곳으로 돌아간다([extendRouteToDestination]).
    _applyRoute(extendRouteToDestination(route, target));
  }

  /// 새 목적지를 선택하거나 안내를 끝낼 때만 완료 이력을 비운다.
  ///
  /// 재탐색으로 [_route] 또는 [_indoorRouteSegment]를 교체하는 동안에는 이
  /// 함수를 부르면 안 된다. 그 순간은 같은 여정의 다음 경로를 붙이는 시점이라
  /// 기존 회색선이 살아 있어야 한다.
  void _clearCompletedRouteHistory() {
    _completedRouteHistory.clear();
    _routeGeneration = 0;
    _outdoorDisplayProgress = null;
  }

  /// 확정된 새 실내 경로를 현재 세대에 연결한다.
  ///
  /// 네트워크/그래프 계산이 성공한 뒤에만 호출한다. 이전 실내 경로의 현재
  /// displayProgress를 그때 회색 이력으로 넘기므로, 재탐색 대기 중에는 기존
  /// 파란·회색 분할이 그대로 고정된다.
  void _acceptIndoorRouteGeneration({
    ({String scopeId, List<ll.LatLng> points})? previousCompletion,
  }) {
    final previous = _indoorRouteSegment;
    final completion = previousCompletion ?? _currentIndoorCompletionSnapshot();
    final replacing =
        previous != null ||
        _indoorMultiFloorRoute != null ||
        completion != null;
    if (replacing && completion != null) {
      _completedRouteHistory.append(
        scopeId: completion.scopeId,
        points: completion.points,
      );
    }
    _routeGeneration++;
  }

  /// 야외 GPS 진행률을 갱신한다.
  ///
  /// 정확도가 나쁘거나 경로에서 멀리 떨어진 GPS, 이전 진행점 주변에서
  /// 재획득한 후보는 채택하지 않는다. 따라서 그 틱에서는 회색선과 파란선의
  /// 분할점이 움직이지 않는다. 다음에 정상 좌표가 들어오면 직전 표시에서
  /// 이어진다.
  void _updateOutdoorDisplayProgress(Position position) {
    final route = _route;
    if (_indoorEntered ||
        _routeIsDriving ||
        _fixedRouteOrigin != null ||
        route == null ||
        route.points.length < 2) {
      return;
    }
    if (!position.accuracy.isFinite ||
        position.accuracy > _lowAccuracyThresholdMeters) {
      return;
    }

    final candidate = computeGeoRouteProgress(
      routePoints: route.points,
      position: ll.LatLng(position.latitude, position.longitude),
      previousTraveledM: _outdoorDisplayProgress?.traveledM,
    );
    if (candidate == null ||
        candidate.offsetM > _outdoorRouteMaxProjectionOffsetM ||
        candidate.reacquired) {
      return;
    }

    final previous = _outdoorDisplayProgress;
    if (previous != null &&
        candidate.traveledM <
            previous.traveledM - _outdoorRouteRegressionToleranceM) {
      return;
    }
    _outdoorDisplayProgress = candidate;
  }

  List<ll.LatLng> _localRoutePointsToWgs84(
    List<LocalPoint> points,
    FloorGraph graph,
  ) {
    final transform = fitFloorGeoTransform(graph.nodes);
    return [
      for (final point in points)
        (() {
          final wgs84 = transform.apply(point.x, point.y);
          return ll.LatLng(wgs84.$1, wgs84.$2);
        })(),
    ];
  }

  void _captureOutdoorCompletedRouteBeforeReplace() {
    final completed = _outdoorRouteVisuals(_route).completed;
    if (completed.length >= 2) {
      _completedRouteHistory.append(
        scopeId: CompletedRouteHistory.outdoorScope,
        points: completed,
      );
    }
  }

  /// 경로가 새로 생기면(이전엔 없다가 이번에 생김) 상위에 ETA 바가 보인다고
  /// 알리고, 경로 전체가 화면에 들어오도록 카메라를 자동으로 줌아웃한다.
  /// 이미 경로가 있는 상태에서 위치가 갱신돼 경로가 매번 다시 계산될 때는
  /// (걷는 동안 계속 일어남) 다시 맞추지 않는다 — 사용자가 지도를 보는 중에
  /// 카메라가 계속 튀면 방해가 된다. 새 목적지를 고르면(showRouteTo) 그때는
  /// 다시 한번 전체 경로가 보이도록 맞춘다.
  void _applyRoute(DirectionsRoute? route) {
    final wasVisible = _route != null;
    final replacingOutdoorWalkingRoute =
        route != null &&
        _route != null &&
        !_routeIsDriving &&
        _fixedRouteOrigin == null &&
        !_indoorEntered;
    if (replacingOutdoorWalkingRoute) {
      // TMAP 응답이 성공해 새 파란 경로를 확정하는 순간에만 이전 경로의
      // 완료 구간을 이력으로 승격한다. 요청 중에는 기존 경로를 건드리지 않는다.
      _captureOutdoorCompletedRouteBeforeReplace();
    }
    if (route != null) {
      _routeGeneration++;
      _outdoorDisplayProgress = null;
    }
    setState(() => _route = route);
    if (route != null && _position != null) {
      _updateOutdoorDisplayProgress(_position!);
    }
    _syncRouteLayer();
    _notifyRouteStateIfChanged();
    final isVisible = route != null;
    if (!wasVisible && isVisible) {
      // **자동으로 생긴 경로는 카메라를 가져가지 않는다.**
      //
      // 야외에서 GPS가 잡히면 사용자가 부탁한 적 없어도 건물 입구까지의 걷기
      // 경로를 계산한다([_updateRoute]의 `_userDestination ?? _entrance`).
      // 그 경로가 처음 생기는 순간 여기서 전체를 화면에 맞추면, 사용자가 지금
      // 무엇을 보고 있든 **내 위치부터 건물까지**가 다 들어오는 배율로 튕겨
      // 나간다. 멀리 있을수록 심해서, 검색으로 건물을 찾아 막 확대한 화면이
      // 도시 전체 축척으로 바뀌고 정작 건물은 점이 된다 — "건물 위치가 안
      // 나온다"의 정체가 이것이다.
      //
      // 사용자가 직접 고른 목적지([_userDestination])면 그대로 맞춘다. 그건
      // "이 경로를 보여 달라"는 요청이라 화면을 가져가는 것이 맞다.
      if (_userDestination != null) _fitCameraToRoute(route);
    }
  }

  void _fitCameraToRoute(DirectionsRoute route) {
    // 출발점과 도착점이 사실상 같은 좌표면(예: 건물 입구 바로 앞) 경계 상자
    // 폭이 0에 가까워져 줌 계산이 발산한다 — 이 경우엔 화면에 맞출 "경로"랄
    // 게 없으니 자동 줌은 건너뛴다.
    if (route.points.length < 2 || route.distanceMeters < 5) return;
    _fitCameraToPoints(route.points);
  }

  /// 길찾기가 **미리 계산해 온** 도로 경로(자동차·도보)를 그대로 그린다.
  ///
  /// [showRouteTo]와 나눈 이유는 경로를 누가 계산하느냐가 다르기 때문이다.
  /// showRouteTo는 목적지만 받아 이 화면이 직접 TMAP을 부르지만, 길찾기는 요약
  /// 카드에 적을 거리·시간이 필요해 이미 응답을 손에 쥐고 있다. 여기서 다시
  /// 부르면 같은 구간을 두 번 조회하고, 두 응답이 미묘하게 달라지면 카드와
  /// 지도가 다른 경로를 말하게 된다.
  ///
  /// 출발점을 [_fixedRouteOrigin]으로 박는 것이 중요하다. 이건 걷는 동안 따라가는
  /// 안내가 아니라 **한 번 그려 놓고 비교하는 계획 화면**이라, GPS가 갱신될
  /// 때마다 경로가 다시 계산되면 사용자가 보던 선이 흔들린다.
  ///
  /// [offerStartGuidance]가 참이면 하단 카드에 "안내 시작"을 붙인다.
  Future<void> showPlannedRoadRoute(
    DirectionsRoute route, {
    required ll.LatLng origin,
    required ll.LatLng destination,
    required String label,
    bool offerStartGuidance = false,
    bool driving = false,
  }) async {
    _clearCompletedRouteHistory();
    _clearPendingIndoorRoute();
    clearTransitRoute();
    // 경로를 **다시 그리는** 중이다(수단 변경·끝점 변경). 아직 "안내 시작" 전
    // 이므로 카메라는 경로 전체를 보여 줘야 한다.
    _stopFollowingUser();
    setState(() {
      _offerStartGuidance = offerStartGuidance;
      _routeIsDriving = driving;
      _fixedRouteOrigin = origin;
      _userDestination = destination;
      _userDestinationLabel = label;
      // 먼저 비워야 [_applyRoute]가 "새로 생김"으로 보고 카메라를 경로 전체에
      // 맞춘다. 안 비우면 수단을 바꿔도 카메라가 옛 경로 자리에 머문다.
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    _applyRoute(route);
  }

  /// [point]가 우리 실내 도면이 있는 건물 **안**이면, 그 건물의 지상 출입구
  /// 좌표를 돌려준다. 밖이거나 건물을 아직 못 받았으면 null.
  ///
  /// TMAP POI 중에는 건물 **안** 매장이 섞여 있다(예: 백화점 입점 브랜드).
  /// 그 좌표를 도로 안내의 끝점으로 그대로 쓰면 도착점이 건물 내부라, TMAP이
  /// 가장 가까운 도로로 스냅하면서 실제로 들어갈 수 있는 문과 다른 면에
  /// 사용자를 내려놓는다.
  ///
  /// 여기는 **엄격한** 판정을 쓴다. 묻는 것이 "이 좌표를 안내의 끝점으로 써도
  /// 되는가"이고, 그게 못 쓰는 좌표가 되는 건 정말로 건물 안일 때뿐이다.
  /// [isAtIndoorBuilding]처럼 여유를 주면 건물 옆 노점까지 건물 문으로 안내한다.
  ll.LatLng? entranceIfInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    final inside = footprint != null && isPointInPolygon(point, footprint);
    if (!inside) return null;
    final building = _building;
    return building == null ? null : entrancePointFor(building.id);
  }

  /// 문 경유 안내의 ETA 카드 라벨. 목적지와 경유하는 문을 함께 적어, 왜 경로가
  /// 목적지가 아니라 건물 모서리로 향하는지 사용자가 화면에서 바로 알 수 있게 한다.
  String _journeyEtaLabel(
    PoiSearchResult destination,
    BuildingEntrance entrance,
  ) {
    final label = entranceDirectionLabel(
      entrance,
      _buildingCenter(_buildingFootprint ?? const []),
    );
    return '${destination.name}까지 · $label 경유';
  }

  /// 안내 중인 문이 바뀌었으면 야외 도착점과 실내 구간을 새 문 기준으로 다시 맞춘다.
  ///
  /// 실내 구간은 서버에 다시 묻지 않고 들고 있던 그래프로 그 자리에서 푼다 —
  /// 문 선택은 GPS를 따라 여러 번 바뀔 수 있고, 그때마다 네트워크를 타면 신호가
  /// 나쁜 건물 앞에서 정확히 실패한다.
  void _retargetJourneyEntrance() {
    final entrance = _selectedEntrance;
    final destination = _pendingIndoorDestination;
    if (entrance == null || destination == null) return;
    // 이미 이 문을 향하고 있으면 할 일이 없다.
    if (entrance.id == _journeyEntrance?.id) return;

    final graph = _journeyBuildingGraph;
    final endNodeId = destination.nodeId;
    final leg = (graph == null || endNodeId == null)
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);
    setState(() {
      _journeyEntrance = entrance;
      _userDestination = entrance.point;
      _userDestinationLabel = _journeyEtaLabel(destination, entrance);
      // 새 문에서 경로가 안 풀리면 옛 구간을 남기지 않는다. 남기면 사용자는
      // 남쪽 문으로 걸어가는데 실내 안내만 서쪽 문에서 시작하는 상태가 된다.
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
    });
  }

  /// 건물에 들어간 순간, 미리 풀어 둔 실내 구간을 실제 안내로 승격한다.
  ///
  /// **야외 구간은 지우지 않고 들고 있는다.** 예전에는 지웠는데, 그러면 건물에
  /// 들어갔다가 다시 밖으로 나온 사용자에게 아무 경로도 안 남는다 — 안내가
  /// 통째로 사라진 것처럼 보이고, 처음부터 다시 검색해야 한다.
  Future<void> _activatePendingIndoorRoute() async {
    final route = _pendingIndoorRoute;
    final destination = _pendingIndoorDestination;
    if (route == null || destination == null) return;

    final startFloor = route.segments.first.floorName;
    if (_activeFloor != startFloor) {
      await _switchOverlayFloor(startFloor);
      if (!mounted) return;
    }
    _routeGeneration++;
    setState(() {
      // _route·_userDestination(야외 구간)은 그대로 둔다. 밖으로 나오면 다시
      // 그려야 하는 값이다.
      _pendingIndoorRoute = null;
      _pendingIndoorDestination = null;
      _journeyEntrance = null;
      _indoorRouteDestination = destination;
      // 새 안내가 시작되면 지난 도착 카드는 자리를 비운다.
      _arrivedDestination = null;
      _indoorMultiFloorRoute = route;
      // 층별 구간은 공용 세션이 소유한다 — 진행률이 그 값에 투영되므로 여기서
      // 따로 들면 남은거리가 갈라진다([_indoorRouteSegment]). 같은 층 경로를
      // 얹는 자리와 같은 순서를 쓴다.
      _guidance
        ..setRouteSegment(route.segmentForFloor(startFloor)?.route)
        ..seedProgress(null)
        ..setRoute(route);
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    final segment = route.segmentForFloor(startFloor);
    if (segment != null && segment.route.points.length >= 2) {
      _fitCameraToIndoorRoute(segment.route);
    }
    _beginRouteRecordingSession();
  }

  /// 건물을 나간 순간, 예약해 둔 야외 구간을 실제 안내로 올린다.
  ///
  /// 출발지를 못박지 않는 이유는 **현재 위치에서 출발해야 하기 때문**이다.
  /// 출구 좌표를 출발지로 주면 [showRouteTo]가 그 값을 [_fixedRouteOrigin]에
  /// 넣어 경로를 고정하고, 그러면 걸어가는 동안 경로가 사용자를 따라오지 않는다.
  Future<void> _activatePendingOutdoorRoute() async {
    final destination = _pendingOutdoorDestination;
    final label = _pendingOutdoorLabel;
    if (destination == null || label == null) return;
    _clearPendingOutdoorRoute();
    // 완료 이력은 들고 간다. 이 호출은 같은 여정의 다음 구간이라, 거울상인
    // [_activatePendingIndoorRoute]가 야외 회색선을 남겨 두는 것과 대칭이다.
    await showRouteTo(
      destination,
      label: label,
      keepCompletedHistory: true,
    );
  }

  /// 실내→야외 예약을 접는다. 그 안내가 더는 유효하지 않은 모든 자리에서 부른다.
  void _clearPendingOutdoorRoute() {
    if (_pendingOutdoorDestination == null && _pendingOutdoorLabel == null) {
      return;
    }
    setState(() {
      _pendingOutdoorDestination = null;
      _pendingOutdoorLabel = null;
    });
  }

  /// 문 경유 안내를 접는다. 야외 구간이 사라지는 모든 경로에서 함께 불린다 —
  /// 남겨 두면 사용자가 안내를 끈 뒤에 건물에 들어갔을 때 지웠던 실내 경로가
  /// 혼자 되살아난다.
  void _clearPendingIndoorRoute() {
    if (_pendingIndoorRoute == null && _pendingIndoorDestination == null) {
      return;
    }
    setState(() {
      _pendingIndoorRoute = null;
      _pendingIndoorDestination = null;
      _journeyEntrance = null;
    });
    // 문 경유가 끝나면 목적지 핀의 조건도 바뀐다([_syncDestinationLayer]).
    unawaited(_syncDestinationLayer());
  }

  /// "이 건물까지" 안내할 때 쓸 도착 좌표.
  ///
  /// 지상 출입구를 **먼저** 고른다. 건물 중심을 도착점으로 주면 TMAP 보행자
  /// 경로가 건물 안쪽을 향하다가 가장 가까운 도로로 스냅해, 실제로 들어갈 수
  /// 있는 문과 다른 면에 사용자를 내려놓는다. 문은 출발 지점에서 가까운 것을
  /// 고른다 — [showOutdoorToIndoorRouteTo]가 매장 안내에서 쓰는 규칙과 같다.
  ///
  /// 문 데이터가 없는 건물이면 [_entrance](백엔드 출입구 좌표)로, 그것도 없으면
  /// 외곽선 중심으로 떨어진다. 셋 다 없으면 null이고, 호출부는 그때 도착·출발
  /// 버튼 자체를 감춘다.
  ///
  /// [buildingId]를 받는 이유는 이 화면이 **한 채**의 건물만 로드하기
  /// 때문이다(demoBuildingId). 인자 없이 좌표만 돌려주면, 호출부가 다른 건물을
  /// 물었을 때도 이 건물의 문을 돌려줘 엉뚱한 좌표가 그 건물의 도착지로 박힌다.
  ll.LatLng? entrancePointFor(String buildingId) {
    if (_building?.id != buildingId) return null;
    final position = _position;
    final reference = position == null
        ? null
        : ll.LatLng(position.latitude, position.longitude);
    if (reference != null) {
      final door = nearestEntrance(_groundEntrances, reference);
      if (door != null) return door.point;
    }
    final known = _entrance;
    if (known != null) return known;
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.isEmpty) return null;
    return _buildingCenter(footprint);
  }

  void _clearUserDestination() {
    _clearCompletedRouteHistory();
    clearTransitRoute();
    // 안내가 여기서 끝난다. 따라가기를 남기면 카메라가 계속 사용자를 쫓아다녀
    // 지도를 훑어볼 수 없다.
    _stopFollowingUser();
    _clearPendingIndoorRoute();
    setState(() {
      _userDestination = null;
      _userDestinationLabel = null;
      _route = null;
      _fixedRouteOrigin = null;
      // 그릴 경로가 없으면 시작할 안내도 없다. 안 지우면 다음에 뜨는 도보 카드에
      // 자동차용 "안내 시작"이 얹힌다.
      _offerStartGuidance = false;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    _notifyRouteStateIfChanged();
  }

  /// 같은 층 안에서 계산한 실내 경로를 지도에 얹는다. 활성 층이 목적지 층과
  /// 다르면 먼저 그 층으로 오버레이를 전환해 필요한 그래프를 다시 로드한다.
  /// [startNodeId]가 주어지면(길찾기 시트에서 매장을 출발지로 고른 경우) 그
  /// 노드에서 바로 출발하고, null이면 PDR 앵커 주변 최근접 통로 노드를 찾는다.
  ///
  /// [playOverview]는 경로를 그린 뒤 개요 연출([_fitCameraToRouteSegment])을 할지다.
  /// **기본값을 두지 않는다** — 안내 시작이냐 재탐색이냐에 따라 답이 정반대라,
  /// 빠뜨리면 조용히 틀린 쪽으로 굴러간다.
  ///
  /// [beginNewRecordingSession]도 같은 이유로 기본값이 없다. 사용자가 목적지를
  /// 새로 고른 경우에만 true다. 재탐색·층 전환 후 재계산은 **같은 길안내의
  /// 연속**이라 false — 여기서 세션을 갈면 층 전환마다 진단 로그가 지워져,
  /// 정작 분석하려는 구간(에스컬레이터 탑승)이 파일에 안 남는다(2026-08-13
  /// 실측에서 주행 로그가 마지막 재탐색 이후 10초만 남았다).
  Future<void> _computeAndShowSingleFloorIndoorRoute({
    required String buildingId,
    required String floor,
    required String endNodeId,
    required bool playOverview,
    required bool beginNewRecordingSession,
    String? startNodeId,
  }) async {
    final completionAtRequest = _currentIndoorCompletionSnapshot();
    final hadExistingIndoorRoute =
        _indoorRouteSegment != null || _indoorMultiFloorRoute != null;
    if (floor != _activeFloor) {
      // 목적지 층으로 화면을 옮기는 사람 조작 흐름이다. 새 도면 페이드인은
      // 이어지는 경로 개요 연출(playOverview)과 겹쳐 하나의 전환으로 읽힌다.
      await _switchOverlayFloorCrossfaded(floor);
      if (!mounted) return;
    }
    final graph = _floorGraph;
    if (graph == null) {
      _showSnack('경로 계산에 필요한 층 정보를 불러오지 못했습니다.');
      return;
    }
    if (startNodeId == null) {
      final anchor = _pdrTrailState.anchor;
      if (anchor == null || anchor.floorId != floor) {
        _showSnack('경로 계산에 필요한 층 정보를 불러오지 못했습니다.');
        return;
      }
      startNodeId = _nearestNodeId(
        graph.nodes,
        anchor.anchorLocalM.eastM,
        anchor.anchorLocalM.northM,
        excludingNodeId: endNodeId,
      );
    }
    if (startNodeId == null) {
      _showSnack('시작 위치 주변에서 통로 노드를 찾지 못했습니다.');
      return;
    }
    final route = await buildingRepository.getShortestRoute(
      buildingId,
      floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    if (route == null) {
      _showSnack('경로를 찾지 못했습니다. 다른 매장을 골라보거나 출발지를 다시 지정해주세요.');
      // 재탐색 실패는 현재 안내의 종료가 아니다. 기존 파란/회색 분할을
      // 유지해 센서·네트워크가 잠깐 불안정해도 화면이 비지 않게 한다.
      if (!hadExistingIndoorRoute) _clearIndoorRoute();
      return;
    }
    _acceptIndoorRouteGeneration(
      previousCompletion:
          _currentIndoorCompletionSnapshot() ?? completionAtRequest,
    );
    setState(() {
      _guidance
        ..setRouteSegment(route)
        ..seedProgress(null)
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    if (playOverview) unawaited(_fitCameraToRouteSegment(route));
    // 진단 세션의 경계는 **길안내 한 건**이다. 목적지를 새로 고른 경우에만
    // 이전 세션을 버리고 새로 연다 — 재탐색·층 전환 후 재계산에서 세션을 갈면
    // 층을 옮길 때마다 로그가 지워진다.
    if (beginNewRecordingSession) {
      if (_pdrDebugRecorder != null) {
        _endRouteRecordingSession(announceExport: false);
      }
      _beginRouteRecordingSession();
    }
  }

  /// 층이 다른 매장까지의 층 간 경로를 계산해 층별 세그먼트로 나누고, 현재
  /// 화면(_activeFloor)에 해당하는 세그먼트를 지도에 얹는다. 층 chip으로
  /// 다른 층을 훑으면 [_switchOverlayFloor]가 그 층 세그먼트로 갈아탄다.
  /// 시작 층부터 훑도록 활성 층을 자동으로 시작 층으로 전환한다.
  /// [startNodeId]가 주어지면(길찾기 시트에서 매장을 출발지로 고른 경우) 그
  /// 노드에서 바로 출발하고, null이면 PDR 앵커 기준으로 시작 노드를 고른다.
  /// [playOverview]·[beginNewRecordingSession]의 뜻은
  /// [_computeAndShowSingleFloorIndoorRoute]와 같다.
  Future<void> _computeAndShowMultiFloorIndoorRoute({
    required String buildingId,
    required String startFloor,
    required String endFloor,
    required String endNodeId,
    required bool playOverview,
    required bool beginNewRecordingSession,
    String? startNodeId,
  }) async {
    final completionAtRequest = _currentIndoorCompletionSnapshot();
    final hadExistingIndoorRoute =
        _indoorRouteSegment != null || _indoorMultiFloorRoute != null;
    final buildingGraph = await buildingRepository.getBuildingGraph(buildingId);
    if (!mounted) return;
    if (buildingGraph == null || buildingGraph.nodes.isEmpty) {
      _showSnack('층 간 경로 계산에 필요한 그래프를 불러오지 못했습니다.');
      _clearIndoorRoute();
      return;
    }
    startNodeId ??= _pickStartNodeIdInBuildingGraph(
      graph: buildingGraph,
      startFloorName: startFloor,
      excludingNodeId: endNodeId,
    );
    if (startNodeId == null) {
      _showSnack('시작 층 주변에서 통로 노드를 찾지 못했습니다.');
      _clearIndoorRoute();
      return;
    }
    final route = computeMultiFloorRoute(buildingGraph, startNodeId, endNodeId);
    if (!mounted) return;
    if (route == null || route.isEmpty) {
      _showSnack('층 간 경로를 찾지 못했습니다. 엘리베이터/에스컬레이터 연결을 확인해주세요.');
      if (!hadExistingIndoorRoute) _clearIndoorRoute();
      return;
    }
    // 새 경로를 확정하기 전에 이전 층의 displayProgress를 이력으로 저장한다.
    // 층을 먼저 바꾸면 이전 그래프가 사라져 WGS84 변환을 할 수 없다.
    _acceptIndoorRouteGeneration(
      previousCompletion:
          _currentIndoorCompletionSnapshot() ?? completionAtRequest,
    );
    // 시작 층으로 화면을 전환한 뒤, 그 층 세그먼트를 지도에 얹는다. 사용자가
    // 훑던 층과 다르더라도 시작 층부터 보는 게 "지금 어디서 어느 방향으로
    // 첫 걸음"을 파악하는 데 자연스럽다(실내 화면과 동일 규칙).
    if (_activeFloor != startFloor) {
      await _switchOverlayFloorCrossfaded(startFloor);
      if (!mounted) return;
    }
    final segment = route.segmentForFloor(startFloor);
    setState(() {
      _indoorMultiFloorRoute = route;
      _guidance
        ..setRouteSegment(segment?.route)
        ..seedProgress(null)
        ..setRoute(route);
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    if (playOverview && segment != null) {
      unawaited(_fitCameraToRouteSegment(segment.route));
    }
    // 세션 경계 규칙은 [_computeAndShowSingleFloorIndoorRoute]와 같다.
    if (beginNewRecordingSession) {
      if (_pdrDebugRecorder != null) {
        _endRouteRecordingSession(announceExport: false);
      }
      _beginRouteRecordingSession();
    }
  }

  void _fitCameraToIndoorRoute(IndoorRoute route) {
    if (route.points.length < 2 || route.distanceMeters < 1) return;
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    var minLng = double.infinity;
    var maxLng = double.negativeInfinity;
    for (final p in route.points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 40,
        top: 110,
        right: 40,
        bottom: 180,
      ),
    );
  }

  /// ETA 카드 라벨. 다층 경로는 층별 이동수단(엘리베이터/에스컬레이터)까지 요약
  /// 노출해 "이 층에 안 그려진 이유"를 사용자가 이해할 수 있게 한다(실내 화면
  /// 규칙과 동일).
  String _indoorEtaLabel(PoiSearchResult destination) {
    final multi = _indoorMultiFloorRoute;
    if (multi == null) return '${destination.name}까지';
    final buffer = StringBuffer('${destination.name}까지');
    for (var index = 0; index < multi.segments.length; index++) {
      final segment = multi.segments[index];
      buffer.write(
        index == 0 ? ' · ${segment.floorName}' : ' → ${segment.floorName}',
      );
      final transferMode = segment.transferModeToNext;
      if (transferMode != null) {
        buffer.write(transferMode == 'elevator' ? ' (엘리베이터)' : ' (에스컬레이터)');
      }
    }
    return buffer.toString();
  }

  /// 실내 경로 표시를 초기화한다. ETA 카드 닫기 버튼과 사용자 destination 초기화
  /// 시 호출된다.
  void _clearIndoorRoute() {
    _clearCompletedRouteHistory();
    setState(() {
      _guidance
        ..setRouteSegment(null)
        ..clearProgress()
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
      _indoorRouteDestination = null;
      _guidanceTrailSession.clear();
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    // 한 번의 길안내가 여기서 끝난다.
    _endRouteRecordingSession();
  }

  /// 안내 배너를 탭했을 때 — 경로 전체를 단계 목록으로 펴서 시트로 보여준다.
  ///
  /// 다층 경로면 **모든 층의 세그먼트**를 순서대로 편다. 화면에 그려지는 것은
  /// 지금 층 세그먼트뿐이지만, 목록의 존재 이유가 "이 다음에 뭐가 오는지"라
  /// 아직 안 간 층의 단계까지 있어야 한다.
  void _showIndoorRouteSteps(PoiSearchResult destination) {
    final multi = _indoorMultiFloorRoute;
    final List<RouteStepLeg> legs;
    if (multi != null && multi.isNotEmpty) {
      legs = [
        for (var i = 0; i < multi.segments.length; i++)
          (
            wgs84Points: multi.segments[i].route.points,
            localPoints: multi.segments[i].route.pointsLocalM,
            floorLabel: multi.segments[i].floorName,
            transferModeToNext: multi.segments[i].transferModeToNext,
            nextFloorLabel: i + 1 < multi.segments.length
                ? multi.segments[i + 1].floorName
                : null,
          ),
      ];
    } else {
      final segment = _indoorRouteSegment;
      final floor = _activeFloor;
      if (segment == null || floor == null) return;
      legs = [
        (
          wgs84Points: segment.points,
          localPoints: segment.pointsLocalM,
          floorLabel: floor,
          transferModeToNext: null,
          nextFloorLabel: null,
        ),
      ];
    }
    final steps = buildRouteStepList(legs);
    if (steps.isEmpty) return;
    showRouteStepsSheet(
      context,
      steps: steps,
      destinationName: destination.name,
    );
  }

  void _dismissUserDestinationFromEtaCard() {
    _retainEtaClosePointer();
    _clearUserDestination();
    widget.onGuidanceDismissed?.call();
  }

  void _dismissIndoorRouteFromEtaCard() {
    _retainEtaClosePointer();
    // 야외 구간도 함께 지운다. 실내 구간은 그 야외 구간의 뒷부분이라, 실내만
    // 지우면 밖으로 나갔을 때 방금 끝낸 안내의 앞부분이 혼자 되살아난다.
    _clearUserDestination();
    _clearIndoorRoute();
    widget.onGuidanceDismissed?.call();
  }

  void _retainEtaClosePointer() {
    final pointerDown = _etaClosePointerDown;
    _etaClosePointerDown = null;
    if (pointerDown != null) {
      _mapOverlayTapGuard.retainPointerDown(pointerDown);
    }
  }

  /// 안내가 시작된 순간, **지금 층 경로 전체**가 한눈에 들어오도록 카메라를 한 번
  /// 크게 움직인다.
  ///
  /// ## 왜 층 도면이 아니라 경로에 맞추나
  ///
  /// 안내를 시작한 사용자가 알고 싶은 것은 "이 층이 어떻게 생겼나"가 아니라
  /// "어디로 얼마나 가나"다. 층 전체를 담으면 경로는 그 안 한 귀퉁이의 짧은
  /// 선이 되어 진행 방향이 읽히지 않는다.
  ///
  /// ## 왜 지금 층 세그먼트만인가
  ///
  /// 다층 경로 전체를 담으려 하면 **화면에 없는 층의 좌표까지** 상자에 들어간다.
  /// 층마다 도면 위치가 어긋나 있으면 상자가 엉뚱하게 커지고, 그만큼 축소돼
  /// 지금 걸을 구간이 도리어 안 보인다. 층은 [_swapIndoorFloorForRide]가 바뀔
  /// 때마다 다시 맞춘다.
  ///
  /// ## 왜 newLatLngBounds를 안 쓰나
  ///
  /// 예전 `_fitCameraToIndoorRoute`가 그걸 썼는데, 그 API는 **항상 정북 정렬
  /// 기준으로 계산해 bearing을 0으로 되돌린다.** 진입·층 전환에서 애써 세로로
  /// 세워 둔 도면이 안내를 시작하는 순간 도로 비스듬히 누웠다. 회전을 유지하려면
  /// [_animateCameraToFitPoints]처럼 `newCameraPosition`으로 직접 계산해야 한다.
  Future<void> _fitCameraToRouteSegment(
    IndoorRoute route, {
    Duration duration = _routeOverviewDuration,
  }) async {
    // 바로 옆 매장이면 담을 것이 없다 — 물러섰다 돌아오는 동작만 남는다.
    if (route.distanceMeters < _routeOverviewMinDistanceM) return;
    // 퇴화한 경로(점 2개, 일직선)를 견디는 몫은 [routeBoxFor]가 진다.
    final box = routeBoxFor(route.points, minSideM: _routeFitMinSideM);
    if (box == null) return;
    await _animateCameraToFitBox(
      box,
      topChromePx: _guidanceFitTopChromePx,
      bottomChromePx: _guidanceFitBottomChromePx,
      duration: duration,
      maxZoom: _routeFitMaxZoom,
    );
  }

  /// 야외 목적지 핀.
  ///
  /// **[_entrance]로 폴백하지 않는다.** 그 값은 진입/이탈 판정의 기준점이지
  /// 목적지가 아니다. 문 좌표가 채워지면서([_syncSelectedEntrance]) 폴백이
  /// 되살아났고, 앱을 켜고 GPS가 잡히기만 하면 아무도 고르지 않은 문에 빨간
  /// 핀이 찍혔다 — 경로 쪽에서 같은 폴백을 걷어낸 것과 같은 이유다.
  ///
  /// **문을 경유하는 안내 중에도 찍지 않는다.** 그때 [_userDestination]은
  /// 목적지가 아니라 지나갈 문이고, 진짜 목적지는 건물 안이라 실내 도착 핀이
  /// 따로 찍힌다([_syncIndoorDestinationLayer]). 둘 다 찍으면 야외 선이 끝나는
  /// 자리에 "여기가 목적지"로 읽히는 핀이 하나 더 생긴다.
  Future<void> _syncDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final passingThroughDoor =
        _pendingIndoorRoute != null || _pendingIndoorDestination != null;
    final target = passingThroughDoor ? null : _userDestination;
    await syncPointSource(controller, kOutdoorDestSourceId, target);
  }

  /// 실내 경로의 도착 노드에 물방울 핀을 찍는다.
  ///
  /// 핀을 찍는 좌표는 매장 중심(centroid)이 아니라 **경로의 마지막 점**이다 —
  /// 그래프 도착 노드는 매장 입구라 centroid와 몇 미터 어긋나고, 그 상태로
  /// centroid에 찍으면 경로선이 핀에 닿지 않고 끊긴 것처럼 보인다. 경로가 아직
  /// 계산되기 전 짧은 순간에는 경로가 없으므로 centroid로 폴백해 핀이 아예
  /// 안 보이는 구간을 만들지 않는다(실내 화면의 _destinationPinForCurrentFloor와
  /// 같은 규칙).
  ///
  /// 다층 경로에서는 **도착지 층을 보고 있을 때만** 찍는다. 중간 층은 지나가는
  /// 층이라 그 층 좌표에 도착 핀이 있으면 "여기가 목적지"로 잘못 읽힌다.
  Future<void> _syncIndoorDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncPointSource(
      controller,
      kOutdoorIndoorDestSourceId,
      _indoorDestinationPinForActiveFloor(),
    );
  }

  ll.LatLng? _indoorDestinationPinForActiveFloor() {
    final destination = _indoorRouteDestination;
    if (destination == null) return null;
    final multi = _indoorMultiFloorRoute;
    if (multi != null) {
      if (multi.destinationSegment.floorName != _activeFloor) return null;
      final points = multi.destinationSegment.route.points;
      return points.isNotEmpty ? points.last : destination.point;
    }
    final segment = _indoorRouteSegment;
    if (segment != null && segment.points.isNotEmpty) {
      return segment.points.last;
    }
    // 단일 층 경로는 목적지 층에서만 그려진다. 층을 옮기면 _switchOverlayFloor가
    // 세그먼트를 비우므로, 그때는 목적지 층이 아닌 곳에 centroid 폴백 핀이
    // 남지 않도록 층을 직접 확인한다.
    return destination.floor == _activeFloor ? destination.point : null;
  }

  /// 고른 대중교통 경로를 지도에 그린다.
  ///
  /// 도보 안내는 여기서 **지운다.** 두 선을 겹쳐 두면 어느 쪽이 지금 안내인지
  /// 알 수 없고, 하단 카드가 서로 다른 소요 시간을 말하게 된다.
  Future<void> showTransitRoute(
    TransitItinerary itinerary, {
    required ll.LatLng destination,
    required String label,
    ll.LatLng? origin,
  }) async {
    _clearCompletedRouteHistory();
    _clearPendingIndoorRoute();
    _stopFollowingUser();
    setState(() {
      _transitItinerary = itinerary;
      _transitLabel = label;
      _fixedRouteOrigin = origin;
      // 도보 경로와 그 목적지 핀은 접는다. 목적지 자체는 대중교통 경로의 끝점
      // 으로 그대로 남아 있다.
      _route = null;
      _offerStartGuidance = false;
      _userDestination = destination;
      _userDestinationLabel = label;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    await _syncTransitLayer();
    _notifyRouteStateIfChanged();
    _fitCameraToPoints(itinerary.points);
  }

  /// 대중교통 안내를 끈다. 경로선·요약 카드가 함께 사라진다.
  void clearTransitRoute() {
    if (_transitItinerary == null) return;
    setState(() {
      _transitItinerary = null;
      _transitLabel = null;
    });
    unawaited(_syncTransitLayer());
    _notifyRouteStateIfChanged();
  }

  /// [point]에서 가장 가까운 지상 출입구 좌표. 문 데이터가 없으면 null이다.
  ///
  /// 대중교통 안내가 **내린 자리 기준으로** 문을 고를 때 쓴다. 예전에는 이
  /// 판단이 없어 하차 지점과 무관하게 매장 좌표로 도보 경로를 그렸고, 그러면
  /// TMAP이 매장에서 가장 가까운 도로로 스냅해 **내린 곳 반대편 문**으로
  /// 데려가는 일이 실제로 있었다.
  ll.LatLng? entranceNearestTo(ll.LatLng point) =>
      nearestEntrance(_groundEntrances, point)?.point;

  /// 대중교통 경로선을 지도에 반영한다. feature로 펼쳐 소스에 쓰는 일은
  /// [syncTransitLayer]가 한다.
  Future<void> _syncTransitLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncTransitLayer(controller, _transitItinerary);
  }

  Future<void> _syncRouteLayer() {
    final scheduled = _routeLayerWriteQueue.then<void>(
      (_) => _syncRouteLayerNow(),
    );
    _routeLayerWriteQueue = scheduled.catchError((Object _, StackTrace _) {});
    return _routeLayerWriteQueue;
  }

  Future<void> _syncRouteLayerNow() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final transferSegment = _indoorMultiFloorRoute?.segmentForFloor(
      _activeFloor ?? '',
    );
    final transferPoints = transferSegment == null
        ? null
        : transferRoutePointsOnFloor(transferSegment, _floorPlan, _floorGraph);
    await controller.setGeoJsonSource(
      kOutdoorTransferRouteSourceId,
      transferPoints == null || transferPoints.length < 2
          ? emptyGeoJsonCollection()
          : geoJsonCollection([
              geoJsonLineFeature(transferPoints, style: 'indoor'),
            ]),
    );
    // 실내 경로가 활성이면 그걸 우선 그린다(GPS 걷기 경로와 동시에 표시하지
    // 않는다 — 사용자는 지금 실내에 있고 실내 경로가 유일한 관심사).
    final indoor = _indoorRouteSegment;
    if (indoor != null && indoor.points.length >= 2) {
      final visuals = _indoorRouteVisuals(indoor);
      await _syncCompletedRouteLayer(
        scopeId: _activeFloor,
        currentCompleted: visuals.completed,
      );
      await controller.setGeoJsonSource(
        kOutdoorRouteSourceId,
        visuals.remaining.length < 2
            ? emptyGeoJsonCollection()
            : geoJsonCollection([
                geoJsonLineFeature(visuals.remaining, style: 'indoor'),
              ]),
      );
      return;
    }
    final outdoorVisuals = _outdoorRouteVisuals(_route);
    await _syncCompletedRouteLayer(
      scopeId: CompletedRouteHistory.outdoorScope,
      currentCompleted: outdoorVisuals.completed,
    );
    final features = <Map<String, dynamic>>[];
    final route = _route;
    if (route != null && outdoorVisuals.remaining.length >= 2) {
      features.add(
        geoJsonLineFeature(
          outdoorVisuals.remaining,
          style: _routeIsDriving ? 'drive' : 'walk',
        ),
      );
    }
    // **밖에서도 실내 구간을 미리 보여준다.** 아직 승격 전이라 상태는
    // [_pendingIndoorRoute]에 있다. 예전에는 건물에 들어가야 그려져서, 안내를
    // 받아 든 사용자가 "매장까지"라는 라벨만 보고 정작 건물 안 어디로 가는지는
    // 도착할 때까지 알 수 없었다.
    //
    // 지금 펼쳐 둔 층의 구간만 그린다. 여러 층을 한꺼번에 겹쳐 그리면 같은
    // 좌표 위에 선이 여러 겹 쌓여, 어느 것이 이 층의 길인지 알 수 없다 —
    // 층 chip을 넘기면 그 층의 구간이 이어서 보인다.
    final preview = _pendingIndoorRoute?.segmentForFloor(_activeFloor ?? '');
    if (preview != null && preview.route.points.length >= 2) {
      features.add(geoJsonLineFeature(preview.route.points, style: 'indoor'));
    }
    await controller.setGeoJsonSource(
      kOutdoorRouteSourceId,
      features.isEmpty ? emptyGeoJsonCollection() : geoJsonCollection(features),
    );
  }

  /// 사용자에게 보여 줄 회색선 source를 갱신한다.
  ///
  /// [currentCompleted]는 아직 재탐색 이력으로 승격되지 않은 현재 경로의
  /// 완료 구간이다. 재탐색이 확정되면 같은 점들이
  /// [_completedRouteHistory]에 저장되고, 새 파란 경로가 이 자리를 대체한다.
  /// GuidanceTrailSession은 여기에 들어오지 않는다.
  Future<void> _syncCompletedRouteLayer({
    required String? scopeId,
    List<ll.LatLng> currentCompleted = const [],
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final segments = <List<ll.LatLng>>[];
    if (scopeId != null) {
      segments.addAll(_completedRouteHistory.segmentsFor(scopeId));
    }
    if (currentCompleted.length >= 2) {
      segments.add(currentCompleted);
    }
    await controller.setGeoJsonSource(
      kOutdoorWalkedRouteSourceId,
      segments.isEmpty
          ? emptyGeoJsonCollection()
          : geoJsonCollection([
              for (final segment in segments)
                geoJsonLineFeature(segment, generation: _routeGeneration),
            ]),
    );
  }

  /// 실내/야외 경로 중 하나라도 활성이면 true. ETA 카드 노출과 하단 바 리프트
  /// 판정에 쓴다.
  bool get _hasAnyRouteVisible =>
      _route != null ||
      _transitItinerary != null ||
      _indoorRouteSegment != null ||
      _indoorMultiFloorRoute != null;

  /// 사용자가 **직접 고른** 목적지로 안내 중인지. 안내 chrome(검색창·카테고리
  /// 줄·층 선택기·하단 바)을 접을지의 유일한 판정 기준이다.
  ///
  /// 판정 규칙과 그렇게 나눈 이유는 [shouldFoldGuidanceChrome]에 있다. 요약하면
  /// **접는 조건은 종료 버튼이 있는 조건과 같아야 한다** — 아래 ETA 카드 두
  /// 분기가 `onClose`를 다는 조건과 이 getter가 정확히 맞물려야 하고, 어느
  /// 한쪽을 고치면 그 함수를 통해 다른 쪽도 같이 바뀐다.
  bool get _guidanceActive => shouldFoldGuidanceChrome(
    hasUserDestination: _userDestination != null,
    hasIndoorRouteDestination: _indoorRouteDestination != null,
    hasComputedRoute: _route != null,
  );

  void _notifyRouteStateIfChanged() {
    final visible = _hasAnyRouteVisible;
    if (visible != _lastRouteVisibleNotified) {
      _lastRouteVisibleNotified = visible;
      widget.onRouteVisibleChanged?.call(visible);
    }
    final guiding = _guidanceActive;
    if (guiding != _lastGuidanceActiveNotified) {
      _lastGuidanceActiveNotified = guiding;
      widget.onGuidanceActiveChanged?.call(guiding);
    }
  }

  /// 세션에 스냅샷을 넘기고, 나온 보정 결과를 로그에 남긴다.
  ///
  /// 층·그래프·앵커·경로는 세션이 들고 있으므로 여기서 다시 확인하지 않는다.
  /// 두 곳에서 같은 조건을 세면 반드시 한쪽이 먼저 낡는다.
  /// 실내 안내를 지금 건물에 붙인다.
  ///
  /// 진입 시점에 건물이 아직 로드되지 않았을 수 있다. 그때 빈 id로 붙여 두면
  /// GPS 추정점의 건물이 영원히 안 맞아 폴백 표시가 조용히 죽는다. 로드된 뒤
  /// 처음 오는 스냅샷에서 제대로 붙인다.
  void _ensureGuidanceAttached() {
    final buildingId = _building?.id;
    if (buildingId == null || _guidance.buildingId == buildingId) return;
    _guidance.attach(buildingId: buildingId);
  }

  /// 실내 경로 진행률을 갱신한다. 계산은 세션이, 다시 그리기는 여기가 한다.
  ///
  /// 홈에도 이게 필요한 이유는 ETA 카드 때문이다. 예전에는 경로 전체 길이를
  /// 고정으로 보여줘서, 목적지 앞에 서 있어도 출발할 때와 같은 거리가 떠 있었다.
  void _syncIndoorRouteProgress(
    CorridorTrackingResult? result,
    PdrSnapshot? snapshot,
  ) {
    if (!_indoorEntered) return;
    final anchor = _pdrTrailState.anchor;
    final toFloor = anchor == null ? null : FloorCoordinateTransform(anchor);
    final update = _guidance.updateProgress(
      result,
      rerouteInFlight: _indoorRerouteInFlight,
      confirmedSteps: snapshot?.steps,
      previewSteps: snapshot?.preview.steps,
      orientationHeadingDeg: snapshot == null || toFloor == null
          ? null
          : toFloor.toFloorBearing(snapshot.orientationHeadingDeg),
      walkingHeadingDeg: snapshot == null || toFloor == null
          ? null
          : toFloor.toFloorBearing(snapshot.walkingHeadingDeg),
    );
    for (final advance in update.stepAdvances) {
      _pdrDebugRecorder?.recordRouteStepAdvance(
        advance.step,
        transition: advance.transition,
      );
    }
    for (final event in update.checkpointEvents) {
      _pdrDebugRecorder?.recordCheckpointEvent(event);
    }
    final measured = update.measuredProgress;
    if (measured != null) {
      _pdrDebugRecorder?.recordRouteProgress(
        measured,
        displayProgress: update.displayProgress,
        holdReason: update.holdReason,
      );
    }
    if (update.shouldReroute &&
        DateTime.now().millisecondsSinceEpoch - _lastIndoorRerouteAtMs >=
            2000) {
      unawaited(_rerouteIndoorFromCurrentPosition());
    }
    if (mounted) setState(() {});
    _syncArrivalHighlight();
    _syncArrival();
  }

  /// 도착을 화면에 반영한다 — 도착 카드를 띄우고, 잠시 뒤 경로를 스스로 지운다.
  ///
  /// 판단은 [decideArrivalAutoClear]가 한다. 여기서 조건을 다시 세지 않는 이유는
  /// "도착 상태에 들락날락하는 동안 카운트다운을 다시 걸지 않는다"는 규칙이
  /// 걸음마다 돌아가는 이 자리에서 제일 틀리기 쉽기 때문이다.
  void _syncArrival() {
    if (!mounted) return;
    final decision = decideArrivalAutoClear(
      action: _indoorRouteGuidance?.action,
      // 측정된 진행률이 없으면 "걸어서 도착"이 아니라 애초에 가까운 것이다.
      hasMeasuredProgress: _guidance.measuredProgress != null,
      alreadyScheduled: _arrivalRouteClearTimer != null,
    );
    switch (decision) {
      case ArrivalAutoClearDecision.keep:
        return;
      case ArrivalAutoClearDecision.cancel:
        // 도착 지점을 지나쳐 계속 걸어간 경우다. 카드는 **지우지 않는다** —
        // 한 번 "도착했습니다"라고 말해 놓고 조용히 거두면 사용자는 자기가
        // 잘못 본 줄 안다. 카드를 닫는 것은 사용자의 확인뿐이다.
        _arrivalRouteClearTimer?.cancel();
        _arrivalRouteClearTimer = null;
        return;
      case ArrivalAutoClearDecision.schedule:
        final destination = _indoorRouteDestination;
        if (destination == null) return;
        setState(() => _arrivedDestination = destination);
        _arrivalRouteClearTimer = Timer(arrivalAutoClearDelay, () {
          _arrivalRouteClearTimer = null;
          if (!mounted) return;
          // 경로·핀·하단 배너를 정리한다. 도착 카드는 남는다 — 그것이 지금
          // 화면에서 유일하게 "끝났다"고 말하는 것이다.
          _clearIndoorRoute();
        });
    }
  }

  /// 도착 카드의 `안내 종료`. 남은 여정을 통째로 정리한다.
  void _confirmArrival() {
    _arrivalRouteClearTimer?.cancel();
    _arrivalRouteClearTimer = null;
    setState(() => _arrivedDestination = null);
    _dismissIndoorRouteFromEtaCard();
  }

  /// 도착한 순간 목적지 매장 폴리곤을 강조하고, 벗어나면 되돌린다.
  ///
  /// 카드가 "여기에 도착했다"고 말할 때 지도에서 **그 여기가 어디인지**를 함께
  /// 보여 준다. 이름만 적힌 카드로는 눈앞의 여러 매장 중 어느 쪽인지 알 수 없다.
  ///
  /// 도착이 아닐 때 강조를 지우는 쪽도 함께 둔다 — 도착 판정은 걸음에 따라
  /// 들락날락할 수 있어서, 켜기만 하면 지나쳐 걸어간 뒤에도 강조가 남는다.
  /// 사용자가 매장을 눌러 직접 켜 둔 강조는 건드리지 않는다.
  void _syncArrivalHighlight() {
    if (!mounted) return;
    final destinationId = _indoorRouteDestination?.placeId;
    if (destinationId == null) return;
    final arrived = _indoorRouteGuidance?.action == RouteGuidanceAction.arrived;
    final shouldHighlight = arrived ? destinationId : null;
    if (shouldHighlight == null && _highlightedStoreId != destinationId) return;
    if (_highlightedStoreId == shouldHighlight) return;
    setState(() => _highlightedStoreId = shouldHighlight);
    unawaited(_syncHighlightLayer());
  }

  /// 경로를 벗어난 것이 확인되면 목적지는 유지한 채 현 위치에서 다시 뽑는다.
  ///
  /// **층 선택기 층이 아니라 앵커 층을 기준으로 한다.** 선택기는 사용자가 다른
  /// 층을 둘러보는 UI 상태일 뿐이다. 그 층으로 재탐색하면 다층 안내 중간
  /// 세그먼트가 단층 경로로 바뀌어 최종 도착처럼 보인다.
  Future<void> _rerouteIndoorFromCurrentPosition() async {
    if (_indoorRerouteInFlight) return;
    final destination = _indoorRouteDestination;
    final destinationNodeId = destination?.nodeId;
    final floor = _pdrTrailState.anchor?.floorId;
    final graph = _floorGraph;
    final buildingId = _building?.id;
    final current = _guidance.trackingResult?.previewPosition;
    if (destination == null ||
        destinationNodeId == null ||
        floor == null ||
        graph == null ||
        buildingId == null ||
        current == null) {
      return;
    }
    final startNodeId = _nearestNodeId(
      graph.nodes,
      current.eastM,
      current.northM,
      excludingNodeId: destinationNodeId,
    );
    if (startNodeId == null) return;

    _indoorRerouteInFlight = true;
    try {
      // **재탐색에는 개요 연출을 붙이지 않는다.** 재탐색은 사용자가 걷고 있는
      // 도중에 일어난다. 그때 카메라가 경로 전체를 담으러 크게 물러섰다 돌아오면
      // 연출이 아니라 방해다 — 다음 걸음을 보려던 화면이 통째로 바뀐다.
      if (destination.floor == floor) {
        await _computeAndShowSingleFloorIndoorRoute(
          buildingId: buildingId,
          floor: floor,
          endNodeId: destinationNodeId,
          playOverview: false,
          // 이탈 재탐색 — 같은 길안내의 연속이다.
          beginNewRecordingSession: false,
          startNodeId: startNodeId,
        );
      } else {
        await _computeAndShowMultiFloorIndoorRoute(
          buildingId: buildingId,
          startFloor: floor,
          endFloor: destination.floor,
          endNodeId: destinationNodeId,
          playOverview: false,
          beginNewRecordingSession: false,
          startNodeId: startNodeId,
        );
      }
      _lastIndoorRerouteAtMs = DateTime.now().millisecondsSinceEpoch;
    } finally {
      _indoorRerouteInFlight = false;
    }
  }

  /// 지금 이 층 실내 경로의 턴바이턴 안내. 없으면 null.
  ///
  /// 실내 탭과 같은 규칙을 쓴다 — 도착 안내는 **목적지 세그먼트에서만** 낸다.
  /// 중간 층 세그먼트의 끝은 도착이 아니라 환승이라, 거기서 "도착했습니다"를
  /// 띄우면 사용자가 남은 층을 안 가고 멈춘다.
  RouteGuidanceInstruction? get _indoorRouteGuidance {
    final route = _indoorRouteSegment;
    if (route == null || route.pointsLocalM.isEmpty) return null;
    // **실내 위치가 없으면 한 줄 안내를 내지 않는다.**
    //
    // [buildRouteGuidance]는 진행률이 null이면 경로 **전체**를 기준으로 다음
    // 회전을 찾는다. 그래서 건물 밖에 서 있어도 "110미터 후 에스컬레이터 탑승"
    // 같은 문장이 떴다 — 사용자는 아직 버스에서 내려 걷는 중인데 화면은 건물 안
    // 몇 미터 앞을 말한다. 실내 오버레이만으로 가르면 안 되는 이유는, 그 오버레이가
    // 건물로 확대하기만 해도 켜지기 때문이다(indoor_entry_zoom.dart).
    //
    // 기준은 "우리가 이 사람이 실내 어디에 있는지 아는가"다. 그게 곧 진행률의
    // 출처이고, 진입을 실제로 감지해 앵커를 잡았을 때만 참이 된다.
    if (_guidance.displayProgress == null) return null;
    final multi = _indoorMultiFloorRoute;
    final segment = multi?.segmentForFloor(_activeFloor ?? '');
    final allowArrival =
        multi == null ||
        (segment != null &&
            identical(segment, multi.destinationSegment) &&
            _activeFloor == _indoorRouteDestination?.floor);
    return buildRouteGuidance(
      localPoints: route.pointsLocalM,
      wgs84Points: route.points,
      progress: _guidance.displayProgress,
      travelDirectionState: _guidance.travelDirectionState,
      transferMode: segment?.transferModeToNext,
      allowArrival: allowArrival,
    );
  }

  void _beginRouteRecordingSession() {
    _ensureGuidanceTrailSessionStarted();
    _pdrDebugRecorder = PdrDebugSessionRecorder()
      ..recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) _pdrDebugRecorder?.recordSnapshot(snapshot);
    _pdrDebugRecorder?.recordCalibration(
      indoorNavigationDriver.currentCalibration,
    );
  }

  /// 경로가 해제되면 세션을 닫는다. [announceExport]는 세션 경계 기록에만 쓴다
  /// — 사용자가 끝낸 것(routeEnded)과 새 경로로 갈아탄 것(routeReplaced)을
  /// 사후 분석에서 구분하기 위해서다.
  ///
  /// 예전에는 여기서 "진단 JSON을 내보낼 수 있다"는 토스트를 띄웠다. 안내가
  /// 끝나는 순간은 도착 카드가 뜨는 순간이라 토스트가 그 위를 덮었고, 내보내기
  /// 진입점은 디버그 모드의 공유 버튼([PdrMapControl])이 이미 지도에 상시로
  /// 있다 — 같은 일을 하는 두 번째 입구가 화면을 가리기만 했다.
  void _endRouteRecordingSession({bool announceExport = true}) {
    final recorder = _pdrDebugRecorder;
    if (recorder == null) return;
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) recorder.recordSnapshot(snapshot);
    recorder.recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    recorder.recordSessionBoundary(
      announceExport ? 'routeEnded' : 'routeReplaced',
    );
  }
}
