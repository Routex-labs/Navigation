import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/directions_route.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/status_badge.dart';

// 위치 조회 실패 시 대체 좌표 (서울시청). 저장·전달은 latlong2 타입으로 하고
// MapLibre API에 넘길 때만 [_toGl]로 변환한다 — 이 파일 외부(Building.entrance,
// DirectionsRoute.points)가 latlong2를 쓰고 있어 그 타입을 저장 형식으로 유지한다.
const _fallbackLocation = ll.LatLng(37.5665, 126.9780);
const _lowAccuracyThresholdMeters = 30.0;

// 건물 진입 판정: "입구 근처" + "신호가 방금 나빠짐"을 같이 봐서
// 건물 앞을 그냥 지나가는 경우(신호는 안 나빠짐)와 구분한다.
// 세 값 다 실측 검증 전이라 추정치이고, 실기기 테스트하며 조정이 필요하다.
const _buildingEntryThresholdMeters = 20.0;
const _degradedAccuracyFloorMeters = 15.0;
const _accuracyWorsenedRatio = 1.3;

// 실내 지도와 같은 이유. maplibre_gl은 web/android/iOS만 지원하므로
// 데스크톱에서는 사전에 안내를 보여주고 지도 자체는 그리지 않는다.
const _mapSupportedNativePlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
};
bool get _isMapSupportedOnThisPlatform =>
    kIsWeb || _mapSupportedNativePlatforms.contains(defaultTargetPlatform);

// MapLibre 소스·레이어 ID. 층 지도의 명명 규칙(_로 시작하지 않는 kebab-case) 준수.
const _routeSourceId = 'outdoor-route';
const _routeCasingLayerId = 'outdoor-route-casing';
const _routeLineLayerId = 'outdoor-route-line';
const _currentSourceId = 'outdoor-current';
const _accuracyLayerId = 'outdoor-accuracy';
const _currentDotLayerId = 'outdoor-current-dot';
const _destSourceId = 'outdoor-destination';
const _destLayerId = 'outdoor-destination-pin';

// latlong2 <-> MapLibre 타입 브릿지.
LatLng _toGl(ll.LatLng p) => LatLng(p.latitude, p.longitude);

// 기본 지도 스타일. vworldApiKey가 있으면 VWorld Base 타일, 없으면 OSM으로 폴백해
// 로컬 개발·테스트 환경에서도 지도가 항상 뜨도록 한다.
String _baseMapStyle() {
  final Map<String, dynamic> source;
  if (vworldApiKey.isEmpty) {
    source = {
      'type': 'raster',
      'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      'tileSize': 256,
      'attribution':
          '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    };
  } else {
    source = {
      'type': 'raster',
      'tiles': [
        'https://api.vworld.kr/req/wmts/1.0.0/$vworldApiKey/Base/{z}/{y}/{x}.png',
      ],
      'tileSize': 256,
      'attribution': '© <a href="https://map.vworld.kr">VWorld</a>',
    };
  }
  return jsonEncode({
    'version': 8,
    'sources': {'base': source},
    'layers': [
      {'id': 'base', 'type': 'raster', 'source': 'base'},
    ],
  });
}

Map<String, dynamic> _pointFeature(ll.LatLng point) {
  return {
    'type': 'Feature',
    'properties': const <String, dynamic>{},
    'geometry': {
      'type': 'Point',
      'coordinates': [point.longitude, point.latitude],
    },
  };
}

Map<String, dynamic> _lineFeature(List<ll.LatLng> points) {
  return {
    'type': 'Feature',
    'properties': const <String, dynamic>{},
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final p in points) [p.longitude, p.latitude],
      ],
    },
  };
}

Map<String, dynamic> _emptyCollection() =>
    {'type': 'FeatureCollection', 'features': const <Map<String, dynamic>>[]};

Map<String, dynamic> _collection(List<Map<String, dynamic>> features) =>
    {'type': 'FeatureCollection', 'features': features};

/// 야외 지도 본문(지도 + 위치/경로 오버레이). 검색창·길찾기·건물 전환 같은
/// 공통 UI는 [MapShellScreen]이 상단/하단 바로 얹으므로 여기서는 다루지 않는다.
class OutdoorMapBody extends StatefulWidget {
  const OutdoorMapBody({
    super.key,
    required this.onEnterBuilding,
    this.onRouteVisibleChanged,
  });

  /// GPS로 건물 입구 진입이 감지됐을 때 호출된다. 상위(MapShellScreen)가
  /// 이 콜백으로 하단 바 모드를 "실내"로 전환한다.
  final VoidCallback onEnterBuilding;

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  @override
  State<OutdoorMapBody> createState() => OutdoorMapBodyState();
}

class OutdoorMapBodyState extends State<OutdoorMapBody> {
  bool _autoNavigated = false;
  Position? _position;
  ll.LatLng? _entrance;
  DirectionsRoute? _route;
  double? _previousAccuracy;
  StreamSubscription<Position>? _positionSubscription;
  bool _interactive = true;
  ll.LatLng? _userDestination;
  String? _userDestinationLabel;

