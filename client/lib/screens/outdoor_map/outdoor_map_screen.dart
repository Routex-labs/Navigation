import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/building.dart';
import '../../models/directions_route.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/location_marker.dart';
import '../../widgets/route_polyline.dart';
import '../../widgets/status_badge.dart';

// 위치 조회 실패 시 대체 좌표 (서울시청).
const _fallbackLocation = LatLng(37.5665, 126.9780);
const _lowAccuracyThresholdMeters = 30.0;

/// 배경지도 타일 공급자. 플랫폼 채널·네트워크가 없는 위젯 테스트 환경에서는
/// 이 변수를 실제 OSM/VWorld에 요청하지 않는 가짜 TileProvider로 교체한다
/// (안 그러면 진짜 HTTP 요청이 백그라운드에 남아 이후 테스트의 pumpAndSettle과
/// 뒤섞여 타임아웃을 일으킨다).
TileProvider Function() outdoorTileProvider = NetworkTileProvider.new;

// 건물 진입 판정: "입구 근처" + "신호가 방금 나빠짐"을 같이 봐서
// 건물 앞을 그냥 지나가는 경우(신호는 안 나빠짐)와 구분한다.
// 세 값 다 실측 검증 전이라 추정치이고, 실기기 테스트하며 조정이 필요하다.
const _buildingEntryThresholdMeters = 20.0;
const _degradedAccuracyFloorMeters = 15.0;
const _accuracyWorsenedRatio = 1.3;

/// 야외 지도 본문(지도 + 위치/경로 오버레이). 검색창·길찾기·건물 전환 같은
/// 공통 UI는 [MapShellScreen]이 상단/하단 바로 얹으므로 여기서는 다루지 않는다.
class OutdoorMapBody extends StatefulWidget {
  const OutdoorMapBody({
    super.key,
    required this.onEnterBuilding,
    this.onRouteVisibleChanged,
  });

  /// GPS로 건물 입구 진입이 감지됐을 때 호출된다. 상위(MapShellScreen)가
  /// 이 콜백으로 하단 바 모드를 "실내"로 전환한다.
  final VoidCallback onEnterBuilding;

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  @override
  State<OutdoorMapBody> createState() => OutdoorMapBodyState();
}

