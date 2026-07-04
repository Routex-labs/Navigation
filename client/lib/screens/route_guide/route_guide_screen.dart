import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/floor_plan.dart';
import '../../models/poi_search_result.dart';
import '../../routing/app_routes.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/location_marker.dart';
import '../../widgets/rag_chat_panel.dart';
import '../../widgets/route_polyline.dart';

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
    setState(() {
      _floorPlan = geojson == null ? null : FloorPlan.fromGeoJson(geojson);
      _loading = false;
    });
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
                  Navigator.of(context).pushNamed(AppRoutes.arrival);
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
    final current = _currentLocation();
    final distance = const Distance().as(
      LengthUnit.Meter,
      current,
      destination.point,
    );
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

    final current = _currentLocation();

    return FlutterMap(
      options: MapOptions(initialCenter: destination.point, initialZoom: 19),
      children: [
        PolylineLayer(
          polylines: [
            for (final corridor in floorPlan.corridors)
              Polyline(points: corridor, color: Colors.grey, strokeWidth: 6),
            buildRoutePolyline([current, destination.point]),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: current,
              child: const LocationMarker(mode: LocationMode.indoor),
            ),
            Marker(
              point: destination.point,
              child: const Icon(Icons.place, color: Colors.red),
            ),
          ],
        ),
      ],
    );
  }
}
