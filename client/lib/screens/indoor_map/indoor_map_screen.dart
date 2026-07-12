import 'package:flutter/material.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/floor_plan.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_theme.dart';
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
      _selectedStore = null;
    });
    _loadFloorPlan(floor);
  }

  @override
  Widget build(BuildContext context) {
    final building = _building;
    return Scaffold(
      body: Column(
        children: [
          _TopBar(
            building: building,
            selectedFloor: _selectedFloor,
            onSelectFloor: _selectFloor,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(),
          ),
          _BottomBar(
            selectedStore: _selectedStore,
            selectedFloor: _selectedFloor,
            onClearStore: () => setState(() => _selectedStore = null),
            onSearch: () {
              Navigator.of(context).pushNamed(AppRoutes.destination);
            },
          ),
        ],
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
      key: ValueKey('$demoBuildingId-$_selectedFloor'),
      buildingId: demoBuildingId,
      floorName: _selectedFloor!,
      floorPlan: floorPlan,
      onStoreSelected: (store) => setState(() => _selectedStore = store),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.building,
    required this.selectedFloor,
    required this.onSelectFloor,
  });

  final Building? building;
  final String? selectedFloor;
  final ValueChanged<String> onSelectFloor;

  @override
  Widget build(BuildContext context) {
    final floors = building?.floors ?? const <String>[];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.chevron_left, color: AppColors.primary),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF3F4F6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size(34, 34),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          building?.name ?? '실내 지도',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (selectedFloor != null)
                          Text(
                            'PDR 모드 · 현재 $selectedFloor 위치',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.indoor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selectedFloor != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.indoor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers, size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            selectedFloor!,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (floors.length > 1)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  itemCount: floors.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final floor = floors[index];
                    final isActive = floor == selectedFloor;
                    return _FloorChip(
                      label: floor,
                      active: isActive,
                      onTap: () => onSelectFloor(floor),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloorChip extends StatelessWidget {
  const _FloorChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: active ? AppColors.indoor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.indoor : const Color(0x14000000),
            width: 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.indoor.withValues(alpha: 0.38),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.selectedStore,
    required this.selectedFloor,
    required this.onClearStore,
    required this.onSearch,
  });

  final StorePolygon? selectedStore;
  final String? selectedFloor;
  final VoidCallback onClearStore;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final store = selectedStore;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (store != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF3FF),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.storefront, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          store.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${store.category ?? '-'} · ${selectedFloor ?? ''}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClearStore,
                    icon: const Icon(Icons.close, size: 16, color: AppColors.muted),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF3F4F6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Material(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(26),
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: onSearch,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 17, color: AppColors.muted),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '매장, 편의시설 검색',
                          style: TextStyle(fontSize: 14, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