class OutdoorMapBodyState extends State<OutdoorMapBody> {
  bool _autoNavigated = false;
  Position? _position;
  LatLng? _entrance;
  DirectionsRoute? _route;
  double? _previousAccuracy;
  StreamSubscription<Position>? _positionSubscription;
  final MapController _mapController = MapController();
  bool _interactive = true;

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
  }

  /// 길찾기 시트에서 사용자가 직접 고른 목적지. null이면 건물 입구까지의
  /// 경로를 대신 보여준다(기존 "자동 안내" 동작).
  LatLng? _userDestination;
  String? _userDestinationLabel;

  @override
  void initState() {
    super.initState();
    _loadBuildingEntrance();
    _positionSubscription = watchPosition().listen(
      _handlePosition,
      onError: (Object _) => _handlePositionError(),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadBuildingEntrance() async {
    final Building? building = await buildingRepository.getBuilding(
      demoBuildingId,
    );
    if (!mounted) return;
    setState(() => _entrance = building?.entrance);
  }

  void _handlePositionError() {
    if (!mounted) return;
    setState(() => _position = null);
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    setState(() => _position = position);
    _maybeAutoEnter(position);
    _updateRoute(position);
  }

  void _maybeAutoEnter(Position position) {
    final entrance = _entrance;
    if (_autoNavigated || entrance == null) return;

    final distance = const Distance().as(
      LengthUnit.Meter,
      LatLng(position.latitude, position.longitude),
      entrance,
    );
    final isNear = distance <= _buildingEntryThresholdMeters;

    final previousAccuracy = _previousAccuracy;
    _previousAccuracy = position.accuracy;
    final accuracyWorsened =
        position.accuracy > _degradedAccuracyFloorMeters &&
        (previousAccuracy == null ||
            position.accuracy > previousAccuracy * _accuracyWorsenedRatio);

    if (!isNear || !accuracyWorsened) return;

    _autoNavigated = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('건물 감지 중...')));
    widget.onEnterBuilding();
  }

  Future<void> _updateRoute(Position position) async {
    final target = _userDestination ?? _entrance;
    if (target == null) return;

    final route = await directionsRepository.getWalkingRoute(
      origin: LatLng(position.latitude, position.longitude),
      destination: target,
    );
    if (!mounted) return;
    _applyRoute(route);
  }

  /// 경로가 새로 생기면(이전엔 없다가 이번에 생김) 상위에 ETA 바가 보인다고
  /// 알리고, 경로 전체가 화면에 들어오도록 카메라를 자동으로 줌아웃한다.
  /// 이미 경로가 있는 상태에서 위치가 갱신돼 경로가 매번 다시 계산될 때는
  /// (걷는 동안 계속 일어남) 다시 맞추지 않는다 — 사용자가 지도를 보는 중에
  /// 카메라가 계속 튀면 방해가 된다. 새 목적지를 고르면(showRouteTo) 그때는
  /// 다시 한번 전체 경로가 보이도록 맞춘다.
  void _applyRoute(DirectionsRoute? route) {
    final wasVisible = _route != null;
    setState(() => _route = route);
    final isVisible = route != null;
    if (wasVisible != isVisible) {
      widget.onRouteVisibleChanged?.call(isVisible);
    }
    if (!wasVisible && isVisible) {
      _fitCameraToRoute(route);
    }
  }

  void _fitCameraToRoute(DirectionsRoute route) {
    // 출발점과 도착점이 사실상 같은 좌표면(예: 건물 입구 바로 앞) 경계 상자
    // 폭이 0에 가까워져 줌 계산이 NaN으로 발산한다 — 이 경우엔 화면에 맞출
    // "경로"랄 게 없으니 자동 줌은 건너뛴다.
    if (route.points.length < 2 || route.distanceMeters < 5) return;
    // FlutterMap이 최소 한 프레임 렌더링을 마치기 전에는 컨트롤러가
    // 카메라 조작을 받아줄 준비가 안 돼 있어 예외를 던진다 — 위치 스트림이
    // 첫 build보다 먼저(또는 그 직후 바로) 값을 내놓는 경우(테스트 환경 등)
    // 실제로 그렇다. 다음 프레임까지 미뤄서 항상 안전하게 호출되게 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(route.points),
          padding: const EdgeInsets.fromLTRB(40, 110, 40, 180),
        ),
      );
    });
  }

  /// 위치 보정 버튼: 즉시 새 GPS 위치를 한 번 더 조회해 마커·지도 중심을 갱신한다.
  Future<void> recalibrate() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      _handlePosition(position);
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        _mapController.camera.zoom,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치를 다시 확인하지 못했습니다')),
      );
    }
  }

  /// 길찾기 시트에서 도착지를 고르면 호출된다. [origin]을 주면(길찾기
  /// 시트에서 출발지도 직접 고른 경우) 현재 GPS 위치 대신 그 지점을
  /// 출발점으로 써서 경로를 한 번만 계산한다 — 두 지점 사이 경로를 보는
  /// 용도라 GPS를 따라 계속 갱신할 필요가 없다. 없으면 기존처럼 현재
  /// 위치에서 [destination]까지의 보행 경로를 계산해 지도 위에 표시한다.
  Future<void> showRouteTo(
    LatLng destination, {
    required String label,
    LatLng? origin,
  }) async {
    setState(() {
      _userDestination = destination;
      _userDestinationLabel = label;
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면
      // _applyRoute가 "새로 생김"으로 보고 카메라를 다시 맞추게 한다.
      _route = null;
    });

    if (origin != null) {
      final route = await directionsRepository.getWalkingRoute(
        origin: origin,
        destination: destination,
      );
      if (!mounted) return;
      _applyRoute(route);
      return;
    }

    final position = _position;
    if (position == null) return;
    await _updateRoute(position);
  }

  void _clearUserDestination() {
    setState(() {
      _userDestination = null;
      _userDestinationLabel = null;
      _route = null;
    });
    widget.onRouteVisibleChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) => _buildBody();

  Widget _buildBody() {
    final position = _position;
    final center = position == null
        ? _fallbackLocation
        : LatLng(position.latitude, position.longitude);
    final accuracy = position?.accuracy ?? 0;
    final lowAccuracy = position == null || accuracy > _lowAccuracyThresholdMeters;
    final markerColor = lowAccuracy ? AppColors.warning : AppColors.primary;
    final entrance = _entrance;
    final userDestination = _userDestination;
    final route = _route;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 17,
            // 검색·길찾기 시트가 열려 있는 동안은 그 시트를 마우스 휠로
            // 스크롤해도 아래 지도까지 같이 움직이지 않도록 제스처를 끈다.
            interactionOptions: InteractionOptions(
              flags: _interactive ? InteractiveFlag.all : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              // VWorld는 키 발급(도메인 등록) 전제. 키가 없으면 OSM으로 대체해
              // 로컬 개발·테스트 환경에서도 지도가 항상 뜨도록 한다.
              urlTemplate: vworldApiKey.isEmpty
                  ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                  : 'https://api.vworld.kr/req/wmts/1.0.0/$vworldApiKey/Base/{z}/{y}/{x}.png',
              userAgentPackageName: 'com.navigation.navigation_client',
              tileProvider: outdoorTileProvider(),
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: center,
                  radius: accuracy > 0 ? accuracy : 20,
                  useRadiusInMeter: true,
                  color: markerColor.withValues(alpha: 0.2),
                  borderColor: markerColor,
                  borderStrokeWidth: 1,
                ),
              ],
            ),
            if (route != null)
              PolylineLayer(polylines: [buildRoutePolyline(route.points)]),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  child: LocationMarker(
                    mode: LocationMode.outdoor,
                    colorOverride: markerColor,
                    // heading은 기기가 유효한 값을 못 줄 때 -1(또는 0)을 내려주는
                    // 경우가 있어, 음수면 회전하지 않고 기본 방향을 유지한다.
                    headingDegrees: (position != null && position.heading >= 0)
                        ? position.heading
                        : null,
                  ),
                ),
                // 경로의 실제 출발점. 대부분은 현재 위치와 같지만, 길찾기
                // 시트에서 출발지를 직접 골랐을 때는 현재 위치와 달라질 수
                // 있어 그 지점에 별도로 표시한다(너무 가까우면 위 마커와
                // 겹치므로 생략).
                if (route != null &&
                    route.points.isNotEmpty &&
                    const Distance().as(LengthUnit.Meter, route.points.first, center) > 5)
                  Marker(
                    point: route.points.first,
                    child: const Icon(Icons.trip_origin, color: AppColors.success),
                  ),
                if (userDestination != null)
                  Marker(
                    point: userDestination,
                    child: const Icon(Icons.place, color: AppColors.dest),
                  )
                else if (entrance != null)
                  Marker(
                    point: entrance,
                    child: const Icon(Icons.place, color: AppColors.dest),
                  ),
              ],
            ),
          ],
        ),

        if (lowAccuracy)
          Positioned(
            top: 76,
            left: 12,
            child: StatusBadge(
              label: 'GPS 신호 약함',
              color: AppColors.warning,
              icon: Icons.warning_amber_rounded,
            ),
          ),

        if (route != null)
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
                  minutes: (route.durationSeconds / 60).ceil().clamp(1, 999),
                  label: userDestination != null
                      ? (_userDestinationLabel ?? '목적지까지')
                      : '건물 입구까지',
                  onClose: userDestination != null ? _clearUserDestination : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
