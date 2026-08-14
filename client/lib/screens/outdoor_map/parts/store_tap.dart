// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **매장 탭 판정** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapStoreTap on OutdoorMapBodyState {
  /// 실내 오버레이 stores 폴리곤을 탭했는지 확인하고, 맞으면 상위에 매장 정보
  /// 시트 노출을 요청한다. 매장이 아니거나 오버레이가 준비되지 않아 처리하지
  /// 않았으면 false를 돌려줘 호출자가 다음 흐름(건물 진입 flash)으로 넘어가게
  /// 한다. 매장 탭 실패는 조용히 무시한다(예: 타일 파싱 지연 중 짧은 순간).
  Future<bool> _tryHandleStoreTap(Point<double> pointPx) async {
    final controller = _mapController;
    final onStoreTap = widget.onStoreTap;
    final plan = _floorPlan;
    final floor = _activeFloor;
    if (controller == null ||
        onStoreTap == null ||
        plan == null ||
        floor == null ||
        !_indoorTilesRegistered) {
      return false;
    }
    // 이름·아이콘을 폴리곤보다 먼저 본다. 한 폴리곤을 여러 매장이 나눠 쓰는
    // 자리(타일 라벨의 `shared`)에서는 폴리곤 feature가 같은 도형이라
    // features.first가 언제나 같은 매장을 돌려준다 — 오설록을 눌러도
    // 일상다완이 열리던 원인. 라벨은 백엔드가 매장마다 다른 점에 흩어 놓았다.
    // 묶음 매장(다른 매장 이름을 이어 붙인 구역 항목)은 탭 대상이 아니다.
    final aggregates = aggregateStoreIds(plan.stores);
    var store = await _storeFromLayers(
      pointPx,
      [_indoorIds.sharedStoresLabel, _indoorIds.storesLabel],
      plan,
      skipIds: aggregates,
      sharingAggregates: aggregates,
    );
    if (store == null) {
      store = await _storeFromLayers(
        pointPx,
        [_indoorIds.storesFill],
        plan,
        skipIds: aggregates,
      );
      if (store != null) {
        // 폴리곤으로 잡혔고 그 자리를 여럿이 나눠 쓰면, 화면에 그려진 라벨
        // 중 누른 곳에서 가장 가까운 매장으로 바꾼다.
        store = await _nearestSharingStoreOnScreen(
          controller,
          pointPx,
          store,
          plan,
          aggregates,
        );
      }
    }
    final resolved = store;
    if (resolved == null) return false;
    setState(() => _highlightedStoreId = resolved.id);
    _syncHighlightLayer();
    onStoreTap(
      PoiSearchResult(
        name: resolved.name,
        floor: floor,
        point: resolved.centroid,
        placeId: resolved.id,
        nodeId: resolved.entranceNodeId,
        category: resolved.category,
        subcategory: resolved.subcategory,
      ),
    );
    return true;
  }

  /// [layerIds]를 순서대로 조회해 처음 맞은 매장을 돌려준다. 없으면 null.
  Future<StorePolygon?> _storeFromLayers(
    Point<double> pointPx,
    List<String> layerIds,
    FloorPlan plan, {
    Set<String> skipIds = const {},
    // 묶음 라벨(「첫 매장 외 N」, 타일의 `cluster` 속성)을 만났을 때 그룹을
    // 되찾는 데 쓴다. null이면 cluster를 일반 매장처럼 취급한다.
    Set<String>? sharingAggregates,
  }) async {
    final controller = _mapController;
    if (controller == null) return null;
    for (final layerId in layerIds) {
      List<dynamic> features;
      try {
        features = await controller.queryRenderedFeatures(pointPx, [
          layerId,
        ], null);
      } catch (_) {
        continue;
      }
      // 구역 폴리곤(묶음)과 그 안 매장 폴리곤이 겹쳐 오므로, [skipIds]가
      // 아닌 첫 feature를 고른다.
      for (final feature in features) {
        final properties = (feature as Map)['properties'] as Map?;
        final id = properties?['id'] as String?;
        if (id == null || skipIds.contains(id)) continue;
        final store = plan.stores.where((s) => s.id == id).firstOrNull;
        if (store == null) continue;
        // 묶음 라벨 — 이 자리의 매장 목록 시트에서 고르게 한다.
        if (properties?['cluster'] != null && sharingAggregates != null) {
          if (!mounted) return null;
          final group = plan.stores
              .where(
                (s) =>
                    !sharingAggregates.contains(s.id) &&
                    s.centroid.latitude == store.centroid.latitude &&
                    s.centroid.longitude == store.centroid.longitude,
              )
              .toList();
          if (group.length >= 2) {
            return showStoreClusterSheet(context, group);
          }
        }
        return store;
      }
    }
    return null;
  }

  /// [hit]과 같은 자리(중심점)를 나눠 쓰는 매장이 여럿이면, 각 매장의 라벨
  /// 앵커(화면에 그려진 라벨 점, 없으면 입구 핀·중심점)를 화면 좌표로 바꿔
  /// **누른 곳에서 가장 가까운** 매장을 고른다. 혼자 쓰면 [hit] 그대로.
  Future<StorePolygon?> _nearestSharingStoreOnScreen(
    MapLibreMapController controller,
    Point<double> pointPx,
    StorePolygon hit,
    FloorPlan plan,
    Set<String> aggregateIds,
  ) async {
    final sharing = plan.stores
        .where(
          (s) =>
              !aggregateIds.contains(s.id) &&
              s.centroid.latitude == hit.centroid.latitude &&
              s.centroid.longitude == hit.centroid.longitude,
        )
        .toList();
    if (sharing.length < 2) return hit;
    // 세 곳 이상은 라벨이 묶음 하나뿐이라 "가장 가까운 라벨"로 가릴 수 없다.
    // 묶음 라벨을 눌렀을 때와 같은 목록 시트에서 고르게 한다.
    if (sharing.length >= 3) {
      if (!mounted) return hit;
      return await showStoreClusterSheet(context, sharing) ?? hit;
    }

    // 화면에 실제로 그려진 라벨 점. 백엔드가 흩어 놓은 좌표가 geometry로 온다.
    final anchorsById = <String, LatLng>{};
    try {
      final rendered = await controller.queryRenderedFeaturesInRect(
        Rect.fromCenter(
          center: Offset(pointPx.x, pointPx.y),
          width: 240,
          height: 240,
        ),
        [_indoorIds.sharedStoresLabel, _indoorIds.storesLabel],
        null,
      );
      for (final feature in rendered) {
        final map = feature as Map;
        final id = (map['properties'] as Map?)?['id'] as String?;
        final coords = ((map['geometry'] as Map?)?['coordinates'] as List?);
        if (id != null && coords != null && coords.length >= 2) {
          anchorsById[id] = LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          );
        }
      }
    } catch (_) {}

    StorePolygon? best;
    var bestDistance = double.infinity;
    for (final store in sharing) {
      // 라벨이 안 그려졌으면(축소 구간) 입구 핀으로 대신한다 — 다비오가 이
      // 매장에 찍은 점이라 상대 배치가 라벨과 같다.
      final anchor =
          anchorsById[store.id] ??
          _toMapLatLng(store.entrance ?? store.centroid);
      Point<num> screen;
      try {
        screen = await controller.toScreenLocation(anchor);
      } catch (_) {
        continue;
      }
      final dx = screen.x.toDouble() - pointPx.x;
      final dy = screen.y.toDouble() - pointPx.y;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = store;
      }
    }
    return best ?? hit;
  }
}
