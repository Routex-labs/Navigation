// ignore_for_file: invalid_use_of_protected_member
//
// 이 파일은 `OutdoorMapBodyState`의 part다. setState는 그 클래스가 State에서
// 물려받은 protected 멤버이고, 여기서 부르는 것은 **같은 클래스의 코드**다 —
// 파일만 갈라져 있을 뿐 바깥에서 남의 protected 멤버를 건드리는 것이 아니다.
// 분석기는 extension을 "서브클래스가 아니다"로 보아 경고하므로 파일 단위로
// 끈다. 본체(생명주기·build)는 클래스 안에 있어 이 해제의 영향을 받지 않는다.
/// `OutdoorMapBodyState`의 **실내 오버레이·층·매장** 부분.
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

extension OutdoorMapIndoor on OutdoorMapBodyState {
  /// 지금 보고 있는 층을 상위에 알린다. 실내 오버레이가 꺼져 있으면 층 개념이
  /// 없으므로 null이다 — 층·진입 상태 둘 중 하나만 바뀌어도 결과가 달라지므로
  /// 양쪽 변경 지점에서 모두 부른다.
  void _notifyActiveFloor() {
    final floor = _indoorEntered ? _activeFloor : null;
    if (_notifiedFloor == floor) return;
    _notifiedFloor = floor;
    widget.onFloorChanged?.call(floor);
  }

  /// 다음 자동 재시도를 예약한다. 이미 예약돼 있거나 사다리를 다 썼으면 아무
  /// 것도 하지 않는다.
  void _scheduleBuildingRetry() {
    if (_buildingRetryTimer != null) return;
    if (_buildingRetryAttempt >= _buildingRetryDelays.length) return;
    final delay = _buildingRetryDelays[_buildingRetryAttempt++];
    _buildingRetryTimer = Timer(delay, () {
      _buildingRetryTimer = null;
      // 사람이 누른 재시도가 도는 중이면 그 결과를 기다린다. 실패하면 그쪽이
      // 다시 사다리를 이어 준다.
      if (!mounted || _retryingBuildingLoad) return;
      unawaited(_loadBuildingEntrance());
    });
  }

  Future<void> _retryBuildingLoad() async {
    if (_retryingBuildingLoad) return;
    // 사람이 직접 눌렀다는 것은 "지금은 될 것 같다"는 신호다. 사다리를 처음
    // 부터 다시 쓸 수 있게 되돌려, 이번에도 실패하면 짧은 간격부터 다시 시도한다.
    _buildingRetryTimer?.cancel();
    _buildingRetryTimer = null;
    _buildingRetryAttempt = 0;
    setState(() => _retryingBuildingLoad = true);
    await _loadBuildingEntrance();
    if (!mounted) return;
    setState(() => _retryingBuildingLoad = false);
  }

  /// 실내 진입 중에는 PDR 세션을 켜 둔다.
  ///
  /// anchor가 없으면 위치를 도면에 놓을 수 없지만, 센서를 미리 돌려두면 사용자가
  /// 위치를 지정하는 순간 heading이 이미 수렴한 상태다. 권한이 거부돼 있으면
  /// 자동 시작을 시도하지 않는다 — 진입마다 재시도하면 degraded warning만 쌓인다.
  /// 실내 위치를 통째로 버린다 — 앵커, 걸음 궤적, 복도 보정, 실내 경로.
  ///
  /// 사용자가 건물을 나갔다고 GPS가 판정했을 때만 부른다. 넷을 **함께** 비우는
  /// 것이 중요하다. 하나라도 남으면 야외 지도 위에 실내의 흔적이 남는다.
  ///
  ///   - 앵커를 안 버리면 다시 도면을 열었을 때 걸어 본 적 없는 자리에서 시작한다.
  ///   - 궤적을 안 버리면 야외 지도에 실내에서 걸은 초록 선이 그대로 얹혀 있다.
  ///   - PDR 세션을 안 끄면 **밖에서 걷는 걸음이 실내 좌표계에 계속 쌓인다.**
  ///     사용자가 신고한 "나갔는데도 실내에서 계속 움직이며 경로가 그려진다"가
  ///     이것이다.
  ///   - 실내 경로를 안 버리면 목적지가 건물 안이던 안내가 야외 화면에 남는다.
  ///
  /// 세션 정지는 여기서 기다리지 않는다 — 화면 상태는 지금 즉시 맞아야 한다.
  /// 대신 그 Future를 [_pdrLifecycle]이 들고 있다가 다음 시작이 기다리게 한다.
  /// 이유는 [PdrSessionLifecycle.awaitStop] 주석에 있다.
  void _dropIndoorPosition() {
    _pdrTrailState.beginNewSession();
    _syncCorridorTracking(null);
    _clearIndoorRoute();
    _pdrLifecycle.stopWithoutWaiting();
  }

  /// 활성 층의 통행 그래프와 매장 목록(FloorPlan)을 함께 로드한다.
  /// - 그래프: PDR 앵커 배치·스냅과 마커 렌더링에 쓰인다.
  /// - 평면도: 실내 오버레이 위 매장 폴리곤 탭으로 벡터 타일 feature id를
  ///   실제 매장 정보로 되돌리는 데 쓴다.
  /// 실패는 조용히 넘겨 그래프/평면도 없이 층 시각화만 유지한다.
  Future<void> _loadFloorGraph(String buildingId, String floor) =>
      _floorGraphLoad = _fetchFloorGraph(buildingId, floor);

