import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../routing/app_routes.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_plan_view.dart';
import '../../widgets/location_marker.dart';
import '../../widgets/rag_chat_panel.dart';

const _fallbackCenter = LatLng(37.5665, 126.9780);
const _walkingSpeedMetersPerSecond = 1.2;

class RouteGuideScreen extends StatefulWidget {
  const RouteGuideScreen({super.key});

  @override
  State<RouteGuideScreen> createState() => _RouteGuideScreenState();
}

class _RouteGuideScreenState extends State<RouteGuideScreen> {
  bool _initialized = false;
  bool _loading = true;
  PoiSearchResult? _destination;
  FloorPlan? _floorPlan;
  IndoorRoute? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _destination = ModalRoute.of(context)?.settings.arguments as PoiSearchResult?;
    _loadFloorPlan();
  }

  Future<void> _loadFloorPlan() async {
    final destination = _destination;
    if (destination == null) {
      setState(() => _loading = false);
      return;
    }

    final geojson = await buildingRepository.getFloorGeoJson(
      demoBuildingId,
      destination.floor,
    );
    if (!mounted) return;
    final floorPlan = geojson == null ? null : FloorPlan.fromJson(geojson);
    setState(() {
      _floorPlan = floorPlan;
      _loading = false;
    });
    if (floorPlan != null) {
      await _loadRoute(floorPlan, destination);
    }
  }

  /// 실제 최단 경로를 조회한다. 시작/도착 노드 ID를 못 구하면(PDR 미연동,
  /// 목적지에 entranceNodeId 없음 등) route는 null로 남고 화면은 직선 fallback을 쓴다.
  Future<void> _loadRoute(FloorPlan floorPlan, PoiSearchResult destination) async {
    final endNodeId = destination.nodeId;
    final startNodeId = _pickStartNodeId(floorPlan, excludingNodeId: endNodeId);
    if (endNodeId == null || startNodeId == null) return;

    final route = await buildingRepository.getShortestRoute(
      demoBuildingId,
      destination.floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    setState(() => _route = route);
  }

  /// PDR이 아직 없어 "현재 위치"를 알 수 없다. 임시로 층 평면도 중심에서
  /// 가장 가까운 매장 입구 노드를 출발점으로 쓴다. 실제 PDR 위치 연동은
  /// M3~M4에서 이 자리를 대체한다.
  String? _pickStartNodeId(FloorPlan floorPlan, {String? excludingNodeId}) {
    final origin = _footprintCenter(floorPlan) ?? _currentLocation();
    StorePolygon? nearest;
    double? nearestDistance;
    for (final store in floorPlan.stores) {
      final nodeId = store.entranceNodeId;
      if (nodeId == null || nodeId == excludingNodeId) continue;
      final distance = localDistanceMeters(origin, store.centroid);
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearest = store;
      }
    }
    return nearest?.entranceNodeId;
  }

  LatLng? _footprintCenter(FloorPlan floorPlan) {
    if (floorPlan.footprint.isEmpty) return null;
    final avgLat =
        floorPlan.footprint.map((p) => p.latitude).reduce((a, b) => a + b) /
            floorPlan.footprint.length;
    final avgLng =
        floorPlan.footprint.map((p) => p.longitude).reduce((a, b) => a + b) /
            floorPlan.footprint.length;
    return LatLng(avgLat, avgLng);
  }

  void _openBuildingInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const RagChatPanel(),
    );
  }

  LatLng _currentLocation() {
    final floorPlan = _floorPlan;
    if (floorPlan == null) return _fallbackCenter;
    if (floorPlan.corridors.isNotEmpty && floorPlan.corridors.first.isNotEmpty) {
      return floorPlan.corridors.first.first;
    }
    if (floorPlan.pois.isNotEmpty) return floorPlan.pois.first.point;
    return _fallbackCenter;
  }

  @override
  Widget build(BuildContext context) {
    final destination = _destination;
    return Scaffold(
      appBar: AppBar(
        title: Text(destination == null ? '경로 안내' : '${destination.name}(으)로 안내'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openBuildingInfo,
        tooltip: '건물 정보',
        child: const Icon(Icons.info_outline),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : destination == null
              ? const Center(child: Text('목적지 정보가 없습니다'))
              : _buildMap(destination),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (destination != null) _buildEtaCard(destination),
              if (destination != null) const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    AppRoutes.arrival,
                    arguments: destination,
                  );
                },
                child: const Text('도착'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEtaCard(PoiSearchResult destination) {
    final route = _route;
    final distance = route != null
        ? route.distanceMeters
        : localDistanceMeters(_currentLocation(), destination.point);
    final minutes = (distance / _walkingSpeedMetersPerSecond / 60)
        .ceil()
        .clamp(1, 999);
    return EtaCard(distanceMeters: distance, minutes: minutes);
  }

  Widget _buildMap(PoiSearchResult destination) {
    final floorPlan = _floorPlan;
    if (floorPlan == null) {
      return const Center(child: Text('평면도를 찾을 수 없습니다'));
    }

    final route = _route;
    // 실제 경로가 있으면 그 시작점을, 없으면(fallback) 임시 현재 위치를 마커에 쓴다 —
    // 그려지는 선의 출발점과 마커 위치가 항상 일치하도록.
    final current = (route != null && route.points.isNotEmpty)
        ? route.points.first
        : _currentLocation();

    return FloorPlanView(
      floorPlan: floorPlan,
      routePoints: route?.points ?? [current, destination.point],
      extraMarkers: [
        Marker(
          point: current,
          child: const LocationMarker(mode: LocationMode.indoor),
        ),
        Marker(
          point: destination.point,
          child: const Icon(Icons.place, color: Colors.red),
        ),
      ],
    );
  }
}
