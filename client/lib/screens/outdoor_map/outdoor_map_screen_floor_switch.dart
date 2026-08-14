// ignore_for_file: invalid_use_of_protected_member
//
// 이 파일은 `OutdoorMapBodyState`의 part다. 사정은 다른 part 파일과 같다.
/// `OutdoorMapBodyState`의 **층 전환 크로스페이드** 부분.
///
/// [outdoor_map_screen_indoor.dart]에서 갈라져 나왔다. 층을 바꾸는 일은 실내
/// 오버레이에서 가장 조심스러운 경로다 — 옛 층 레이어를 지우기 전에 새 층을
/// 깔아야 깜빡임이 없고, 그 사이에 사용자가 또 층을 바꾸면 두 전환이 겹친다.
///
/// 그 순서와 세대(generation) 관리가 한 덩어리라 따로 둔다. 실내 오버레이의
/// 다른 일(레이어 동기화·카메라 맞춤·탭 판정)과는 고치는 이유가 다르다.
part of 'outdoor_map_screen.dart';

extension OutdoorMapFloorSwitch on OutdoorMapBodyState {
  /// 층 선택기에서 사용자가 직접 층을 골랐을 때.
  ///
  /// 층을 갈아 끼운 뒤 **그 층 외곽선에 카메라를 다시 맞춘다.** 층마다 크기가
  /// 달라서(지상 약 180 x 190 m ↔ B3·B4 286 x 305 m) 이전 층에 맞춰 둔 배율이
  /// 새 층에는 안 맞는다 — 지하로 내려가면 도면이 화면 밖으로 잘리고, 올라오면
  /// 여백만 남는다.
  ///
  /// **자동 층 전환에는 붙이지 않는다.** 안내 중 층이 바뀌는 순간
  /// ([_enqueueFloorTransition])에는 카메라가 사용자를 따라가야지 층 전체를
  /// 담으려 물러서면 안 된다. 그래서 재정렬을 [_switchOverlayFloor] 안이 아니라
  /// 이 사용자 조작 경로에만 둔다. (안내 중에는 층 선택기 자체가 접혀 있어
  /// 이 경로로 들어올 수도 없다.)
  Future<void> _onFloorChipSelected(String floor) async {
    if (floor == _activeFloor) return;
    // 크로스페이드 마무리(타일 대기 → 페이드인)는 떼어 둔 채 곧바로 돌아오므로
    // 카메라 재정렬(500ms)이 이전 층 도면이 아직 보이는 동안 시작된다 — 새
    // 도면은 카메라가 움직이는 위로 준비되는 대로 페이드인돼 하나의 전환으로
    // 읽힌다. 재정렬을 페이드 뒤로 미루면 전환이 두 박자("바뀌고, 그 다음
    // 움직이고")로 쪼개진다.
    await _switchOverlayFloorCrossfaded(floor, recenterIfNeeded: false);
    // 연타로 이 탭이 추월당했으면 카메라를 만지지 않는다 — 여기서 fit하면
    // 사용자가 마지막으로 고른 층 화면을 이전 탭의 층 외곽선에 맞춰 버린다
    // (지하층처럼 층마다 크기가 크게 다르면 정렬이 눈에 띄게 어긋난다).
    // 카메라는 마지막 탭의 이 함수 호출이 맞춘다.
    if (!mounted || _activeFloor != floor) return;
    // 층 그래프가 도착한 뒤라 [_activeFloorOutlineRing]이 새 층 외곽선을 준다
    // (`_switchOverlayFloor`가 `_loadFloorGraph`까지 기다린다).
    await _fitCameraToActiveFloor(duration: floorSwitchZoomDuration);
  }

