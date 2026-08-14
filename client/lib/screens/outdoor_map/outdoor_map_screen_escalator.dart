// ignore_for_file: invalid_use_of_protected_member
//
// 이 파일은 `OutdoorMapBodyState`의 part다. setState는 그 클래스가 State에서
// 물려받은 protected 멤버이고, 여기서 부르는 것은 **같은 클래스의 코드**다 —
// 파일만 갈라져 있을 뿐 바깥에서 남의 protected 멤버를 건드리는 것이 아니다.
// 분석기는 extension을 "서브클래스가 아니다"로 보아 경고하므로 파일 단위로
// 끈다. 본체(생명주기·build)는 클래스 안에 있어 이 해제의 영향을 받지 않는다.
/// `OutdoorMapBodyState`의 **에스컬레이터·층 전환** 부분.
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

extension OutdoorMapEscalator on OutdoorMapBodyState {
  void _onFloorSwitchMotifChanged(FloorSwitchDirection? direction) {
    if (!mounted) return;
    setState(() {
      _floorSwitchMotifVisible = direction != null;
      if (direction != null) _floorSwitchMotifDirection = direction;
    });
  }

  /// 기압 샘플 한 건을 세션에 넣고, 확정이 나오면 층을 옮긴다.
  void _onAltitudeSample(AltitudeSample sample) {
    if (!mounted) return;
    // 스냅샷이 아직 없거나(PDR 시작 직후) 서 있어서 멈춘 동안에도 판정기는
    // 층 그래프를 알아야 에스컬레이터 노드에 허가가 걸린다. 기압은 걸음과
    // 무관하게 흐르므로 여기서도 컨텍스트를 준다.
    _guidance.setContext(
      floorId: _activeFloor,
      graph: _floorGraph,
      floorLabels: _building?.floors ?? const [],
    );
    final outcome = _guidance.onAltitude(sample);
    final recorder = _pdrDebugRecorder;
    if (recorder != null) {
      recorder.recordAltimeterStatus(indoorNavigationDriver.altimeterStatus);
      recorder.recordAltitudeSample(
        sample,
        smoothedM: _guidance.escalator.smoothedAltitudeM,
        baselineM: _guidance.escalator.baselineM,
        deltaM: _guidance.escalator.deltaM,
        armed: _guidance.escalator.isArmed,
        candidate: _guidance.escalator.hasCandidate,
      );
    }
    if (outcome.events.isNotEmpty) {
      recorder?.recordFloorTransitionEvents(outcome.events);
      _lastEscalatorEvent = outcome.events.last;
    }
    // 진단 칩은 이벤트 유무와 무관하게 매 샘플 갱신한다. 층이 **안** 바뀌는
    // 동안의 Δ와 무장 여부가 곧 원인이라, 아무 일도 안 일어나는 구간이야말로
    // 봐야 할 구간이다.
    _escalatorDebugText.value = _debugModeController.enabled
        ? describeEscalatorJudgement(
            deltaM: _guidance.escalator.deltaM,
            armed: _guidance.escalator.isArmed,
            hasCandidate: _guidance.escalator.hasCandidate,
            phase: _guidance.escalator.phase,
            lastEvent: _lastEscalatorEvent,
          )
        : null;

    // 활강 진행률 목표를 기압으로 갱신한다. 단조 증가만 허용 — 평활 노이즈로
    // 점이 뒤로 가지 않는다. 1.0은 하차 확정([_completeEscalatorTransition])만
    // 채운다.
    final ride = _escalatorRide;
    final rideDelta = _guidance.escalator.deltaM;
    if (_escalatorGlide != null && ride != null && rideDelta != null) {
      final sign = ride.direction == EscalatorDirection.up ? 1.0 : -1.0;
      _escalatorRideTargetProgress = math.max(
        _escalatorRideTargetProgress,
        escalatorRideProgressTarget(
          deltaTowardsM: rideDelta * sign,
          swapDeltaM: _escalatorRideSwapDeltaM,
          expectedTotalM: _escalatorRideExpectedM,
        ),
      );
    }
    _handleEscalatorPhaseChanges();

    // 순서가 중요하다. 시작 → 취소 → 확정 순으로 큐에 넣어야 층·경로 복원이
    // 어긋나지 않는다.
    if (outcome.started != null) {
      _enqueueFloorTransition(
        () => _beginEscalatorTransition(outcome.started!),
      );
    }
    if (outcome.cancelled != null) {
      _enqueueFloorTransition(
        () => _cancelEscalatorTransition(outcome.cancelled!),
      );
    }
    if (outcome.confirmed != null) {
      _enqueueFloorTransition(
        () => _completeEscalatorTransition(outcome.confirmed!),
      );
    }
  }

