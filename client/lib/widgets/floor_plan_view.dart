import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/api_config.dart';
import '../features/debug_mode/debug_map_overlay.dart';
import '../models/floor_plan.dart';

/// maplibre_gl은 web/android/iOS만 지원한다(패키지 자체 pubspec에 명시된
/// 플랫폼 목록). Windows/Linux/macOS 데스크톱에서 `flutter run`으로 띄우면
/// 플러그인이 대체 구현을 찾지 못해 알아보기 힘든
/// "TargetPlatform.windows is not yet supported by the maps plugin" 텍스트를
/// 그대로 그리므로, 그 대신 원인이 분명한 안내를 보여준다.
const _mapSupportedNativePlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
};

bool get _isMapSupportedOnThisPlatform =>
    kIsWeb || _mapSupportedNativePlatforms.contains(defaultTargetPlatform);

const _tileSourceId = 'floor-tiles';
const _routeSourceId = 'floor-route';
const _pdrTrailSourceId = 'floor-pdr-trail';
const _pdrRawTrailSourceId = 'floor-pdr-raw-trail';
const _pdrConfirmedTrailSourceId = 'floor-pdr-confirmed-trail';
const _debugGraphSourceId = 'floor-debug-graph';
const _markersSourceId = 'floor-markers';
const _highlightSourceId = 'floor-highlight';
const _storesFillLayerId = 'floor-stores-fill';

/// POI `type` 속성(백엔드 실데이터 값)을 지도 위 아이콘에 매핑한다. 건물마다
/// 명명이 조금씩 달라(더현대는 elevator/escalator/toilet/exit, 데모 건물인
/// 데이터셋마다 vertical-connection/core-entrance 등을 쓸 수 있어 여러 값을 같은
/// 아이콘으로 묶는다. 매핑에 없는 값(facility/poi 등)은 [_defaultPoiIcon]으로
/// 그린다.
const _poiIconByType = <String, IconData>{
  'elevator': Icons.elevator,
  'vertical-connection': Icons.elevator,
  'escalator': Icons.escalator,
  'toilet': Icons.wc,
  'exit': Icons.exit_to_app,
  'core-entrance': Icons.exit_to_app,
  'facility': Icons.info_outline,
};
const _defaultPoiIcon = Icons.place;
const _poiIconBackgroundColor = Color(0xFF76AE6D);

/// [MapLibreMapController.addImage]에 등록할 때 쓰는 이름. 같은 아이콘을
/// 여러 type이 공유할 수 있으므로 type이 아니라 아이콘 자체를 키로 삼아
/// 중복 렌더링/등록을 피한다.
String _poiIconImageName(IconData icon) => 'poi-icon-${icon.codePoint}';