  /// [_switchOverlayFloor]를 크로스페이드로 돈다. **사람 조작으로 층이 바뀌는
  /// 모든 경로**(층 선택기, 검색·카테고리에서 타 층 매장, 경로 계산의 층 이동,
  /// 자동 전환 취소·되돌리기)가 이걸 쓴다 — 크로스페이드 없이 직접
  /// [_switchOverlayFloor]를 부르면 타일 교체가 "지워졌다 다시 그려지는"
  /// 장면으로 드러난다. 안내 중 자동 전환([_swapIndoorFloorForRide])도 같은
  /// 길로 들어오며, 페이드 시간만 두 배로 늘려 잡는다.
  ///
  /// 이전 층 도면은 새 층 타일이 실제로 도착할 때까지 그대로 남고, 도착하면
  /// 새 도면이 그 위로 페이드인된다(오래 걸리면 그동안 에스컬레이터 모티프가
  /// 뜬다 — 판단은 [FloorSwitchProgressController]). 마무리(타일 대기 →
  /// 페이드인 → 이전 블록 제거)는 [_finalizeIndoorFloorCrossfade]가 떼어져
  /// 돌므로 이 함수는 층 그래프 로드까지만 기다린다. 연타 시 모티프의 주인은
  /// 마지막 호출이다(토큰).
  Future<void> _switchOverlayFloorCrossfaded(
    String floor, {
    bool recenterIfNeeded = true,
    Duration crossfadeDuration = floorSwitchCrossfadeDuration,
  }) async {
    final token = _floorSwitchProgress.begin(
      floorSwitchDirectionBetween(_activeFloor, floor),
    );
    var handedOff = false;
    try {
      handedOff = await _switchOverlayFloor(
        floor,
        recenterIfNeeded: recenterIfNeeded,
        crossfade: true,
        progressToken: token,
        crossfadeDuration: crossfadeDuration,
      );
    } finally {
      // 크로스페이드 마무리가 예약됐으면 완료 통지도 거기서 한다(타일이 아직
      // 오는 중인데 여기서 finish하면 모티프가 "로딩 중"에 걷힌다). 예약까지
      // 못 갔으면(같은 층, 지도 미준비, 예외) 여기서 반드시 알린다 — 안
      // 그러면 모티프가 영영 안 걷힌다.
      if (!handedOff) _floorSwitchProgress.finish(token);
    }
  }