  /// 판정기의 단계 전이를 화면 동작으로 옮긴다.
  ///
  /// 단계마다 하는 일이 다르다. 배너는 근거가 약해도 띄우고(되돌리기 비용이
  /// 없다), 걸음 pause는 실제 수직 이동에서 시작하며, 목적 층 지도는 midpoint
  /// 근거에서만 연다. 층 전환과 하차 확정은 started/confirmed 경로가 담당한다.
  void _handleEscalatorPhaseChanges() {
    final changes = _guidance.takePhaseChanges();
    if (changes.isEmpty) return;
    for (final change in changes) {
      switch (change.phase) {
        case EscalatorPhase.boardingDetected:
        case EscalatorPhase.verticalMotionDetected:
          if (!mounted) return;
          setState(() => _escalatorStage = change);
          if (change.phase == EscalatorPhase.verticalMotionDetected) {
            _enqueueFloorTransition(_pauseStepsForRide);
          }
        case EscalatorPhase.cancelled:
        case EscalatorPhase.failed:
          if (!mounted) return;
          setState(() => _escalatorStage = null);
          // 후보가 열린 뒤의 취소는 층·경로 복원까지 해야 하므로 cancelled
          // 경로가 처리한다. 여기서는 배너만 띄운 단계에서 멈춘 걸음을
          // 되살리는 것만 책임진다.
          if (change.transition == null) {
            _enqueueFloorTransition(_endEscalatorRide);
          }
        case EscalatorPhase.midpointReached:
        case EscalatorPhase.landed:
          // 여기서 단계를 비우지 않는다. 층 전환은 큐를 거쳐 다음 프레임 이후에
          // 적용되므로, 지금 비우면 그 사이 배너가 한 번 깜빡였다가 다시 뜬다.
          break;
        case EscalatorPhase.idle:
          if (!mounted) return;
          setState(() => _escalatorStage = null);
      }
    }
  }

  /// 위치에 반영하는 걸음만 멈춘다. 센서·기압·방향은 계속 흐른다.
  Future<void> _pauseStepsForRide() async {
    if (_stepsPausedForRide) return;
    _stepsPausedForRide = true;
    await indoorNavigationDriver.pauseStepTracking();
    if (mounted) return;
    // pause Future가 끝나기 직전에 화면이 닫히면 dispose는 pause된 사실을 볼 수
    // 없다. 여기서 직접 되돌려 전역 PDR 세션을 살려 둔다.
    _stepsPausedForRide = false;
    await indoorNavigationDriver.resumeStepTracking();
  }

  /// 탑승 상태를 끝낸다. 걸음 누적을 다시 켜고 배너·스크림을 지운다.
  ///
  /// 확정·취소·되돌리기 **모든 출구**가 이걸 지나야 한다. 한 경로라도 빠뜨리면
  /// 배너가 남고 걸음이 영영 멈춘 상태로 사용자가 복구할 방법이 없어진다.
  Future<void> _endEscalatorRide() async {
    if (_escalatorRide == null &&
        _escalatorStage == null &&
        !_stepsPausedForRide &&
        _escalatorGlide == null &&
        _floorSwapVeil == 0) {
      return;
    }
    _stepsPausedForRide = false;
    await indoorNavigationDriver.resumeStepTracking();
    if (!mounted) return;
    _stopEscalatorGlide();
    _floorSwapVeilTimer?.cancel();
    _floorSwapVeilTimer = null;
    setState(() {
      _escalatorRide = null;
      _escalatorStage = null;
      _floorSwapVeil = 0;
    });
    _guidance.clearBoardingHold();
  }

