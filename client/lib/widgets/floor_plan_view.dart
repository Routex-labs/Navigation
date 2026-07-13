import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/api_config.dart';
import '../models/floor_plan.dart';

/// maplibre_gl은 web/android/iOS만 지원한다(패키지 자체 pubspec에 명시된
/// 플랫폼 목록). Windows/Linux/macOS 데스크톱에서 `flutter run`으로 띄우면
/// 플러그인이 대체 구현을 찾지 못해 알아보기 힘든
/// "TargetPlatform.windows is not yet supported by the maps plugin" 텍스트를
/// 그대로 그리므로, 그 대신 원인이 분명한 안내를 보여준다.
const _mapSupportedNativePlatforms = {TargetPlatform.android, TargetPlatform.iOS};

bool get _isMapSupportedOnThisPlatform =>
    kIsWeb || _mapSupportedNativePlatforms.contains(defaultTargetPlatform);

const _tileSourceId = 'floor-tiles';
const _routeSourceId = 'floor-route';
const _markersSourceId = 'floor-markers';
const _storesFillLayerId = 'floor-stores-fill';

/// 지도 위에 얹을 현재 위치/목적지 점 마커. 종류에 따라 스타일이 달라진다
/// (마커 색상은 [_markersGeoJson]의 circle-color data-driven 표현식이 결정).
enum MapMarkerKind { current, destination }

/// 매장 폴리곤을 탭할 수 있는 실내 평면도 뷰.
///
/// 건물/층의 벡터 타일(MVT, `GET /buildings/{id}/floors/{floor}/tiles/{z}/{x}/{y}.mvt`)을
/// MapLibre GL 벡터 소스로 얹어서 외곽선·매장·POI를 그린다. 매장 이름 라벨은
/// MapLibre 심볼 레이어(`text-max-width` + 충돌 감지)가 자동 배치하므로,
/// 예전처럼 폴리곤 픽셀 크기에 맞춰 폰트를 직접 계산하다가 텍스트가 박스를
/// 벗어나는 문제가 생기지 않는다.
///
/// 경로선과 현재 위치/목적지 마커는 벡터 타일과 별개로 GeoJSON 소스에
/// 얹는다 — 다익스트라 결과가 바뀔 때마다 소스 데이터만 교체한다.
class FloorPlanView extends StatefulWidget {
  const FloorPlanView({
    super.key,
    required this.buildingId,
    required this.floorName,
    required this.floorPlan,
    this.onStoreSelected,
    this.currentLocation,
    this.destination,
    this.routePoints = const [],
    this.interactive = true,
  });

  final String buildingId;
  final String floorName;
  final FloorPlan floorPlan;
  final ValueChanged<StorePolygon>? onStoreSelected;

  /// 현재 위치 마커. null이면 표시하지 않는다.
  final ll.LatLng? currentLocation;

  /// 목적지 마커. null이면 표시하지 않는다.
  final ll.LatLng? destination;

  /// 시작점→목적지 경로선. 2개 미만이면 그리지 않는다.
  final List<ll.LatLng> routePoints;

  /// false면 스크롤/줌/회전 제스처를 전부 끈다. 웹에서는 MapLibre 지도가
  /// 실제 DOM 캔버스라 그 위에 떠 있는 바텀시트를 스크롤해도 마우스 휠
  /// 이벤트가 새어나가 지도가 같이 움직일 수 있다 — 시트가 열려 있는
  /// 동안은 상위(MapShellScreen)가 이 값을 false로 내려 막는다.
  final bool interactive;

  @override
  State<FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends State<FloorPlanView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;

  @override
  Widget build(BuildContext context) {
    if (!_isMapSupportedOnThisPlatform) {
      return const _UnsupportedPlatformNotice();
    }
    return MapLibreMap(
      styleString: _initialStyle,
      initialCameraPosition: CameraPosition(
        target: _initialCenter(widget.floorPlan),
        zoom: 18,
        bearing: _straighteningBearing(widget.floorPlan.footprint),
      ),
      onMapCreated: (controller) => _controller = controller,
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: _handleMapClick,
      compassEnabled: false,
      myLocationEnabled: false,
      logoEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: widget.interactive,
      tiltGesturesEnabled: widget.interactive,
      dragEnabled: widget.interactive,
    );
  }