  Future<void> _fetchFloorGraph(String buildingId, String floor) async {
    try {
      final geojson = await buildingRepository.getFloorGeoJson(
        buildingId,
        floor,
      );
      // **추월당한 응답은 버린다.** 층을 연달아 바꾸면 요청이 겹치는데,
      // 저장소가 층별 future를 캐시하므로 이미 가 본 층은 즉시, 처음 가는
      // 층은 네트워크 시간 뒤에 도착한다 — 나중에 도착한 이전 층 응답이
      // 지금 층의 도면·그래프를 덮어쓰면, 화면에 그려진 층과 [_floorPlan]이
      // 어긋난다. 그 상태로는 카메라 fit이 엉뚱한 외곽선에 맞고(지하층 정렬
      // 이상), 매장 탭이 feature id를 다른 층 목록에서 찾다 실패하며(탭 불능
      // + 건물 파란 반짝임만 남음), 검색 포커스도 매장을 못 찾는다.
      if (!mounted || _activeFloor != floor) {
        debugPrint(
          '[outdoor overlay] 층 도면 버림: 요청=$floor 지금=$_activeFloor '
          'mounted=$mounted',
        );
        return;
      }
      final graphJson = geojson?['navigation_graph'];
      final graph = graphJson is Map<String, dynamic>
          ? FloorGraph.fromJson(graphJson)
          : null;
      final plan = geojson != null ? FloorPlan.fromJson(geojson) : null;
      setState(() {
        _floorGraph = graph;
        _floorPlan = plan;
        _mapCalibrationVersion =
            geojson?['map_calibration_version'] as String? ?? 'unversioned';
      });
      _syncCorridorTracking(_pdrTrailState.snapshot);
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
      // 층 외곽선은 방금 받은 도면에서 나온다(어느 층이든 — [floorOutlineRing]).
      // 도면이 도착한 이 시점에 한 번 더 그려야 층을 바꾼 직후의 빈 외곽선이
      // 채워진다.
      unawaited(_syncFloorOutlineLayer());
      _syncDimScrimLayer();
      // 도면이 없어서 미뤄 둔 카메라 fit이 이 층 것이면 지금 실행한다
      // ([_pendingFloorFit]). 이 자리가 "그 층 외곽선이 처음으로 존재하는"
      // 시점이라, 여기서 맞춰야 배율이 정확히 한 번에 잡힌다.
      final pending = _pendingFloorFit;
      if (pending != null && pending.floor == floor) {
        _pendingFloorFit = null;
        // 이 함수 자체가 `_floorGraphLoad`라서, 기다리는 껍데기를 부르면
        // 자기 자신을 기다린다 — 몸통을 직접 부른다.
        unawaited(_fitCameraToLoadedFloor(pending.duration));
      }
    } catch (error, stackTrace) {
      // 로드 실패 시 앵커 배치·매장 탭은 안내로 막고 나머지 야외 지도 동작은
      // 그대로 유지한다. 성공 경로와 같은 이유로, 추월당한 요청의 실패가
      // 지금 층의 도면을 지우면 안 된다.
      //
      // **삼키되 조용하지는 않게 한다.** 여기서 터지면 층 외곽선·매장 탭·카메라
      // fit이 한꺼번에 죽는데, 화면에는 "실내 기능만 없는" 상태로만 보여서
      // 원인을 화면 밖에서 찾을 단서가 하나도 없다.
      debugPrint('[outdoor overlay] 층 도면 로드 실패($floor): $error\n$stackTrace');
      if (mounted && _activeFloor == floor) {
        setState(() {
          _floorGraph = null;
          _floorPlan = null;
          _mapCalibrationVersion = 'unversioned';
        });
        unawaited(_syncFloorOutlineLayer());
        _syncDimScrimLayer();
      }
    }
  }