  /// 탑승 중에 목적 층 도면으로 갈아탄다.
  ///
  /// 교체 구간만 덮개로 가린다([_floorSwapVeil]). 덮지 않고 크로스페이드만으로
  /// 넘겨 본 적이 있는데, 층이 바뀌는 사건 자체가 화면에 드러나지 않아 사용자가
  /// 다른 층 도면을 읽고 있는 줄 모른다. 반대로 하차까지 덮으면 내리기 전에
  /// 새 층과 다음 경로를 볼 시간이 없다. 그래서 **교체 앞뒤 약 3초**만이다.
  ///
  /// 덮개 뒤에서는 사람이 층 chip을 눌렀을 때와 같은 크로스페이드가 돈다
  /// ([_switchOverlayFloorCrossfaded]) — 이전 층 도면이 새 층 타일이 실제로
  /// 도착할 때까지 남아 있어, 덮개가 걷히는 순간 흰 화면이나 반쯤 그려진 도면이
  /// 보이지 않는다. 안내 중에는 페이드를 두 배 느리게 준다
  /// ([floorSwitchGuidedCrossfadeDuration]).
  ///
  /// 마커 활강과 카메라 정렬도 여기서 건다. 셋(도면 교체·마커·카메라)이 같은
  /// 시간 축 위에서 시작해야 하나의 전환으로 읽힌다.
  Future<bool> _swapIndoorFloorForRide(EscalatorTransition transition) async {
    final floor = transition.toFloorLabel;
    if (!(_building?.floors.contains(floor) ?? false)) return false;
    // 탑승 노드 좌표는 **층을 바꾸기 전에** 절대 좌표로 떠 둔다. 층이 바뀌면
    // 이전 층 그래프가 사라져 local m을 WGS84로 옮길 수가 없다.
    final boardingWgs84 =
        _nodeWgs84(_floorGraph, transition.boardingNodeId) ??
        _pdrCurrentWgs84();
    // 덮개가 다 올라온 **뒤에** 교체한다. 셸의 페이드와 여기 대기가 어긋나면
    // 아직 덜 덮인 화면에서 도면이 바뀌는 장면이 그대로 보인다.
    setState(() => _floorSwapVeil = 1);
    await Future<void>.delayed(floorTransitionScrimFadeIn);
    if (!mounted) return false;
    await _switchOverlayFloorCrossfaded(
      floor,
      recenterIfNeeded: false,
      crossfadeDuration: floorSwitchGuidedCrossfadeDuration,
    );
    if (!mounted || _activeFloor != floor) return false;

    final arrival = findEscalatorArrivalNode(_floorGraph, transition);
    if (arrival != null) setState(() => _pendingArrivalNode = arrival);
    // **새 층 경로를 여기서 다시 뽑는다.** 안내가 계획한 에스컬레이터와 사용자가
    // 실제로 탄 에스컬레이터가 다를 수 있다(경로를 벗어나 걸어가면 이 층 세그먼트
    // 는 재탐색으로 갱신되지만, 다음 층 세그먼트는 계획 당시 그대로다). 그대로
    // 두면 덮개가 걷힌 화면에 **하차 지점과 이어지지도 않는** 경로가 그려지고,
    // 사용자는 엉뚱한 에스컬레이터로 유도된다. 하차 확정 뒤에도 같은 계산을
    // 하지만([_rerouteAfterVerticalTransfer]), 그때까지 기다리면 타는 내내 틀린
    // 경로를 보게 된다.
    if (arrival != null) {
      await _recomputeRouteFrom(nodeId: arrival.id, floor: floor);
      if (!mounted || _activeFloor != floor) return false;
    }
    final arrivalWgs84 = _nodeWgs84(_floorGraph, arrival?.id);
    _startEscalatorGlide(
      from: boardingWgs84,
      to: arrivalWgs84,
      transition: transition,
      // 새 층 도면에서 하차 노드에 가장 가까운 에스컬레이터 폴리곤의 긴 축.
      // 이게 없으면 활강이 두 노드를 직선으로 이어, 크로스형 뱅크에서 마커가
      // 구조물을 대각선으로 가로지른다.
      axis: arrival == null
          ? null
          : escalatorAxisNearLocal(arrival.xM, arrival.yM, _floorPlan),
    );
    // 카메라는 **기다리지 않는다.** 이 함수는 층 전환 큐 위에서 도는데, 여기서
    // 활강 시간만큼 붙잡으면 그 뒤 하차 확정이 그만큼 밀린다.
    unawaited(_aimCameraAtEscalatorExit(from: boardingWgs84, to: arrivalWgs84));
    // 덮개도 같은 이유로 예약해서 내린다. 걷히면 사용자는 새 층 도면과 다음
    // 경로를 보며 남은 구간을 탄다.
    _floorSwapVeilTimer?.cancel();
    _floorSwapVeilTimer = Timer(_indoorFloorSwapVeilHold, () {
      _floorSwapVeilTimer = null;
      if (!mounted) return;
      setState(() => _floorSwapVeil = 0);
    });
    return true;
  }