  /// 층 도면을 갈아 끼운다. 실내 MVT 오버레이 소스를 새 층 타일로 바꾸고,
  /// PDR 스냅용 층 그래프도 함께 갱신한다.
  /// [recenterIfNeeded]가 false면 마지막의 [_recenterOnBuildingIfNeeded]를
  /// 건너뛴다. 호출자가 곧바로 카메라를 다시 맞출 때 쓴다 — 두 애니메이션이
  /// 겹치면 지도가 한 번 움찔했다가 다시 움직인다.
  ///
  /// [crossfade]가 false(안내 중 자동 전환 — 셸의 불투명 스크림이 교체를
  /// 가린다)면 이전 층 소스·레이어를 지우고 새 층을 등록하는 즉시 교체다.
  /// true(사람 조작, [_switchOverlayFloorCrossfaded])면 이전 층 블록을 화면에
  /// 남긴 채 새 층 블록을 **투명하게** 위에 등록하고, 타일 도착을 기다렸다가
  /// 페이드인하는 마무리([_finalizeIndoorFloorCrossfade])를 떼어서 예약한다.
  /// 반환값은 그 마무리가 예약됐는지 — 예약됐다면 [progressToken]의 finish도
  /// 마무리가 맡는다.
  Future<bool> _switchOverlayFloor(
    String floor, {
    bool recenterIfNeeded = true,
    bool crossfade = false,
    int? progressToken,
    Duration crossfadeDuration = floorSwitchCrossfadeDuration,
  }) async {
    if (floor == _activeFloor) return false;
    final controller = _mapController;
    final building = _building;
    if (building == null) return false;
    // **컨트롤러가 없어도 층 상태와 그래프는 바꾼다.** 예전에는 여기서 통째로
    // 빠져나갔는데, 그러면 스타일이 아직 안 올라온 사이에 온 층 전환(자동 층
    // 이동이 대표적이다)이 조용히 사라진다. 지도 레이어를 만지는 부분만
    // 컨트롤러가 있을 때 한다.
    final canDrawLayers = controller != null && _styleReady;

    // 다층 경로가 있으면 새 층의 세그먼트로 갈아 끼운다(없으면 이 층에는
    // 안 그린다). 단일층 경로였다면 다른 층으로 옮기는 순간 경로가 무의미해지므로
    // 지도에서 지운다 — 실내 화면과 동일 규칙.
    final multiRoute = _indoorMultiFloorRoute;
    final nextSegmentRoute = multiRoute?.segmentForFloor(floor)?.route;
    setState(() {
      _activeFloor = floor;
      _floorGraph = null;
      _floorPlan = null;
      _mapCalibrationVersion = 'unversioned';
      // 세그먼트가 갈아타면 진행거리 기준점도 새 세그먼트 기준으로 다시 잡아야
      // 한다. 남겨두면 층을 바꾼 순간 남은거리가 튄다.
      _guidance
        ..setRouteSegment(multiRoute == null ? null : nextSegmentRoute)
        ..seedProgress(null);
      // 층이 바뀌면 그 층에 강조하던 매장은 지도에 없다. 강조도 초기화.
      _highlightedStoreId = null;
    });
    // **세션에도 지금 알린다.** 다음 스냅샷까지 미루면 그 사이 세션은 이전 층
    // 기준 보정 위치를 들고 있고, 화면은 새 층 그래프로 좌표를 되돌린다 —
    // 마커가 새 층 도면 위 엉뚱한 자리에 찍힌다. 서 있으면 스냅샷이 몇 초씩
    // 안 오므로 한 프레임이 아니라 눈에 보이는 시간 동안 어긋난다.
    _guidance.setContext(
      floorId: floor,
      graph: _floorGraph,
      floorLabels: building.floors,
    );
    _notifyActiveFloor();
    // 층이 바뀐 순간 이전 층의 외곽선은 더 이상 맞지 않는다. 새 도면이 도착할
    // 때까지(지하 → 다른 층) 선을 지워 둔다 — 틀린 경계를 보여주지 않는다.
    unawaited(_syncFloorOutlineLayer());
    // 크로스페이드면 이전 층 블록을 지우지 않고 은퇴 목록으로 넘긴다 — 새 층
    // 타일이 도착할 때까지 이전 도면이 그대로 보이는 것이 연출의 핵심이다.
    // 제거는 페이드인이 끝난 뒤 [_finalizeIndoorFloorCrossfade]가 한다.
    var retiredForCrossfade = false;
    if (canDrawLayers && _indoorTilesRegistered) {
      if (crossfade) {
        _retiringIndoorBlocks.add((
          layerIds: _indoorIds.layersTopFirst,
          sourceId: _indoorIds.source,
        ));
        retiredForCrossfade = true;
        _indoorTilesRegistered = false;
        _indoorIds = _indoorIds.next();
      } else {
        // 앞선 크로스페이드가 마무리 전에 이 경로(안내 중 자동 전환)로
        // 끊겼으면 은퇴 블록이 남아 있을 수 있다 — 여기서 함께 지운다.
        await _removeRetiringIndoorBlocks(controller);
        // 순서 중요: 레이어부터 지워야 소스를 지울 수 있다(레이어가 붙어있으면
        // 오류). 이미 없는 레이어에 대해 removeLayer가 예외를 던지는 native
        // 구현도 있어 각 항목을 try/catch로 감싼다.
        for (final id in _indoorIds.layersTopFirst) {
          try {
            await controller.removeLayer(id);
          } catch (_) {}
        }
        try {
          await controller.removeSource(_indoorIds.source);
        } catch (_) {}
        _indoorTilesRegistered = false;
        // 다음 등록은 새 세대 ID로. 같은 ID로 즉시 addSource를 다시 부르면
        // native(Android/iOS)가 이전 remove의 정리를 아직 못 끝내 조용히
        // 실패하는 경우가 있다(특정 층으로 전환 시 아무것도 안 그려지는
        // 원인이었음).
        _indoorIds = _indoorIds.next();
      }
    }
    // 은퇴 블록이 있으면 새 블록은 투명(계수 0)하게 얹는다 — 타일이 도착해도
    // 페이드인 전까지는 이전 도면이 보인다. 은퇴 블록이 없으면(첫 등록) 가릴
    // 이전 도면 자체가 없으므로 원래 불투명도로 바로 얹는다.
    await _ensureIndoorTilesRegistered(fadeFactor: retiredForCrossfade ? 0 : 1);
    var crossfadeScheduled = false;
    if (crossfade && canDrawLayers && _indoorTilesRegistered) {
      crossfadeScheduled = true;
      unawaited(
        _finalizeIndoorFloorCrossfade(
          generation: _indoorIds.generation,
          progressToken: progressToken,
          crossfadeDuration: crossfadeDuration,
        ),
      );
    }
    await _loadFloorGraph(building.id, floor);
    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    _syncRouteLayer();
    // 층이 바뀌면 도착 핀도 다시 판정한다 — 다층 경로에서 도착지 층을 벗어나면
    // 핀이 사라지고, 다시 그 층으로 돌아오면 살아난다.
    _syncIndoorDestinationLayer();
    _syncHighlightLayer();
    _notifyRouteStateIfChanged();
    // 층 chip을 눌렀는데 카메라가 건물 밖을 보거나 실내 오버레이가 페이드인되기
    // 전 zoom(<17.5)에 있으면 사용자는 새 층 도면을 볼 수 없다 — "5F/6F를 골랐는데
    // 아무것도 안 나온다"는 인상을 준다. 층 chip 탭은 명시적으로 "그 층을 보고
    // 싶다"는 신호이므로, 이 경우 건물 중심으로 카메라를 옮겨 오버레이가 확실히
    // 화면에 뜨게 한다. 이미 건물이 잘 보이는 상태에서 층만 바꾼 경우에는 카메라를
    // 건드리지 않는다 — 그 상황에서 강제로 재정렬하면 사용자의 view가 불필요하게
    // 튀어 조작감이 나빠진다.
    if (recenterIfNeeded) await _recenterOnBuildingIfNeeded();
    return crossfadeScheduled;
  }

