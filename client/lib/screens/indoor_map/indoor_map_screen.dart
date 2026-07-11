import 'package:flutter/material.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/floor_plan.dart';
import '../../routing/app_routes.dart';
import '../../widgets/floor_plan_view.dart';

class IndoorMapScreen extends StatefulWidget {
  const IndoorMapScreen({super.key});

  @override
  State<IndoorMapScreen> createState() => _IndoorMapScreenState();
}

class _IndoorMapScreenState extends State<IndoorMapScreen> {
  bool _loading = true;
  Building? _building;
  String? _selectedFloor;
  FloorPlan? _floorPlan;
  StorePolygon? _selectedStore;

  @override
  void initState() {
    super.initState();
    _loadBuilding();
  }

  Future<void> _loadBuilding() async {
    final building = await buildingRepository.getBuilding(demoBuildingId);
    if (!mounted) return;

    final selectedFloor =
        building != null && building.floors.isNotEmpty ? building.floors.first : null;
    setState(() {
      _building = building;
      _selectedFloor = selectedFloor;
      _loading = false;
    });
    if (selectedFloor != null) await _loadFloorPlan(selectedFloor);
  }

  /// 목적지 검색·경로 안내 화면(route_guide_screen.dart)과 동일하게
  /// buildingRepository를 통해 층 지도를 받아온다 — 데이터 소스를 하나로
  /// 맞춰야 실내 지도에서 본 것과 경로 안내 화면의 지도가 어긋나지 않는다.
  Future<void> _loadFloorPlan(String floor) async {
    final geojson = await buildingRepository.getFloorGeoJson(demoBuildingId, floor);
    if (!mounted || geojson == null) return;
    setState(() => _floorPlan = FloorPlan.fromJson(geojson));
  }

  void _selectFloor(String floor) {
    setState(() {
      _selectedFloor = floor;
      _floorPlan = null;
    });
    _loadFloorPlan(floor);
  }

  @override
  Widget build(BuildContext context) {
    final building = _building;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          building == null
              ? '실내 지도 (PDR 모드)'
              : '${building.name} · $_selectedFloor',
        ),
        actions: [
          if (building != null && building.floors.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.layers),
              tooltip: '층 전환',
              onSelected: _selectFloor,
              itemBuilder: (context) => building.floors
                  .map(
                    (floor) => PopupMenuItem(value: floor, child: Text(floor)),
                  )
                  .toList(),
            ),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectedStore != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_selectedStore!.name} · ${_selectedStore!.category ?? '-'}',
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.destination);
                },
                child: const Text('목적지 검색'),
              ),
            ],
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
      return const Center(child: CircularProgressIndicator());
    }

    return FloorPlanView(
      floorPlan: floorPlan,
      onStoreSelected: (store) => setState(() => _selectedStore = store),
    );
  }
}
