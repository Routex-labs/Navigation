import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/building_switcher_sheet.dart';
import '../../widgets/directions_sheet.dart';
import '../../widgets/map_bottom_bar.dart';
import '../../widgets/map_top_bar.dart';
import '../../widgets/store_info_sheet.dart';
import '../indoor_map/indoor_map_screen.dart';
import '../outdoor_map/outdoor_map_screen.dart';

/// 야외/실내 지도의 공통 뼈대. 홈(야외) ↔ 실내 전환은 Navigator push 없이
/// 이 화면 안에서 모드만 바꿔 탭처럼 즉시 반응하게 한다. 검색·길찾기·건물
/// 전환·위치 보정은 전부 이 화면이 상단/하단 공용 바를 통해 중계한다.
class MapShellScreen extends StatefulWidget {
  const MapShellScreen({super.key, this.initialMode = MapMode.outdoor});

  final MapMode initialMode;

  @override
  State<MapShellScreen> createState() => _MapShellScreenState();
}

/// 경로가 표시되면 ETA 카드가 화면 최하단에 직접 도킹하므로, 하단 공용 바를
/// 그 위로 띄워야 하는 높이. EtaCard 실제 높이(패딩 포함)에 여유를 더한 값.
const _etaBarLiftHeight = 92.0;

class _MapShellScreenState extends State<MapShellScreen> {
  late MapMode _mode = widget.initialMode;
  String _buildingId = demoBuildingId;
  ({String title, String subtitle})? _placeInfo;
  bool _outdoorRouteVisible = false;
  bool _indoorRouteVisible = false;

  final _outdoorKey = GlobalKey<OutdoorMapBodyState>();
  final _indoorKey = GlobalKey<IndoorMapBodyState>();

  @override
  void initState() {
    super.initState();
    _requestStartupPermissions();
  }