  /// 크로스페이드 마무리 — 새 층 타일 도착을 기다렸다가 새 도면을 페이드인하고
  /// 이전 층 블록을 지운다. [_switchOverlayFloor]가 새 블록을 등록한 직후
  /// 떼어서(unawaited) 부른다 — 호출자는 타일을 기다릴 필요가 없고, 카메라
  /// 재정렬이 로드와 겹쳐서 돈다.
  ///
  /// "타일 도착"은 고정 딜레이가 아니라 **실제 로드 신호**다: 새 소스의
  /// `footprint`를 [MapLibreMapController.querySourceFeatures]로 폴링해, 로드된
  /// 타일에 feature가 잡히는 순간을 준비 완료로 본다. 주차구역 폴리곤이 수백
  /// 개라 로드에 수 초 걸리는 층(B3·5F·6F)에서도 이전 도면이 끝까지 유지되는
  /// 근거다. 화면 밖·minzoom 미만이라 타일 요청 자체가 없으면 feature가 영영
  /// 안 잡히므로 [floorSwitchTilesReadyTimeout]에서 끊고 그냥 교체한다(그
  /// 줌에서는 오버레이가 어차피 안 보여 교체 장면도 없다).
  ///
  /// [generation]은 이 마무리가 맡은 소스 세대다. 기다리는 사이 새 전환이
  /// 시작되면(세대 불일치) 즉시 물러난다 — 은퇴 블록 정리까지 포함해 마지막
  /// 전환의 마무리가 이어받는다. [progressToken]이 있으면 어떤 경로로 끝나든
  /// 에스컬레이터 모티프 컨트롤러에 완료를 알린다(추월당한 토큰의 finish는
  /// 컨트롤러가 무시한다).
  Future<void> _finalizeIndoorFloorCrossfade({
    required int generation,
    int? progressToken,
    Duration crossfadeDuration = floorSwitchCrossfadeDuration,
  }) async {
    try {
      final elapsed = Stopwatch()..start();
      while (true) {
        if (!mounted || _indoorIds.generation != generation) return;
        final controller = _mapController;
        if (controller == null) return;
        List<dynamic> features = const [];
        try {
          features = await controller.querySourceFeatures(
            _indoorIds.source,
            'footprint',
            null,
          );
        } catch (_) {}
        if (features.isNotEmpty ||
            elapsed.elapsed >= floorSwitchTilesReadyTimeout) {
          break;
        }
        await Future<void>.delayed(floorSwitchTilesPollInterval);
      }
      if (!mounted || _indoorIds.generation != generation) return;
      final controller = _mapController;
      if (controller == null) return;

      // 즉시 교체 임계 안에 준비된 전환(캐시된 층)은 페이드 없이 바로 보여
      // 준다 — 빠른 층 훑기에 페이드 잔상이 끌리지 않게. 계수가 이미 1이면
      // (첫 등록이라 은퇴 블록이 없던 경우) 페이드할 것도 없다.
      final animate =
          _indoorOverlayFadeFactor < 1 &&
          elapsed.elapsed >= floorSwitchInstantSwapThreshold;
      if (animate) {
        final stepInterval = crossfadeDuration ~/ floorSwitchCrossfadeSteps;
        for (var step = 1; step <= floorSwitchCrossfadeSteps; step++) {
          _indoorOverlayFadeFactor = Curves.easeOut.transform(
            step / floorSwitchCrossfadeSteps,
          );
          await _applyOverlayFillFadeFactor(controller);
          if (step < floorSwitchCrossfadeSteps) {
            await Future<void>.delayed(stepInterval);
          }
          if (!mounted || _indoorIds.generation != generation) return;
        }
      }
      // 최종 상태: 계수 1로 전체 레이어(심볼 포함)를 원래 불투명도로 되돌린다.
      // 심볼(라벨·아이콘)은 단계 페이드에서 뺐다 — 성긴 점 요소라 fill이 다
      // 올라온 끝에 한 번에 켜져도 팝이 안 읽히고, 단계마다 보내는 전체 속성
      // 교체(플랫폼 채널 호출)를 절반으로 줄인다.
      _indoorOverlayFadeFactor = 1;
      await _syncIndoorOverlayFade();
      if (!mounted || _indoorIds.generation != generation) return;
      // 새 도면이 완전히 올라왔으니 이전 층 블록(연타로 쌓인 것 포함)을 지운다.
      await _removeRetiringIndoorBlocks(controller);
    } finally {
      if (progressToken != null) {
        _floorSwitchProgress.finish(progressToken);
      }
    }
  }

  /// 크로스페이드 뒤에 남은 이전 층 소스·레이어 묶음을 전부 지운다. 이미 없는
  /// 레이어에 removeLayer가 예외를 던지는 native 구현이 있어 각각 삼킨다.
  Future<void> _removeRetiringIndoorBlocks(
    MapLibreMapController controller,
  ) async {
    while (_retiringIndoorBlocks.isNotEmpty) {
      final block = _retiringIndoorBlocks.removeLast();
      for (final id in block.layerIds) {
        try {
          await controller.removeLayer(id);
        } catch (_) {}
      }
      try {
        await controller.removeSource(block.sourceId);
      } catch (_) {}
    }
  }

  /// 크로스페이드 단계마다 현재 계수([_indoorOverlayFadeFactor])를 fill 레이어
  /// 4종에 적용한다.
  Future<void> _applyOverlayFillFadeFactor(MapLibreMapController controller) {
    return syncIndoorOverlayProps(
      controller,
      ids: _indoorIds,
      fadeExpr: _overlayFadeExpr(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
      scope: IndoorOverlaySyncScope.fills,
    );
  }
}