  /// 층 chip 탭·자동 실내 진입 뒤에 실내 오버레이를 보장 노출하기 위한 헬퍼.
  /// - 카메라 zoom이 이탈 임계값 미만(=도면이 사실상 안 보임)이면 진입 임계값
  ///   + 건물 중심으로 이동.
  /// - 카메라가 건물 중심에서 크게 벗어나 있으면 zoom 유지한 채 건물 중심으로 이동.
  /// - 두 조건 모두 아니면 아무 것도 하지 않는다(사용자의 현재 view 존중).
  Future<void> _recenterOnBuildingIfNeeded() async {
    final controller = _mapController;
    final footprint = _buildingFootprint;
    if (controller == null || footprint == null || footprint.length < 3) {
      return;
    }
    final cam = controller.cameraPosition;
    if (cam == null) return;
    final center = _buildingCenter(footprint);
    if (center == null) return;

    // 이탈 임계값 기준으로 판정한다. 진입 임계값(17.5)으로 재면, 넓은 지하층
    // 전체를 담으려고 z≈16.05까지 축소해 둔 사용자가 층 chip을 누르는 순간
    // 카메라가 다시 17.5로 튀어올라 방금 맞춘 view를 빼앗긴다.
    final needZoomIn = cam.zoom < indoorExitZoomThreshold;
    // 건물 중심에서 카메라까지 대략적인 거리. 위경도 도 단위지만 근사적으로
    // 계산해 "화면 밖" 판정에만 쓴다 — 정확한 거리 계산은 필요 없다.
    final distDeg = math.sqrt(
      math.pow(cam.target.latitude - center.latitude, 2) +
          math.pow(cam.target.longitude - center.longitude, 2),
    );
    // 대략 300m 이상 떨어져 있으면 화면 밖으로 간주(37°에서 0.003° ≈ 300m).
    final farFromBuilding = distDeg > 0.003;

    if (!needZoomIn && !farFromBuilding) return;

    // 확대해 줄 때의 목표 zoom도 화면 폭에 맞춘 임계값을 쓴다. 고정 17.5로
    // 올리면 폰에서는 건물이 화면 밖으로 넘치게 확대돼, 포커스를 맞췄는데
    // 오히려 건물이 안 보이게 된다.
    final targetZoom = needZoomIn ? _entryZoomThreshold() : cam.zoom;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(center), targetZoom),
    );
  }

  ll.LatLng? _buildingCenter(List<ll.LatLng> footprint) {
    if (footprint.isEmpty) return null;
    var minLat = double.infinity, maxLat = double.negativeInfinity;
    var minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in footprint) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  /// 실내(PDR) 위치를 화면과 길찾기에 써도 되는 상태인지 — [_outdoorGpsVisible]의
  /// 반대쪽 짝이다. 두 값은 **동시에 true가 되지 않는다**: 실내 오버레이가 켜져
  /// 있으면 PDR만, 야외 상태면 GPS만 쓴다.
  ///
  /// 이 구분이 없으면 실내에서 위치를 지정한 뒤 축소해 야외로 나왔을 때, 야외
  /// 지도 위에 실내 위치 아이콘이 그대로 남고(도면은 페이드로 사라졌는데 파란
  /// 점만 공중에 떠 있는 상태) 길찾기 출발지도 그 실내 앵커로 잡힌다. 야외에서는
  /// GPS가 위치의 유일한 출처여야 한다.
  bool get _indoorLocationVisible => _indoorEntered;

  /// 위치 한 건이 말하는 건물 안팎을 상태에 반영한다.
  ///
  /// 판정 자체는 [judgeBuildingFromGps]가 하고, 여기서는 **그 판정으로 무엇을
  /// 할지**만 정한다. 셋으로 갈린다.
  ///
  ///   - 안 + 야외 상태 + 자동 진입 무장 → 실내로 들어가고 위치를 잡는다.
  ///   - 밖 + **실내에 실제로 있던 사람** → 야외로 되돌린다. 자동 진입을 다시
  ///     무장하는 것도 여기서 한다.
  ///   - 모름 → 아무것도 하지 않는다.
  ///
  /// ## "실내에 실제로 있던 사람"을 어떻게 가리는가
  ///
  /// 예전에는 [_indoorEnteredByGps]로 갈랐다 — GPS가 들여보낸 경우에만 GPS가
  /// 내보낸다는 규칙이다. 그래야 길 건너에서 층 도면을 훑어보려던 사람의 화면이
  /// 좌표가 들어오는 순간 제멋대로 닫히지 않는다.
  ///
  /// 그런데 그 규칙은 **걸어서 들어온 사람을 놓친다.** 건물을 탭하거나 확대해서
  /// 도면을 연 뒤 실제로 안을 걸어 다닌 사용자가 밖으로 나와도 실내 상태가
  /// 유지되고, PDR이 계속 걸음을 쌓아 야외에 실내 궤적이 그려진다.
  ///
  /// 그래서 기준을 **"실내 위치가 잡혀 있는가"**([_indoorPositionPlaced])로
  /// 넓힌다. PDR 앵커가 있다는 것은 이 사람이 건물 안 어딘가에 서 있다고 앱이
  /// 믿고 있다는 뜻이고, 그 믿음은 밖으로 나온 순간 틀린 것이 된다. 반대로
  /// 도면만 구경하는 사용자는 앵커가 없으므로 예전처럼 화면이 안 닫힌다.
  void _applyBuildingVerdict(Position position, {Duration? sinceLastFix}) {
    final judgement = judgeBuildingFromGps(
      fix: GpsFix(
        point: ll.LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
      ),
      footprint: _buildingFootprint,
    );
    // 진단 칩은 아래 switch가 상태를 바꾸기 **전에** 채운다. 무장 여부는 이 판정을
    // 내릴 때의 값이어야 하는데, switch가 그 값을 갱신하기 때문이다.
    _gpsVerdictDebugText.value = _debugModeController.enabled
        ? describeGpsBuildingJudgement(
            judgement,
            armed: _gpsEntryArmed,
            sinceLastFix: sinceLastFix,
            fromStream: _gps.lastFixFromStream,
            streamRestarts: _gps.restartCount,
          )
        : null;
    switch (judgement.verdict) {
      case GpsBuildingVerdict.inside:
        if (_indoorEntered || !_gpsEntryArmed) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('건물 감지 중...')));
        // _setIndoorEntered가 이 표식을 보므로 **먼저** 세운다.
        _indoorEnteredByGps = true;
        _setIndoorEntered(true);
        unawaited(_startTrackingFromGpsFix(position));
      case GpsBuildingVerdict.outside:
        // 건물을 확실히 벗어났다. 다음 진입을 다시 자동으로 잡을 수 있게 한다.
        _gpsEntryArmed = true;
        if (!_indoorEntered) return;
        if (!_indoorEnteredByGps && !_indoorPositionPlaced) return;
        // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
        if (_placingPdrAnchor) _setPlacingAnchor(false);
        // **이 자리가 유일하게 "정말로 나갔다"고 말할 수 있는 곳이다.**
        // 실내 위치를 버리는 것도, 실내→야외 안내의 야외 구간을 올리는 것도
        // 여기서만 일어난다([_setIndoorEntered]의 leftBuilding).
        _setIndoorEntered(false, leftBuilding: true);
        // 위치의 주인이 GPS로 돌아온 순간이다. 마커는 [_setIndoorEntered] 안의
        // [_syncCurrentLayer]가 이미 켰지만, 카메라는 아직 건물을 보고 있다.
        // 실내에서 도면에 맞춰 확대해 둔 화면 그대로라 방금 켠 GPS 마커가 화면
        // 밖일 수 있다 — 사용자 눈에는 "나왔는데 내 위치가 없다"로 보인다.
        //
        // 들어올 때 카메라가 건물로 붙는 것과 대칭이다. 나가면 나를 따라온다.
        unawaited(_moveCameraToUser(position));
      case GpsBuildingVerdict.unclear:
        break;
    }
  }

  /// arbitrary reference 기기에서 쓸 "진입 방향"을 층 좌표 벡터로 만든다.
  /// 층 좌표계는 데이터셋마다 축이 뒤집혀 있을 수 있어, 나침반 각도는 반드시
  /// [axes]를 거쳐 층 벡터로 바꾼다.
  PdrLocalPoint? _entryFloorDirection({
    required Position position,
    required PdrLocalPoint anchorFloorPoint,
    required FloorGraph graph,
    required PdrToFloorAxes axes,
  }) {
    // 1순위: GPS course. 실제로 측정된 이동 방향이라 가장 정확하다. 다만 멈춰
    // 있을 때는 값이 의미 없고 플랫폼이 0으로 채우므로 속도로 먼저 거른다.
    final course = position.heading;
    if (position.speed >= entryCourseMinSpeedMps &&
        course > 0 &&
        course < 360) {
      return axes.apply(pdrDirectionForBearing(course));
    }
    // 2순위: 입구 → 층 그래프 중심. 입구를 통과한 사람은 건물 안쪽을 향한다.
    // GPS course보다 거칠지만, 방향을 몰라 awaitingHeading에 멈춰 서면 앵커가
    // 확정되지 않아 위치 아이콘도 걸음 추적도 아예 없다. 회전이 어긋나면
    // 사용자가 "위치 지정"으로 다시 잡을 수 있으므로 되돌릴 수 있는 오차다.
    var sumX = 0.0;
    var sumY = 0.0;
    for (final node in graph.nodes) {
      sumX += node.xM;
      sumY += node.yM;
    }
    final dx = sumX / graph.nodes.length - anchorFloorPoint.eastM;
    final dy = sumY / graph.nodes.length - anchorFloorPoint.northM;
    // 입구가 그래프 중심과 사실상 같은 점이면 방향 벡터가 0이 된다.
    if (dx * dx + dy * dy < 1e-6) return null;
    return PdrLocalPoint(dx, dy);
  }

  /// 좌표열 전체가 화면에 들어오도록 카메라를 맞춘다. 도보 경로와 대중교통
  /// 경로가 같은 여백 규칙을 쓰도록 뽑아 두었다 — 값이 갈리면 안내를 바꿀
  /// 때마다 경로가 화면에서 다른 크기로 잡힌다.
  void _fitCameraToPoints(List<ll.LatLng> points) {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    unawaited(animateCameraToPoints(controller, points));
  }

  String? _pickStartNodeIdInBuildingGraph({
    required BuildingGraph graph,
    required String startFloorName,
    String? excludingNodeId,
  }) {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != startFloorName) return null;
    // 앵커의 floorId는 사람이 보는 층 라벨이고, 그래프 노드의 floorId는 내부
    // Floor.id다. floorNamesById로 매핑해 그 층의 노드만 후보로 쓴다.
    final floorId = graph.floorNamesById.entries
        .firstWhere(
          (entry) => entry.value == startFloorName,
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (floorId.isEmpty) return null;
    final candidates = graph.nodes
        .where((node) => node.floorId == floorId)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return _nearestNodeId(
      candidates,
      anchor.anchorLocalM.eastM,
      anchor.anchorLocalM.northM,
      excludingNodeId: excludingNodeId,
    );
  }

  Future<void> _syncBuildingLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncPolygonSource(
      controller,
      kOutdoorBuildingSourceId,
      _buildingFootprint,
    );
    // 건물 footprint가 바뀌면 dim scrim의 hole과 층 외곽선도 함께 갱신해야 한다.
    _syncDimScrimLayer();
    _syncFloorOutlineLayer();
  }

  /// 지금 "층 경계"로 삼아야 하는 링. 어느 층이든 그 층 도면의 외곽선이고,
  /// 실내에 들어가 있지 않거나 도면이 아직 없으면 null이다. 규칙과 근거(특히
  /// 지상층에서도 건물 외곽선을 쓰지 않는 이유)는 [floorOutlineRing] 참고.
  ///
  /// 외곽선·dim scrim hole·건물 안 탭 판정이 **모두 이 하나를 본다.** 셋이 서로
  /// 다른 링을 쓰면 사용자가 보는 선 안쪽이 어두워지거나(scrim), 선 안쪽을
  /// 탭했는데 야외로 튕겨 나가는(탭 판정) 모순이 생긴다.
  List<ll.LatLng>? _activeFloorOutlineRing() => floorOutlineRing(
    indoorEntered: _indoorEntered,
    floorFootprint: _floorPlan?.footprint,
  );

  /// 현재 층 외곽선 갱신. 그릴 링이 없으면 소스를 비워 선을 지운다 — 레이어
  /// 속성은 건드리지 않는다(등록 시 넣은 값 그대로 쓴다).
  Future<void> _syncFloorOutlineLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncPolygonSource(
      controller,
      kOutdoorFloorOutlineSourceId,
      _activeFloorOutlineRing(),
    );
  }

  /// 지금 선택에 해당하는 MapLibre 필터 표현식. 선택이 없으면 아무것도 맞지
  /// 않는 필터를 돌려준다. 레이어 등록 시점과 갱신 시점이 같은 함수를 쓰게 해서
  /// 한쪽만 고쳐 어긋나는 일을 막는다(indoor_overlay_layers.dart의 "등록과
  /// 갱신이 같은 함수를 쓴다" 규칙과 같은 이유).
  List<Object> _categoryFilterExpression() {
    final selection = widget.categorySelection;
    if (selection == null) return kCategoryHighlightNoneFilter;
    return categoryHighlightFilter(selection);
  }

  /// 선택이 바뀌었을 때 오버레이에 그 선택을 반영한다.
  ///
  /// 두 가지가 바뀐다 — **어느 매장이 색으로 강조되는가**(강조 fill의 필터)와
  /// **어느 매장이 이름을 다는가**(라벨의 `text-field`).
  ///
  /// 강조 fill은 `setLayerProperties`가 아니라 `setFilter`를 쓴다 — 전자는 넘기지
  /// 않은 속성까지 null로 함께 보내 스펙 기본값(fill-color는 검정)으로 되돌리므로
  /// 실기기에서 지도가 검게 덮인다(indoor_overlay_layers.dart 상단 주석). 라벨은
  /// 바뀌는 것이 필터가 아니라 layout 속성이라 그 경로를 쓸 수 없고, 대신
  /// [indoorStoresLabelProps]·[indoorFacilityLabelProps]가 **전체 속성**을 다시
  /// 만들어 넘긴다.
  Future<void> _applyCategoryFilter() async {
    final controller = _mapController;
    if (controller == null || !_styleReady || !_indoorTilesRegistered) return;
    // 층 전환과 겹치면 이미 제거된 레이어를 가리킬 수 있다. 페이드 갱신과 같은
    // 이유로 삼킨다 — 다음 등록이 어차피 현재 선택으로 필터를 넣어 준다.
    try {
      await controller.setFilter(
        _indoorIds.categoryHighlightFill,
        _categoryFilterExpression(),
      );
    } catch (_) {}
    await syncIndoorOverlayProps(
      controller,
      ids: _indoorIds,
      fadeExpr: _overlayFadeExpr(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
      // fill·아이콘은 카테고리 선택과 무관하다. 라벨만 다시 민다.
      scope: IndoorOverlaySyncScope.labels,
    );
  }

  /// 실내 오버레이 **레이어**용 페이드 표현식 — [_fadeExpr]에 층 전환
  /// 크로스페이드 계수([_indoorOverlayFadeFactor])를 곱한 것. 오버레이 레이어
  /// 속성을 쓰는 모든 경로(등록·페이드 갱신·카테고리 필터·크로스페이드 단계)가
  /// 이걸 써야 페이드 도중 끼어든 갱신이 계수를 되돌리지 않는다. 건물 단위
  /// dim scrim은 층 전환과 무관하므로 [_fadeExpr]를 그대로 쓴다.
  ///
  /// 곱셈을 `['*', ...]`로 감싸지 않고 램프 끝 스톱에 곱해 넣는 이유
  /// (native의 top-level zoom 제약)는 [indoorOverlayCrossfadeExpr]에 있다.
  List<Object> _overlayFadeExpr() {
    final factor = _indoorOverlayFadeFactor;
    if (factor >= 1) return _fadeExpr();
    return indoorOverlayCrossfadeExpr(
      entered: _indoorEntered,
      crossfadeFactor: factor,
    );
  }

  /// 실내 진입/이탈로 페이드 구간이 바뀌었을 때 이미 등록된 오버레이 레이어의
  /// opacity 표현식을 갈아 끼운다. 레이어가 아직 등록되지 않았으면
  /// [_ensureIndoorTilesRegistered]가 등록 시점의 상태로 넣어주므로 아무것도
  /// 하지 않아도 된다.
  ///
  /// **각 레이어의 전체 속성을 매번 다시 넘긴다.** opacity만 넘기면 안 된다 —
  /// 이유는 indoor_overlay_layers.dart 상단 주석 참고.
  Future<void> _syncIndoorOverlayFade() async {
    final controller = _mapController;
    if (controller == null || !_styleReady || !_indoorTilesRegistered) return;
    await syncIndoorOverlayProps(
      controller,
      ids: _indoorIds,
      fadeExpr: _overlayFadeExpr(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
    );
  }

  /// 지도에서 탭한 위경도가 건물 footprint 내부인지 판정한다.
  /// 판정 자체는 [isPointInPolygon]에 있다 — 실내 진입 근접 판정
  /// ([isIndoorBuildingNearCamera])과 같은 계산을 써야 "탭은 건물 안인데 근접은
  /// 아니다" 같은 모순이 생기지 않는다.
  ///
  /// 실내 진입 중이면 그 층 외곽선 안쪽도 "건물 안"으로 본다. 화면에 그려진
  /// 외곽선 안을 탭했는데 야외로 튕겨 나가면(지하처럼 건물 외곽선 밖까지 뻗은
  /// 층이 있다) 사용자 입장에서는 도면 위를 눌렀을 뿐이다. 두 링의 **합집합**을
  /// 보므로 야외에서의 판정은 지금까지와 같다.
  bool _isInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint != null && isPointInPolygon(point, footprint)) return true;
    final ring = _activeFloorOutlineRing();
    return ring != null && isPointInPolygon(point, ring);
  }

  /// 실내 진입 오버레이를 켜는 테스트 진입점.
  ///
  /// 실기기에서는 GPS·줌·건물 탭이 [_setIndoorEntered]를 부르는데, 그 셋 다
  /// 건물 폴리곤과 입구 좌표가 있어야 한다. 그래프만 있는 fixture로 실내 동작을
  /// 검증하려는 테스트는 그 준비를 할 수 없으므로, 실기기가 지나는 것과 **같은
  /// 함수**를 직접 부른다.
  @visibleForTesting
  void enterIndoorForTest() => _setIndoorEntered(true);

  /// 건물을 탭해 들어온 직후, 도면이 화면을 채우도록 카메라를 끌어온다.
  ///
  /// **한 번에 갈아 끼우지 않고 애니메이션으로 간다.** 배율이 즉시 튀면 지도가
  /// 다른 장소로 순간이동한 것처럼 보여서, 사용자가 방금 누른 건물과 지금 보는
  /// 도면이 같은 곳이라는 연결이 끊긴다. 확대되는 과정을 보여 주면 그 연결이
  /// 눈으로 이어진다.
  ///
  /// **지도도 함께 돌린다.** 건물은 정북 기준 아무 방향으로나 앉아 있어서(더현대
  /// 서울은 약 53도), 북쪽을 위로 둔 채 확대하면 도면이 화면에 비스듬히 누워
  /// 들어온다. 세로로 긴 폰 화면에 누운 사각형을 담는 꼴이라 좌우가 남고 도면은
  /// 그만큼 작아진다. 건물의 긴 축을 화면 세로에 맞추면 같은 배율에서 도면이
  /// 훨씬 크게 들어오고, 폰을 든 방향과 건물 축도 나란해진다.
  ///
  /// 배율은 **돌려 세운 상자**를 화면에 맞춘 값이다([zoomToFitRotatedBox]).
  /// 다만 진입 임계값보다 아래로는 내려가지 않게 잡는다 — 그 아래로 가면 도착한
  /// 뒤 [_handleCameraIdle]이 이탈로 판정해 방금 연 도면이 도로 닫힌다.
  /// 지금 보고 있는 **층 도면**이 화면을 채우도록 카메라를 맞춘다.
  ///
  /// 기준은 건물 외곽선이 아니라 **그 층의 외곽선**이다. 층마다 크기가 크게
  /// 다르기 때문이다 — 더현대 서울은 지상층이 약 180 x 190 m인데 B3·B4는
  /// 286 x 305 m다. 건물 외곽선 하나로 맞춰 두면 지상층에서는 여백이 남고
  /// 지하로 내려가면 도면이 화면 밖으로 잘린다.
  ///
  /// **건물 외곽선으로 폴백하지 않는다.** 예전에는 층 도면이 아직 없으면 건물
  /// 외곽선에 맞췄는데("한 프레임 어긋난 배율이 낫다"), 그 값은 시드 구조상
  /// **1F의 외곽선**이다([floorOutlineRing] 주석). 지상층끼리는 거의 같아서
  /// 티가 안 나지만 지하는 1.8배 크고 위치도 달라서, 그 배율로 굳으면 B1·B2는
  /// 한쪽이 잘리고 B3~B6은 사방이 잘려 층 전체가 화면에 안 들어온다. 그리고
  /// 이건 "한 프레임"이 아니다 — 뒤이어 다시 맞춰 주는 곳이 없어 그대로 남는다.
  ///
  /// 그래서 도면 로드를 **기다렸다가** 맞춘다.
  ///
  /// 기다려도 없으면 건물 외곽선으로 일단 맞추되(연출을 잃지 않는다) **다시
  /// 맞추기를 예약해 둔다**([_pendingFloorFit]). 폴백을 아예 없애 봤더니 "틀린
  /// 배율"이 "배율을 아예 안 잡음"이 됐고, 그건 더 나쁘다 — 실기기에서 건물에
  /// 들어가도 도면이 야외 지도 위 작은 사각형으로 남고 진입 줌인이 통째로
  /// 사라졌다. 예약해 두면 도면이 도착하는 순간 그 층 크기로 한 번 더 맞는다.
  Future<void> _fitCameraToActiveFloor({
    Duration duration = indoorZoomInDuration,
  }) async {
    // 층을 막 바꾼 직후면 도면이 아직 오는 중이다. 여기서 기다려야 대부분의
    // 경우 예약까지 가지 않고 바로 맞는다.
    await _floorGraphLoad;
    if (!mounted) return;
    await _fitCameraToLoadedFloor(duration);
  }

  /// [_fitCameraToActiveFloor]의 몸통 — **도면 로드를 기다리지 않는다.**
  ///
  /// 예약분을 실행하는 쪽([_fetchFloorGraph])은 이미 그 로드 **안에** 있어서,
  /// 거기서 `_floorGraphLoad`를 기다리면 자기 자신을 기다리다 멈춘다. 그래서
  /// 기다리는 껍데기와 실제로 맞추는 몸통을 나눠 둔다.
  Future<void> _fitCameraToLoadedFloor(Duration duration) async {
    final ring = _activeFloorOutlineRing();
    // 층 도면이 없으면 건물 외곽선으로 **일단 맞춘다.** 그 값은 1F 외곽선이라
    // 지하에서는 크기가 안 맞지만, 안 맞추면 진입 줌인 연출이 통째로 사라진다 —
    // 실기기에서 확인했다. 대신 도면이 도착하면 그 층 크기로 다시 맞추도록
    // 예약해 둔다([_pendingFloorFit]).
    final footprint = ring ?? _buildingFootprint;
    if (footprint == null || footprint.length < 3) return;
    final floor = _activeFloor;
    if (ring == null) {
      if (floor != null) _pendingFloorFit = (floor: floor, duration: duration);
      debugPrint(
        '[outdoor overlay] fit 폴백(건물 외곽선): $floor 도면 없음 '
        '(entered=$_indoorEntered)',
      );
    } else {
      _pendingFloorFit = null;
    }
    // 화면에 그려지는 것은 외곽선만이 아니다 — 매장·POI까지 덮어야 "층 전체가
    // 보인다"가 된다([_activeFloorDrawnPoints]). 폴백 중이면 그 층 도면이 없으니
    // 덮을 점도 없다.
    final box = minAreaBoxFor(
      footprint,
      covering: ring == null ? const [] : _activeFloorDrawnPoints(),
    );
    if (box != null) {
      await _animateCameraToFitBox(
        box,
        topChromePx: floorFitTopChromePx,
        bottomChromePx: floorFitBottomChromePx,
        duration: duration,
      );
      return;
    }
    // 상자를 못 구하면(퇴화한 외곽선) 돌리지 않고 임계값까지만 간다.
    final center = _buildingCenter(footprint);
    final controller = _mapController;
    if (center == null || controller == null || !_styleReady) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(center), _entryZoomThreshold()),
      duration: duration,
    );
  }

  List<ll.LatLng> _activeFloorDrawnPoints() {
    final plan = _floorPlan;
    if (plan == null) return const [];
    return <ll.LatLng>[
      ...plan.footprint,
      for (final store in plan.stores) ...[store.centroid, ...store.polygon],
      for (final poi in plan.pois) poi.point,
    ];
  }

  /// 건물 폴리곤을 잠깐 진하게 칠했다 되돌린다 — "이 건물을 말하는 것"이라는
  /// 시각 피드백.
  ///
  /// 건물을 탭했을 때와 검색에서 골랐을 때가 **같은 신호**를 써야 한다. 탭에만
  /// 있으면, 검색으로 고른 사용자는 카메라만 슥 움직이고 아무것도 강조되지 않는
  /// 화면을 본다 — 옅은 파랑(0.15) 폴리곤은 배경 지도 위에서 눈에 잘 띄지 않아
  /// "골랐다"는 사실이 화면에 드러나지 않는다.
  ///
  /// 장식이라 컨트롤러가 아직 없으면 조용히 건너뛴다. 이 반짝임에 진입이나
  /// 카메라 이동을 걸어 두면 안 된다.
  Future<void> _flashBuildingFill() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    // fillColor를 매번 함께 넘긴다 — 빼면 검정으로 되돌아간다
    // (indoor_overlay_layers.dart 상단 주석 참고).
    await controller.setLayerProperties(
      kOutdoorBuildingFillLayerId,
      buildingFillProps(buildingFillOpacityPressed),
    );
    await Future<void>.delayed(
      const Duration(milliseconds: buildingPressedHoldMs),
    );
    if (!mounted) return;
    await controller.setLayerProperties(
      kOutdoorBuildingFillLayerId,
      buildingFillProps(buildingFillOpacityDefault),
    );
  }

  /// 실내 진입 트리거 — 건물 탭·줌 임계값 초과·GPS 근접 감지 중 하나로 호출.
  /// 화면 모드는 바꾸지 않고 야외 지도 위에 얹는 실내 UI 오버레이만 켠다.
  /// 사용자가 축소해 임계값 아래로 내려가면 [_handleCameraIdle]이 오버레이를
  /// 다시 끄고 트리거를 재무장한다.
  ///
  /// [ignoreZoomArming]은 **자기 게이트를 따로 가진 호출자**가 쓴다.
  /// [_autoIndoorEntryArmed]는 "같은 줌에서 카메라가 멈출 때마다 반복 발화하지
  /// 않게" 하려는 zoom 트리거 전용 플래그이고, [_exitIndoorByOutsideTap]이 일부러
  /// 재무장하지 않는다(아래 주석 참고). 그래서 이 플래그로 다른 경로까지 막으면
  /// 두 가지가 조용히 죽는다.
  ///   - 건물 밖을 탭해 나온 사용자가 건물을 **직접 다시 탭**해도 안 들어감
  ///   - GPS 자동 진입이 [_gpsEntryArmed]로 다시 무장돼도 여기서 막힘
  /// 둘 다 자기 쪽 게이트를 이미 통과한 호출이므로 zoom 무장은 보지 않는다.
  void _triggerIndoorEntry({bool ignoreZoomArming = false}) {
    if (!ignoreZoomArming && !_autoIndoorEntryArmed) return;
    _autoIndoorEntryArmed = false;
    if (_indoorEntered) return;
    _setIndoorEntered(true);
  }

  /// 실내 모드에서 건물 바깥 야외 지도를 탭했을 때의 이탈.
  ///
  /// 재무장([_autoIndoorEntryArmed])은 **하지 않는다.** 탭으로 나온 시점의 줌은
  /// 보통 진입 임계값 위이므로, 재무장하면 다음 카메라 정지에서 곧바로 다시
  /// 실내로 끌려 들어가 "나갈 수 없는" 상태가 된다. 다시 들어오는 경로는 두
  /// 가지가 열려 있다 — 건물을 직접 탭하거나(위 [_triggerIndoorEntry]의
  /// `ignoreZoomArming`), 이탈 임계값 아래로 축소했다가 다시 확대하는 것.
  ///
  /// **GPS 자동 진입도 함께 끈다**([_gpsEntryArmed]). 건물 안에 서서 밖을 탭해
  /// 나온 경우 GPS는 여전히 "건물 안"을 가리키므로, 안 끄면 다음 위치 한 건이
  /// 곧바로 다시 끌고 들어간다. 다시 자동으로 들어가는 것은 사용자가 실제로
  /// 건물을 벗어난 뒤다([GpsBuildingVerdict.outside]).
  void _exitIndoorByOutsideTap() {
    // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
    // (배치 대기 중인 탭은 위에서 이미 소비되므로 방어적 처리다.)
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _gpsEntryArmed = false;
    _setIndoorEntered(false);
  }

  /// [_indoorEntered] 상태 변경을 한 곳으로 모은 헬퍼. setState + 상위 콜백 통지에
  /// 더해 dim scrim의 fillOpacity도 함께 갱신해, 실내 진입/이탈에 스포트라이트
  /// 효과가 즉시 반영되게 한다.
  /// 실내 위치가 지금 잡혀 있는지. 자동 이탈을 허용할지 가르는 기준이다
  /// ([_applyBuildingVerdict]).
  ///
  /// 앵커만으로 판단한다. 궤적(snapshot)은 세션이 끝난 뒤에도 남아 있어서
  /// "지금 안에 있다"의 근거가 못 된다.
  bool get _indoorPositionPlaced => _pdrTrailState.anchor != null;

  /// [leftBuilding]은 **사용자가 실제로 건물을 나갔다**는 뜻이다(GPS 판정).
  /// 화면에서 도면만 접은 것([returnToOutdoorView], 바깥 탭)과 구분해야 하는
  /// 이유는 두 가지다.
  ///
  ///   - **실내 위치를 버릴지.** 도면을 접은 사용자는 잠시 뒤 다시 펼 수 있으니
  ///     앵커와 걸음 누적을 남겨야 한다(안 남기면 오버레이를 여닫을 때마다 실내
  ///     위치가 초기화된다). 반대로 건물을 나간 사용자의 앵커는 이미 틀린 값이라,
  ///     남겨 두면 야외 지도 위에 실내 궤적이 계속 자란다.
  ///   - **야외 구간을 올릴지.** 실내→야외 안내 중 사용자가 도면만 접었다고
  ///     야외 구간으로 넘어가면, 아직 건물 안인데 실내 구간이 사라진다. 다시
  ///     확대해도 예약은 이미 소비돼 안내가 통째로 없어진다.
  void _setIndoorEntered(bool value, {bool leftBuilding = false}) {
    if (_indoorEntered == value) return;
    // 상태를 내리기 **전에** 버린다. 아래 [_syncPdrCurrentLayer]가 이 값을 보고
    // 그릴지 말지를 정하므로, 뒤에 버리면 그 한 프레임 동안 옛 위치가 남는다.
    if (!value && leftBuilding) _dropIndoorPosition();
    // 자동으로 들어왔다는 표식은 야외로 나가는 순간 내린다. 남겨 두면 다음에
    // 사용자가 건물을 직접 탭해 연 도면까지 GPS가 제멋대로 닫는다
    // ([_applyBuildingVerdict]의 outside 갈래).
    if (!value) _indoorEnteredByGps = false;
    // 실내 안내를 켜고 끄는 유일한 지점이다.
    //
    // 예전에는 오버레이가 꺼져도 복도 보정이 계속 돌았다 — 화면에 안 보일 뿐
    // 야외를 걸어 다닌 거리가 실내 좌표계에 누적되다가, 다시 들어오는 순간
    // 걸어 본 적 없는 자리에서 시작했다.
    if (value) {
      _ensureGuidanceAttached();
    } else {
      _guidance.detach();
      // 야외로 나가면 진행 중이던 층 전환도 끝난다. 남겨 두면 배너가 야외
      // 화면에 떠 있고 걸음이 멈춘 채로 유지된다.
      _enqueueFloorTransition(_endEscalatorRide);
    }
    setState(() => _indoorEntered = value);
    widget.onIndoorEnteredChanged?.call(value);
    // 진입/이탈로 "지금 보고 있는 층"의 유무 자체가 바뀐다.
    _notifyActiveFloor();
    // 구독 자체는 실내에서도 유지된다(이탈 판정의 유일한 입력이다) — 여기서
    // 하는 일은 이 화면이 안 보이게 됐을 때 끊는 것뿐이다.
    _syncGpsSubscription();
    // GPS 마커는 **이 자리에서 직접** 지운다.
    //
    // [_syncCurrentLayer]가 [_outdoorGpsVisible]을 보고 알아서 비우기는 하지만,
    // 그 함수는 다음 위치 이벤트가 와야 불린다. 진입 순간에 안 지우면 마지막
    // 야외 좌표가 실내 도면 위에 그대로 남아, 사용자는 실내 위치 아이콘과 건물
    // 밖 파란 점을 **동시에** 보게 된다. 위치 아이콘의 주인이 바뀌는 시점은
    // 다음 좌표가 아니라 지금이다.
    unawaited(_syncCurrentLayer());
    // 위치 아이콘의 주인이 바뀌는 순간이다. 야외로 나가면 실내 위치 마커를
    // 지우고(GPS 마커가 그 역할을 받는다), 실내로 들어가면 다시 그린다.
    unawaited(_syncPdrCurrentLayer());
    _syncDimScrimLayer();
    // 외곽선은 실내 진입 상태에서만 그린다 — 이탈하면 여기서 소스가 비워진다.
    unawaited(_syncFloorOutlineLayer());
    // 진입/이탈로 페이드 구간 자체가 바뀌므로 이미 붙어 있는 오버레이 레이어의
    // opacity 표현식도 함께 갈아 끼운다.
    unawaited(_syncIndoorOverlayFade());
    // 실내로 들어온 시점이 PDR을 켤 지점이다. 야외로 나갈 때는 세션을 끄지
    // 않는다 — 실내/야외 오버레이를 오가는 동안 세션이 껐다 켜지면 anchor와
    // 걸음 누적이 매번 초기화된다. 진짜로 건물을 나간 경우만 예외이고, 그건
    // 위에서 [dropIndoorPosition]으로 이미 처리했다.
    if (value) unawaited(_startPdrIfIdle());
    // 문 경유 안내로 여기까지 왔다면, 지금이 두 구간을 넘기는 지점이다. 진입도
    // 이탈도 어느 경로로 판정되든 이 함수를 지나므로 승격은 여기 한 곳에만 둔다.
    //
    // 방향에 따라 넘기는 것이 반대다.
    //   - 들어왔다 → 야외 구간이 끝났으니 실내 구간을 올린다.
    //   - 나갔다   → 실내 구간이 끝났으니 야외 구간을 올린다.
    //
    // 나가는 쪽만 [leftBuilding]으로 한 번 더 좁힌다. 근거는 이 함수 문서에 있다.
    if (value) {
      unawaited(_activatePendingIndoorRoute());
    } else if (leftBuilding) {
      unawaited(_activatePendingOutdoorRoute());
    }
  }

  /// [fadeFactor]는 등록되는 레이어에 곱할 층 전환 크로스페이드 계수다. 기본
  /// 1(원래 불투명도). 크로스페이드가 이전 층 위에 새 블록을 투명하게 얹을
  /// 때만 0을 넘긴다 — 이후 [_finalizeIndoorFloorCrossfade]가 1까지 올린다.
  Future<void> _ensureIndoorTilesRegistered({double fadeFactor = 1}) async {
    final controller = _mapController;
    final building = _building;
    if (controller == null || !_styleReady || building == null) {
      debugPrint(
        '[outdoor overlay] skip register: controller=${controller != null} '
        'styleReady=$_styleReady building=${building != null}',
      );
      return;
    }
    if (_indoorTilesRegistered) return;
    final floor = _activeFloor ?? building.initialFloor;
    if (floor == null) {
      debugPrint('[outdoor overlay] skip register: no active floor');
      return;
    }

    final tileUrl = indoorTileUrl(
      buildingId: building.id,
      floorName: floor,
      tileRevision: building.tileRevision,
    );
    debugPrint(
      '[outdoor overlay] registering MVT source url=$tileUrl '
      'apiBaseUrl=$apiBaseUrl',
    );
    // 실내 도면은 확대에 따라 자연스럽게 나타나야 한다(Google Maps의 건물 내부
    // 표시와 같은 패턴). 페이드 구간은 진입 상태에 따라 달라지므로
    // [indoorOverlayFadeExpr]가 만들어 준다. zoom-interpolate 표현식이라
    // 카메라 이동 중에는 setLayerProperties 없이도 실시간으로 반영되고,
    // 진입/이탈로 구간 자체가 바뀔 때만 [_syncIndoorOverlayFade]가 갱신한다.
    //
    // **아래 호출보다 먼저** 반영해야 한다. [_overlayFadeExpr]이 이 값을 읽어
    // 표현식을 만들기 때문이다 — 순서를 바꾸면 크로스페이드가 0이 아니라 이전
    // 계수로 등록돼 새 층이 처음부터 불투명하게 튀어나온다.
    _indoorOverlayFadeFactor = fadeFactor;
    // 실패 시 부분 등록분 정리까지 저쪽이 한다. 여기서는 성공 여부만 받아
    // 플래그에 반영한다.
    final registered = await registerIndoorOverlayLayers(
      controller,
      ids: _indoorIds,
      tileUrl: tileUrl,
      fadeExpr: _overlayFadeExpr(),
      categoryFilter: _categoryFilterExpression(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
      ensureIconImages: _ensureFacilityIconImagesRegistered,
    );
    _indoorTilesRegistered = registered;
    if (registered) {
      debugPrint('[outdoor overlay] MVT source+layers registered ($floor)');
    }
  }

  /// POI/편의시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록한다.
  /// [_ensureIndoorTilesRegistered]가 층 전환마다 소스/레이어를 다시 붙일 때
  /// 매번 렌더를 반복하지 않도록 [_facilityIconImagesRegistered]로 게이팅한다.
  /// 스타일이 바뀌면(개발 hot restart 등) MapLibre가 이미지를 잃을 수 있어
  /// 그때는 [_onStyleLoaded]에서 다시 false로 리셋된다.
  Future<void> _ensureFacilityIconImagesRegistered(
    MapLibreMapController controller,
  ) async {
    if (_facilityIconImagesRegistered) return;
    for (final icon in {...kPoiIconByType.values, kDefaultPoiIcon}) {
      final imageName = poiIconImageName(icon);
      await controller.addImage(
        imageName,
        // 실내 화면과 같은 비트맵 캐시를 공유한다([map_icon_cache.dart]).
        await cachedIconPng(imageName, () => renderPoiIconPng(icon)),
      );
    }
    for (final entry in kStoreFacilityStyleByName.entries) {
      final imageName = facilityIconImageName(entry.key);
      await controller.addImage(
        imageName,
        await cachedIconPng(
          imageName,
          () => renderFacilityIconPng(entry.value),
        ),
      );
    }
    // 매장명 라벨에 붙는 대분류 아이콘. 실내 화면과 같은 이름·같은 비트맵이라
    // 두 화면 사이를 오가도 같은 매장이 같은 아이콘을 단다.
    for (final category in storeCategoryIconKeys) {
      final imageName = storeCategoryIconImageName(category);
      await controller.addImage(
        imageName,
        await cachedIconPng(
          imageName,
          () => renderStoreCategoryIconPng(category),
        ),
      );
    }
    _facilityIconImagesRegistered = true;
  }

  /// 대중교통에서 내린 뒤 들어갈 문을 정하고, 그 문에서 매장까지의 실내 구간을
  /// 미리 풀어 둔다. 실제로 그리는 것은 [_syncRouteLayer]다(밖에서는 미리보기,
  /// 건물에 들어가면 [_activatePendingIndoorRoute]가 승격한다).
  ///
  /// [showTransitRoute]가 시작할 때 pending을 비우므로 **그 뒤에** 불러야 한다.
  /// 순서를 뒤집으면 여기서 쌓은 실내 구간이 곧바로 지워진다.
  Future<void> prepareIndoorLegFromDrop(
    PoiSearchResult destination, {
    required ll.LatLng dropPoint,
  }) async {
    final building = _building;
    final endNodeId = destination.nodeId;
    if (building == null || endNodeId == null || destination.floor.isEmpty) {
      return;
    }
    final entrance = nearestEntrance(_groundEntrances, dropPoint);
    if (entrance == null) return;

    final graph =
        _journeyBuildingGraph ??
        await buildingRepository.getBuildingGraph(building.id);
    if (!mounted) return;
    final leg = graph == null
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);
    setState(() {
      _journeyBuildingGraph = graph;
      _journeyEntrance = entrance;
      _pendingIndoorDestination = destination;
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
    });
    _syncRouteLayer();
    _syncDestinationLayer();
    _syncIndoorDestinationLayer();
  }

  /// 지금 그려야 하는 실내 위치. 출처 판단은 [IndoorGuidanceSession]이 한다.
  ///
  /// 예전에는 여기서 **앵커만** 그렸다. 홈은 층 전환을 감지하지 못하니 걸음
  /// 누적 위치를 그리면 엉뚱한 층 도면 위에서 점이 걸어간다는 이유였는데,
  /// 이제 세션이 에스컬레이터 층 전환까지 판정하므로 그 전제가 사라졌다.
  GuidancePosition? get _indoorPosition => _guidance.position;

  List<ll.LatLng> _floorPathToWgs84(List<PdrLocalPoint> path) {
    final graph = _floorGraph;
    if (graph == null || path.isEmpty) return const [];
    final floorToWgs84 = fitFloorGeoTransform(graph.nodes);
    return path
        .map((point) {
          final wgs84 = floorToWgs84.apply(point.eastM, point.northM);
          return ll.LatLng(wgs84.$1, wgs84.$2);
        })
        .toList(growable: false);
  }

  /// 강조 매장 폴리곤을 highlight 소스에 채운다. null 또는 미매치면 비운다.
  Future<void> _syncHighlightLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final storeId = _highlightedStoreId;
    final plan = _floorPlan;
    final store = (storeId == null || plan == null)
        ? null
        : plan.stores.where((s) => s.id == storeId).firstOrNull;
    await syncPolygonSource(
      controller,
      kOutdoorHighlightSourceId,
      store?.polygon,
    );
  }

  /// [localPoint]가 지도 위 Flutter 오버레이(층 선택기·PDR 제어와 상위가 얹은
  /// 검색창·카테고리 열·하단 바) 영역이면 true. 인자는 MapLibre가
  /// 준 지도 위젯 로컬 좌표라 전역 좌표로 바꿔 비교한다.
  bool _isTapOnMapOverlay(Offset localPoint) {
    final mapBox = context.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.attached) return false;
    final globalPoint = mapBox.localToGlobal(localPoint);
    if (_mapOverlayTapGuard.consumeIfBlocked(globalPoint)) return true;

    for (final key in [
      _floorSelectorKey,
      _pdrControlKey,
      _placingHintKey,
      _buildingLoadFailedKey,
      _etaCardKey,
      _arrivalCardKey,
      ...widget.outerOverlayKeys,
    ]) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if ((box.localToGlobal(Offset.zero) & box.size).contains(globalPoint)) {
        return true;
      }
    }
    return false;
  }
}
