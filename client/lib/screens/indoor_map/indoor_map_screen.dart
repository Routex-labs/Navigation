import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/floor_plan.dart';
import '../../routing/app_routes.dart';
import '../../widgets/location_marker.dart';
import '../../widgets/uncertainty_circle.dart';

const _fallbackCenter = LatLng(37.5665, 126.9780);

class IndoorMapScreen extends StatefulWidget {
  const IndoorMapScreen({super.key});

  @override
  State<IndoorMapScreen> createState() => _IndoorMapScreenState();
}

class _IndoorMapScreenState extends State<IndoorMapScreen> {
  bool _loading = true;
  Building? _building;
  int? _selectedFloor;
  FloorPlan? _floorPlan;

  @override
  void initState() {
    super.initState();
    _loadBuilding();
  }

  Future<void> _loadBuilding() async {
    final building = await buildingRepository.getBuilding(demoBuildingId);
    if (!mounted) return;

    if (building == null || building.floors.isEmpty) {
      setState(() {
        _building = building;
        _loading = false;
      });
      return;
    }

    setState(() => _building = building);
    await _loadFloorPlan(building.floors.first);
  }

  Future<void> _loadFloorPlan(int floor) async {
    setState(() => _loading = true);
    final geojson = await buildingRepository.getFloorGeoJson(
      demoBuildingId,
      floor,
    );
    if (!mounted) return;
    setState(() {
      _selectedFloor = floor;
      _floorPlan = geojson == null ? null : FloorPlan.fromGeoJson(geojson);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final building = _building;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          building == null
              ? '실내 지도 (PDR 모드)'
              : '${building.name} · $_selectedFloor층',
        ),
        actions: [
          if (building != null && building.floors.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.layers),
              tooltip: '층 전환',
              onSelected: (floor) => _loadFloorPlan(floor),
              itemBuilder: (context) => building.floors
                  .map(
                    (floor) => PopupMenuItem(value: floor, child: Text('$floor층')),
                  )
                  .toList(),
            ),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.destination);
            },
            child: const Text('목적지 검색'),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_building == null) {
      return const Center(child: Text('건물 정보를 찾을 수 없습니다'));
    }

    final floorPlan = _floorPlan;
    if (floorPlan == null) {
      return const Center(child: Text('평면도를 찾을 수 없습니다'));
    }

    final center = floorPlan.corridors.isNotEmpty &&
            floorPlan.corridors.first.isNotEmpty
        ? floorPlan.corridors.first.first
        : (floorPlan.pois.isNotEmpty ? floorPlan.pois.first.point : _fallbackCenter);

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 19),
      children: [
        PolylineLayer(
          polylines: [
            for (final corridor in floorPlan.corridors)
              Polyline(points: corridor, color: Colors.grey, strokeWidth: 6),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final poi in floorPlan.pois)
              Marker(
                point: poi.point,
                width: 80,
                height: 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place, size: 16, color: Colors.black54),
                    Text(
                      poi.name,
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            // 더미 현재 위치 마커. 실제 PDR 위치 갱신은 M3~M4에서 연결한다.
            Marker(
              point: center,
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  UncertaintyCircle(diameter: 40, color: Color(0xFF6C3FE0)),
                  LocationMarker(mode: LocationMode.indoor),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
