import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../../models/floor_plan.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_plan_view.dart';

const _walkingSpeedMetersPerSecond = 1.2;

/// hyundai_floor_map_corrected_v6.svg에서 변환한 매장 폴리곤 데이터를
/// FloorPlanView로 그려서, 매장을 검색하거나 지도에서 탭하면 임시 시작점부터
/// 그 매장까지 직선 경로 + ETA를 보여준다. PDR이 없어 실제 현재 위치를 모르니
/// 출입구(게이트) 중 하나를 임시 시작점으로 쓴다.
class FloorMapPreviewScreen extends StatefulWidget {
  const FloorMapPreviewScreen({super.key});

  @override
  State<FloorMapPreviewScreen> createState() => _FloorMapPreviewScreenState();
}

class _FloorMapPreviewScreenState extends State<FloorMapPreviewScreen> {
  FloorPlan? _floorPlan;
  LatLng? _startPoint;
  StorePolygon? _selectedStore;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/mock/hyundai_floor_1f.json');
    final floorPlan = FloorPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (!mounted) return;
    setState(() {
      _floorPlan = floorPlan;
      _startPoint = _pickStartPoint(floorPlan);
    });
  }

  /// PDR이 없어 "현재 위치"를 모른다. 출입구(게이트) POI가 있으면 그중 하나를,
  /// 없으면 건물 외곽 중심을 임시 시작점으로 쓴다.
  LatLng _pickStartPoint(FloorPlan floorPlan) {
    final gate = floorPlan.pois.where((poi) => poi.type == 'exit').firstOrNull;
    if (gate != null) return gate.point;

    if (floorPlan.footprint.isNotEmpty) {
      final avgLat = floorPlan.footprint.map((p) => p.latitude).reduce((a, b) => a + b) /
          floorPlan.footprint.length;
      final avgLng = floorPlan.footprint.map((p) => p.longitude).reduce((a, b) => a + b) /
          floorPlan.footprint.length;
      return LatLng(avgLat, avgLng);
    }
    return floorPlan.stores.first.centroid;
  }

  void _selectStore(StorePolygon store) {
    setState(() {
      _selectedStore = store;
      _searchController.clear();
      _query = '';
    });
  }

  List<StorePolygon> _matchingStores(FloorPlan floorPlan) {
    if (_query.isEmpty) return const [];
    return floorPlan.stores
        .where((store) => store.name.contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final floorPlan = _floorPlan;
    return Scaffold(
      appBar: AppBar(title: const Text('더현대 서울 평면도 미리보기')),
      body: floorPlan == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(floorPlan),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBottomBar(),
        ),
      ),
    );
  }

  Widget _buildBody(FloorPlan floorPlan) {
    final start = _startPoint;
    final selected = _selectedStore;
    final routePoints =
        start != null && selected != null ? [start, selected.centroid] : const <LatLng>[];

    return Stack(
      children: [
        FloorPlanView(
          floorPlan: floorPlan,
          onStoreSelected: _selectStore,
          routePoints: routePoints,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(8),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '매장을 검색하세요',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                    ),
                    child: _buildSearchResults(floorPlan),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(FloorPlan floorPlan) {
    final results = _matchingStores(floorPlan);
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('찾을 수 없어요. 다시 입력해볼까요?'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final store = results[index];
        return ListTile(
          leading: const Icon(Icons.place),
          title: Text(store.name),
          subtitle: Text(store.category ?? '-'),
          onTap: () => _selectStore(store),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final selected = _selectedStore;
    final start = _startPoint;
    if (selected == null || start == null) {
      return const Text('매장을 검색하거나 지도에서 탭해보세요', textAlign: TextAlign.center);
    }

    final distance = const Distance().as(LengthUnit.Meter, start, selected.centroid);
    final minutes = (distance / _walkingSpeedMetersPerSecond / 60).ceil().clamp(1, 999);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${selected.name} · ${selected.category ?? '-'}'),
        const SizedBox(height: 8),
        EtaCard(distanceMeters: distance, minutes: minutes),
      ],
    );
  }
}
