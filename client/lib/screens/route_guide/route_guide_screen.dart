import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_plan_view.dart';
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
    final origin = floorPlan.approximateCurrentLocation() ?? _fallbackCenter;
    StorePolygon? nearest;
    double? nearestDistance;
    for (final store in floorPlan.stores) {
      final nodeId = store.entranceNodeId;
      if (nodeId == null || nodeId == excludingNodeId) continue;
      final distance = wgs84DistanceMeters(origin, store.centroid);
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearest = store;
      }
    }
    return nearest?.entranceNodeId;
  }

  void _openBuildingInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const RagChatPanel(),
    );
  }

  LatLng _currentLocation() {
    return _floorPlan?.approximateCurrentLocation() ?? _fallbackCenter;
  }

  ({double distanceMeters, int minutes}) _etaFor(PoiSearchResult destination) {
    final route = _route;
    final distance = route != null
        ? route.distanceMeters
        : wgs84DistanceMeters(_currentLocation(), destination.point);
    final minutes = (distance / _walkingSpeedMetersPerSecond / 60)
        .ceil()
        .clamp(1, 999);
    return (distanceMeters: distance, minutes: minutes);
  }

  @override
  Widget build(BuildContext context) {
    final destination = _destination;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (destination != null)
              _GuidanceBanner(
                destinationName: destination.name,
                eta: _etaFor(destination),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : destination == null
                      ? const Center(child: Text('목적지 정보가 없습니다'))
                      : Stack(
                          children: [
                            _buildMap(destination),
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: FloatingActionButton(
                                heroTag: 'rag-info',
                                onPressed: _openBuildingInfo,
                                tooltip: '건물 정보',
                                child: const Icon(Icons.info_outline),
                              ),
                            ),
                          ],
                        ),
            ),
            if (destination != null)
              _BottomEta(
                eta: _etaFor(destination),
                floor: destination.floor,
                onArrived: () {
                  Navigator.of(context).pushNamed(
                    AppRoutes.arrival,
                    arguments: destination,
                  );
                },
              ),
          ],
        ),
      ),
    );
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
      buildingId: demoBuildingId,
      floorName: destination.floor,
      floorPlan: floorPlan,
      routePoints: route?.points ?? [current, destination.point],
      currentLocation: current,
      destination: destination.point,
    );
  }
}

class _GuidanceBanner extends StatelessWidget {
  const _GuidanceBanner({required this.destinationName, required this.eta});

  final String destinationName;
  final ({double distanceMeters, int minutes}) eta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.42),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(34, 34),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.navigation, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$destinationName(으)로 안내',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            children: [
              _Chip(label: '📱 실내 PDR 모드'),
              _Chip(label: '목적지까지 ${eta.distanceMeters.round()}m'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _BottomEta extends StatelessWidget {
  const _BottomEta({required this.eta, required this.floor, required this.onArrived});

  final ({double distanceMeters, int minutes}) eta;
  final String floor;
  final VoidCallback onArrived;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0x11000000))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: EtaCard(distanceMeters: eta.distanceMeters, minutes: eta.minutes)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.blue50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    floor,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.indoor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onArrived,
                child: const Text('도착'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
