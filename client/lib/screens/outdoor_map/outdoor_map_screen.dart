import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/directions_route.dart';
import '../../routing/app_routes.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/location_marker.dart';
import '../../widgets/route_polyline.dart';
import '../../widgets/status_badge.dart';

// 위치 조회 실패 시 대체 좌표 (서울시청).
const _fallbackLocation = LatLng(37.5665, 126.9780);
const _lowAccuracyThresholdMeters = 30.0;

/// 배경지도 타일 공급자. 플랫폼 채널·네트워크가 없는 위젯 테스트 환경에서는
/// 이 변수를 실제 OSM/VWorld에 요청하지 않는 가짜 TileProvider로 교체한다
/// (안 그러면 진짜 HTTP 요청이 백그라운드에 남아 이후 테스트의 pumpAndSettle과
/// 뒤섞여 타임아웃을 일으킨다).
TileProvider Function() outdoorTileProvider = NetworkTileProvider.new;

// 건물 진입 판정: "입구 근처" + "신호가 방금 나빠짐"을 같이 봐서
// 건물 앞을 그냥 지나가는 경우(신호는 안 나빠짐)와 구분한다.
// 세 값 다 실측 검증 전이라 추정치이고, 실기기 테스트하며 조정이 필요하다.
const _buildingEntryThresholdMeters = 20.0;
const _degradedAccuracyFloorMeters = 15.0;
const _accuracyWorsenedRatio = 1.3;

class OutdoorMapScreen extends StatefulWidget {
  const OutdoorMapScreen({super.key});

  @override
  State<OutdoorMapScreen> createState() => _OutdoorMapScreenState();
}

class _OutdoorMapScreenState extends State<OutdoorMapScreen> {
  bool _loading = true;
  bool _autoNavigated = false;
  Position? _position;
  LatLng? _entrance;
  DirectionsRoute? _route;
  double? _previousAccuracy;
  StreamSubscription<Position>? _positionSubscription;

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
  }

  void _handlePositionError() {
    if (!mounted) return;
    setState(() {
      _position = null;
      _loading = false;
    });
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    setState(() {
      _position = position;
      _loading = false;
    });
    _maybeAutoEnter(position);
    _updateRoute(position);
  }

  void _maybeAutoEnter(Position position) {
    final entrance = _entrance;
    if (_autoNavigated || entrance == null) return;

    final distance = const Distance().as(
      LengthUnit.Meter,
      LatLng(position.latitude, position.longitude),
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
    _positionSubscription?.cancel();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('건물 감지 중...')));
    Navigator.of(context).pushNamed(AppRoutes.indoorMap);
  }

  Future<void> _updateRoute(Position position) async {
    final entrance = _entrance;
    if (entrance == null) return;

    final route = await directionsRepository.getWalkingRoute(
      origin: LatLng(position.latitude, position.longitude),
      destination: entrance,
    );
    if (!mounted) return;
    setState(() => _route = route);
  }

  @override
  Widget build(BuildContext context) {
    final entrance = _entrance;
    return Scaffold(
      appBar: AppBar(title: const Text('야외 지도 (GPS 모드)')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_route != null)
                EtaCard(
                  distanceMeters: _route!.distanceMeters,
                  minutes: (_route!.durationSeconds / 60).ceil().clamp(1, 999),
                ),
              if (_route != null) const SizedBox(height: 8),
              // 건물 입구 좌표를 모를 때만 수동 진입 버튼을 남겨둔다.
              // 좌표를 아는 경우엔 design.md 원칙대로 자동 감지만으로 전환한다.
              if (!_loading && entrance == null)
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.indoorMap);
                  },
                  child: const Text('건물 진입 감지 (임시)'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final position = _position;
    final center = position == null
        ? _fallbackLocation
        : LatLng(position.latitude, position.longitude);
    final accuracy = position?.accuracy ?? 0;
    final lowAccuracy = position == null || accuracy > _lowAccuracyThresholdMeters;
    final markerColor = lowAccuracy ? Colors.amber : Colors.blue;
    final entrance = _entrance;
    final route = _route;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 17),
          children: [
            TileLayer(
              // VWorld는 키 발급(도메인 등록) 전제. 키가 없으면 OSM으로 대체해
              // 로컬 개발·테스트 환경에서도 지도가 항상 뜨도록 한다.
              urlTemplate: vworldApiKey.isEmpty
                  ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                  : 'https://api.vworld.kr/req/wmts/1.0.0/$vworldApiKey/Base/{z}/{y}/{x}.png',
              userAgentPackageName: 'com.navigation.navigation_client',
              tileProvider: outdoorTileProvider(),
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: center,
                  radius: accuracy > 0 ? accuracy : 20,
                  useRadiusInMeter: true,
                  color: markerColor.withValues(alpha: 0.2),
                  borderColor: markerColor,
                  borderStrokeWidth: 1,
                ),
              ],
            ),
            if (route != null)
              PolylineLayer(polylines: [buildRoutePolyline(route.points)]),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  child: LocationMarker(
                    mode: LocationMode.outdoor,
                    colorOverride: markerColor,
                  ),
                ),
                if (entrance != null)
                  Marker(
                    point: entrance,
                    child: const Icon(Icons.place, color: Colors.red),
                  ),
              ],
            ),
          ],
        ),
        if (lowAccuracy)
          const Positioned(
            top: 12,
            left: 12,
            child: StatusBadge(label: 'GPS 신호 약함'),
          ),
      ],
    );
  }
}
