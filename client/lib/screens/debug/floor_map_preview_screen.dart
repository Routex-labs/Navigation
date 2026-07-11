import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../repositories/http_building_repository.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_plan_view.dart';

const _walkingSpeedMetersPerSecond = 1.2;
const _buildingId = 'thehyundai-seoul';
const _floorName = '1F';

/// 임시 시작점으로 쓰는 매장. PDR이 없어 실제 현재 위치를 모르니
/// 항상 이 매장 입구에서 출발한 것으로 가정한다.
const _startStoreName = '발렌시아가';

/// 더현대 서울 실제 층 데이터를 백엔드에서 받아 FloorPlanView로 그려서,
/// 매장을 검색하거나 지도에서 탭하면 임시 시작점(발렌시아가)부터 그 매장까지
/// 백엔드 다익스트라 최단 경로 + ETA를 보여준다.
class FloorMapPreviewScreen extends StatefulWidget {
  const FloorMapPreviewScreen({super.key});

  @override
  State<FloorMapPreviewScreen> createState() => _FloorMapPreviewScreenState();
}

class _FloorMapPreviewScreenState extends State<FloorMapPreviewScreen> {
  final _repository = HttpBuildingRepository();
  FloorPlan? _floorPlan;
  LatLng? _startPoint;
  String? _startNodeId;
  StorePolygon? _selectedStore;
  IndoorRoute? _route;
  bool _routeLoading = false;
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
    final geojson = await _repository.getFloorGeoJson(_buildingId, _floorName);
    if (!mounted || geojson == null) return;

    final floorPlan = FloorPlan.fromJson(geojson);
    final startStore =
        floorPlan.stores.where((store) => store.name == _startStoreName).firstOrNull;
    setState(() {
      _floorPlan = floorPlan;
      _startPoint = startStore?.centroid ?? _fallbackStartPoint(floorPlan);
      _startNodeId = startStore?.entranceNodeId;
    });
  }

  /// 발렌시아가를 못 찾으면(데이터 변경 등) 건물 외곽 중심을 임시 시작점으로 쓴다.
  /// 이 경우 노드 ID가 없어 다익스트라 경로 대신 직선 fallback으로만 표시된다.
  LatLng _fallbackStartPoint(FloorPlan floorPlan) {
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
      _route = null;
      _searchController.clear();
      _query = '';
    });
    _loadRoute(store);
  }

  /// 시작/도착 노드 ID가 모두 있으면 백엔드 다익스트라 경로를 가져온다.
  /// 실패하거나 노드 ID가 없으면 route는 null로 남아 직선 fallback으로 그려진다.
  Future<void> _loadRoute(StorePolygon destination) async {
    final startNodeId = _startNodeId;
    final endNodeId = destination.entranceNodeId;
    if (startNodeId == null || endNodeId == null) return;

    setState(() => _routeLoading = true);
    final route = await _repository.getShortestRoute(
      _buildingId,
      _floorName,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    setState(() {
      _route = route;
      _routeLoading = false;
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
    final route = _route;
    final routePoints = route != null
        ? route.points
        : (start != null && selected != null ? [start, selected.centroid] : const <LatLng>[]);

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
    if (_routeLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: CircularProgressIndicator(),
      );
    }

    final route = _route;
    final distance = route?.distanceMeters ?? localDistanceMeters(start, selected.centroid);
    final minutes = (distance / _walkingSpeedMetersPerSecond / 60).ceil().clamp(1, 999);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$_startStoreName → ${selected.name} · ${selected.category ?? '-'}'),
        const SizedBox(height: 8),
        EtaCard(distanceMeters: distance, minutes: minutes),
      ],
    );
  }
}