  /// 탑승 노드 → 하차 노드 구간을 마커가 흐르게 한다.
  ///
  /// 양 끝 중 하나라도 모르면 걸지 않는다 — 출발이나 도착을 모르는 활강은
  /// 아무 방향으로나 흐르는 점일 뿐이다. 그때는 예전처럼 마커가 잠깐 사라졌다
  /// 하차 확정과 함께 도착 노드에 나타난다.
  ///
  /// 진행률은 시간이 아니라 **기압**이 정한다([_onAltitude]가 목표를 갱신).
  /// 서 있든 걷든 몸이 오르내린 높이만큼 점이 가고, 끝(1.0)은 하차 확정만이
  /// 채운다 — 점이 끝에 닿는 순간이 곧 실제 하차다.
  void _startEscalatorGlide({
    required ll.LatLng? from,
    required ll.LatLng? to,
    required EscalatorTransition transition,
    (ll.LatLng, ll.LatLng)? axis,
  }) {
    _escalatorGlideTimer?.cancel();
    _escalatorGlideTimer = null;
    if (from == null || to == null) {
      _escalatorGlide = null;
      return;
    }
    _escalatorGlide = EscalatorGlide(
      points: _glidePathPoints(from: from, to: to, axis: axis),
    );
    // 진행률 정규화의 양 끝: 지금(도면 교체 순간)의 Δ가 0, 예상 층고가 1이다.
    // 층고는 같은 그룹의 직전 확정 Δ가 있으면 실측을 쓴다.
    final sign = transition.direction == EscalatorDirection.up ? 1.0 : -1.0;
    _escalatorRideSwapDeltaM = (_guidance.escalator.deltaM ?? 0) * sign;
    _escalatorRideExpectedM =
        _escalatorGroupHeightM[transition.group] ?? escalatorDefaultFloorHeightM;
    _escalatorRideTargetProgress = 0;
    _escalatorGlideProgress.value = 0;
    _escalatorGlideTimer = Timer.periodic(_escalatorGlideFrame, (timer) {
      final glide = _escalatorGlide;
      if (!mounted || glide == null) {
        timer.cancel();
        return;
      }
      final value = _escalatorGlideProgress.value;
      final target = _escalatorRideTargetProgress;
      // 기압 샘플(0.18~1.07초 간격)을 그대로 그리면 점이 툭툭 끊긴다. 틱마다
      // 목표 쪽으로 지수 평활 — 시정수 약 0.5초.
      final next = (target - value).abs() < 0.002
          ? target
          : value + (target - value) * escalatorRideProgressEase;
      if (next != value) {
        _escalatorGlideProgress.value = next;
        unawaited(_syncPdrCurrentLayer());
      }
      // 하차 확정(목표 1.0)에 다 붙었으면 타이머만 접는다. 활강 자체는 확정
      // 절차가 끝날 때까지 살려 둬야 마커가 그 자리를 지킨다.
      if (target >= 1 && next >= 1) timer.cancel();
    });
  }