/// 목적지 핀 이미지의 addImage 등록 이름.
const _destinationPinImageName = 'marker-destination-pin';
const _currentLocationImageName = 'marker-current-location';
const _currentLocationDotImageName = 'marker-current-location-dot';

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
    this.onMapPressed,
    this.currentLocation,
    this.currentHeadingDegrees,
    this.destination,
    this.routePoints = const [],
    this.pdrPathPoints = const [],
    this.pdrRawPathPoints = const [],
    this.pdrConfirmedPathPoints = const [],
    this.debugMapOverlay = const DebugMapOverlay(),
    this.interactive = true,
    this.highlightedStoreId,
    this.visibleInsets = EdgeInsets.zero,
    this.overlayHitTest,
    this.onCameraBearingChanged,
  });

  final String buildingId;
  final String floorName;
  final FloorPlan floorPlan;
  final ValueChanged<StorePolygon>? onStoreSelected;

  /// PDR anchor를 놓는 중인 경우 지도 빈 곳 탭을 상위에 전달한다. true를
  /// 반환하면 해당 탭은 매장 선택으로 이어지지 않는다.
  final bool Function(ll.LatLng point)? onMapPressed;

  /// 선택된(또는 포커스된) 매장의 [StorePolygon.id]. null이면 강조 표시가 없다.
  final String? highlightedStoreId;

  /// 지도 위에 얹은 Flutter 오버레이(층 selector 같은)가 자기 영역을 알려주는
  /// 콜백. 인자는 화면 전역 좌표. true 반환 시 그 좌표의 탭은 매장 선택으로
  /// 이어지지 않는다.
  ///
  /// MapLibre는 PlatformView라 위에 얹힌 Flutter 위젯 위의 탭이 gesture arena
  /// 를 우회해 네이티브 지도까지 흘러들어와 매장까지 함께 선택되는 문제가 있다.
  /// 이 콜백으로 오버레이 소유자가 명시적으로 그 영역의 탭을 무시하게 한다.
  final bool Function(Offset globalPoint)? overlayHitTest;

  /// 화면 위/오른쪽처럼 뷰포트 기준 방향을 실제 지도 방향으로 바꿀 수 있도록
  /// 현재 카메라 bearing(0°=북쪽)을 상위에 알린다.
  final ValueChanged<double>? onCameraBearingChanged;

  /// 현재 위치 마커. null이면 표시하지 않는다.
  final ll.LatLng? currentLocation;

  /// 현재 위치 화살표가 가리킬 방향(북쪽 기준 시계방향 각도). null이면
  /// 아직 방향을 몰라 북쪽(0도)을 기본값으로 그린다 — 실내는 PDR 방향
  /// 추정이 이 값으로 연동되기 전까지는 항상 null이다.
  final double? currentHeadingDegrees;

  /// 목적지 마커. null이면 표시하지 않는다.
  final ll.LatLng? destination;

  /// 시작점→목적지 경로선. 2개 미만이면 그리지 않는다.
  final List<ll.LatLng> routePoints;

  /// navigation graph에 부착한 PDR 경로. 보라색 실선으로 렌더한다.
  /// 기존 호출부 호환을 위해 필드 이름은 유지한다.
  final List<ll.LatLng> pdrPathPoints;

  /// 아직 확정되지 않은 accel preview 경로. 주황색 점선으로 렌더한다.
  final List<ll.LatLng> pdrRawPathPoints;

  /// 센서 파이프라인이 자체 확정한 PDR 경로. 초록색 실선으로 렌더한다.
  final List<ll.LatLng> pdrConfirmedPathPoints;

  /// 디버그 모드에서만 채워지는 navigation graph 노드·간선 데이터.
  final DebugMapOverlay debugMapOverlay;

  /// false면 스크롤/줌/회전 제스처를 전부 끈다. 웹에서는 MapLibre 지도가
  /// 실제 DOM 캔버스라 그 위에 떠 있는 바텀시트를 스크롤해도 마우스 휠
  /// 이벤트가 새어나가 지도가 같이 움직일 수 있다 — 시트가 열려 있는
  /// 동안은 상위(MapShellScreen)가 이 값을 false로 내려 막는다.
  final bool interactive;

  /// 지도 위에 얹혀 있어 실제 지도 영역을 가리는 UI(상단 검색바/하단 홈-실내
  /// 버튼바/ETA 카드 등)의 두께. 지도 자체는 화면 끝까지 그려지지만 축소 하한을
  /// 계산할 때는 이만큼 좁은 영역에 건물이 들어오도록 잡아야, 하한에 도달했을 때
  /// 건물의 위/아래가 오버레이 뒤로 밀려 안 보이는 일이 없다. 상위가 자기가
  /// 얹은 UI 크기를 알고 있으므로 여기에 그대로 전달한다.
  final EdgeInsets visibleInsets;

  @override
  State<FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends State<FloorPlanView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  Size? _lastViewport;
  double? _minZoom;

  @override
  Widget build(BuildContext context) {
    if (!_isMapSupportedOnThisPlatform) {
      return const _UnsupportedPlatformNotice();
    }
    // 건물 전체가 화면에 다 들어오는 줌보다 더 축소되지 않도록 최솟값으로
    // 고정한다. _fitBearingAndZoom은 건물 정렬 각도를 가정하고 화면을 꽉
    // 채우는 줌을 구하는데, 그 값을 그대로 하한으로 쓰면 사용자가 지도를
    // 회전했을 때(회전하면 외곽선이 화면에 더 넓게 걸쳐짐) 그 줌으로는
    // 건물 일부가 화면 밖으로 밀려나는데도 더 축소를 못 하는 문제가 있었다
    // — 그래서 회전 각도와 무관하게 항상 전체가 들어오도록 회전-불변
    // 반지름(중심~가장 먼 꼭짓점) 기준으로 따로 계산한다.
    //
    // 뷰포트 크기는 MediaQuery.sizeOf 대신 LayoutBuilder로 얻은 지도 위젯의
    // 실제 크기를 쓴다. 상단 정보바/하단 ETA 카드처럼 지도 밖 UI가 자리를
    // 차지하고 있을 때 화면 전체 크기로 계산하면 실제 지도 영역보다 큰
    // 뷰포트를 가정해 하한이 필요 이상으로 낮게(=더 많이 축소 가능) 나온다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return _buildMap(viewport);
      },
    );
  }

  Widget _buildMap(Size viewport) {
    _lastViewport = viewport;
    // 축소 하한은 "건물이 실제로 얼마나 큰가"만 알면 되고, 그 위치가 지도 어디에
    // 놓여 있는지는 필요 없다(줌 레벨은 화면 픽셀당 지도 미터 비율만 결정하므로).
    // 백엔드가 항상 채워 내려주는 footprint_local_m(미터 좌표)에서 반지름을
    // 뽑아 쓴다 — 실좌표 앵커가 없어 footprint_wgs84가 비어 오는 건물이라도
    // 여기서는 상관없이 정확한 건물 크기를 얻는다. local_m이 어쩌다 비어
    // 있다면 매장/POI 좌표(wgs84)로 폴백한다.
    final minZoom = _computeMinZoom(
      widget.floorPlan,
      viewport,
      widget.visibleInsets,
    );
    _minZoom = minZoom;
    return MapLibreMap(
      styleString: _initialStyle,
      initialCameraPosition: CameraPosition(
        target: _initialCenter(widget.floorPlan),
        zoom: 18,
        bearing: _straighteningBearing(widget.floorPlan.footprint),
      ),
      minMaxZoomPreference: MinMaxZoomPreference(minZoom, null),
      // _enforceMinZoom이 controller.cameraPosition으로 현재 줌을 읽는데,
      // 이 값은 trackCameraPosition이 켜져 있을 때만 갱신된다. 꺼두면
      // initialCameraPosition의 줌(18)에 영원히 멈춰 있어서, 사용자가 확대해도
      // onCameraIdle마다 "하한보다 낮다"고 오판하고 줌을 되돌려버린다.
      trackCameraPosition: true,
      onMapCreated: (controller) {
        _controller = controller;
        _notifyCameraBearing();
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: _handleMapClick,
      onCameraMove: (position) =>
          widget.onCameraBearingChanged?.call(position.bearing),
      // maplibre_gl 웹 구현이 minMaxZoomPreference를 놓치는 경우에 대비한
      // 이중 안전장치. 제스처가 끝난 시점에 하한 아래로 내려가 있으면
      // 하한으로 다시 올려서, "축소하면 건물이 사라진다"는 문제를 뿌리째 막는다.
      onCameraIdle: _handleCameraIdle,
      // 웹에서는 기본값(false)이면 매장 폴리곤처럼 상호작용 가능한 레이어를
      // 탭했을 때 onMapClick이 아예 안 불려서(대신 별도 feature-tap 이벤트만
      // 발생) 매장을 눌러도 아무 반응이 없었다. onMapClick 하나로 매장 탭
      // 여부까지 직접 판별하는 _handleMapClick 구조를 그대로 쓰려면 이 값을
      // true로 켜서 매장을 눌렀을 때도 onMapClick이 항상 같이 불리게 해야 한다.
      featureTapsTriggersMapClick: true,
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
    if (oldWidget.pdrPathPoints != widget.pdrPathPoints) {
      _updatePdrTrailSource();
    }
    if (oldWidget.pdrRawPathPoints != widget.pdrRawPathPoints) {
      _updatePdrRawTrailSource();
    }
    if (oldWidget.pdrConfirmedPathPoints != widget.pdrConfirmedPathPoints) {
      _updatePdrConfirmedTrailSource();
    }
    if (oldWidget.debugMapOverlay != widget.debugMapOverlay) {
      _updateDebugGraphSource();
    }
    if (oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.currentHeadingDegrees != widget.currentHeadingDegrees ||
        oldWidget.destination != widget.destination) {
      _updateMarkersSource();
    }
    if (oldWidget.highlightedStoreId != widget.highlightedStoreId) {
      _updateHighlightSource();
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
        textFont: _mapFontStack,
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

    // 엘리베이터/에스컬레이터/화장실 같은 POI는 단순 점 대신 종류별 아이콘으로
    // 그린다. MapLibre 심볼 레이어는 사전 등록된 비트맵만 참조할 수 있어서,
    // 필요한 아이콘들을 먼저 오프스크린 렌더링해 addImage로 등록한 다음
    // type 속성에 따라 골라 쓰는 match 표현식을 iconImage에 건다.
    for (final icon in {..._poiIconByType.values, _defaultPoiIcon}) {
      await controller.addImage(
        _poiIconImageName(icon),
        await _renderPoiIcon(icon),
      );
    }
    await controller.addImage(
      _destinationPinImageName,
      await _renderDestinationPinIcon(),
    );
    await controller.addImage(
      _currentLocationImageName,
      await _renderCurrentLocationIcon(showHeading: true),
    );
    await controller.addImage(
      _currentLocationDotImageName,
      await _renderCurrentLocationIcon(showHeading: false),
    );
    await controller.addSymbolLayer(
      _tileSourceId,
      'floor-pois-icon',
      SymbolLayerProperties(
        iconImage: [
          'match',
          ['get', 'type'],
          for (final entry in _poiIconByType.entries) ...[
            entry.key,
            _poiIconImageName(entry.value),
          ],
          _poiIconImageName(_defaultPoiIcon),
        ],
        iconSize: 0.32,
        iconAllowOverlap: true,
      ),
      sourceLayer: 'pois',
      enableInteraction: false,
    );
    await controller.addSymbolLayer(
      _tileSourceId,
      'floor-pois-label',
      const SymbolLayerProperties(
        textField: ['get', 'name'],
        textFont: _mapFontStack,
        textSize: 10,
        textOffset: [0, 1.6],
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
        lineOpacity: 0.6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _debugGraphSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _debugGraphSourceId,
      'floor-debug-graph-edges',
      const LineLayerProperties(
        lineColor: '#607D8B',
        lineWidth: 2,
        lineOpacity: 0.72,
        lineDasharray: [2, 1.5],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'kind'],
        'edge',
      ],
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _debugGraphSourceId,
      'floor-debug-graph-active-edges',
      const LineLayerProperties(
        lineColor: '#00ACC1',
        lineWidth: 5,
        lineOpacity: 0.88,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        'all',
        [
          '==',
          ['get', 'kind'],
          'edge',
        ],
        [
          '==',
          ['get', 'active'],
          true,
        ],
      ],
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _debugGraphSourceId,
      'floor-debug-graph-nodes',
      const CircleLayerProperties(
        circleRadius: 4,
        circleColor: '#FFFFFF',
        circleStrokeColor: '#455A64',
        circleStrokeWidth: 2,
      ),
      filter: [
        '==',
        ['get', 'kind'],
        'node',
      ],
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _debugGraphSourceId,
      'floor-debug-graph-active-nodes',
      const CircleLayerProperties(
        circleRadius: 6,
        circleColor: '#00ACC1',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
      filter: [
        'all',
        [
          '==',
          ['get', 'kind'],
          'node',
        ],
        [
          '==',
          ['get', 'active'],
          true,
        ],
      ],
      enableInteraction: false,
    );
    await controller.addGeoJsonSource(
      _pdrRawTrailSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _pdrRawTrailSourceId,
      'floor-pdr-raw-trail-line',
      const LineLayerProperties(
        lineColor: '#F57C00',
        lineWidth: 3.25,
        lineOpacity: 0.95,
        lineDasharray: [1.5, 1.5],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _pdrConfirmedTrailSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _pdrConfirmedTrailSourceId,
      'floor-pdr-confirmed-trail-casing',
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 6.25,
        lineOpacity: 0.82,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _pdrConfirmedTrailSourceId,
      'floor-pdr-confirmed-trail-line',
      const LineLayerProperties(
        lineColor: '#2E7D32',
        lineWidth: 3.25,
        lineOpacity: 0.96,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _pdrTrailSourceId,
      _emptyFeatureCollection,
    );
    // 그래프에 부착한 경로는 raw(주황)·confirmed(초록)와 겹쳐도 구별되도록
    // 보라색으로 그린다. 세 소스가 독립적이라 디버그 설정에서 각각 끌 수 있다.
    await controller.addLineLayer(
      _pdrTrailSourceId,
      'floor-pdr-trail-casing',
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 6.5,
        lineOpacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _pdrTrailSourceId,
      'floor-pdr-trail-line',
      const LineLayerProperties(
        lineColor: '#7E57C2',
        lineWidth: 3.25,
        lineOpacity: 0.96,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _markersSourceId,
      _emptyFeatureCollection,
    );

    // 현재 위치와 heading을 하나의 심볼로 합친다. 미터 단위 GeoJSON 폴리곤은
    // 확대할수록 화살표만 커지므로, 고정 픽셀 PNG를 회전시켜 점과 방향 표시가
    // 언제나 같은 비율과 크기를 유지하게 한다. heading이 없을 때는 북쪽을
    // 임의로 가리키지 않고 동일 디자인의 원형 점만 사용한다.
    await controller.addSymbolLayer(
      _markersSourceId,
      'floor-markers-current',
      const SymbolLayerProperties(
        iconImage: [
          'case',
          ['has', 'heading'],
          _currentLocationImageName,
          _currentLocationDotImageName,
        ],
        iconSize: 1.15,
        iconRotate: [
          'coalesce',
          ['get', 'heading'],
          0,
        ],
        iconRotationAlignment: 'map',
        iconPitchAlignment: 'viewport',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      filter: [
        '==',
        ['get', 'kind'],
        'current',
      ],
      enableInteraction: false,
    );

    // 목적지는 빨간 물방울 핀(_destinationPinImageName)에 "도착" 텍스트를
    // 얹어서 표시한다. 텍스트는 아이콘에 미리 굽지 않고 MapLibre의 textField로
    // 얹는데, 이는 Flutter 웹 CanvasKit에서 오프스크린 캔버스로 렌더링한
    // 이미지에는 한글 글리프가 있는 폰트가 자동으로 딸려오지 않아 "도착"이
    // 두부(tofu) 박스로 뭉개지기 때문이다(반면 MapLibre의 심볼 텍스트는
    // 매장명 라벨과 동일한 경로를 타서 한글이 정상적으로 나온다).
    //
    // 아이콘 바닥(tip)이 실제 좌표에 오도록 iconAnchor는 bottom, 텍스트는
    // 핀의 흰 원 안쪽 중앙에 오도록 textAnchor를 center로 잡고 textOffset
    // y를 -3.7 em 만큼 올려 얹는다(핀 원본 이미지에서 흰 원 중앙이 밑변에서
    // 위로 112px, iconSize/textSize 비율을 0.033으로 고정하면 offset은
    // 112 × 0.033 ≈ 3.7 em이 되어 zoom과 무관하게 같은 위치를 유지한다).
    // iconSize/textSize는 zoom 16↔20 구간에서 같이 커지는 interpolate 식으로
    // 걸어, 축소했을 때 핀이 지도를 다 가리는 문제를 피한다.
    //
    // 현재 위치는 이 소스에 함께 들어와 있어도 filter가 걸러낸다.
    await controller.addSymbolLayer(
      _markersSourceId,
      'floor-markers-destination-pin',
      const SymbolLayerProperties(
        iconImage: _destinationPinImageName,
        iconSize: [
          'interpolate',
          ['linear'],
          ['zoom'],
          16,
          0.115,
          20,
          0.25,
        ],
        iconAnchor: 'bottom',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        textField: '도착',
        textSize: [
          'interpolate',
          ['linear'],
          ['zoom'],
          16,
          3.5,
          20,
          7.5,
        ],
        textColor: '#1E2033',
        textAnchor: 'center',
        textOffset: [0, -3.7],
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      filter: [
        '==',
        ['get', 'kind'],
        'destination',
      ],
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _highlightSourceId,
      _emptyFeatureCollection,
    );
    // 선택된 매장을 옅게 채우고 테두리 선 색을 진하게 바꿔서 "포커스"가
    // 어디 있는지 보여준다. 매장 탭/검색으로 고른 매장이 바뀔 때마다
    // _updateHighlightSource가 이 소스의 폴리곤만 바꿔치기한다.
    await controller.addFillLayer(
      _highlightSourceId,
      'floor-highlight-fill',
      const FillLayerProperties(fillColor: '#1A73E8', fillOpacity: 0.16),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _highlightSourceId,
      'floor-highlight-line',
      const LineLayerProperties(
        lineColor: '#1A73E8',
        lineWidth: 3,
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    _styleReady = true;
    await _updateRouteSource();
    await _updateDebugGraphSource();
    await _updatePdrRawTrailSource();
    await _updatePdrConfirmedTrailSource();
    await _updatePdrTrailSource();
    await _updateMarkersSource();
    await _updateHighlightSource();
    if (widget.routePoints.length >= 2) {
      await _fitToRouteBounds(widget.routePoints);
    } else {
      await _fitToFootprint();
    }
  }

  void _enforceMinZoom() {
    final controller = _controller;
    final minZoom = _minZoom;
    if (controller == null || minZoom == null) return;
    final position = controller.cameraPosition;
    if (position == null) return;
    // 부동소수 오차로 하한과 사실상 같은 값에서 반복적으로 카메라를 옮기지
    // 않도록 아주 작은 여유(0.01)를 둔다.
    if (position.zoom < minZoom - 0.01) {
      controller.moveCamera(CameraUpdate.zoomTo(minZoom));
    }
  }

  void _handleCameraIdle() {
    _enforceMinZoom();
    _notifyCameraBearing();
  }

  void _notifyCameraBearing() {
    final bearing = _controller?.cameraPosition?.bearing;
    if (bearing != null && bearing.isFinite) {
      widget.onCameraBearingChanged?.call(bearing);
    }
  }

  /// 선택된 매장(있으면)의 폴리곤을 강조 표시용 GeoJSON 소스에 채운다.
  /// 선택이 없으면 빈 FeatureCollection으로 비워서 강조를 지운다.
  Future<void> _updateHighlightSource() async {
    final controller = _controller;
    if (controller == null) return;

    final storeId = widget.highlightedStoreId;
    final store = storeId == null
        ? null
        : widget.floorPlan.stores.where((s) => s.id == storeId).firstOrNull;
    if (store == null || store.polygon.length < 3) {
      await controller.setGeoJsonSource(
        _highlightSourceId,
        _emptyFeatureCollection,
      );
      return;
    }

    final ring = [
      for (final point in store.polygon) [point.longitude, point.latitude],
    ];
    // GeoJSON Polygon 링은 닫혀 있어야 한다(첫 점 == 마지막 점).
    if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
      ring.add(ring.first);
    }

    await controller.setGeoJsonSource(_highlightSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [ring],
          },
        },
      ],
    });
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
    if ((maxLat - minLat).abs() < 1e-6 && (maxLng - minLng).abs() < 1e-6) {
      return;
    }

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

    final viewport = _lastViewport ?? MediaQuery.sizeOf(context);
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
    final lat =
        footprint.map((p) => p.latitude).reduce((a, b) => a + b) /
        footprint.length;
    final lng =
        footprint.map((p) => p.longitude).reduce((a, b) => a + b) /
        footprint.length;
    return ll.LatLng(lat, lng);
  }

  /// Material 아이콘 글리프를 흰 테두리 + 초록 원 배경 위에 흰색으로 그려
  /// PNG 바이트로 오프스크린 렌더링한다. MapLibre 심볼 레이어는 미리 등록된
  /// 비트맵 이미지만 참조할 수 있어서([MapLibreMapController.addImage]),
  /// 폰트 글리프를 직접 캔버스에 그려 이미지로 바꿔야 한다.
  static Future<Uint8List> _renderPoiIcon(IconData icon) async {
    const canvasSize = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
    );
    const center = Offset(canvasSize / 2, canvasSize / 2);

    canvas.drawCircle(center, canvasSize / 2, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      canvasSize / 2 - 5,
      Paint()..color = _poiIconBackgroundColor,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: canvasSize * 0.55,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final image = await recorder.endRecording().toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 목적지 마커의 빨간 물방울 핀 이미지를 오프스크린 렌더링해 PNG 바이트로
  /// 돌려준다. 위쪽 원 + 아래쪽 삼각 꼬리를 같은 빨간색으로 합쳐 물방울
  /// 모양을 만들고, 그 안에 흰 원을 얹는다. 삼각 꼬리의 두 밑변은 원의
  /// 접선에 정확히 맞물리도록 tangentAngle(중심-끝점 축과 접점 사이의 각도,
  /// acos(r/d))로 계산해서 원과 이음매가 매끄럽게 이어진다.
  ///
  /// "도착" 텍스트는 이 이미지에 굽지 않고 MapLibre 심볼 레이어의 textField로
  /// 얹는다(자세한 이유는 심볼 레이어 등록부의 주석 참고). 흰 원 중심은
  /// 이미지 밑변에서 위로 112px(= canvasHeight − tipPadding − headCenterY,
  /// 즉 172 − 6 − 60) 위치에 있고, 이 값이 심볼 레이어 textOffset 계산의
  /// 근거가 된다.
  static Future<Uint8List> _renderDestinationPinIcon() async {
    const canvasWidth = 128.0;
    const canvasHeight = 172.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    const cx = canvasWidth / 2;
    const headRadius = 54.0;
    const headCenterY = headRadius + 6;
    const tipY = canvasHeight - 6;
    const centerToTipDistance = tipY - headCenterY;

    final tangentAngle = acos(headRadius / centerToTipDistance);
    final tangentDx = headRadius * sin(tangentAngle);
    final tangentDy = headRadius * cos(tangentAngle);

    final pinPaint = Paint()..color = const Color(0xFFE53935);
    canvas.drawCircle(const Offset(cx, headCenterY), headRadius, pinPaint);
    final tail = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx + tangentDx, headCenterY + tangentDy)
      ..lineTo(cx - tangentDx, headCenterY + tangentDy)
      ..close();
    canvas.drawPath(tail, pinPaint);

    const innerRadius = 38.0;
    canvas.drawCircle(
      const Offset(cx, headCenterY),
      innerRadius,
      Paint()..color = Colors.white,
    );

    final image = await recorder.endRecording().toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 상용 지도 앱처럼 흰 테두리의 파란 현재 위치 점 뒤로 반투명 heading cone이
  /// 퍼지는 하나의 고정 크기 심볼을 렌더링한다. MapLibre가 이 비트맵 전체를
  /// 회전하므로 확대/축소해도 점과 방향 범위의 크기·간격이 흐트러지지 않는다.
  static Future<Uint8List> _renderCurrentLocationIcon({
    required bool showHeading,
  }) async {
    const canvasSize = 144.0;
    const center = Offset(canvasSize / 2, canvasSize / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
    );

    if (showHeading) {
      const coneRadius = 62.0;
      const halfAngle = 31 * pi / 180;
      final coneBounds = Rect.fromCircle(center: center, radius: coneRadius);
      final headingCone = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(coneBounds, -pi / 2 - halfAngle, halfAngle * 2, false)
        ..close();
      canvas.drawPath(
        headingCone,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            coneRadius,
            const [Color(0x8F1976D2), Color(0x451976D2), Color(0x001976D2)],
            const [0, 0.58, 1],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }

    canvas.drawCircle(
      center + const Offset(0, 2),
      27,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(center, 24, Paint()..color = Colors.white);

    const blue = Color(0xFF1976D2);
    canvas.drawCircle(center, 18, Paint()..color = blue);
    canvas.drawCircle(
      center - const Offset(5, 5),
      4.5,
      Paint()..color = const Color(0x66FFFFFF),
    );

    final image = await recorder.endRecording().toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
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
      final dx =
          (p.longitude - center.longitude) * cosLat * _metersPerDegreeLat;
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
      final metersPerPixelNeeded = max(
        widthM / availableWidth,
        heightM / availableHeight,
      );
      final zoom = log(metersPerPixelAtLat / metersPerPixelNeeded) / log(2);

      if (zoom > bestZoom) {
        bestZoom = zoom;
        bestBearing = candidate;
      }
    }

    if (bestZoom.isFinite) return (bearing: bestBearing, zoom: bestZoom);
    return (bearing: axisBearing, zoom: 18.0);
  }

  /// 건물 전체가 뷰포트 안에 들어오는 축소 하한을 뽑는다.
  ///
  /// [_initialCenter]가 카메라를 bbox 중심에 놓으므로, 하한은 그 중심에서 잰
  /// 회전-불변 반지름의 지름(2 × maxRadius)이 뷰포트 짧은 변의 실제 보이는
  /// 영역([visibleInsets] 뺀 크기)에 딱 들어가는 줌으로 잡는다. 임의 여유
  /// 계수를 곱하지 않는다 — 곱하는 순간 하한에서 건물이 너무 작게 보이거나
  /// 반대로 너무 타이트해서 건물이 잘리는 문제가 매번 반복된다.
  static double? _computeMinZoom(
    FloorPlan floorPlan,
    Size viewport,
    EdgeInsets visibleInsets,
  ) {
    // 지도는 화면 끝까지 그려지지만 상단 검색바·하단 버튼바가 위쪽/아래쪽을
    // 가리고 있어, "건물이 실제로 보이는" 세로/가로 영역은 오버레이만큼 좁다.
    // 그 실제 영역을 짧은 변으로 잡아야 하한에 도달했을 때 건물이 오버레이에
    // 가려지지 않는다.
    final visibleWidth = viewport.width - visibleInsets.horizontal;
    final visibleHeight = viewport.height - visibleInsets.vertical;
    final shortSide = min(visibleWidth, visibleHeight);
    if (!shortSide.isFinite || shortSide <= 0) return null;
    final availableShortSide = max(1.0, shortSide - _fitPaddingPx * 2);

    final points = _extentWgs84Points(floorPlan);
    if (points.isEmpty) return null;
    final center = _bboxCenter(points);
    final radiusMeters = _maxRadiusMeters(points, center);
    if (radiusMeters <= 0) return null;

    final cosLat = cos(center.latitude * pi / 180);
    final metersPerPixelAtLat = _metersPerPixelAtZoom0Equator * cosLat;
    final metersPerPixelNeeded = (radiusMeters * 2) / availableShortSide;
    final zoom = log(metersPerPixelAtLat / metersPerPixelNeeded) / log(2);
    return zoom.isFinite ? zoom : null;
  }

  /// 축소 하한/초기 카메라 위치 계산에 쓰는 "화면에 반드시 보여야 할" wgs84
  /// 좌표 집합. 실좌표 앵커가 없는 건물은 footprint 자체가 비어 있으므로
  /// 매장 폴리곤/중심점과 POI 위치까지 함께 넣는다. footprint_local_m은 크기
  /// 정보만 담을 뿐 wgs84 위치가 없어 여기서는 쓰지 않는다.
  static List<ll.LatLng> _extentWgs84Points(FloorPlan floorPlan) {
    return <ll.LatLng>[
      ...floorPlan.footprint,
      for (final store in floorPlan.stores) ...[
        store.centroid,
        ...store.polygon,
      ],
      for (final poi in floorPlan.pois) poi.point,
    ];
  }

  static ll.LatLng _bboxCenter(List<ll.LatLng> points) {
    var minLat = double.infinity, maxLat = double.negativeInfinity;
    var minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    return ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  static double _maxRadiusMeters(List<ll.LatLng> points, ll.LatLng center) {
    final cosLat = cos(center.latitude * pi / 180);
    var maxRadius = 0.0;
    for (final p in points) {
      final dx =
          (p.longitude - center.longitude) * cosLat * _metersPerDegreeLat;
      final dy = (p.latitude - center.latitude) * _metersPerDegreeLat;
      maxRadius = max(maxRadius, sqrt(dx * dx + dy * dy));
    }
    return maxRadius;
  }

  Future<void> _updateRouteSource() async {
    final controller = _controller;
    if (controller == null) return;
    final points = widget.routePoints;
    if (points.length < 2) {
      await controller.setGeoJsonSource(
        _routeSourceId,
        _emptyFeatureCollection,
      );
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

  Future<void> _updatePdrTrailSource() async {
    await _updateLineSource(_pdrTrailSourceId, widget.pdrPathPoints);
  }

  Future<void> _updatePdrRawTrailSource() async {
    await _updateLineSource(_pdrRawTrailSourceId, widget.pdrRawPathPoints);
  }

  Future<void> _updatePdrConfirmedTrailSource() async {
    await _updateLineSource(
      _pdrConfirmedTrailSourceId,
      widget.pdrConfirmedPathPoints,
    );
  }

  Future<void> _updateLineSource(
    String sourceId,
    List<ll.LatLng> points,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    if (points.length < 2) {
      await controller.setGeoJsonSource(sourceId, _emptyFeatureCollection);
      return;
    }
    await controller.setGeoJsonSource(sourceId, {
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

  Future<void> _updateDebugGraphSource() async {
    final controller = _controller;
    if (controller == null) return;
    final overlay = widget.debugMapOverlay;
    if (overlay.isEmpty) {
      await controller.setGeoJsonSource(
        _debugGraphSourceId,
        _emptyFeatureCollection,
      );
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final edge in overlay.edges) {
      if (overlay.showEdges) {
        features.add({
          'type': 'Feature',
          'properties': {'kind': 'edge', 'active': edge.active},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final point in edge.points)
                [point.longitude, point.latitude],
            ],
          },
        });
      }
    }
    for (final node in overlay.nodes) {
      if (overlay.showNodes) {
        features.add({
          'type': 'Feature',
          'properties': {'kind': 'node', 'active': node.active},
          'geometry': {
            'type': 'Point',
            'coordinates': [node.position.longitude, node.position.latitude],
          },
        });
      }
    }
    await controller.setGeoJsonSource(_debugGraphSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  Future<void> _updateMarkersSource() async {
    final controller = _controller;
    if (controller == null) return;
    final features = <Map<String, dynamic>>[];
    final current = widget.currentLocation;
    final destination = widget.destination;
    if (current != null) {
      features.add(
        _markerFeature(
          current,
          MapMarkerKind.current,
          headingDegrees: widget.currentHeadingDegrees,
        ),
      );
    }
    if (destination != null) {
      features.add(_markerFeature(destination, MapMarkerKind.destination));
    }
    await controller.setGeoJsonSource(_markersSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  Map<String, dynamic> _markerFeature(
    ll.LatLng point,
    MapMarkerKind kind, {
    double? headingDegrees,
  }) {
    return {
      'type': 'Feature',
      'properties': {
        'kind': kind.name,
        if (headingDegrees != null && headingDegrees.isFinite)
          'heading': headingDegrees,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [point.longitude, point.latitude],
      },
    };
  }

  Future<void> _handleMapClick(Point<double> point, LatLng coordinates) async {
    // 매장 정보/길찾기 시트가 열려 있는 동안(widget.interactive == false)은
    // 무시한다. 웹에서는 시트 안 버튼(예: "도착지로 설정")을 누른 클릭이
    // 그 아래 실제 DOM 캔버스(MapLibre)까지 새어나가, 마침 그 자리에 다른
    // 매장 폴리곤이 있으면 그 매장 정보 시트가 겹쳐 열리는 문제가 있었다.
    if (!widget.interactive) return;

    // 층 selector 같은 지도 위 오버레이 영역의 탭은 무시한다. MapLibre가
    // PlatformView라 Flutter gesture arena를 우회해 네이티브 지도가 독립적으로
    // 탭을 받아버려, 오버레이 InkWell이 소비하더라도 뒤의 매장이 함께
    // 선택되는 문제가 남아 있었다. onMapClick의 point는 지도 위젯 로컬 좌표
    // 이므로 지도 자체의 RenderBox로 전역 좌표로 변환한 뒤 오버레이 소유자에
    // 게 물어본다.
    final overlayHitTest = widget.overlayHitTest;
    if (overlayHitTest != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        final globalTap = box.localToGlobal(Offset(point.x, point.y));
        if (overlayHitTest(globalTap)) return;
      }
    }

    final mapPressed = widget.onMapPressed;
    if (mapPressed?.call(
          ll.LatLng(coordinates.latitude, coordinates.longitude),
        ) ==
        true) {
      return;
    }

    final controller = _controller;
    final onStoreSelected = widget.onStoreSelected;
    if (controller == null || onStoreSelected == null) return;

    final features = await controller.queryRenderedFeatures(point, [
      _storesFillLayerId,
    ], null);
    if (features.isEmpty) return;

    final properties = (features.first as Map)['properties'] as Map?;
    final id = properties?['id'] as String?;
    if (id == null) return;

    final store = widget.floorPlan.stores.where((s) => s.id == id).firstOrNull;
    if (store != null) onStoreSelected(store);
  }

  LatLng _initialCenter(FloorPlan floorPlan) {
    // 축소 하한 계산이 이 중심점 기준으로 반지름을 재기 때문에, 같은 함수로
    // 뽑은 bbox 중심을 그대로 쓴다 — 첫 매장이나 첫 POI 좌표를 그대로 쓰면
    // 카메라가 건물 한쪽 구석에 놓여, 하한에 도달해도 반대편 끝이 시야
    // 밖으로 밀려나 전체가 안 보이는 문제가 있었다.
    final points = _extentWgs84Points(floorPlan);
    if (points.isNotEmpty) return _toMapLibreLatLng(_bboxCenter(points));
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

    final meanLatRad =
        footprint.map((p) => p.latitude).reduce((a, b) => a + b) /
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

const _emptyFeatureCollection = {
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[],
};

// 원본 SVG(hyundai_floor_map_corrected_v6.svg)의 배경색을 그대로 옮겼다.
// 나머지 레이어(외곽선/매장/POI/경로)는 스타일 로드 후 벡터·GeoJSON
// 소스로 추가한다.
/// 심볼 레이어(매장명/POI 라벨)가 쓰는 폰트. API가 app/data/fonts 아래 같은
/// 이름의 디렉터리로 글리프를 서빙한다(GET /fonts/{fontstack}/{range}.pbf).
/// 매장명이 한글이라 한글 글리프가 있는 폰트여야 한다 — MapLibre 기본값인
/// Open Sans에는 한글이 없어서 라벨이 깨진다.
const _mapFontStack = ['Noto Sans KR Regular'];

/// [_initialStyle]의 glyphs 템플릿. `{fontstack}`/`{range}`는 MapLibre가
/// 치환하는 자리표시자라 Dart 보간과 섞이지 않게 따로 조립한다.
String get _glyphsUrl => '$apiBaseUrl/fonts/{fontstack}/{range}.pbf';

/// glyphs가 비어 있으면 심볼 레이어가 폰트를 못 받아 레이아웃을 끝내지 못하고,
/// 그 여파로 같은 벡터 타일의 fill 레이어까지 전부 안 그려진다. 배경색만 남고
/// 지도가 빈 화면이 되므로 glyphs는 반드시 채워야 한다.
String get _initialStyle =>
    '''
{
  "version": 8,
  "glyphs": "$_glyphsUrl",
  "sources": {},
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "#EDF4E7"}}
  ]
}
''';