  @override
  void didUpdateWidget(covariant FloorPlanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_styleReady) return;
    if (oldWidget.buildingId != widget.buildingId ||
        oldWidget.floorName != widget.floorName) {
      // 건물/층이 바뀌면 위젯을 통째로 다시 만드는 편이 안전하므로
      // (다른 key로 재생성됨) 여기서는 데이터만 갱신되는 경우만 다룬다.
      return;
    }
    if (oldWidget.routePoints != widget.routePoints) {
      _updateRouteSource();
      // 경로가 새로 생기면(이전엔 없다가 이번에 생김) 경로 전체가 화면에
      // 들어오도록 카메라를 자동으로 줌아웃한다. 이미 경로가 있는 상태에서
      // 갱신될 때는(예: PDR 위치가 계속 바뀌는 경우) 다시 맞추지 않는다 —
      // 사용자가 지도를 보는 중에 카메라가 계속 튀면 방해가 된다.
      if (widget.routePoints.length >= 2 && oldWidget.routePoints.length < 2) {
        _fitToRouteBounds(widget.routePoints);
      }
    }
    if (oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.destination != widget.destination) {
      _updateMarkersSource();
    }
  }

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;

    final tileUrl =
        '$apiBaseUrl/buildings/${widget.buildingId}/floors/${widget.floorName}/tiles/{z}/{x}/{y}.mvt';

    await controller.addSource(
      _tileSourceId,
      VectorSourceProperties(tiles: [tileUrl]),
    );

    // 원본 SVG 디자인(hyundai_floor_map_corrected_v6.svg)의 색상을 그대로 옮긴다.
    await controller.addFillLayer(
      _tileSourceId,
      'floor-footprint-fill',
      const FillLayerProperties(
        fillColor: '#FFFFFF',
        fillOutlineColor: '#00000088',
      ),
      sourceLayer: 'footprint',
      enableInteraction: false,
    );
    await controller.addFillLayer(
      _tileSourceId,
      _storesFillLayerId,
      const FillLayerProperties(
        fillColor: '#F3F1EF',
        fillOutlineColor: '#D8D4D1',
      ),
      sourceLayer: 'stores',
    );
    // 매장명 라벨: 폴리곤 크기에 맞춰 폰트를 직접 계산하던 예전 로직 대신
    // MapLibre의 자동 줄바꿈(text-max-width)과 충돌 감지에 맡긴다 —
    // 이게 벡터 타일로 바꾼 핵심 이유(텍스트가 매장 박스를 벗어나는 문제)다.
    await controller.addSymbolLayer(
      _tileSourceId,
      'floor-stores-label',
      SymbolLayerProperties(
        textField: ['get', 'name'],
        textSize: [
          'interpolate',
          ['linear'],
          ['zoom'],
          16,
          9,
          20,
          14,
        ],
        textMaxWidth: 6,
        textVariableAnchor: const ['center'],
        textColor: '#444846',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.2,
        symbolAvoidEdges: true,
        textAllowOverlap: false,
      ),
      sourceLayer: 'stores',
      enableInteraction: false,
    );

    await controller.addCircleLayer(
      _tileSourceId,
      'floor-pois-circle',
      const CircleLayerProperties(
        circleRadius: 4,
        circleColor: '#76AE6D',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 1.2,
      ),
      sourceLayer: 'pois',
      enableInteraction: false,
    );
    await controller.addSymbolLayer(
      _tileSourceId,
      'floor-pois-label',
      const SymbolLayerProperties(
        textField: ['get', 'name'],
        textSize: 10,
        textOffset: [0, 1.2],
        textColor: '#4F5451',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1,
      ),
      sourceLayer: 'pois',
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(_routeSourceId, _emptyFeatureCollection);
    await controller.addLineLayer(
      _routeSourceId,
      'floor-route-line',
      const LineLayerProperties(
        lineColor: '#1A73E8',
        lineWidth: 5,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(_markersSourceId, _emptyFeatureCollection);

    // 세 레이어를 kind별로 나누지 않고(레이어 filter는 웹 플랫폼에서 안정적으로
    // 안 먹는 경우가 있었다), 기존에 이미 검증된 match 표현식(paint 속성 자체를
    // kind로 분기)만으로 스타일을 나눈다 — 해당 kind가 아니면 반지름 0으로 숨긴다.
    //
    // 후광(halo): 현재 위치에서만 보이는 옅은 원 — "여기 있어요" 느낌.
    await controller.addCircleLayer(
      _markersSourceId,
      'floor-markers-halo',
      const CircleLayerProperties(
        circleRadius: [
          'match',
          ['get', 'kind'],
          'current',
          20,
          0,
        ],
        circleColor: '#6C3FE0',
        circleOpacity: [
          'match',
          ['get', 'kind'],
          'current',
          0.15,
          0,
        ],
      ),
      enableInteraction: false,
    );
    // 받침(base): 현재 위치는 흰 원 + 보라 테두리, 목적지는 흰 원(테두리 없음).
    await controller.addCircleLayer(
      _markersSourceId,
      'floor-markers-base',
      const CircleLayerProperties(
        circleRadius: [
          'match',
          ['get', 'kind'],
          'current',
          9,
          'destination',
          11,
          0,
        ],
        circleColor: '#FFFFFF',
        circleStrokeColor: '#6C3FE0',
        circleStrokeWidth: [
          'match',
          ['get', 'kind'],
          'current',
          2.5,
          0,
        ],
      ),
      enableInteraction: false,
    );
    // 중심점(dot): 현재 위치는 보라, 목적지는 빨강 + 흰 테두리의 "핀" 느낌.
    await controller.addCircleLayer(
      _markersSourceId,
      'floor-markers-dot',
      const CircleLayerProperties(
        circleRadius: [
          'match',
          ['get', 'kind'],
          'current',
          4,
          'destination',
          8,
          0,
        ],
        circleColor: [
          'match',
          ['get', 'kind'],
          'destination',
          '#E53935',
          '#6C3FE0',
        ],
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: [
          'match',
          ['get', 'kind'],
          'destination',
          1.5,
          0,
        ],
      ),
      enableInteraction: false,
    );

    _styleReady = true;
    await _updateRouteSource();
    await _updateMarkersSource();
    if (widget.routePoints.length >= 2) {
      await _fitToRouteBounds(widget.routePoints);
    } else {
      await _fitToFootprint();
    }
  }

  /// 경로 전체(출발점~도착점)가 화면 안에 들어오도록 카메라를 맞춘다.
  /// `newLatLngBounds`는 카메라 tilt/bearing을 0(정북)으로 되돌리므로,
  /// [_fitToFootprint]가 쓰는 건물 정렬 회전은 경로를 보여주는 동안은 잠시
  /// 포기한다 — 경로 전체를 보여주는 목적이 건물 정렬보다 우선한다.
  Future<void> _fitToRouteBounds(List<ll.LatLng> points) async {
    final controller = _controller;
    if (controller == null || points.length < 2) return;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    // 출발점과 도착점이 사실상 같은 좌표면 경계 상자 폭이 0에 가까워져
    // 줌 계산이 발산한다 — 이 경우엔 화면에 맞출 "경로"랄 게 없으니 건너뛴다.
    if ((maxLat - minLat).abs() < 1e-6 && (maxLng - minLng).abs() < 1e-6) return;

    await controller.moveCamera(
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

  /// 화면(뷰포트) 크기에 맞춰 건물이 최대한 크게(=매장 라벨이 최대한 많이
  /// 안 겹치고 보이게) 나오도록 카메라 bearing과 zoom을 같이 계산해서 적용한다.
  ///
  /// `newLatLngBounds`는 항상 지도를 정북 방향으로 맞춘 뒤 그 상태 기준으로
  /// zoom을 정하기 때문에, 그 다음에 건물을 반듯하게 돌리는(bearing) 회전을
  /// 더하면 회전된 모양이 뷰포트에 다시 안 맞아 여백이 생긴다(예: 가로로
  /// 긴 건물을 세로로 긴 화면에 정북 기준으로 맞추면 좌우 폭에 걸려 축소된
  /// 채로, 돌려도 그 축소율 그대로 남는다). 그래서 bearing 후보 두 개(건물
  /// 외곽선에 맞춘 각도, 그리고 그걸 90도 돌린 각도) 각각에 대해 "그 각도로
  /// 봤을 때 건물이 뷰포트에 얼마나 크게 들어가는지"를 직접 계산해서 더 크게
  /// 보이는 쪽을 고른다.
  Future<void> _fitToFootprint() async {
    final controller = _controller;
    final footprint = widget.floorPlan.footprint;
    if (controller == null || footprint.isEmpty) return;

    final viewport = MediaQuery.sizeOf(context);
    final fit = _fitBearingAndZoom(footprint, viewport);

    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toMapLibreLatLng(_centroid(footprint)),
          zoom: fit.zoom,
          bearing: fit.bearing,
        ),
      ),
    );
  }

  static ll.LatLng _centroid(List<ll.LatLng> footprint) {
    final lat = footprint.map((p) => p.latitude).reduce((a, b) => a + b) / footprint.length;
    final lng = footprint.map((p) => p.longitude).reduce((a, b) => a + b) / footprint.length;
    return ll.LatLng(lat, lng);
  }

  static const _metersPerDegreeLat = 111320.0;
  static const _fitPaddingPx = 24.0;
  // 표준 Web Mercator 상수: 적도에서 zoom 0일 때 픽셀당 미터.
  static const _metersPerPixelAtZoom0Equator = 156543.03392804097;

  static ({double bearing, double zoom}) _fitBearingAndZoom(
    List<ll.LatLng> footprint,
    Size viewport,
  ) {
    final center = _centroid(footprint);
    final cosLat = cos(center.latitude * pi / 180);

    // 외곽선을 중심 기준 등방(=1 단위가 어느 축이든 같은 실제 거리) 평면
    // 좌표(미터)로 바꾼다 — 회전/거리 계산을 위/경도 그대로 하면 위도에 따라
    // 경도 1도의 실제 거리가 달라 왜곡되기 때문이다.
    final localPoints = footprint.map((p) {
      final dx = (p.longitude - center.longitude) * cosLat * _metersPerDegreeLat;
      final dy = (p.latitude - center.latitude) * _metersPerDegreeLat;
      return Offset(dx, dy);
    }).toList();

    final axisBearing = _straighteningBearing(footprint);
    final availableWidth = max(1.0, viewport.width - _fitPaddingPx * 2);
    final availableHeight = max(1.0, viewport.height - _fitPaddingPx * 2);

    var bestBearing = 0.0;
    var bestZoom = double.negativeInfinity;
    for (final candidate in [axisBearing, axisBearing + 90]) {
      final rad = candidate * pi / 180;
      final cosB = cos(rad);
      final sinB = sin(rad);

      var minX = double.infinity, maxX = double.negativeInfinity;
      var minY = double.infinity, maxY = double.negativeInfinity;
      for (final p in localPoints) {
        // 카메라 bearing이 candidate일 때 화면에 어떻게 투영되는지: 화면
        // "위"는 나침반 방향 candidate, "오른쪽"은 candidate+90을 가리킨다.
        final rx = p.dx * cosB - p.dy * sinB;
        final ry = p.dx * sinB + p.dy * cosB;
        minX = min(minX, rx);
        maxX = max(maxX, rx);
        minY = min(minY, ry);
        maxY = max(maxY, ry);
      }
      final widthM = maxX - minX;
      final heightM = maxY - minY;
      if (widthM <= 0 || heightM <= 0) continue;

      final metersPerPixelAtLat = _metersPerPixelAtZoom0Equator * cosLat;
      final metersPerPixelNeeded = max(widthM / availableWidth, heightM / availableHeight);
      final zoom = log(metersPerPixelAtLat / metersPerPixelNeeded) / log(2);

      if (zoom > bestZoom) {
        bestZoom = zoom;
        bestBearing = candidate;
      }
    }

    if (bestZoom.isFinite) return (bearing: bestBearing, zoom: bestZoom);
    return (bearing: axisBearing, zoom: 18.0);
  }

  Future<void> _updateRouteSource() async {
    final controller = _controller;
    if (controller == null) return;
    final points = widget.routePoints;
    if (points.length < 2) {
      await controller.setGeoJsonSource(_routeSourceId, _emptyFeatureCollection);
      return;
    }
    await controller.setGeoJsonSource(_routeSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final point in points) [point.longitude, point.latitude],
            ],
          },
        },
      ],
    });
  }

  Future<void> _updateMarkersSource() async {
    final controller = _controller;
    if (controller == null) return;
    final features = <Map<String, dynamic>>[];
    final current = widget.currentLocation;
    final destination = widget.destination;
    if (current != null) {
      features.add(_markerFeature(current, MapMarkerKind.current));
    }
    if (destination != null) {
      features.add(_markerFeature(destination, MapMarkerKind.destination));
    }
    await controller.setGeoJsonSource(_markersSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  Map<String, dynamic> _markerFeature(ll.LatLng point, MapMarkerKind kind) {
    return {
      'type': 'Feature',
      'properties': {'kind': kind.name},
      'geometry': {
        'type': 'Point',
        'coordinates': [point.longitude, point.latitude],
      },
    };
  }

  Future<void> _handleMapClick(Point<double> point, LatLng coordinates) async {
    final controller = _controller;
    final onStoreSelected = widget.onStoreSelected;
    if (controller == null || onStoreSelected == null) return;

    final features = await controller.queryRenderedFeatures(
      point,
      [_storesFillLayerId],
      null,
    );
    if (features.isEmpty) return;

    final properties = (features.first as Map)['properties'] as Map?;
    final id = properties?['id'] as String?;
    if (id == null) return;

    final store = widget.floorPlan.stores.where((s) => s.id == id).firstOrNull;
    if (store != null) onStoreSelected(store);
  }

  LatLng _initialCenter(FloorPlan floorPlan) {
    if (floorPlan.footprint.isNotEmpty) {
      return _toMapLibreLatLng(floorPlan.footprint.first);
    }
    if (floorPlan.stores.isNotEmpty) {
      return _toMapLibreLatLng(floorPlan.stores.first.centroid);
    }
    if (floorPlan.pois.isNotEmpty) {
      return _toMapLibreLatLng(floorPlan.pois.first.point);
    }
    return const LatLng(37.5665, 126.9780); // fallback: 서울시청
  }

  static LatLng _toMapLibreLatLng(ll.LatLng point) {
    return LatLng(point.latitude, point.longitude);
  }

  /// 건물 외곽선의 실제 방위각(진북 기준)과 화면(북쪽=위) 사이의 어긋남만큼
  /// 카메라를 회전시켜서, 실좌표(WGS84) 데이터는 그대로 두고 화면에는 건물이
  /// 반듯하게(축에 맞춰) 보이도록 하는 bearing을 계산한다.
  ///
  /// 외곽선에서 가장 긴 변의 진북 기준 방위각을 구해 90으로 나눈 나머지를
  /// 쓴다 — 그 나머지만큼 카메라를 돌리면 그 변이 화면에서 수평/수직에 맞춰진다.
  static double _straighteningBearing(List<ll.LatLng> footprint) {
    if (footprint.length < 2) return 0.0;

    final meanLatRad = footprint.map((p) => p.latitude).reduce((a, b) => a + b) /
        footprint.length *
        (pi / 180);
    final cosLat = cos(meanLatRad);

    var longestLength = -1.0;
    var longestBearingDeg = 0.0;
    for (var i = 0; i < footprint.length; i++) {
      final p1 = footprint[i];
      final p2 = footprint[(i + 1) % footprint.length];
      final dx = (p2.longitude - p1.longitude) * cosLat;
      final dy = p2.latitude - p1.latitude;
      final length = sqrt(dx * dx + dy * dy);
      if (length > longestLength) {
        longestLength = length;
        longestBearingDeg = atan2(dx, dy) * 180 / pi;
      }
    }

    return longestBearingDeg % 90;
  }
}

class _UnsupportedPlatformNotice extends StatelessWidget {
  const _UnsupportedPlatformNotice();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF3F1EF),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 40, color: Colors.black45),
              SizedBox(height: 12),
              Text(
                '실내 지도는 웹 브라우저 또는 모바일 앱에서만 볼 수 있어요.\n'
                'Windows 데스크톱 앱에서는 아직 지원하지 않아요.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _emptyFeatureCollection = {'type': 'FeatureCollection', 'features': <Map<String, dynamic>>[]};

// 원본 SVG(hyundai_floor_map_corrected_v6.svg)의 배경색을 그대로 옮겼다.
// 나머지 레이어(외곽선/매장/POI/경로)는 스타일 로드 후 벡터·GeoJSON
// 소스로 추가한다.
const _initialStyle = '''
{
  "version": 8,
  "sources": {},
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "#EDF4E7"}}
  ]
}
''';
