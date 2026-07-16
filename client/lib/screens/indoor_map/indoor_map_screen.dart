import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_plan_view.dart';

const _walkingSpeedMetersPerSecond = 1.2;

/// 실내 지도 본문(층 평면도 + 경로/매장 오버레이). 검색창·길찾기·건물 전환 같은
/// 공통 UI는 [MapShellScreen]이 상단/하단 바로 얹으므로 여기서는 다루지 않는다.
class IndoorMapBody extends StatefulWidget {
  const IndoorMapBody({
    super.key,
    required this.buildingId,
    this.onRouteVisibleChanged,
    this.onStoreTap,
  });

  final String buildingId;

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  /// 지도 위 매장 폴리곤을 탭하면 호출된다. 상위(MapShellScreen)가 검색
  /// 결과를 탭했을 때와 똑같이 매장 정보 시트를 띄운다.
  final ValueChanged<PoiSearchResult>? onStoreTap;

  @override
  State<IndoorMapBody> createState() => IndoorMapBodyState();
}

class IndoorMapBodyState extends State<IndoorMapBody> {
  bool _loading = true;
  Building? _building;
  String? _selectedFloor;
  FloorPlan? _floorPlan;
  IndoorRoute? _route;
  PoiSearchResult? _routeDestination;
  bool _interactive = true;
  String? _highlightedStoreId;

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
  }

  /// 매장 정보 시트가 닫히면 상위(MapShellScreen)가 호출해서 지도 위
  /// 강조 표시도 같이 지운다.
  void clearHighlight() {
    if (_highlightedStoreId == null) return;
    setState(() => _highlightedStoreId = null);
  }

  /// 백엔드 연결 실패 시 사용자에게 보여줄 메시지. null이면 정상 상태.
  /// 이게 없으면 fetch 예외가 조용히 삼켜져 로딩 스피너가 영원히 멈추지 않는다.
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBuilding();
  }

  @override
  void didUpdateWidget(covariant IndoorMapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buildingId != widget.buildingId) {
      _route = null;
      _routeDestination = null;
      _highlightedStoreId = null;
      _loadBuilding();
    }
  }

  Future<void> _loadBuilding() async {
    setState(() {
      _loading = true;
      _error = null;
      // 건물을 바꾸는 동안 이전 건물의 층 평면도가 남아있으면, 아직 로딩
      // 중인데도 _buildBody가 "새 건물 ID + 이전 건물 평면도" 조합으로
      // FloorPlanView를 그려버린다 — 그 상태로 지도 위젯이 한 번 초기
      // 카메라를 잡아버리면(_fitToFootprint) 이후 진짜 평면도가 도착해도
      // 다시 맞추지 않아 엉뚱한 위치를 보여준 채로 굳는다(햄버거로 건물
      // 전환한 직후 지도가 빈 화면으로 보이는 원인). 새 평면도가 준비될
      // 때까지는 로딩 스피너만 보이도록 확실히 비워둔다.
      _floorPlan = null;
    });
    try {
      final building = await buildingRepository.getBuilding(widget.buildingId);
      if (!mounted) return;

      final selectedFloor =
          building != null && building.floors.isNotEmpty ? building.floors.first : null;
      setState(() {
        _building = building;
        _selectedFloor = selectedFloor;
        _loading = false;
      });
      if (selectedFloor != null) await _loadFloorPlan(selectedFloor);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '지도를 불러오지 못했습니다. 서버 연결을 확인해주세요.';
      });
    }
  }

  Future<void> _loadFloorPlan(String floor) async {
    try {
      final geojson = await buildingRepository.getFloorGeoJson(widget.buildingId, floor);
      if (!mounted || geojson == null) return;
      setState(() => _floorPlan = FloorPlan.fromJson(geojson));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '지도를 불러오지 못했습니다. 서버 연결을 확인해주세요.');
    }
  }

  void _selectFloor(String floor) {
    final hadRoute = _route != null;
    setState(() {
      _selectedFloor = floor;
      _floorPlan = null;
      // 층을 바꾸면 이전 경로는 다른 층 지도 위에 남아 있어도 의미가 없다.
      _route = null;
      _routeDestination = null;
      _highlightedStoreId = null;
    });
    if (hadRoute) widget.onRouteVisibleChanged?.call(false);
    _loadFloorPlan(floor);
  }

  /// 위치 보정 버튼. 실제 PDR 위치 연동 전까지는 별도로 보정할 상태가 없어
  /// 재조회만 트리거하는 자리표시자다 — PDR이 붙으면 이 자리에서 재보정한다.
  Future<void> recalibrate() async {
    final floor = _selectedFloor;
    if (floor != null) await _loadFloorPlan(floor);
  }

  /// 길찾기 시트에서 도착지를 고르면 호출된다. 목적지가 다른 층이면 그 층으로
  /// 먼저 전환한 뒤 최단 경로(다익스트라)를 조회해 지도 위에 표시한다.
  ///
  /// [origin]을 주면(매장 정보 시트의 "출발지로 설정") 그 매장의 입구 노드를
  /// 시작점으로 쓰고, 없으면 기존처럼 현재 위치에서 가장 가까운 매장 입구를
  /// 자동으로 고른다.
  Future<void> showRouteTo(PoiSearchResult destination, {PoiSearchResult? origin}) async {
    if (destination.floor != _selectedFloor) {
      _selectFloor(destination.floor);
      await _loadFloorPlan(destination.floor);
    }
    if (!mounted) return;
    final floorPlan = _floorPlan;
    if (floorPlan == null) return;
    setState(() {
      _routeDestination = destination;
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면 지도가
      // 전체 경로에 맞춰 다시 줌아웃되게 한다(FloorPlanView의 null→값 전환).
      _route = null;
    });

    final endNodeId = destination.nodeId;
    final startNodeId = origin?.nodeId ?? _pickStartNodeId(floorPlan, excludingNodeId: endNodeId);
    if (endNodeId == null || startNodeId == null) return;

    final route = await buildingRepository.getShortestRoute(
      widget.buildingId,
      destination.floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    setState(() => _route = route);
    widget.onRouteVisibleChanged?.call(route != null);
  }

  /// PDR이 아직 없어 "현재 위치"를 알 수 없다. 임시로 층 평면도 중심에서
  /// 가장 가까운 매장 입구 노드를 출발점으로 쓴다.
  String? _pickStartNodeId(FloorPlan floorPlan, {String? excludingNodeId}) {
    final origin = floorPlan.approximateCurrentLocation();
    if (origin == null) return null;
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

  void _clearRoute() {
    setState(() {
      _route = null;
      _routeDestination = null;
    });
    widget.onRouteVisibleChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) return _buildError(error);
    return _buildBody();
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 40, color: Colors.black45),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadBuilding,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final building = _building;
    if (building == null) {
      return const Center(child: Text('건물 정보를 찾을 수 없습니다'));
    }
    final floorPlan = _floorPlan;
    if (floorPlan == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final route = _route;
    final routeDestination = _routeDestination;
    final current = (route != null && route.points.isNotEmpty)
        ? route.points.first
        : floorPlan.approximateCurrentLocation();

    return Stack(
      children: [
        FloorPlanView(
          key: ValueKey('${widget.buildingId}-$_selectedFloor'),
          buildingId: widget.buildingId,
          floorName: _selectedFloor!,
          floorPlan: floorPlan,
          currentLocation: current,
          destination: routeDestination?.point,
          routePoints: route?.points ?? const [],
          onStoreSelected: (selected) {
            setState(() => _highlightedStoreId = selected.id);
            widget.onStoreTap?.call(
              PoiSearchResult(
                name: selected.name,
                floor: _selectedFloor!,
                point: selected.centroid,
                nodeId: selected.entranceNodeId,
              ),
            );
          },
          interactive: _interactive,
          highlightedStoreId: _highlightedStoreId,
        ),

        Positioned(
          top: 78,
          left: 0,
          right: 0,
          child: _IndoorInfoBar(
            building: building,
            selectedFloor: _selectedFloor,
            onSelectFloor: _selectFloor,
          ),
        ),

        if (route != null && routeDestination != null)
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
                  minutes: (route.distanceMeters / _walkingSpeedMetersPerSecond / 60)
                      .ceil()
                      .clamp(1, 999),
                  label: '${routeDestination.name}까지',
                  onClose: _clearRoute,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 건물명 + 현재 층 + (여러 층이면) 층 전환 칩을 묶은 오버레이 정보 바.
/// 예전에는 이 내용이 전용 Scaffold 상단바였지만, 검색/길찾기/건물전환은
/// 이제 [MapShellScreen]의 공용 상단바가 맡으므로 여기서는 "지금 보고
/// 있는 건물/층이 어디인지"만 알려주는 보조 역할만 한다.
class _IndoorInfoBar extends StatelessWidget {
  const _IndoorInfoBar({
    required this.building,
    required this.selectedFloor,
    required this.onSelectFloor,
  });

  final Building building;
  final String? selectedFloor;
  final ValueChanged<String> onSelectFloor;

  @override
  Widget build(BuildContext context) {
    final floors = building.floors;
    final selectedFloor = this.selectedFloor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          building.name,
                          style: const TextStyle(
                            fontSize: 14,
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.indoor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers, size: 13, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            selectedFloor,
                            style: const TextStyle(
                              fontSize: 12.5,
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
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: floors.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final floor = floors[index];
                    return _FloorChip(
                      label: floor,
                      active: floor == selectedFloor,
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
          boxShadow: [
            BoxShadow(
              color: active
                  ? AppColors.indoor.withValues(alpha: 0.38)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: active ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
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
