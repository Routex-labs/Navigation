import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/floor_plan.dart';
import 'route_polyline.dart';

/// 매장 폴리곤을 탭할 수 있는 실내 평면도 뷰.
///
/// 원본 SVG(예: 더현대 서울 실내 지도)의 매장 path + data-name/data-category를
/// FloorPlan 데이터로 변환해 넘기면, flutter_map PolygonLayer 기반으로
/// 같은 모양을 그리고 탭 시 [onStoreSelected] 콜백과 선택 하이라이트로
/// "이벤트를 받는" 동작을 재현한다.
class FloorPlanView extends StatefulWidget {
  const FloorPlanView({
    super.key,
    required this.floorPlan,
    this.onStoreSelected,
    this.extraMarkers = const [],
    this.routePoints = const [],
  });

  final FloorPlan floorPlan;
  final ValueChanged<StorePolygon>? onStoreSelected;

  /// 현재 위치 마커 등, 평면도 데이터에는 없는 마커를 추가로 겹쳐 그릴 때 사용.
  final List<Marker> extraMarkers;

  /// 시작점→목적지 경로선. 2개 미만이면 그리지 않는다.
  final List<LatLng> routePoints;

  @override
  State<FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends State<FloorPlanView> {
  final LayerHitNotifier<int> _storeHitNotifier = ValueNotifier(null);
  int? _selectedStoreIndex;

  void _handleTap() {
    final hit = _storeHitNotifier.value;
    if (hit == null || hit.hitValues.isEmpty) return;

    final index = hit.hitValues.first;
    final store = widget.floorPlan.stores[index];
    setState(() => _selectedStoreIndex = index);
    widget.onStoreSelected?.call(store);
  }

  @override
  Widget build(BuildContext context) {
    final floorPlan = widget.floorPlan;
    final fallbackCenter = floorPlan.corridors.isNotEmpty &&
            floorPlan.corridors.first.isNotEmpty
        ? floorPlan.corridors.first.first
        : floorPlan.stores.isNotEmpty
            ? floorPlan.stores.first.centroid
            : (floorPlan.pois.isNotEmpty
                ? floorPlan.pois.first.point
                : const LatLng(0, 0));

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = _fitToViewport(floorPlan, constraints.biggest);
        final pixelsPerUnit = fit?.pixelsPerUnit ?? 1.0;

        return FlutterMap(
          options: MapOptions(
            crs: const CrsSimple(),
            initialCenter: fit?.center ?? fallbackCenter,
            initialZoom: fit?.zoom ?? 19,
          ),
          children: [
            if (floorPlan.footprint.isNotEmpty)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: floorPlan.footprint,
                    color: Colors.transparent,
                    borderColor: Colors.black54,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            if (floorPlan.stores.isNotEmpty)
              GestureDetector(
                onTap: _handleTap,
                child: PolygonLayer<int>(
                  hitNotifier: _storeHitNotifier,
                  polygons: [
                    // 폴리곤 없이 점 정보만 있는 매장(예: 백엔드 실데이터의 호텔 항목)은
                    // 매장 영역을 그릴 수 없으니 건너뛴다.
                    for (final (index, store) in floorPlan.stores.indexed)
                      if (store.polygon.isNotEmpty)
                        Polygon(
                          points: store.polygon,
                          color: index == _selectedStoreIndex
                              ? _selectedFillColor
                              : _storeFillColor(store.category),
                          borderColor: index == _selectedStoreIndex
                              ? _selectedBorderColor
                              : _storeBorderColor,
                          borderStrokeWidth: index == _selectedStoreIndex ? 2.2 : 1.35,
                          hitValue: index,
                        ),
                  ],
                ),
              ),
            PolylineLayer(
              polylines: [
                for (final corridor in floorPlan.corridors)
                  Polyline(points: corridor, color: Colors.grey, strokeWidth: 6),
                if (widget.routePoints.length >= 2)
                  buildRoutePolyline(widget.routePoints),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final store in floorPlan.stores)
                  // 폴리곤이 있으면 폴리곤 크기에 맞춘 라벨을, 점 정보만 있으면
                  // (예: 백엔드 실데이터의 사무시설형 공간) POI와 같은 형태의
                  // 아이콘+라벨 마커를 대신 그린다 — 폴리곤이 없다고 이름 자체가
                  // 안 보이면 지도가 텅 비어 보인다.
                  if (store.polygon.isEmpty)
                    _pointStoreMarker(store)
                  else
                    ?_storeLabelMarker(store, pixelsPerUnit),
                for (final poi in floorPlan.pois)
                  Marker(
                    point: poi.point,
                    width: 80,
                    height: 40,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_iconForPoiType(poi.type), size: 16, color: Colors.black54),
                          Text(
                            poi.name,
                            style: const TextStyle(fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ...widget.extraMarkers,
              ],
            ),
          ],
        );
      },
    );
  }