  /// 활강 폴리라인. 에스컬레이터 축이 있으면 하차 노드에 가까운 끝이 마지막에
  /// 오도록 방향을 맞춰 끼운다. 양 끝(탑승·하차 노드)과 1m 안으로 겹치는
  /// 경유점은 버린다 — 겹친 점을 남기면 그 구간 진행률이 0으로 나뉜다.
  List<ll.LatLng> _glidePathPoints({
    required ll.LatLng from,
    required ll.LatLng to,
    required (ll.LatLng, ll.LatLng)? axis,
  }) {
    if (axis == null) return [from, to];
    const distance = ll.Distance();
    final (a, b) = axis;
    final ordered = distance(b, to) <= distance(a, to) ? [a, b] : [b, a];
    final via = ordered
        .where(
          (point) => distance(from, point) >= 1.0 && distance(point, to) >= 1.0,
        )
        .toList();
    return [from, ...via, to];
  }

  void _stopEscalatorGlide() {
    _escalatorGlideTimer?.cancel();
    _escalatorGlideTimer = null;
    _escalatorRideTargetProgress = 0;
    _escalatorRideSwapDeltaM = 0;
    _escalatorRideExpectedM = escalatorDefaultFloorHeightM;
    if (_escalatorGlide == null) return;
    _escalatorGlide = null;
    _escalatorGlideProgress.value = 0;
    unawaited(_syncPdrCurrentLayer());
  }

