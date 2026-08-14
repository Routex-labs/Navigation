// ignore_for_file: invalid_use_of_protected_member
//
// 이 파일은 `OutdoorMapBodyState`의 part다. setState는 그 클래스가 State에서
// 물려받은 protected 멤버이고, 여기서 부르는 것은 **같은 클래스의 코드**다 —
// 파일만 갈라져 있을 뿐 바깥에서 남의 protected 멤버를 건드리는 것이 아니다.
// 분석기는 extension을 "서브클래스가 아니다"로 보아 경고하므로 파일 단위로
// 끈다. 본체(생명주기·build)는 클래스 안에 있어 이 해제의 영향을 받지 않는다.
/// `OutdoorMapBodyState`의 **지도·카메라·레이어 동기화** 부분.
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

extension OutdoorMapMap on OutdoorMapBodyState {
  /// 카메라를 [position]으로 옮긴다. [zoom]을 주면 그 값으로 확대하고, 없으면
  /// 지금 배율을 유지한다 — 따라가는 동안 사용자가 맞춘 배율을 빼앗지 않는다.
  Future<void> _moveCameraToUser(Position position, {double? zoom}) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await animateCameraToPoint(
      controller,
      ll.LatLng(position.latitude, position.longitude),
      zoom: zoom,
    );
  }

  // --- MapLibre 스타일/레이어 설정 ---

  Future<void> _onStyleLoaded() async {
    final controller = _mapController;
    if (controller == null) return;

    // 새 스타일에는 이전 스타일이 갖고 있던 addImage 비트맵이 넘어오지 않는다.
    // 다음 _ensureIndoorTilesRegistered 호출이 아이콘을 다시 등록하도록 리셋.
    _facilityIconImagesRegistered = false;

    // 건물 fill과 실내 진입 dim scrim. 등록 순서가 곧 쌓임 순서라 가장 먼저다.
    await registerBuildingAndScrimLayers(
      controller,
      buildingFillOpacity: buildingFillOpacityDefault,
    );

    // 경로선 묶음(회색 완료선 → casing → 본선들 → 화살표). 등록 순서가 곧
    // 쌓임 순서라 아래 세 호출의 순서를 바꾸면 안 된다.
    await registerRouteLayers(controller);
    // 대중교통 경로. 도보 경로 **바로 위**에 올려, 두 안내가 잠깐 겹치는
    // 순간에도 사용자가 방금 고른 대중교통 선이 가려지지 않게 한다.
    await registerTransitLayers(controller);
    await registerTransferRouteLayer(controller);

    // 현재 층 외곽선. 경로선 다음이어야 하는 이유는 그 함수 doc에 있다.
    await registerFloorOutlineLayer(controller);

    // 현재 위치(GPS)와 야외 목적지 핀. 등록 순서가 곧 쌓임 순서다.
    await registerCurrentLocationLayers(controller);
    await registerDestinationLayer(controller);

    // 매장 강조. PDR 마커보다 아래·경로선보다 위다(그 함수 doc 참고).
    await registerHighlightLayers(controller);

    // PDR 마커 비트맵을 먼저 굽고, 진단 레이어를 그 사이에 끼운 뒤 마커를
    // 얹는다 — 순서의 근거는 각 함수 doc에 있다.
    await registerPdrLocationImages(controller);
    await registerPdrDebugLayers(controller);
    await registerPdrLocationLayer(controller);

    // 실내 경로 도착 핀 — 현재 위치 마커보다 **나중에** 등록해, 도착 노드와
    // 사용자 위치가 겹칠 때 도착 핀이 위에 오게 한다(실내 지도와 같은 순서).
    // 핀 바닥(tip)이 도착 노드 좌표에 오도록 iconAnchor는 bottom이고, 크기는
    // zoom 보간식으로 걸어 축소했을 때 핀이 도면을 다 덮지 않게 한다.
    // allowOverlap을 켜 매장 라벨과 겹쳐도 핀은 항상 보인다.
    await registerIndoorDestinationLayers(controller);

    if (!mounted) return;
    setState(() => _styleReady = true);
    _syncBuildingLayer();
    _syncCurrentLayer();
    _syncDestinationLayer();
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    _syncHighlightLayer();
    _syncDimScrimLayer();
    _ensureIndoorTilesRegistered();
    // 스타일이 뜨기 전에 받아둔 첫 GPS 위치로의 카메라 이동. 그 사이에 실내로
    // 들어갔다면(줌 임계값·건물 탭) 실행하지 않는다 — 실내 도면을 보고 있는데
    // 카메라가 GPS 좌표로 튀면 안 된다.
    if (_pendingCenterOnPosition && _position != null && _outdoorGpsVisible) {
      _pendingCenterOnPosition = false;
      await controller.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_position!.latitude, _position!.longitude),
        ),
      );
    }
  }

  /// dim scrim 갱신. 건물 footprint가 있으면 세계 전체를 덮는 outer ring +
  /// 건물 hole 폴리곤을 넣고, 실내 진입 상태에 따라 fillOpacity를 실내 오버레이와
  /// 같은 zoom 페이드 구간(16.5~17.5)에 맞춰 0 → 0.35로 켠다. 실내 진입이 꺼져
  /// 있을 땐 opacity=0으로 완전히 사라진다. 이렇게 하면 건물 밖만 반투명 검정으로
  /// 덮이고 실내 오버레이는 그대로 밝게 보인다.
  Future<void> _syncDimScrimLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    // hole은 외곽선과 **같은 링**을 쓴다. 건물 외곽선으로 뚫으면 그 층 도면 중
    // 건물 외곽선 밖으로 나간 부분이 스크림에 덮여, 사용자가 보는 외곽선 안쪽이
    // 어두워지는 모순이 생긴다(지하가 특히 심하다). 링이 아직 없으면(층 도면
    // 로딩 중) 건물 외곽선으로 폴백해 스크림 자체는 유지한다 — 스포트라이트가
    // 한 프레임 통째로 꺼지는 것보다 낫다. 여기만 폴백을 허용하는 이유는
    // 스크림이 "경계선"이 아니라 밝기 대비이기 때문이다 — 선은 폴백하지 않는다
    // ([floorOutlineRing]).
    await syncDimScrimSource(
      controller,
      _activeFloorOutlineRing() ?? _buildingFootprint,
    );

    if (_indoorEntered) {
      // 실내 MVT 오버레이 페이드 구간과 동일한 zoom 창을 쓴다 — 오버레이가
      // 뜨는 것과 동시에 스크림도 자연스럽게 짙어진다. 최대치 0.35는 기존 위젯
      // 스크림(#40000000 = 0.25)보다 살짝 진하게 잡아 실내 vs 야외의 밝기
      // 대비를 조금 더 명확히 준다.
      // fillColor를 반드시 함께 넘긴다 — setLayerProperties는 patch가 아니라
      // 전체 교체다(indoor_overlay_layers.dart 상단 주석 참고).
      await controller.setLayerProperties(
        kOutdoorDimScrimFillLayerId,
        dimScrimProps(_fadeExpr(maxOpacity: 0.35)),
      );
    } else {
      await controller.setLayerProperties(
        kOutdoorDimScrimFillLayerId,
        dimScrimProps(0),
      );
    }
  }

  /// 지도 탭 처리의 테스트 진입점.
  ///
  /// MapLibre 플랫폼 뷰는 위젯 테스트에 없어 `onMapClick`이 아예 발화하지
  /// 않는다. 그래서 실기기에서 쓰이는 것과 **같은 함수**를 직접 부른다 —
  /// 테스트용 축약 경로를 따로 두면 정작 검증하려는 분기(건물 밖 탭 → 야외
  /// 전환)를 우회해 버린다.
  ///
  /// [screenPoint]는 지도 위젯 로컬 픽셀 좌표다. 오버레이(층 선택기 등) 위를
  /// 누른 탭이 지도 탭으로 새어들어가는 경우를 재현하려면 이 값이 필요하다 —
  /// 좌표가 늘 (0,0)이면 오버레이 배제 로직 자체가 검증되지 않는다.
  @visibleForTesting
  Future<void> handleMapClickForTest(
    ll.LatLng point, {
    Offset screenPoint = Offset.zero,
  }) => _handleMapClick(
    Point<double>(screenPoint.dx, screenPoint.dy),
    LatLng(point.latitude, point.longitude),
  );

  Future<void> _handleMapClick(Point<double> pointPx, LatLng coords) async {
    final point = ll.LatLng(coords.latitude, coords.longitude);

    // 지도 위에 얹은 PDR 제어·디버그 설정 버튼을 누른 탭은 여기서 끊는다.
    // 그러지 않으면 "PDR 시작"을 누른 손가락이 버튼 아래의 매장까지 함께
    // 선택하거나, 앵커 배치 대기 중에 버튼 위치에 앵커가 찍힌다.
    if (_isTapOnMapOverlay(Offset(pointPx.x, pointPx.y))) return;

    // 위치 지정 대기 중이라면 이 탭은 PDR 앵커 배치로 소비된다 — 지도 탭이
    // 건물 진입 처리로 새어들어가면 사용자가 위치를 지정하는 순간 오버레이가
    // 다시 리셋되는 것처럼 보인다.
    if (_placingPdrAnchor) {
      await _onMapPressedForPdr(point);
      return;
    }

    // 실내 진입 오버레이 위에서 매장 폴리곤을 탭하면 실내 화면과 동일한 매장
    // 정보 시트를 띄운다. 픽셀 좌표(pointPx)로 벡터 타일의 stores fill을
    // hit-test 하고 feature id로 FloorPlan에서 실제 매장을 되찾는다. 매장이
    // 아닌 곳(복도·footprint)을 탭하면 features가 비어 있어 아래 건물 진입
    // 처리로 자연스럽게 흘러간다.
    if (_indoorEntered && await _tryHandleStoreTap(pointPx)) return;

    // 매장을 맞히지 못했고 길찾기에서 지도로 고르는 중이라면, 이 탭은 복도(또는
    // 빈 공간)를 고른 것이다. **아래 진입/이탈 처리보다 먼저** 소비해야 한다 —
    // 그러지 않으면 건물 안을 눌렀을 땐 진입 트리거로, 건물 밖을 눌렀을 땐
    // 오버레이 닫기로 먹혀서 사용자는 복도를 눌렀는데 화면만 바뀌는 것을 본다.
    if (_indoorEntered && widget.pickingOnMap && _handleMapPickTap(point)) {
      return;
    }

    // 폴리곤 히트 검사만 하고, 나머지 탭은 흡수하지 않아 지도 pan/zoom 제스처를
    // 방해하지 않는다(단일 탭이 여기 오면 그건 pan이 아닌 명시적 탭).
    if (!_isInsideBuilding(point)) {
      // 실내 모드에서 건물 밖을 탭한 것 — 사용자가 야외로 나가겠다는 뜻이다.
      // 축소해서 나가는 것보다 훨씬 직관적인 탈출 경로다.
      //
      // 단, **외곽선 바로 바깥은 이탈로 치지 않는다**
      // ([isTapOutsideBuildingForExit]). 벽에 붙은 매장을 누르다 손가락이 선을
      // 몇 미터 넘기는 일은 흔한데, 그때마다 실내가 닫히면 매장을 누르려던
      // 사용자가 건물에서 쫓겨난다. 여기서 그냥 흡수해 아무 일도 일어나지 않게
      // 두는 편이, 되돌리는 데 건물을 다시 찾아 탭해야 하는 것보다 낫다.
      if (_indoorEntered &&
          isTapOutsideBuildingForExit(
            point: point,
            footprint: _buildingFootprint,
          )) {
        _exitIndoorByOutsideTap();
      }
      return;
    }

    // 폴리곤을 잠깐 진하게 반짝여 "인식됐다"는 시각 피드백을 준 뒤, 야외 지도
    // 위에 실내 UI 오버레이(층 chip, 위치 지정 버튼 등)를 켠다. 화면 모드는
    // 그대로 야외로 유지된다.
    //
    // 반짝임은 장식이라 컨트롤러가 아직 없으면 건너뛴다. 진입을 컨트롤러 유무에
    // 걸어 두면(예전 `if (controller == null) return;`) 스타일 로드 전에 건물을
    // 탭한 사용자에게 아무 반응도 없다.
    await _flashBuildingFill();
    if (!mounted) return;
    _triggerIndoorEntry(ignoreZoomArming: true);
    // 오버레이만 켜면 도면이 지금 배율 그대로 뜬다 — 바깥에서 건물을 눌러
    // 들어온 경우 건물이 화면의 60% 남짓이라 "들어왔다"는 느낌이 안 난다.
    // 카메라도 함께 도면이 화면을 채우는 자리까지 끌어온다.
    if (_indoorEntered) unawaited(_fitCameraToActiveFloor());
  }

  /// [box]를 **가려지지 않는 띠**에 맞춰 카메라를 움직인다. 컨트롤러가 아직
  /// 없으면 아무것도 하지 않고 false.
  ///
  /// 층 도면 fit([_fitCameraToActiveFloor])과 경로 개요([_fitCameraToRouteSegment])의
  /// **공통 몸통**이다. 둘을 한 함수로 묶는 이유는 chrome 보정과 줌 하한이 한
  /// 곳에만 있어야 하기 때문이다 — 각자 갖게 두면 한쪽만 고쳐져 도면을 맞춘
  /// 화면과 경로를 맞춘 화면에서 같은 지점이 다른 높이에 온다.
  ///
  /// 상자를 **어떻게 구하느냐**는 호출부가 정한다([minAreaBoxFor] / [routeBoxFor]).
  /// 퇴화 입력 방어처럼 입력 종류마다 다른 규칙이 여기 섞이면, 이 함수가 층
  /// 외곽선용인지 경로용인지 알 수 없게 된다.
  /// [maxZoom]은 확대해 들어가는 상한이다. 경로 개요만 준다([routeFitMaxZoom])
  /// — 층 외곽선은 커서 그 배율까지 올라갈 일이 없다.
  Future<bool> _animateCameraToFitBox(
    BuildingBox box, {
    required double topChromePx,
    required double bottomChromePx,
    required Duration duration,
    double maxZoom = double.infinity,
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return false;
    await animateCameraToFitBox(
      controller,
      box,
      viewport: MediaQuery.sizeOf(context),
      topChromePx: topChromePx,
      bottomChromePx: bottomChromePx,
      duration: duration,
      maxZoom: maxZoom,
    );
    return true;
  }

  /// 지금 화면 폭에서 쓸 실내 진입 임계값.
  ///
  /// 고정값 [indoorEntryZoomThreshold]는 화면이 좁을수록 "더 깊이 확대해야
  /// 닿는" 값이라, 폰에서는 건물이 화면 밖으로 넘칠 때까지 확대해야 진입이
  /// 발화했다. 근거와 보정식은 [indoorEntryZoomThresholdFor] 참고.
  ///
  /// 확대 진입 판정([_handleCameraIdle])과 건물 포커스
  /// ([_recenterOnBuildingIfNeeded])가 **같은 값을 봐야 한다.** 둘이 어긋나면
  /// 포커스가 맞춰 준 zoom이 진입 임계값에 못 미쳐, 건물로 포커스는 됐는데
  /// 정작 실내로는 들어가지 않는 상태가 만들어진다.
  double _entryZoomThreshold() {
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) {
      return indoorEntryZoomThreshold;
    }
    return indoorEntryZoomThresholdFor(
      buildingWidthMeters: polygonWidthMeters(footprint),
      // 이 화면의 지도는 Stack을 꽉 채우고, MapShellScreen도 Scaffold body
      // 전체를 내주므로 지도 폭 == 화면 폭이다.
      viewportWidthPx: MediaQuery.sizeOf(context).width,
      latitude: _buildingCenter(footprint)?.latitude ?? referenceLatitude,
    );
  }

  void _handleCameraIdle() {
    // 카메라 콜백은 위젯이 사라진 뒤에도 한 박자 늦게 도착할 수 있다.
    // _entryZoomThreshold가 context를 읽으므로 먼저 걸러낸다.
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null) return;
    // zoom과 target은 같은 CameraPosition에서 나오고 둘 다 non-nullable이므로,
    // 카메라를 받았다면 중심 좌표도 항상 있다.
    final camera = controller.cameraPosition;
    if (camera == null) return;
    // 확대만으로는 실내로 들어가지 않는다. 카메라 중심이 실내 도면이 있는 건물
    // 근처일 때만 진입을 허용한다 — 건물이 없는 지역을 확대했을 때 도면 없이
    // 층 선택기·위치 지정 버튼만 뜨는 것을 막는다.
    final buildingNearby = isIndoorBuildingNearCamera(
      camera: ll.LatLng(camera.target.latitude, camera.target.longitude),
      footprint: _buildingFootprint,
    );
    switch (indoorEntryTransitionForZoom(
      camera.zoom,
      buildingNearby: buildingNearby,
      entryZoom: _entryZoomThreshold(),
    )) {
      case IndoorEntryTransition.enter:
        _triggerIndoorEntry();
      case IndoorEntryTransition.exit:
        // 사용자가 건물을 벗어날 만큼 축소했으므로 오버레이를 접고 다음 확대에서
        // 재발화할 수 있게 무장한다. 배치 대기 중이면 종료해 하단 바 표시도 함께
        // 초기화한다.
        _autoIndoorEntryArmed = true;
        if (_indoorEntered) {
          if (_placingPdrAnchor) _setPlacingAnchor(false);
          _setIndoorEntered(false);
        }
      case IndoorEntryTransition.keep:
        // 히스테리시스 밴드 — 현재 상태를 그대로 유지한다.
        break;
    }
  }

  /// GPS 현재 위치 마커. 실내에서는 [_outdoorGpsVisible]이 false라 항상 빈
  /// 소스로 밀어 넣어 마커가 지도에서 사라진다 — [_syncGpsSubscription]이
  /// `_position`을 비우는 것과 이중으로 막아, 어느 경로로 들어와도 건물 안에서
  /// GPS 기반 위치가 보이지 않게 한다.
  Future<void> _syncCurrentLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) {
      _pendingCenterOnPosition = _outdoorGpsVisible && _position != null;
      return;
    }
    final pos = _outdoorGpsVisible ? _position : null;
    await syncPointSource(
      controller,
      kOutdoorCurrentSourceId,
      pos == null ? null : ll.LatLng(pos.latitude, pos.longitude),
    );
  }

  /// 길찾기 "지도에서 선택" 중에 매장이 아닌 곳을 눌렀을 때. 후보를 만들어
  /// 넘겼으면 true(=이 탭은 여기서 끝난다).
  ///
  /// 스냅 규칙은 [_onMapPressedForPdr]와 **같은 것**을 쓰고, 노드까지 확정해
  /// 넘기는 이유도 실내 화면의 동명 처리와 같다(다익스트라가 노드에서 시작·종료
  /// 하므로 노드 id 없는 후보는 경로를 만들지 못한다).
  ///
  /// 통로에서 너무 먼 탭은 **false를 돌려 흘려보낸다.** 실내와 다른 점이 여기다 —
  /// 야외 지도에서 그 탭은 대개 "건물 밖을 눌러 실내에서 나가겠다"는 뜻이므로,
  /// 여기서 삼키면 고르는 중에는 실내에서 빠져나올 방법이 사라진다.
  bool _handleMapPickTap(ll.LatLng point) {
    final floor = _activeFloor;
    final graph = _floorGraph;
    if (floor == null || graph == null || graph.nodes.isEmpty) return false;
    final transform = fitFloorGeoTransform(graph.nodes);
    final local = transform.invert(point.latitude, point.longitude);
    if (local == null) return false;
    final snapped = FloorMapMatcher(
      graph,
    ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
    if (snapped == null) return false;
    if (snapped.distanceToGraphM > maxPdrAnchorSnapDistanceM) return false;

    final nodeId = _nearestGraphNodeId(
      graph.nodes,
      snapped.point.eastM,
      snapped.point.northM,
    );
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return false;
    // 노드에 실측 좌표가 있으면 그대로 쓴다. 있는 값을 두고 변환을 태우면
    // 피팅 오차만큼 어긋난 자리에 핀이 찍힌다(실내 화면과 같은 규칙).
    final latLng = node.lat != null && node.lng != null
        ? ll.LatLng(node.lat!, node.lng!)
        : () {
            final (lat, lng) = transform.apply(node.xM, node.yM);
            return ll.LatLng(lat, lng);
          }();
    widget.onMapPointPicked?.call(
      PoiSearchResult(
        name: kMapPickedPointLabel,
        floor: floor,
        point: latLng,
        nodeId: node.id,
      ),
    );
    return true;
  }
}