  MapLibreMapController? _mapController;
  bool _styleReady = false;
  // 지도가 아직 안 뜬 시점의 첫 GPS 위치를 잊지 않도록 pending 값을 두고,
  // 스타일 로드 콜백에서 이를 반영한다.
  bool _pendingCenterOnPosition = false;

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
  }

  @override
  void initState() {
    super.initState();
    _loadBuildingEntrance();
    _positionSubscription = watchPosition().listen(
      _handlePosition,
      onError: (Object _) => _handlePositionError(),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadBuildingEntrance() async {
    final Building? building = await buildingRepository.getBuilding(
      demoBuildingId,
    );
    if (!mounted) return;
    setState(() => _entrance = building?.entrance);
    _syncDestinationLayer();
  }

  void _handlePositionError() {
    if (!mounted) return;
    setState(() => _position = null);
    _syncCurrentLayer();
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    setState(() => _position = position);
    _syncCurrentLayer();
    _maybeAutoEnter(position);
    _updateRoute(position);
  }

  void _maybeAutoEnter(Position position) {
    final entrance = _entrance;
    if (_autoNavigated || entrance == null) return;

    final distance = const ll.Distance().as(
      ll.LengthUnit.Meter,
      ll.LatLng(position.latitude, position.longitude),
      entrance,
    );
    final isNear = distance <= _buildingEntryThresholdMeters;

    final previousAccuracy = _previousAccuracy;
    _previousAccuracy = position.accuracy;
    final accuracyWorsened =
        position.accuracy > _degradedAccuracyFloorMeters &&
        (previousAccuracy == null ||
            position.accuracy > previousAccuracy * _accuracyWorsenedRatio);

    if (!isNear || !accuracyWorsened) return;

    _autoNavigated = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('건물 감지 중...')));
    widget.onEnterBuilding();
  }

  Future<void> _updateRoute(Position position) async {
    final target = _userDestination ?? _entrance;
    if (target == null) return;

    final route = await directionsRepository.getWalkingRoute(
      origin: ll.LatLng(position.latitude, position.longitude),
      destination: target,
    );
    if (!mounted) return;
    _applyRoute(route);
  }

  /// 경로가 새로 생기면(이전엔 없다가 이번에 생김) 상위에 ETA 바가 보인다고
  /// 알리고, 경로 전체가 화면에 들어오도록 카메라를 자동으로 줌아웃한다.
  /// 이미 경로가 있는 상태에서 위치가 갱신돼 경로가 매번 다시 계산될 때는
  /// (걷는 동안 계속 일어남) 다시 맞추지 않는다 — 사용자가 지도를 보는 중에
  /// 카메라가 계속 튀면 방해가 된다. 새 목적지를 고르면(showRouteTo) 그때는
  /// 다시 한번 전체 경로가 보이도록 맞춘다.
  void _applyRoute(DirectionsRoute? route) {
    final wasVisible = _route != null;
    setState(() => _route = route);
    _syncRouteLayer();
    final isVisible = route != null;
    if (wasVisible != isVisible) {
      widget.onRouteVisibleChanged?.call(isVisible);
    }
    if (!wasVisible && isVisible) {
      _fitCameraToRoute(route);
    }
  }

  void _fitCameraToRoute(DirectionsRoute route) {
    // 출발점과 도착점이 사실상 같은 좌표면(예: 건물 입구 바로 앞) 경계 상자
    // 폭이 0에 가까워져 줌 계산이 발산한다 — 이 경우엔 화면에 맞출 "경로"랄
    // 게 없으니 자동 줌은 건너뛴다.
    if (route.points.length < 2 || route.distanceMeters < 5) return;
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

  /// 위치 보정 버튼: 즉시 새 GPS 위치를 한 번 더 조회해 마커·지도 중심을 갱신한다.
  Future<void> recalibrate() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      _handlePosition(position);
      final controller = _mapController;
      if (controller != null && _styleReady) {
        await controller.animateCamera(
          CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치를 다시 확인하지 못했습니다')),
      );
    }
  }

  /// 길찾기 시트에서 도착지를 고르면 호출된다. [origin]을 주면(길찾기
  /// 시트에서 출발지도 직접 고른 경우) 현재 GPS 위치 대신 그 지점을
  /// 출발점으로 써서 경로를 한 번만 계산한다 — 두 지점 사이 경로를 보는
  /// 용도라 GPS를 따라 계속 갱신할 필요가 없다. 없으면 기존처럼 현재
  /// 위치에서 [destination]까지의 보행 경로를 계산해 지도 위에 표시한다.
  Future<void> showRouteTo(
    ll.LatLng destination, {
    required String label,
    ll.LatLng? origin,
  }) async {
    setState(() {
      _userDestination = destination;
      _userDestinationLabel = label;
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면
      // _applyRoute가 "새로 생김"으로 보고 카메라를 다시 맞추게 한다.
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();

    if (origin != null) {
      final route = await directionsRepository.getWalkingRoute(
        origin: origin,
        destination: destination,
      );
      if (!mounted) return;
      _applyRoute(route);
      return;
    }

    final position = _position;
    if (position == null) return;
    await _updateRoute(position);
  }

  void _clearUserDestination() {
    setState(() {
      _userDestination = null;
      _userDestinationLabel = null;
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    widget.onRouteVisibleChanged?.call(false);
  }

  // --- MapLibre 스타일/레이어 설정 ---

  Future<void> _onStyleLoaded() async {
    final controller = _mapController;
    if (controller == null) return;

    // 경로선: 두께 있는 파란 실선 + 흰 casing으로 배경 대비를 확보한다.
    await controller.addSource(
      _routeSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _routeSourceId,
      _routeCasingLayerId,
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 8,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await controller.addLineLayer(
      _routeSourceId,
      _routeLineLayerId,
      LineLayerProperties(
        lineColor: AppColors.primary.toHexString(),
        lineWidth: 5,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // 현재 위치: 반투명 원(정확도 반경 시각화용, 픽셀 반경) + 진한 점.
    await controller.addSource(
      _currentSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addCircleLayer(
      _currentSourceId,
      _accuracyLayerId,
      CircleLayerProperties(
        circleRadius: 22,
        circleColor: AppColors.primary.toHexString(),
        circleOpacity: 0.18,
        circleStrokeColor: AppColors.primary.toHexString(),
        circleStrokeWidth: 1,
      ),
    );
    await controller.addCircleLayer(
      _currentSourceId,
      _currentDotLayerId,
      CircleLayerProperties(
        circleRadius: 7,
        circleColor: AppColors.primary.toHexString(),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );

    // 목적지 핀.
    await controller.addSource(
      _destSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addCircleLayer(
      _destSourceId,
      _destLayerId,
      CircleLayerProperties(
        circleRadius: 9,
        circleColor: AppColors.dest.toHexString(),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );

    if (!mounted) return;
    setState(() => _styleReady = true);
    _syncCurrentLayer();
    _syncDestinationLayer();
    _syncRouteLayer();
    if (_pendingCenterOnPosition && _position != null) {
      _pendingCenterOnPosition = false;
      await controller.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_position!.latitude, _position!.longitude),
        ),
      );
    }
  }

  Future<void> _syncCurrentLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) {
      _pendingCenterOnPosition = _position != null;
      return;
    }
    final pos = _position;
    if (pos == null) {
      await controller.setGeoJsonSource(_currentSourceId, _emptyCollection());
      return;
    }
    await controller.setGeoJsonSource(
      _currentSourceId,
      _collection([
        _pointFeature(ll.LatLng(pos.latitude, pos.longitude)),
      ]),
    );
  }

  Future<void> _syncDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final target = _userDestination ?? _entrance;
    if (target == null) {
      await controller.setGeoJsonSource(_destSourceId, _emptyCollection());
      return;
    }
    await controller.setGeoJsonSource(
      _destSourceId,
      _collection([_pointFeature(target)]),
    );
  }

  Future<void> _syncRouteLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final route = _route;
    if (route == null || route.points.length < 2) {
      await controller.setGeoJsonSource(_routeSourceId, _emptyCollection());
      return;
    }
    await controller.setGeoJsonSource(
      _routeSourceId,
      _collection([_lineFeature(route.points)]),
    );
  }

  @override
  Widget build(BuildContext context) => _buildBody();

  Widget _buildBody() {
    final position = _position;
    final accuracy = position?.accuracy ?? 0;
    final lowAccuracy = position == null || accuracy > _lowAccuracyThresholdMeters;
    final route = _route;
    final userDestination = _userDestination;
    final initialCenter = position == null
        ? _fallbackLocation
        : ll.LatLng(position.latitude, position.longitude);

    return Stack(
      children: [
        if (_isMapSupportedOnThisPlatform)
          MapLibreMap(
            styleString: _baseMapStyle(),
            initialCameraPosition: CameraPosition(
              target: _toGl(initialCenter),
              zoom: 17,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onStyleLoadedCallback: _onStyleLoaded,
            compassEnabled: false,
            myLocationEnabled: false,
            logoEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            scrollGesturesEnabled: _interactive,
            zoomGesturesEnabled: _interactive,
            rotateGesturesEnabled: _interactive,
            tiltGesturesEnabled: _interactive,
            dragEnabled: _interactive,
          )
        else
          const ColoredBox(color: AppColors.surface),

        if (lowAccuracy)
          const Positioned(
            top: 76,
            left: 12,
            child: StatusBadge(
              label: 'GPS 신호 약함',
              color: AppColors.warning,
              icon: Icons.warning_amber_rounded,
            ),
          ),

        if (route != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: EtaCard(
                  distanceMeters: route.distanceMeters,
                  minutes: (route.durationSeconds / 60).ceil().clamp(1, 999),
                  label: userDestination != null
                      ? (_userDestinationLabel ?? '목적지까지')
                      : '건물 입구까지',
                  onClose: userDestination != null ? _clearUserDestination : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// AppColors 는 Color 인스턴스라 CircleLayerProperties가 요구하는 문자열 색상으로
// 자주 변환해 쓰기 편하도록 확장으로 감싼다.
extension _ColorHex on Color {
  String toHexString() {
    final rgb =
        (r * 255).round() << 16 | (g * 255).round() << 8 | (b * 255).round();
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