  /// 하차 지점을 화면에 두고, **내리는 방향**이 화면 위로 오게 돌린다.
  ///
  /// 예전에는 새 층 경로 전체를 담는 개요([_fitCameraToRouteSegment])를 썼다.
  /// 그러면 에스컬레이터에서 내리는 순간 화면은 이미 "앞으로 갈 방향"으로
  /// 돌아가 있는데 몸은 아직 에스컬레이터 정면을 보고 있어서, 사용자가 어느
  /// 쪽으로 몸을 틀어야 하는지 화면에서 읽을 수가 없었다.
  ///
  /// 방향을 못 구하면(두 노드가 겹쳐 있는 도면) 카메라 각도를 그대로 둔다 —
  /// 틀린 방향으로 돌리는 것보다 안 돌리는 편이 낫다.
  Future<void> _aimCameraAtEscalatorExit({
    required ll.LatLng? from,
    required ll.LatLng? to,
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    if (to == null) {
      // 하차 지점을 모르면 적어도 새 층 경로는 보여 준다(예전 동작).
      final segment = _indoorRouteSegment;
      if (segment != null) await _fitCameraToRouteSegment(segment);
      return;
    }
    final camera = controller.cameraPosition;
    final bearing = from == null
        ? null
        : escalatorExitBearingDeg(boarding: from, arrival: to);
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toGl(to),
          zoom: math.max(camera?.zoom ?? _walkingViewZoom, _walkingViewZoom),
          bearing: bearing ?? camera?.bearing ?? 0,
          tilt: camera?.tilt ?? 0,
        ),
      ),
      // 하차 지점이 화면에 자리 잡는 시간. 마커는 기압 진행률로 따로 흐르지만
      // 카메라까지 하차 확정을 기다리면 타는 내내 화면 구도가 안 잡힌다.
      duration: escalatorGlideDuration,
    );
  }

  /// 디버그 모드에서 강제로 태울 수 있는 다음 환승(지금 층 세그먼트 + 도착 층).
  /// 없으면 null.
  ///
  /// 지금 층 세그먼트에 **에스컬레이터** 환승이 붙어 있을 때만이다. 판정기
  /// ([EscalatorTransitionDetector])가 에스컬레이터 전용이라, 엘리베이터 환승을
  /// 강제로 태우면 실제로는 나올 수 없는 화면을 검증하게 된다.
  ({IndoorRouteSegment segment, String nextFloorLabel})?
  get _debugForceableTransfer {
    final multi = _indoorMultiFloorRoute;
    final floor = _activeFloor;
    if (multi == null || floor == null) return null;
    final i = multi.segments.indexWhere((s) => s.floorName == floor);
    if (i < 0 || i + 1 >= multi.segments.length) return null;
    final seg = multi.segments[i];
    if (seg.transferModeToNext != 'escalator') return null;
    if (seg.transferFromNodeId == null) return null;
    return (segment: seg, nextFloorLabel: multi.segments[i + 1].floorName);
  }

  /// 반 층을 지났다. 목적 층 지도를 먼저 연다(하차는 아직).
  Future<void> _beginEscalatorTransition(EscalatorTransition transition) async {
    if (_applyingFloorTransition) return;
    final building = _building;
    if (building == null) return;
    if (!building.floors.contains(transition.toFloorLabel)) return;
    if (_activeFloor != transition.fromFloorLabel) {
      // 판정 중에 사용자가 층 선택기로 다른 층을 열었다. 어느 층 기준인지
      // 모호해졌으므로 적용하지 않는다.
      return;
    }

    _applyingFloorTransition = true;
    try {
      _preTransferFloor = _activeFloor;
      _preTransferRoute = _indoorRouteSegment;
      _preTransferMultiRoute = _indoorMultiFloorRoute;
      _preTransferDestination = _indoorRouteDestination;
      final completion = _currentIndoorCompletionSnapshot();
      _pendingTransferCompletedScope = completion?.scopeId;
      _pendingTransferCompleted = completion?.points;

      // 보통은 verticalMotionDetected에서 이미 멈췄다. 수직 속도 근거 없이
      // 누적 고도만으로 여기 도달한 경우를 위해 한 번 더 보장한다(idempotent).
      await _pauseStepsForRide();
      if (!mounted) return;
      setState(() {
        _escalatorRide = transition;
        _escalatorStage = null;
      });

      if (!await _swapIndoorFloorForRide(transition)) {
        _discardPendingTransferCompletion();
        await _endEscalatorRide();
        if (mounted) {
          _showSnack('${transition.toFloorLabel} 지도를 불러오지 못했습니다. 현재 층을 유지합니다.');
        }
        return;
      }
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 하차가 확정됐다. 새 층 도착 노드로 앵커를 옮기고 경로를 다시 잡는다.
  Future<void> _completeEscalatorTransition(
    EscalatorTransition transition,
  ) async {
    if (_applyingFloorTransition) return;
    _applyingFloorTransition = true;
    try {
      // 후보 단계 없이 바로 확정되는 기기/상황도 있다. 그 경우에도 층을 바꾸기
      // 전에 현재 층의 완료 구간을 떠 둬야 새 그래프가 덮어쓰지 못한다.
      if (_pendingTransferCompleted == null) {
        final completion = _currentIndoorCompletionSnapshot();
        _pendingTransferCompletedScope = completion?.scopeId;
        _pendingTransferCompleted = completion?.points;
      }
      if (_activeFloor != transition.toFloorLabel) {
        // 조기 전환 없이 바로 확정된 경우(후보와 확정이 거의 동시).
        if (!await _swapIndoorFloorForRide(transition)) {
          _discardPendingTransferCompletion();
          await _endEscalatorRide();
          if (mounted) {
            _showSnack(
              '${transition.toFloorLabel} 지도를 불러오지 못했습니다. 현재 층을 유지합니다.',
            );
          }
          return;
        }
      }
      // 하차가 확정됐다 — 진행률 1.0은 오직 여기서 채워진다. 표시값은 틱마다
      // 따라붙어(시정수 0.5초) 마커가 도착 노드에 부드럽게 닿는다.
      _escalatorRideTargetProgress = 1;
      // 이 그룹의 실측 층고를 기억한다. 다음 탑승부터 진행률이 기본값(5.8m)이
      // 아니라 이 에스컬레이터의 실제 높이로 정규화된다.
      if (transition.deltaM.abs() > 1.0) {
        _escalatorGroupHeightM[transition.group] = transition.deltaM.abs();
      }
      final graph = _floorGraph;
      final arrival =
          _pendingArrivalNode ?? findEscalatorArrivalNode(graph, transition);
      if (graph == null || arrival == null) {
        _discardPendingTransferCompletion();
        // 도착 지점을 못 찾아도 **탑승 상태는 반드시 끝낸다.** 안 그러면 배너가
        // 남고 걸음 누적이 영영 멈춘 채로 사용자가 복구할 방법이 없다.
        await _endEscalatorRide();
        if (!mounted) return;
        setState(() => _pendingArrivalNode = null);
        _showSnack(
          '${transition.toFloorLabel} 도착 지점을 찾지 못했습니다. '
          '하단 "위치 지정"으로 현재 위치를 찍어주세요.',
        );
        return;
      }

      setState(() {
        // 이전 층 궤적과 복도 보정 상태는 새 층에서 이어지지 않는다.
        _pdrTrailState.beginNewSession();
        _guidance.resetTracking();
      });
      await indoorNavigationDriver.applyVerticalTransfer(
        floorId: transition.toFloorLabel,
        anchorLocalM: PdrLocalPoint(arrival.xM, arrival.yM),
        axes: fitPdrToFloorAxes(graph.nodes),
      );
      if (!mounted) return;
      // 하차했으므로 걸음 누적을 다시 켠다. applyVerticalTransfer가 경로 원점을
      // 옮긴 **뒤에** 켜야 탑승 중 걸음이 새 층 원점에 붙지 않는다.
      await _endEscalatorRide();
      if (!mounted) return;
      // 층 전환이 확정된 순간에만 이전 층의 완료 구간을 history로 승격한다.
      // 후보 단계에서 저장하지 않아, 잘못된 에스컬레이터 판정으로 되돌아가도
      // 회색선이 앞서 생기지 않는다.
      _commitPendingTransferCompletion();
      setState(() => _pendingArrivalNode = null);

      await _rerouteAfterVerticalTransfer(
        arrivalNodeId: arrival.id,
        floor: transition.toFloorLabel,
      );
      if (!mounted) return;

      // 별도 토스트를 띄우지 않는다. 배너가 이미 같은 자리에서 같은 사실을
      // 말하고 있어서, 확정 순간에 토스트가 겹치면 같은 내용이 두 벌이 된다.
      _escalatorArrivalTimer?.cancel();
      setState(() => _escalatorArrival = transition);
      _escalatorArrivalTimer = Timer(_indoorArrivalBannerHold, () {
        if (!mounted) return;
        setState(() => _escalatorArrival = null);
      });
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 반 층 후보가 되돌아가거나 타임아웃되면 화면·경로를 탑승 전으로 복원한다.
  Future<void> _cancelEscalatorTransition(
    EscalatorTransition transition,
  ) async {
    final floor = _preTransferFloor;
    _discardPendingTransferCompletion();
    await _endEscalatorRide();
    if (!mounted) return;
    if (floor == null) return;
    if (_activeFloor != floor) {
      // 잘못 열린 목적 층을 원래 층으로 되돌린다. 사람 조작과 같은
      // 크로스페이드를 쓴다 — 되돌리기는 사용자가 인지해야 하는 전환이 아니라
      // 없던 일로 만드는 것이라, 안내 전환처럼 늦출 이유가 없다.
      await _switchOverlayFloorCrossfaded(floor);
      if (!mounted) return;
    }
    setState(() {
      _guidance
        ..setRouteSegment(_preTransferRoute)
        ..clearProgress()
        ..setRoute(_preTransferMultiRoute);
      _indoorMultiFloorRoute = _preTransferMultiRoute;
      _indoorRouteDestination = _preTransferDestination;
      _pendingArrivalNode = null;
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _clearTransferRouteBackups();
  }

  /// 새 층에서 목적지까지 경로를 다시 뽑는다.
  Future<void> _rerouteAfterVerticalTransfer({
    required String arrivalNodeId,
    required String floor,
  }) async {
    await _recomputeRouteFrom(nodeId: arrivalNodeId, floor: floor);
    if (!mounted) return;
    _clearTransferRouteBackups();
  }

  /// 전환 직전 백업을 버린다. 확정으로 끝났든 취소로 끝났든, 이 이동에 대해
  /// 되돌릴 것은 더 남아 있지 않다.
  void _clearTransferRouteBackups() {
    _preTransferRoute = null;
    _preTransferMultiRoute = null;
    _preTransferDestination = null;
    _preTransferFloor = null;
  }

  void _commitPendingTransferCompletion() {
    final scope = _pendingTransferCompletedScope;
    final points = _pendingTransferCompleted;
    if (scope != null && points != null && points.length >= 2) {
      _completedRouteHistory.append(scopeId: scope, points: points);
    }
    _pendingTransferCompletedScope = null;
    _pendingTransferCompleted = null;
  }

  void _discardPendingTransferCompletion() {
    _pendingTransferCompletedScope = null;
    _pendingTransferCompleted = null;
  }
}
