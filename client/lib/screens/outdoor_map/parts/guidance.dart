// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **안내 진행·도착 판정** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapGuidance on OutdoorMapBodyState {
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
  /// **도착을 말하는 것과 경로를 지우는 것은 조건이 다르다.** 바로 옆 매장은 걸어서
  /// 도착한 것이 아니라 애초에 가까운 것이라 경로를 자동으로 지우지 않지만, 도착한
  /// 사실은 그때도 말해야 한다. 둘을 한 조건에 묶어 뒀더니 그 경로에서는 도착을
  /// 말하는 것이 화면에 하나도 없었다.
  ///
  /// 지우는 쪽 판단은 [decideArrivalAutoClear]가 한다. 여기서 조건을 다시 세지 않는
  /// 이유는 "도착 상태에 들락날락하는 동안 카운트다운을 다시 걸지 않는다"는 규칙이
  /// 걸음마다 돌아가는 이 자리에서 제일 틀리기 쉽기 때문이다.
  void _syncArrival() {
    if (!mounted) return;

    final destination = _indoorRouteDestination;
    if (_arrivedDestination == null &&
        shouldAnnounceArrival(
          action: _indoorRouteGuidance?.action,
          hasDestination: destination != null,
        )) {
      setState(() => _arrivedDestination = destination);
    }

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
        _arrivalRouteClearTimer = Timer(arrivalAutoClearDelay, () {
          _arrivalRouteClearTimer = null;
          if (!mounted) return;
          // 경로·핀·하단 배너를 정리한다. 도착 카드는 남는다 — 그것이 지금
          // 화면에서 유일하게 "끝났다"고 말하는 것이다.
          _clearIndoorRoute();
        });
    }
  }

  /// GPS가 지금 이 사람을 **건물 밖이라고 분명히 말하는가.**
  ///
  /// 판정하지 못하는 경우(`unclear`)는 밖으로 치지 않는다. 실내에서는 GPS 오차가
  /// 커서 unclear가 흔하고, 거기서 막으면 **정작 건물 안에 있는 사람이 안내를
  /// 시작하지 못한다.** 막아야 할 것은 확실히 밖인 경우뿐이다.
  bool get _gpsSaysOutsideBuilding {
    final position = _position;
    if (position == null) return false;
    final judgement = judgeBuildingFromGps(
      fix: GpsFix(
        point: ll.LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
      ),
      footprint: _buildingFootprint,
    );
    return judgement.verdict == GpsBuildingVerdict.outside;
  }

  /// 미리 보던 실내 경로에서 **실제 안내를 시작한다.**
  ///
  /// 여기서야 출발지 매장에 앵커를 찍는다. 미리 보는 동안 찍지 않는 이유는
  /// [_indoorRoutePreview]에 적었다 — 그 사람은 아직 거기 서 있지 않다.
  ///
  /// **건물 밖에서 누르면 아무것도 바꾸지 않는다.** 앵커를 찍어 봐야 다음 GPS 틱이
  /// 곧바로 뒤집어 도면과 경로가 아무 말 없이 사라진다. 그래서 화면은 그대로 두고
  /// 언제 시작할 수 있는지만 말한다 — 보던 경로를 잃지 않는 것이 이 화면의 목적이다.
  Future<void> _startIndoorGuidance() async {
    if (_gpsSaysOutsideBuilding) {
      _showSnack('건물에 도착하면 안내를 시작할 수 있습니다.');
      return;
    }
    final origin = _indoorRoutePreviewOrigin;
    final floor = origin?.floor;
    final nodeId = origin?.nodeId;
    if (origin == null || nodeId == null || floor == null || floor.isEmpty) {
      return;
    }
    setState(() {
      _indoorRoutePreview = false;
      _indoorRoutePreviewOrigin = null;
    });
    await _anchorAtStoreOrigin(
      floor: floor,
      nodeId: nodeId,
      storePoint: origin.point,
      storeName: origin.name,
    );
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