  /// 예전에는 스플래시 화면이 이 요청을 진행 중 화면과 함께 보여줬지만,
  /// 이제 앱이 바로 지도 화면으로 시작하므로 화면을 막지 않고 백그라운드로
  /// 요청만 하고, 거부된 게 있으면 지도 위에 짧게 안내만 띄운다.
  Future<void> _requestStartupPermissions() async {
    try {
      final statuses = await requestStartupPermissions();
      final anyDenied = statuses.values.any((status) => !status.isGranted);
      if (!mounted || !anyDenied) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('일부 권한이 거부되어 위치·실내 이동 관련 기능이 제한될 수 있습니다'),
        ),
      );
    } catch (_) {
      // 권한 플러그인을 쓸 수 없는 환경(테스트 등)에서도 앱을 계속 진행한다.
    }
  }

  void _setMode(MapMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _placeInfo = null;
    });
  }

  /// 바텀시트가 떠 있는 동안 지도 제스처를 꺼서, 시트를 마우스 휠로
  /// 스크롤할 때 그 아래 지도까지 같이 스크롤/줌되지 않게 한다. 실내 지도는
  /// 웹에서 실제 DOM 캔버스(MapLibre)라 시트 위에서도 휠 이벤트가 새어나갈
  /// 수 있어서 필요하다.
  Future<T?> _withMapsLocked<T>(Future<T?> Function() showSheet) async {
    _outdoorKey.currentState?.setInteractive(false);
    _indoorKey.currentState?.setInteractive(false);
    try {
      return await showSheet();
    } finally {
      _outdoorKey.currentState?.setInteractive(true);
      _indoorKey.currentState?.setInteractive(true);
    }
  }

  Future<void> _onSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      setState(() => _placeInfo = null);
      return;
    }

    if (_mode == MapMode.outdoor) {
      final buildings = await buildingRepository.getAllBuildings();
      final match = buildings
          .where((b) => b.name.toLowerCase().contains(normalized.toLowerCase()))
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        _placeInfo = match == null
            ? null
            : (title: match.name, subtitle: '${match.floors.length}개 층');
      });
      if (match == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검색 결과가 없습니다')),
        );
      }
      return;
    }

    final results = await destinationRepository.searchDestinations(_buildingId, normalized);
    if (!mounted) return;
    final match = results.firstOrNull;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색 결과가 없습니다')),
      );
      return;
    }

    await _showStoreInfo(match);
  }

  /// 매장 정보 시트를 띄운다. 검색 결과를 탭했을 때와 지도 위 매장 폴리곤을
  /// 직접 탭했을 때 모두 이 메서드를 거쳐 같은 시트가 뜨고, 출발지/도착지로
  /// 지정하면 그 매장을 채운 채로 길찾기 시트로 넘어간다.
  Future<void> _showStoreInfo(PoiSearchResult match) async {
    final action = await _withMapsLocked(
      () => StoreInfoSheet.show(context, title: match.name, subtitle: match.floor),
    );
    if (!mounted) return;
    // 시트가 어떻게 닫혔든(선택 없이 닫힘 포함) 지도 위 강조 표시도 같이 지운다.
    _indoorKey.currentState?.clearHighlight();
    if (action == null) return;

    final candidate = DirectionsCandidate(
      title: match.name,
      subtitle: match.floor,
      point: match.point,
      nodeId: match.nodeId,
      floor: match.floor,
    );
    if (action == StoreInfoAction.setOrigin) {
      await _openDirections(presetOrigin: candidate);
    } else {
      await _openDirections(presetDestination: candidate);
    }
  }

  Future<List<DirectionsCandidate>> _searchDirectionsCandidates(String query) async {
    final normalized = query.trim().toLowerCase();
    if (_mode == MapMode.outdoor) {
      final buildings = await buildingRepository.getAllBuildings();
      return buildings
          .where((b) => b.entrance != null)
          .where((b) => normalized.isEmpty || b.name.toLowerCase().contains(normalized))
          .map(
            (b) => DirectionsCandidate(
              title: b.name,
              subtitle: '${b.floors.length}개 층',
              point: b.entrance!,
            ),
          )
          .toList();
    }
    final results = await destinationRepository.searchDestinations(_buildingId, query);
    return results
        .map(
          (r) => DirectionsCandidate(
            title: r.name,
            subtitle: r.floor,
            point: r.point,
            nodeId: r.nodeId,
            floor: r.floor,
          ),
        )
        .toList();
  }

  /// 길찾기 시트를 연다. [presetOrigin]/[presetDestination]은 매장 정보
  /// 시트의 "출발지로 설정"/"도착지로 설정"에서 넘어올 때 그 매장으로 채워
  /// 둘 값이다 — 상단 바 길찾기 아이콘으로 직접 열 때는 둘 다 비워 기존처럼
  /// 현재 위치 → 검색한 도착지 흐름을 그대로 쓴다. 시트 안에서 출발지를
  /// 직접 고르면(맨 위 "현재 위치" 포함) 그 선택이 [presetOrigin]보다 우선한다.
  Future<void> _openDirections({
    DirectionsCandidate? presetOrigin,
    DirectionsCandidate? presetDestination,
  }) async {
    final result = await _withMapsLocked(
      () => DirectionsSheet.show(
        context,
        originLabel: '현재 위치',
        initialOrigin: presetOrigin,
        initialDestination: presetDestination,
        search: _searchDirectionsCandidates,
      ),
    );
    if (result == null || !mounted) return;

    final destination = result.destination;
    final origin = result.origin;

    if (_mode == MapMode.outdoor) {
      await _outdoorKey.currentState?.showRouteTo(
        destination.point,
        label: destination.title,
        origin: origin?.point,
      );
    } else {
      await _indoorKey.currentState?.showRouteTo(
        PoiSearchResult(
          name: destination.title,
          floor: destination.floor ?? '',
          point: destination.point,
          nodeId: destination.nodeId,
        ),
        origin: origin == null
            ? null
            : PoiSearchResult(
                name: origin.title,
                floor: origin.floor ?? '',
                point: origin.point,
                nodeId: origin.nodeId,
              ),
      );
    }
  }

  Future<void> _onHamburgerTap() async {
    final selected = await _withMapsLocked(
      () => BuildingSwitcherSheet.show(context, selectedBuildingId: _buildingId),
    );
    if (selected == null || selected == _buildingId || !mounted) return;
    setState(() {
      _buildingId = selected;
      _placeInfo = null;
    });
  }

  void _onCalibrate() {
    if (_mode == MapMode.outdoor) {
      _outdoorKey.currentState?.recalibrate();
    } else {
      _indoorKey.currentState?.recalibrate();
    }
  }

  void _onEnterBuilding() => _setMode(MapMode.indoor);

  @override
  Widget build(BuildContext context) {
    final placeInfo = _placeInfo;
    final routeVisible = _mode == MapMode.outdoor ? _outdoorRouteVisible : _indoorRouteVisible;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _mode == MapMode.outdoor ? 0 : 1,
            children: [
              OutdoorMapBody(
                key: _outdoorKey,
                onEnterBuilding: _onEnterBuilding,
                onRouteVisibleChanged: (visible) =>
                    setState(() => _outdoorRouteVisible = visible),
              ),
              IndoorMapBody(
                key: _indoorKey,
                buildingId: _buildingId,
                onRouteVisibleChanged: (visible) =>
                    setState(() => _indoorRouteVisible = visible),
                onStoreTap: _showStoreInfo,
              ),
            ],
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MapTopBar(
              showHamburger: _mode == MapMode.indoor,
              onHamburgerTap: _onHamburgerTap,
              onSearch: _onSearch,
              onDirectionsTap: _openDirections,
            ),
          ),

          if (placeInfo != null)
            Positioned(
              top: 84,
              left: 12,
              right: 12,
              child: _PlaceInfoCard(
                title: placeInfo.title,
                subtitle: placeInfo.subtitle,
                onClose: () => setState(() => _placeInfo = null),
              ),
            ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: routeVisible ? _etaBarLiftHeight : 0,
            child: MapBottomBar(
              mode: _mode,
              onModeChanged: _setMode,
              onCalibrate: _onCalibrate,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceInfoCard extends StatelessWidget {
  const _PlaceInfoCard({required this.title, required this.subtitle, required this.onClose});

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