  ({LatLng center, double zoom, double pixelsPerUnit})? _fitToViewport(
    FloorPlan floorPlan,
    Size viewportSize,
  ) {
    final points = [
      ...floorPlan.footprint,
      for (final store in floorPlan.stores) ...[store.centroid, ...store.polygon],
      for (final corridor in floorPlan.corridors) ...corridor,
      for (final poi in floorPlan.pois) poi.point,
    ];
    if (points.isEmpty || viewportSize.isEmpty) return null;

    var minX = points.first.longitude;
    var maxX = points.first.longitude;
    var minY = points.first.latitude;
    var maxY = points.first.latitude;
    for (final point in points) {
      minX = math.min(minX, point.longitude);
      maxX = math.max(maxX, point.longitude);
      minY = math.min(minY, point.latitude);
      maxY = math.max(maxY, point.latitude);
    }

    const padding = 32.0;
    final availableWidth = math.max(viewportSize.width - padding * 2, 1.0);
    final availableHeight = math.max(viewportSize.height - padding * 2, 1.0);
    // 평면도 폭/높이가 0에 가까우면(예: mock의 단일 지점) 과도한 줌을 막는다.
    final spanX = math.max(maxX - minX, 1e-6);
    final spanY = math.max(maxY - minY, 1e-6);

    // CrsSimple 스케일 공식(Crs.scale)과 동일: scale(zoom) = 256 * 2^zoom.
    final zoomForWidth = _log2(availableWidth / (256 * spanX));
    final zoomForHeight = _log2(availableHeight / (256 * spanY));
    final zoom = math.min(zoomForWidth, zoomForHeight);

    return (
      center: LatLng((minY + maxY) / 2, (minX + maxX) / 2),
      zoom: zoom,
      // 이 줌에서 좌표 1단위가 차지하는 화면 픽셀 수. 매장 라벨 폰트/박스 크기를
      // 매장 폴리곤의 실제 화면 크기에 비례시키는 데 쓴다(안 그러면 작은 매장 위에
      // 고정 크기 글자가 얹혀서 지도보다 텍스트가 더 커 보인다).
      pixelsPerUnit: 256 * math.pow(2, zoom).toDouble(),
    );
  }

  /// 매장 폴리곤의 화면 픽셀 크기에 맞춰 라벨을 그린다. 폴리곤이 너무 작게
  /// 렌더링되면(예: 축소된 상태의 좁은 뷰티 카운터) 라벨을 아예 생략한다.
  /// 폴리곤이 없는 매장(점 정보만 있음)도 라벨을 생략한다.
  Marker? _storeLabelMarker(StorePolygon store, double pixelsPerUnit) {
    if (store.polygon.isEmpty) return null;

    var minX = store.polygon.first.longitude;
    var maxX = store.polygon.first.longitude;
    var minY = store.polygon.first.latitude;
    var maxY = store.polygon.first.latitude;
    for (final point in store.polygon) {
      minX = math.min(minX, point.longitude);
      maxX = math.max(maxX, point.longitude);
      minY = math.min(minY, point.latitude);
      maxY = math.max(maxY, point.latitude);
    }
    final pxWidth = (maxX - minX) * pixelsPerUnit;
    final pxHeight = (maxY - minY) * pixelsPerUnit;
    if (pxWidth < 18 || pxHeight < 12) return null;

    final fontSize = (pxWidth * 0.11).clamp(6.0, 13.0);
    return Marker(
      point: store.centroid,
      width: pxWidth.clamp(20.0, 100.0),
      height: math.min(pxHeight, 28.0),
      child: IgnorePointer(
        child: Text(
          store.name,
          style: TextStyle(fontSize: fontSize),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 폴리곤 없이 점 정보만 있는 매장(공간)용 마커. POI 마커와 같은 모양이다.
  Marker _pointStoreMarker(StorePolygon store) {
    return Marker(
      point: store.centroid,
      width: 80,
      height: 40,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront, size: 16, color: Colors.black54),
            Text(
              store.name,
              style: const TextStyle(fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  static double _log2(double value) => math.log(value) / math.ln2;

  IconData _iconForPoiType(String? type) {
    switch (type) {
      case 'elevator':
        return Icons.elevator;
      case 'escalator':
        return Icons.escalator;
      case 'toilet':
        return Icons.wc;
      case 'exit':
        return Icons.exit_to_app;
      case 'facility':
        return Icons.info_outline;
      default:
        return Icons.place;
    }
  }

  // 원본 SVG의 .store-fashion/.store-beauty/.store-service 채우기 색을 그대로 옮겼다.
  Color _storeFillColor(String? category) {
    switch (category) {
      case 'fashion':
        return const Color(0xFFF3F1EF);
      case 'beauty':
        return const Color(0xFFF5F0F2);
      case 'service':
        return const Color(0xFFF1EEF3);
      default:
        return Colors.blueGrey.withValues(alpha: 0.15);
    }
  }
}

// 원본 SVG .store 테두리 색.
const _storeBorderColor = Color(0xFFD8D4D1);
// 원본 SVG .store.selected 채우기/테두리 색.
const _selectedFillColor = Color(0xFFFFE8AD);
const _selectedBorderColor = Color(0xFFDF8F0C);
