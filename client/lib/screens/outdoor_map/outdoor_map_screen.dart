import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show Point, pi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../domain/geo_transform.dart';
import '../../features/debug_mode/debug_pdr_trail_state.dart';
import '../../features/indoor_navigation/application/floor_map_matcher.dart';
import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';
import '../../domain/multi_floor_router.dart';
import '../../models/building.dart';
import '../../models/building_graph.dart';
import '../../models/directions_route.dart';
import '../../models/floor_graph.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/floor_facility_style.dart';
import '../../widgets/floor_selector.dart';
import '../../widgets/status_badge.dart';

// 위치 조회 실패 시 대체 좌표 (서울시청). 저장·전달은 latlong2 타입으로 하고
// MapLibre API에 넘길 때만 [_toGl]로 변환한다 — 이 파일 외부(Building.entrance,
// DirectionsRoute.points)가 latlong2를 쓰고 있어 그 타입을 저장 형식으로 유지한다.
const _fallbackLocation = ll.LatLng(37.5665, 126.9780);
const _lowAccuracyThresholdMeters = 30.0;
// 실내 경로 ETA 분 계산에 쓰는 평균 걷기 속도. 실내 화면 상수와 일치시켜야
// 같은 목적지 라우팅에서 두 화면 사이 표시가 어긋나지 않는다.
const _indoorWalkingSpeedMetersPerSecond = 1.2;

// 건물 진입 판정: "입구 근처" + "신호가 방금 나빠짐"을 같이 봐서
// 건물 앞을 그냥 지나가는 경우(신호는 안 나빠짐)와 구분한다.
// 세 값 다 실측 검증 전이라 추정치이고, 실기기 테스트하며 조정이 필요하다.
const _buildingEntryThresholdMeters = 20.0;
const _degradedAccuracyFloorMeters = 15.0;
const _accuracyWorsenedRatio = 1.3;

// 실내 지도와 같은 이유. maplibre_gl은 web/android/iOS만 지원하므로
// 데스크톱에서는 사전에 안내를 보여주고 지도 자체는 그리지 않는다.
const _mapSupportedNativePlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
};
bool get _isMapSupportedOnThisPlatform =>
    kIsWeb || _mapSupportedNativePlatforms.contains(defaultTargetPlatform);

// MapLibre 소스·레이어 ID. 층 지도의 명명 규칙(_로 시작하지 않는 kebab-case) 준수.
const _buildingSourceId = 'outdoor-building';
const _buildingFillLayerId = 'outdoor-building-fill';
const _buildingOutlineLayerId = 'outdoor-building-outline';
const _indoorTilesSourceId = 'outdoor-indoor-tiles';
const _indoorFootprintLayerId = 'outdoor-indoor-footprint';
const _indoorStoresFillLayerId = 'outdoor-indoor-stores-fill';
// 수직이동(에스컬레이터/엘리베이터) 구조물 폴리곤을 초록톤으로 덧칠하는 fill.
// _indoorStoresFillLayerId 위, 라벨/아이콘보다 아래에 삽입해 초록 배경 + 라벨/
// 아이콘이 한 덩어리로 읽히게 한다. 실내 화면의 _verticalTransportFillLayerId와
// 시각 언어를 맞춘다.
const _indoorVerticalTransportFillLayerId =
    'outdoor-indoor-vertical-transport-fill';
const _indoorStoresLabelLayerId = 'outdoor-indoor-stores-label';
// POI(엘리베이터·에스컬레이터·화장실 등 `pois` 소스 레이어) 위 아이콘 심볼과
// `stores` 소스 레이어에 이름으로 매칭되는 편의시설(화장실·정수기·수유실 등)
// 위 아이콘 심볼. 실내 화면과 같은 아이콘/색을 써 두 화면 사이에서 위치를
// 이어보아도 시설 표기가 흔들리지 않는다.
const _indoorPoiIconLayerId = 'outdoor-indoor-pois-icon';
const _indoorStoreFacilityIconLayerId =
    'outdoor-indoor-store-facility-icons';
const _routeSourceId = 'outdoor-route';
const _routeCasingLayerId = 'outdoor-route-casing';
const _routeLineLayerId = 'outdoor-route-line';
const _currentSourceId = 'outdoor-current';
const _accuracyLayerId = 'outdoor-accuracy';
const _currentDotLayerId = 'outdoor-current-dot';
const _destSourceId = 'outdoor-destination';
const _destLayerId = 'outdoor-destination-pin';
// 실내 진입 상태에서 사용자의 PDR 위치(앵커 또는 실시간 확정 위치)를 그리는
// 전용 소스·레이어. 야외 GPS 마커와 함께 그려질 수 있지만 색과 위치가 달라
// 겹쳐도 서로 구분된다 — GPS는 건물 밖 신호, PDR은 건물 내 실측이라 두 표시가
// 동시에 보이는 순간이 자연스러운 전환기다.
const _pdrCurrentSourceId = 'outdoor-pdr-current';
const _pdrCurrentLayerId = 'outdoor-pdr-current-dot';
// PDR 위치 심볼 아이콘 이름(addImage 등록 키). heading이 있으면 방향 원뿔이
// 함께 그려진 이미지, 없으면 원형 도트만 있는 이미지로 자동 교체된다. 실내
// 지도의 현재 위치 마커와 동일한 시각 언어를 유지하려고 같은 파란 색·크기를
// 사용한다(현시점 이 렌더링은 두 화면에 각각 있음 — 시각 스타일을 바꿀 땐
// floor_plan_view.dart의 _renderCurrentLocationIcon도 함께 맞춰야 한다).
const _pdrLocationImageName = 'outdoor-pdr-location';
const _pdrLocationDotImageName = 'outdoor-pdr-location-dot';
// 실내 오버레이에서 매장 폴리곤을 탭했을 때 그 매장 하나만 옅은 파란색 + 진한
// 테두리로 강조 표시하는 전용 소스·레이어. 실내 지도의 highlight와 같은 톤
// (#1A73E8, 옅은 fill + 얇은 line)으로 맞춰 두 화면 사이 UX가 흔들리지 않게 한다.
const _highlightSourceId = 'outdoor-highlight';
const _highlightFillLayerId = 'outdoor-highlight-fill';
const _highlightLineLayerId = 'outdoor-highlight-line';

// 건물 폴리곤의 기본/눌린 상태 fill opacity. 기본은 옅게 존재만 알리고,
// 사용자가 탭한 순간 잠깐 진하게 반짝여서 "인식됐다"는 시각 피드백을 준다.
const _buildingFillOpacityDefault = 0.15;
const _buildingFillOpacityPressed = 0.45;
// 탭 후 오버레이 페이드인이 완료되는 시간 감각. 시각 피드백이 잠깐 이어져야
// "인식됐다" 느낌을 준다.
const _buildingPressedHoldMs = 220;

// 실내 오버레이가 zoom-interpolate로 페이드인되는 줌 구간. 이 아래는 완전히
// 숨겨져 야외 지도만 보이고, 이 위는 완전히 보인다.
const _indoorOverlayFadeInStartZoom = 16.5;
const _indoorOverlayFadeInEndZoom = 17.5;

// 실내 MVT 소스에 minzoom을 걸어 이 값 미만에서는 아예 타일 요청이 나가지 않게
// 한다. 이유: 백엔드 MVT는 요청 타일 경계로 지오메트리를 4096 유닛에 양자화하는데
// (mapbox_vector_tile.encode의 quantize_bounds), 낮은 zoom(예: z=10)에서는 1
// 유닛이 10 m 이상이라 건물이 눈에 띄게 뒤틀린 채로 저장된다. 사용자가 야외 지도를
// 축소했다 다시 확대하는 순간 MapLibre가 캐시된 저-zoom 부모 타일을 over-scale해
// 잠깐 표시하는데(정확한 z=17 타일이 도착하기 전), 이 부모 타일이 회전된 도면처럼
// 보이는 원인이었다. 페이드 시작(_indoorOverlayFadeInStartZoom=16.5) 바로 아래에
// 잡아 이하 zoom에서는 요청도 캐시도 없게 한다 — 어차피 opacity=0이라 시각적
// 손해가 없고, 저-zoom 캐시가 없으므로 zoom-in 시 항상 fresh 고정밀 타일이 뜬다.
const _indoorTilesMinZoom = 16.0;

// 극한 확대(z>=19) 시 MapLibre가 backend에 매우 좁은 tile bounds로 quantize된
// MVT를 요청하는데, tile 경계가 좁을수록 double 좌표 → 4096 유닛 quantize 과정에서
// 상대 오차가 누적돼 도면이 미세하게 뒤틀린다. maxzoom을 이 값으로 잡아 그 이상에서는
// z=18 tile을 over-scale하도록 한다. z=18 tile은 ~150m 폭이라 0.04m/유닛의 안정된
// precision을 가진다.
const _indoorTilesMaxZoom = 18.0;

// 사용자가 지도를 이만큼 이상 확대하면 "실내 진입" 의도로 보고, 야외 지도 위에
// 층 chip과 위치 지정 버튼 등 실내 UI 오버레이를 얹는다. 오버레이가 완전히
// 보이는 시점(_indoorOverlayFadeInEndZoom)과 맞춰 페이드가 끝나는 순간 부가
// 인터페이스도 함께 나타나도록 한다. 모드(홈/실내)는 여기서 전환하지 않는다 —
// 사용자는 하단 세그먼트로 언제든 전환 가능하고, 이 오버레이는 야외 화면
// 그대로에서 실내 기능을 즉시 쓸 수 있게 확장하는 목적이다.
const _indoorEntryZoomThreshold = _indoorOverlayFadeInEndZoom;

// PDR 앵커 배치 시 탭 위치에서 통로 그래프까지 허용하는 최대 거리(m).
// 야외 지도에서는 건물이 화면 안에서 상대적으로 작게 보이고 탭 정밀도가 떨어져
// 실내 SVG(12m)보다 크게 잡는다 — 사용자가 매장 폴리곤 안쪽을 탭해도 인근
// 복도 노드까지 20~25m 벌어지는 경우가 흔하다. 그 이상이면 사실상 건물 밖을
// 잘못 탭한 것으로 보고 다시 유도한다.
const _maxPdrAnchorSnapDistanceM = 40.0;

// 층 선택기와 하단 바 사이 baseline 계산에 쓰이는 MapBottomBar 내부 여백.
// map_bottom_bar.dart의 outer padding(14) + ModeSegment 실제 높이(≈45) + spacer(10).
// 실내 화면과 동일한 상수로 계산해 두 화면 사이 pill 위치가 어긋나지 않게 한다.
const _bottomBarInnerBottomPaddingPx = 14.0;
const _floorSelectorBottomOffset =
    _bottomBarInnerBottomPaddingPx + 45.0 + 10.0;
// 경로 ETA 카드가 화면에 뜨면 하단 바(=층 선택기 기준선)가 이만큼 위로 올라간다.
// map_shell_screen.dart의 _etaBarLiftHeight와 동일해야 한다.
const _bottomBarLiftPx = 92.0;

// latlong2 <-> MapLibre 타입 브릿지.
LatLng _toGl(ll.LatLng p) => LatLng(p.latitude, p.longitude);

/// PDR 현재 위치 마커용 아이콘을 오프스크린 캔버스에 그려 PNG 바이트로 만든다.
/// [showHeading]이 true면 파란 도트 위에 방향 원뿔(radial gradient)이 함께
/// 그려진 이미지가 나오고, false면 도트만 있는 이미지가 나온다. MapLibre
/// SymbolLayer는 미리 addImage로 등록된 비트맵만 참조할 수 있어 이렇게 캔버스
/// 렌더가 필요하다. 실내 [floor_plan_view.dart:_renderCurrentLocationIcon]의
/// 시각을 그대로 옮겨, 실내·야외에서 같은 지점을 봤을 때 마커가 달라 보이지
/// 않게 한다.
Future<Uint8List> _renderPdrLocationIcon({required bool showHeading}) async {
  const canvasSize = 144.0;
  const center = Offset(canvasSize / 2, canvasSize / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
  );

  if (showHeading) {
    const coneRadius = 62.0;
    const halfAngle = 31 * pi / 180;
    final coneBounds = Rect.fromCircle(center: center, radius: coneRadius);
    final headingCone = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(coneBounds, -pi / 2 - halfAngle, halfAngle * 2, false)
      ..close();
    canvas.drawPath(
      headingCone,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          coneRadius,
          const [Color(0x8F1976D2), Color(0x451976D2), Color(0x001976D2)],
          const [0, 0.58, 1],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  canvas.drawCircle(
    center + const Offset(0, 2),
    27,
    Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
  canvas.drawCircle(center, 24, Paint()..color = Colors.white);

  const blue = Color(0xFF1976D2);
  canvas.drawCircle(center, 18, Paint()..color = blue);
  canvas.drawCircle(
    center - const Offset(5, 5),
    4.5,
    Paint()..color = const Color(0x66FFFFFF),
  );

  final image = await recorder.endRecording().toImage(
    canvasSize.toInt(),
    canvasSize.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

// 기본 지도 스타일. vworldApiKey가 있으면 VWorld Base 타일, 없으면 OSM으로 폴백해
// 로컬 개발·테스트 환경에서도 지도가 항상 뜨도록 한다.
String _baseMapStyle() {
  final Map<String, dynamic> source;
  if (vworldApiKey.isEmpty) {
    source = {
      'type': 'raster',
      'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      'tileSize': 256,
      'attribution':
          '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    };
  } else {
    source = {
      'type': 'raster',
      'tiles': [
        'https://api.vworld.kr/req/wmts/1.0.0/$vworldApiKey/Base/{z}/{y}/{x}.png',
      ],
      'tileSize': 256,
      'attribution': '© <a href="https://map.vworld.kr">VWorld</a>',
    };
  }
  return jsonEncode({
    'version': 8,
    // glyphs 없이는 나중에 얹는 실내 오버레이의 매장명 SymbolLayer가 폰트를
    // 못 받아 layout을 못 끝낸다. MapLibre GL Native는 같은 벡터 타일 소스에
    // 딸린 fill 레이어(footprint/stores)까지 이 pending에 묶여 통째로 안
    // 그려진다 — 실기기에서 야외 지도 위에 실내 오버레이가 통째로 사라지는
    // 원인이었다. 웹은 이 부분이 관대해 fill만 그대로 보이지만, 실기기에서는
    // 반드시 채워야 한다. 백엔드가 실내 지도용으로 이미 같은 endpoint를 서빙
    // 하므로 같은 URL을 쓴다(fonts/{fontstack}/{range}.pbf).
    'glyphs': '$apiBaseUrl/fonts/{fontstack}/{range}.pbf',
    'sources': {'base': source},
    'layers': [
      {'id': 'base', 'type': 'raster', 'source': 'base'},
    ],
  });
}

Map<String, dynamic> _pointFeature(ll.LatLng point) {
  return {
    'type': 'Feature',
    'properties': const <String, dynamic>{},
    'geometry': {
      'type': 'Point',
      'coordinates': [point.longitude, point.latitude],
    },
  };
}

Map<String, dynamic> _lineFeature(List<ll.LatLng> points) {
  return {
    'type': 'Feature',
    'properties': const <String, dynamic>{},
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final p in points) [p.longitude, p.latitude],
      ],
    },
  };
}

Map<String, dynamic> _emptyCollection() =>
    {'type': 'FeatureCollection', 'features': const <Map<String, dynamic>>[]};

Map<String, dynamic> _collection(List<Map<String, dynamic>> features) =>
    {'type': 'FeatureCollection', 'features': features};

/// 야외 지도 본문(지도 + 위치/경로 오버레이). 검색창·길찾기·건물 전환 같은
/// 공통 UI는 [MapShellScreen]이 상단/하단 바로 얹으므로 여기서는 다루지 않는다.
///
/// 실내 진입(건물 탭·줌 임계값 초과·GPS 근접 감지)은 화면 모드를 실내로 전환
/// 하지 않고, 이 화면 위에 층 chip과 위치 지정 등 실내 UI 오버레이를 얹어
/// 하나의 화면에서 계속 조작할 수 있게 한다. 하단 홈/실내 세그먼트는 그대로
/// 두어 사용자가 원하면 종래의 별도 실내 지도로도 진입할 수 있다.
class OutdoorMapBody extends StatefulWidget {
  const OutdoorMapBody({
    super.key,
    this.onRouteVisibleChanged,
    this.onPlacingLocationChanged,
    this.onIndoorEnteredChanged,
    this.onStoreTap,
  });

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  /// PDR 앵커 배치 대기 상태가 바뀔 때 호출된다. 상위(MapShellScreen)가 이
  /// 값으로 하단 바의 "위치 지정" 버튼을 눌린(활성) 톤으로 표시한다.
  final ValueChanged<bool>? onPlacingLocationChanged;

  /// 야외 지도의 실내 진입 오버레이가 켜지거나 꺼질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 바의 "위치 지정" 버튼 노출 여부를
  /// 결정한다 — 오버레이가 꺼져 있을 때는 눌러도 의미가 없어 아예 숨긴다.
  final ValueChanged<bool>? onIndoorEnteredChanged;

  /// 실내 진입 오버레이에서 매장 폴리곤을 탭했을 때 호출된다. 상위
  /// (MapShellScreen)가 실내 화면과 동일한 매장 정보 시트를 띄운다.
  final ValueChanged<PoiSearchResult>? onStoreTap;

  @override
  State<OutdoorMapBody> createState() => OutdoorMapBodyState();
}

class OutdoorMapBodyState extends State<OutdoorMapBody> {
  bool _autoNavigated = false;
  Position? _position;
  ll.LatLng? _entrance;
  Building? _building;
  List<ll.LatLng>? _buildingFootprint;
  DirectionsRoute? _route;
  // 실내 진입 오버레이 위에 그리는 실내 경로. 현재 보고 있는 층에 해당하는
  // 세그먼트만 지도에 그려지고, 층 chip으로 다른 층을 훑으면 해당 층 세그먼트로
  // 갈아탄다. 다층 경로일 때는 [_indoorMultiFloorRoute]에 전체가 남아 있어
  // ETA 총 거리도 유지된다.
  IndoorRoute? _indoorRouteSegment;
  MultiFloorRoute? _indoorMultiFloorRoute;
  PoiSearchResult? _indoorRouteDestination;
  double? _previousAccuracy;
  StreamSubscription<Position>? _positionSubscription;
  bool _interactive = true;
  ll.LatLng? _userDestination;
  String? _userDestinationLabel;

  MapLibreMapController? _mapController;
  bool _styleReady = false;
  // 야외 오버레이가 지금 보여주는 층. 건물 로드 시 initialFloor로 자동 결정되고,
  // 실내 진입 상태에서 층 chip으로 사용자가 다른 층을 훑어볼 수 있다.
  String? _activeFloor;
  // 활성 층의 통행 그래프. PDR 앵커 배치 시 탭 좌표를 층 로컬로 되돌리고
  // 통로 노드에 스냅하는 데 쓴다. 층 전환마다 다시 로드한다.
  FloorGraph? _floorGraph;
  // 활성 층의 평면도(매장 목록 포함). 실내 오버레이 위에서 매장 폴리곤을
  // 탭했을 때 벡터 타일 feature id로 실제 매장 정보를 되찾는 데 쓴다.
  FloorPlan? _floorPlan;
  // 실내 오버레이에서 지금 강조 표시 중인 매장 id. null이면 강조 없음.
  // 사용자가 매장을 탭하면 채워지고, 매장 정보 시트가 닫히면 상위가
  // [clearHighlight]로 지운다.
  String? _highlightedStoreId;
  // 지도가 아직 안 뜬 시점의 첫 GPS 위치를 잊지 않도록 pending 값을 두고,
  // 스타일 로드 콜백에서 이를 반영한다.
  bool _pendingCenterOnPosition = false;
  // 줌 임계값을 넘겼을 때 실내 진입 오버레이를 한 번만 켜기 위한 히스테리시스.
  // 임계값 아래로 다시 내려오기 전까지는 재발화하지 않는다.
  bool _autoIndoorEntryArmed = true;
  // POI/시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록하기 위한 게이팅.
  // 층 전환마다 소스/레이어는 다시 붙지만 이미지는 그대로 재사용된다.
  bool _facilityIconImagesRegistered = false;

  /// 실내 진입 오버레이 상태. true면 층 chip과 위치 지정 버튼 등 실내 UI를
  /// 야외 지도 위에 그린다. 건물 폴리곤 탭, 줌 임계값 초과, GPS 근접 감지
  /// 중 하나로 켜지고, 사용자가 지도를 축소해 임계값 아래로 내려가면 자동으로
  /// 꺼진다 — 실내에서 벗어난 시점에는 오버레이가 시야를 방해하지 않아야 한다.
  bool _indoorEntered = false;

  /// PDR 앵커 배치 대기 중인지. true면 다음 지도 탭은 건물 진입 처리가 아닌
  /// PDR 시작점 지정으로 소비된다.
  bool _placingPdrAnchor = false;
  late final DebugPdrTrailState _pdrTrailState;
  StreamSubscription<PdrSnapshot>? _pdrSnapshotSub;
  StreamSubscription<CalibrationStatus>? _pdrCalibrationSub;

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
  }

  @override
  void initState() {
    super.initState();
    _pdrTrailState = DebugPdrTrailState.fromCurrent(
      snapshot: indoorNavigationDriver.currentSnapshot,
      calibration: indoorNavigationDriver.currentCalibration,
    );
    _pdrSnapshotSub = indoorNavigationDriver.snapshots.listen((snapshot) {
      if (!mounted) return;
      setState(() => _pdrTrailState.recordSnapshot(snapshot));
      _syncPdrCurrentLayer();
    });
    _pdrCalibrationSub = indoorNavigationDriver.calibration.listen((status) {
      if (!mounted) return;
      setState(() => _pdrTrailState.recordCalibration(status));
      if (status.phase == CalibrationPhase.calibrated ||
          status.phase == CalibrationPhase.uncalibrated) {
        _setPlacingAnchor(false);
      }
      _syncPdrCurrentLayer();
    });
    _loadBuildingEntrance();
    _positionSubscription = watchPosition().listen(
      _handlePosition,
      onError: (Object _) => _handlePositionError(),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    super.dispose();
  }

  Future<void> _loadBuildingEntrance() async {
    final Building? building = await buildingRepository.getBuilding(
      demoBuildingId,
    );
    if (!mounted) return;
    setState(() {
      _building = building;
      _entrance = building?.entrance;
      _buildingFootprint = building?.footprintWgs84;
      _activeFloor = building?.initialFloor;
    });
    _syncDestinationLayer();
    _syncBuildingLayer();
    // 스타일이 이미 로드된 뒤 건물이 늦게 도착한 케이스(테스트/느린 네트워크)를
    // 위해 실내 MVT 소스도 여기서 한 번 더 등록 시도.
    _ensureIndoorTilesRegistered();
    final floor = _activeFloor;
    if (building != null && floor != null) {
      await _loadFloorGraph(building.id, floor);
    }
  }

  /// 활성 층의 통행 그래프와 매장 목록(FloorPlan)을 함께 로드한다.
  /// - 그래프: PDR 앵커 배치·스냅과 마커 렌더링에 쓰인다.
  /// - 평면도: 실내 오버레이 위 매장 폴리곤 탭으로 벡터 타일 feature id를
  ///   실제 매장 정보로 되돌리는 데 쓴다.
  /// 실패는 조용히 넘겨 그래프/평면도 없이 층 시각화만 유지한다.
  Future<void> _loadFloorGraph(String buildingId, String floor) async {
    try {
      final geojson = await buildingRepository.getFloorGeoJson(
        buildingId,
        floor,
      );
      if (!mounted) return;
      final graphJson = geojson?['navigation_graph'];
      final graph = graphJson is Map<String, dynamic>
          ? FloorGraph.fromJson(graphJson)
          : null;
      final plan = geojson != null ? FloorPlan.fromJson(geojson) : null;
      setState(() {
        _floorGraph = graph;
        _floorPlan = plan;
      });
      _syncPdrCurrentLayer();
    } catch (_) {
      // 로드 실패 시 앵커 배치·매장 탭은 안내로 막고 나머지 야외 지도 동작은
      // 그대로 유지한다.
      if (mounted) {
        setState(() {
          _floorGraph = null;
          _floorPlan = null;
        });
      }
    }
  }

  /// 층 chip으로 다른 층을 골랐을 때. 실내 MVT 오버레이 소스를 통째로 갈아
  /// 끼워 새 층 타일을 받아오게 하고, PDR 스냅용 층 그래프도 함께 갱신한다.
  Future<void> _switchOverlayFloor(String floor) async {
    if (floor == _activeFloor) return;
    final controller = _mapController;
    final building = _building;
    if (controller == null || building == null || !_styleReady) return;

    // 다층 경로가 있으면 새 층의 세그먼트로 갈아 끼운다(없으면 이 층에는
    // 안 그린다). 단일층 경로였다면 다른 층으로 옮기는 순간 경로가 무의미해지므로
    // 지도에서 지운다 — 실내 화면과 동일 규칙.
    final multiRoute = _indoorMultiFloorRoute;
    final nextSegmentRoute = multiRoute?.segmentForFloor(floor)?.route;
    setState(() {
      _activeFloor = floor;
      _floorGraph = null;
      _floorPlan = null;
      if (multiRoute == null) {
        _indoorRouteSegment = null;
      } else {
        _indoorRouteSegment = nextSegmentRoute;
      }
      // 층이 바뀌면 그 층에 강조하던 매장은 지도에 없다. 강조도 초기화.
      _highlightedStoreId = null;
    });
    if (_indoorTilesRegistered) {
      // 순서 중요: 레이어부터 지워야 소스를 지울 수 있다(레이어가 붙어있으면 오류).
      // 이미 없는 레이어에 대해 removeLayer가 예외를 던지는 native 구현도 있어
      // 각 항목을 try/catch로 감싼다.
      for (final id in _indoorOverlayLayerIds) {
        try {
          await controller.removeLayer(id);
        } catch (_) {}
      }
      try {
        await controller.removeSource(_indoorTilesSourceId);
      } catch (_) {}
      _indoorTilesRegistered = false;
    }
    await _ensureIndoorTilesRegistered();
    await _loadFloorGraph(building.id, floor);
    _syncPdrCurrentLayer();
    _syncRouteLayer();
    _syncHighlightLayer();
    _notifyRouteVisibilityIfChanged();
    // 층 chip을 눌렀는데 카메라가 건물 밖을 보거나 실내 오버레이가 페이드인되기
    // 전 zoom(<17.5)에 있으면 사용자는 새 층 도면을 볼 수 없다 — "5F/6F를 골랐는데
    // 아무것도 안 나온다"는 인상을 준다. 층 chip 탭은 명시적으로 "그 층을 보고
    // 싶다"는 신호이므로, 이 경우 건물 중심으로 카메라를 옮겨 오버레이가 확실히
    // 화면에 뜨게 한다. 이미 건물이 잘 보이는 상태에서 층만 바꾼 경우에는 카메라를
    // 건드리지 않는다 — 그 상황에서 강제로 재정렬하면 사용자의 view가 불필요하게
    // 튀어 조작감이 나빠진다.
    await _recenterOnBuildingIfNeeded();
  }

  /// 층 chip 탭·자동 실내 진입 뒤에 실내 오버레이를 보장 노출하기 위한 헬퍼.
  /// - 카메라 zoom이 오버레이 fade-in end 미만이면 그 zoom + 건물 중심으로 이동.
  /// - 카메라가 건물 중심에서 크게 벗어나 있으면 zoom 유지한 채 건물 중심으로 이동.
  /// - 두 조건 모두 아니면 아무 것도 하지 않는다(사용자의 현재 view 존중).
  Future<void> _recenterOnBuildingIfNeeded() async {
    final controller = _mapController;
    final footprint = _buildingFootprint;
    if (controller == null || footprint == null || footprint.length < 3) {
      return;
    }
    final cam = controller.cameraPosition;
    if (cam == null) return;
    final center = _buildingCenter(footprint);
    if (center == null) return;

    final needZoomIn = cam.zoom < _indoorOverlayFadeInEndZoom;
    // 건물 중심에서 카메라까지 대략적인 거리. 위경도 도 단위지만 근사적으로
    // 계산해 "화면 밖" 판정에만 쓴다 — 정확한 거리 계산은 필요 없다.
    final distDeg = math.sqrt(
      math.pow(cam.target.latitude - center.latitude, 2) +
          math.pow(cam.target.longitude - center.longitude, 2),
    );
    // 대략 300m 이상 떨어져 있으면 화면 밖으로 간주(37°에서 0.003° ≈ 300m).
    final farFromBuilding = distDeg > 0.003;

    if (!needZoomIn && !farFromBuilding) return;

    final targetZoom = needZoomIn ? _indoorOverlayFadeInEndZoom : cam.zoom;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(center), targetZoom),
    );
  }

  ll.LatLng? _buildingCenter(List<ll.LatLng> footprint) {
    if (footprint.isEmpty) return null;
    var minLat = double.infinity, maxLat = double.negativeInfinity;
    var minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in footprint) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  void _handlePositionError() {
    if (!mounted) return;
    setState(() => _position = null);
    _syncCurrentLayer();
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    setState(() => _position = position);
    _syncCurrentLayer();
    _maybeAutoEnter(position);
    _updateRoute(position);
  }

  void _maybeAutoEnter(Position position) {
    final entrance = _entrance;
    if (_autoNavigated || entrance == null) return;

    final distance = const ll.Distance().as(
      ll.LengthUnit.Meter,
      ll.LatLng(position.latitude, position.longitude),
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
    _triggerIndoorEntry();
  }

  Future<void> _updateRoute(Position position) async {
    final target = _userDestination ?? _entrance;
    if (target == null) return;

    final route = await directionsRepository.getWalkingRoute(
      origin: ll.LatLng(position.latitude, position.longitude),
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
    _syncRouteLayer();
    _notifyRouteVisibilityIfChanged();
    final isVisible = route != null;
    if (!wasVisible && isVisible) {
      _fitCameraToRoute(route);
    }
  }

  void _fitCameraToRoute(DirectionsRoute route) {
    // 출발점과 도착점이 사실상 같은 좌표면(예: 건물 입구 바로 앞) 경계 상자
    // 폭이 0에 가까워져 줌 계산이 발산한다 — 이 경우엔 화면에 맞출 "경로"랄
    // 게 없으니 자동 줌은 건너뛴다.
    if (route.points.length < 2 || route.distanceMeters < 5) return;
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    var minLng = double.infinity;
    var maxLng = double.negativeInfinity;
    for (final p in route.points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 40,
        top: 110,
        right: 40,
        bottom: 180,
      ),
    );
  }

  /// 위치 보정 버튼: 즉시 새 GPS 위치를 한 번 더 조회해 마커·지도 중심을 갱신한다.
  Future<void> recalibrate() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      _handlePosition(position);
      final controller = _mapController;
      if (controller != null && _styleReady) {
        await controller.animateCamera(
          CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
        );
      }
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
    ll.LatLng destination, {
    required String label,
    ll.LatLng? origin,
  }) async {
    setState(() {
      _userDestination = destination;
      _userDestinationLabel = label;
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면
      // _applyRoute가 "새로 생김"으로 보고 카메라를 다시 맞추게 한다.
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();

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
    _syncDestinationLayer();
    _syncRouteLayer();
    _notifyRouteVisibilityIfChanged();
  }

  /// 실내 진입 오버레이에서 매장까지의 실내 경로를 계산·표시한다. 사용자가
  /// "위치 지정"으로 잡아둔 PDR 앵커를 시작점으로 쓰고, 결과는 야외 화면 위에
  /// 그대로 그려서 다른 탭(실내 화면)으로 이동하지 않고 같은 화면에서 확인
  /// 가능하도록 한다. 시작·도착 층이 같으면 서버의 단층 최단 경로 API를 쓰고,
  /// 다르면 건물 전체 그래프로 층 간 경로를 계산해 현재 보고 있는 층의 세그먼트만
  /// 지도에 얹는다(층 chip으로 다른 층을 훑을 때 [_switchOverlayFloor]가
  /// 세그먼트를 갈아 끼운다).
  Future<void> showIndoorRouteTo(PoiSearchResult destination) async {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null) {
      _showSnack('출발 위치를 먼저 지정해주세요. 하단 "위치 지정" 버튼으로 시작점을 탭하면 됩니다.');
      return;
    }
    final endFloor = destination.floor;
    final endNodeId = destination.nodeId;
    final building = _building;
    if (endNodeId == null || endFloor.isEmpty || building == null) {
      _showSnack('도착지 노드 정보가 없어 경로를 계산할 수 없습니다.');
      return;
    }
    final startFloor = anchor.floorId;
    // 이전 걷기 경로가 남아 있으면 함께 지워, 실내 경로만 화면에 뜨도록 한다.
    setState(() {
      _route = null;
      _userDestination = null;
      _userDestinationLabel = null;
      _indoorRouteDestination = destination;
      // 새 경로를 그리기 전에 초기화 — 아래 compute가 성공하면 다시 채운다.
      _indoorRouteSegment = null;
      _indoorMultiFloorRoute = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    _notifyRouteVisibilityIfChanged();

    if (startFloor == endFloor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: building.id,
        floor: endFloor,
        endNodeId: endNodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: building.id,
        startFloor: startFloor,
        endFloor: endFloor,
        endNodeId: endNodeId,
      );
    }
  }

  /// 같은 층 안에서 계산한 실내 경로를 지도에 얹는다. 활성 층이 목적지 층과
  /// 다르면 먼저 그 층으로 오버레이를 전환해 필요한 그래프를 다시 로드한다.
  Future<void> _computeAndShowSingleFloorIndoorRoute({
    required String buildingId,
    required String floor,
    required String endNodeId,
  }) async {
    if (floor != _activeFloor) {
      await _switchOverlayFloor(floor);
      if (!mounted) return;
    }
    final graph = _floorGraph;
    final anchor = _pdrTrailState.anchor;
    if (graph == null || anchor == null || anchor.floorId != floor) {
      _showSnack('경로 계산에 필요한 층 정보를 불러오지 못했습니다.');
      return;
    }
    final startNodeId = _nearestNodeId(
      graph.nodes,
      anchor.anchorLocalM.eastM,
      anchor.anchorLocalM.northM,
      excludingNodeId: endNodeId,
    );
    if (startNodeId == null) {
      _showSnack('시작 위치 주변에서 통로 노드를 찾지 못했습니다.');
      return;
    }
    final route = await buildingRepository.getShortestRoute(
      buildingId,
      floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    if (route == null) {
      _showSnack('경로를 찾지 못했습니다. 다른 매장을 골라보거나 출발지를 다시 지정해주세요.');
      _clearIndoorRoute();
      return;
    }
    setState(() {
      _indoorRouteSegment = route;
      _indoorMultiFloorRoute = null;
    });
    _syncRouteLayer();
    _notifyRouteVisibilityIfChanged();
    _fitCameraToIndoorRoute(route);
  }

  /// 층이 다른 매장까지의 층 간 경로를 계산해 층별 세그먼트로 나누고, 현재
  /// 화면(_activeFloor)에 해당하는 세그먼트를 지도에 얹는다. 층 chip으로
  /// 다른 층을 훑으면 [_switchOverlayFloor]가 그 층 세그먼트로 갈아탄다.
  /// 시작 층부터 훑도록 활성 층을 자동으로 시작 층으로 전환한다.
  Future<void> _computeAndShowMultiFloorIndoorRoute({
    required String buildingId,
    required String startFloor,
    required String endFloor,
    required String endNodeId,
  }) async {
    final buildingGraph = await buildingRepository.getBuildingGraph(buildingId);
    if (!mounted) return;
    if (buildingGraph == null || buildingGraph.nodes.isEmpty) {
      _showSnack('층 간 경로 계산에 필요한 그래프를 불러오지 못했습니다.');
      _clearIndoorRoute();
      return;
    }
    final startNodeId = _pickStartNodeIdInBuildingGraph(
      graph: buildingGraph,
      startFloorName: startFloor,
      excludingNodeId: endNodeId,
    );
    if (startNodeId == null) {
      _showSnack('시작 층 주변에서 통로 노드를 찾지 못했습니다.');
      _clearIndoorRoute();
      return;
    }
    final route = computeMultiFloorRoute(buildingGraph, startNodeId, endNodeId);
    if (!mounted) return;
    if (route == null || route.isEmpty) {
      _showSnack('층 간 경로를 찾지 못했습니다. 엘리베이터/에스컬레이터 연결을 확인해주세요.');
      _clearIndoorRoute();
      return;
    }
    // 시작 층으로 화면을 전환한 뒤, 그 층 세그먼트를 지도에 얹는다. 사용자가
    // 훑던 층과 다르더라도 시작 층부터 보는 게 "지금 어디서 어느 방향으로
    // 첫 걸음"을 파악하는 데 자연스럽다(실내 화면과 동일 규칙).
    if (_activeFloor != startFloor) {
      await _switchOverlayFloor(startFloor);
      if (!mounted) return;
    }
    final segment = route.segmentForFloor(startFloor);
    setState(() {
      _indoorMultiFloorRoute = route;
      _indoorRouteSegment = segment?.route;
    });
    _syncRouteLayer();
    _notifyRouteVisibilityIfChanged();
    if (segment != null && segment.route.points.length >= 2) {
      _fitCameraToIndoorRoute(segment.route);
    }
  }

  String? _pickStartNodeIdInBuildingGraph({
    required BuildingGraph graph,
    required String startFloorName,
    String? excludingNodeId,
  }) {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != startFloorName) return null;
    // 앵커의 floorId는 사람이 보는 층 라벨이고, 그래프 노드의 floorId는 내부
    // Floor.id다. floorNamesById로 매핑해 그 층의 노드만 후보로 쓴다.
    final floorId = graph.floorNamesById.entries
        .firstWhere(
          (entry) => entry.value == startFloorName,
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (floorId.isEmpty) return null;
    final candidates = graph.nodes
        .where((node) => node.floorId == floorId)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return _nearestNodeId(
      candidates,
      anchor.anchorLocalM.eastM,
      anchor.anchorLocalM.northM,
      excludingNodeId: excludingNodeId,
    );
  }

  String? _nearestNodeId(
    List<GraphNode> nodes,
    double xM,
    double yM, {
    String? excludingNodeId,
  }) {
    GraphNode? nearest;
    double? nearestDistanceSquared;
    for (final node in nodes) {
      if (node.id == excludingNodeId) continue;
      final dx = node.xM - xM;
      final dy = node.yM - yM;
      final distanceSquared = dx * dx + dy * dy;
      if (nearestDistanceSquared == null ||
          distanceSquared < nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearest = node;
      }
    }
    return nearest?.id;
  }

  void _fitCameraToIndoorRoute(IndoorRoute route) {
    if (route.points.length < 2 || route.distanceMeters < 1) return;
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    var minLng = double.infinity;
    var maxLng = double.negativeInfinity;
    for (final p in route.points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 40,
        top: 110,
        right: 40,
        bottom: 180,
      ),
    );
  }

  /// ETA 카드에 쓸 거리. 다층 경로면 전 세그먼트 합, 단일 층이면 그 세그먼트
  /// 거리. 실내 화면과 같은 규칙.
  double _indoorEtaDistanceMeters() {
    final multi = _indoorMultiFloorRoute;
    if (multi != null) return multi.totalDistanceMeters;
    return _indoorRouteSegment?.distanceMeters ?? 0;
  }

  /// ETA 카드 라벨. 다층 경로는 층별 이동수단(엘리베이터/에스컬레이터)까지 요약
  /// 노출해 "이 층에 안 그려진 이유"를 사용자가 이해할 수 있게 한다(실내 화면
  /// 규칙과 동일).
  String _indoorEtaLabel(PoiSearchResult destination) {
    final multi = _indoorMultiFloorRoute;
    if (multi == null) return '${destination.name}까지';
    final buffer = StringBuffer('${destination.name}까지');
    for (var index = 0; index < multi.segments.length; index++) {
      final segment = multi.segments[index];
      buffer.write(index == 0 ? ' · ${segment.floorName}' : ' → ${segment.floorName}');
      final transferMode = segment.transferModeToNext;
      if (transferMode != null) {
        buffer.write(transferMode == 'elevator' ? ' (엘리베이터)' : ' (에스컬레이터)');
      }
    }
    return buffer.toString();
  }

  /// 실내 경로 표시를 초기화한다. ETA 카드 닫기 버튼과 사용자 destination 초기화
  /// 시 호출된다.
  void _clearIndoorRoute() {
    setState(() {
      _indoorRouteSegment = null;
      _indoorMultiFloorRoute = null;
      _indoorRouteDestination = null;
    });
    _syncRouteLayer();
    _notifyRouteVisibilityIfChanged();
  }

  // --- MapLibre 스타일/레이어 설정 ---

  Future<void> _onStyleLoaded() async {
    final controller = _mapController;
    if (controller == null) return;

    // 새 스타일에는 이전 스타일이 갖고 있던 addImage 비트맵이 넘어오지 않는다.
    // 다음 _ensureIndoorTilesRegistered 호출이 아이콘을 다시 등록하도록 리셋.
    _facilityIconImagesRegistered = false;

    // 건물 폴리곤: 옅은 반투명 fill + 외곽선. "이 건물이 탭 가능하다"는 시각
    // 힌트가 되고, 사용자가 탭하면 opacity를 잠깐 올려 인식됐다는 피드백을 준다.
    // 다른 레이어(경로선·위치 점)가 위에 오도록 가장 먼저 추가한다.
    await controller.addSource(
      _buildingSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addFillLayer(
      _buildingSourceId,
      _buildingFillLayerId,
      FillLayerProperties(
        fillColor: AppColors.primary.toHexString(),
        fillOpacity: _buildingFillOpacityDefault,
      ),
    );
    await controller.addLineLayer(
      _buildingSourceId,
      _buildingOutlineLayerId,
      LineLayerProperties(
        lineColor: AppColors.primary.toHexString(),
        lineWidth: 2,
        lineOpacity: 0.7,
      ),
    );

    // 경로선: 두께 있는 파란 실선 + 흰 casing으로 배경 대비를 확보한다.
    await controller.addSource(
      _routeSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _routeSourceId,
      _routeCasingLayerId,
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 8,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await controller.addLineLayer(
      _routeSourceId,
      _routeLineLayerId,
      LineLayerProperties(
        lineColor: AppColors.primary.toHexString(),
        lineWidth: 5,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // 현재 위치: 반투명 원(정확도 반경 시각화용, 픽셀 반경) + 진한 점.
    await controller.addSource(
      _currentSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addCircleLayer(
      _currentSourceId,
      _accuracyLayerId,
      CircleLayerProperties(
        circleRadius: 22,
        circleColor: AppColors.primary.toHexString(),
        circleOpacity: 0.18,
        circleStrokeColor: AppColors.primary.toHexString(),
        circleStrokeWidth: 1,
      ),
    );
    await controller.addCircleLayer(
      _currentSourceId,
      _currentDotLayerId,
      CircleLayerProperties(
        circleRadius: 7,
        circleColor: AppColors.primary.toHexString(),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );

    // 목적지 핀.
    await controller.addSource(
      _destSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addCircleLayer(
      _destSourceId,
      _destLayerId,
      CircleLayerProperties(
        circleRadius: 9,
        circleColor: AppColors.dest.toHexString(),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );

    // 매장 강조 표시 소스·레이어. PDR 마커보다 아래·경로선보다 위에 두고,
    // 실내 오버레이 fill(_indoorStoresFillLayerId)이 나중에 belowLayerId로
    // 이 아래에 삽입되어 강조가 매장 fill 위에 확실히 덮이도록 순서를 잡는다.
    await controller.addSource(
      _highlightSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addFillLayer(
      _highlightSourceId,
      _highlightFillLayerId,
      const FillLayerProperties(fillColor: '#1A73E8', fillOpacity: 0.16),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _highlightSourceId,
      _highlightLineLayerId,
      const LineLayerProperties(
        lineColor: '#1A73E8',
        lineWidth: 1.2,
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    // PDR 위치 마커 — 실내 지도와 같은 파란 도트 + heading 원뿔로 그린다.
    // heading 유무에 따라 다른 아이콘을 자동 선택하고, heading이 있을 때만
    // iconRotate로 지도 위에서 실제 방향을 가리키게 한다. iconRotationAlignment:
    // 'map'을 넣어야 사용자가 지도를 돌려도 원뿔이 실좌표 방향을 유지한다.
    await controller.addImage(
      _pdrLocationImageName,
      await _renderPdrLocationIcon(showHeading: true),
    );
    await controller.addImage(
      _pdrLocationDotImageName,
      await _renderPdrLocationIcon(showHeading: false),
    );
    await controller.addSource(
      _pdrCurrentSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addSymbolLayer(
      _pdrCurrentSourceId,
      _pdrCurrentLayerId,
      SymbolLayerProperties(
        iconImage: [
          'case',
          ['has', 'heading'],
          _pdrLocationImageName,
          _pdrLocationDotImageName,
        ],
        iconSize: [
          'interpolate',
          ['linear'],
          ['zoom'],
          16,
          0.26,
          20,
          0.56,
        ],
        iconRotate: [
          'coalesce',
          ['get', 'heading'],
          0,
        ],
        iconRotationAlignment: 'map',
        iconPitchAlignment: 'viewport',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );

    if (!mounted) return;
    setState(() => _styleReady = true);
    _syncBuildingLayer();
    _syncCurrentLayer();
    _syncDestinationLayer();
    _syncRouteLayer();
    _syncPdrCurrentLayer();
    _syncHighlightLayer();
    _ensureIndoorTilesRegistered();
    if (_pendingCenterOnPosition && _position != null) {
      _pendingCenterOnPosition = false;
      await controller.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_position!.latitude, _position!.longitude),
        ),
      );
    }
  }

  Future<void> _syncBuildingLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) {
      await controller.setGeoJsonSource(_buildingSourceId, _emptyCollection());
      return;
    }
    final ring = [
      for (final p in footprint) [p.longitude, p.latitude],
    ];
    // GeoJSON Polygon linear ring은 첫 점과 마지막 점이 같아야 한다. 백엔드가
    // 이미 닫아 보내주면 중복 추가하지 않는다.
    if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
      ring.add(ring.first);
    }
    await controller.setGeoJsonSource(
      _buildingSourceId,
      _collection([
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [ring],
          },
        },
      ]),
    );
  }

  /// 지도에서 탭한 위경도가 건물 footprint 내부인지 판정한다(ray-casting).
  /// 백엔드가 자기 참조 없이 단일 외곽선만 내려주므로 hole/멀티 폴리곤은 안 다룬다.
  bool _isInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) return false;
    var inside = false;
    final n = footprint.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = footprint[i].longitude;
      final yi = footprint[i].latitude;
      final xj = footprint[j].longitude;
      final yj = footprint[j].latitude;
      final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  Future<void> _handleMapClick(Point<double> pointPx, LatLng coords) async {
    final point = ll.LatLng(coords.latitude, coords.longitude);

    // 위치 지정 대기 중이라면 이 탭은 PDR 앵커 배치로 소비된다 — 지도 탭이
    // 건물 진입 처리로 새어들어가면 사용자가 위치를 지정하는 순간 오버레이가
    // 다시 리셋되는 것처럼 보인다.
    if (_placingPdrAnchor) {
      await _onMapPressedForPdr(point);
      return;
    }

    // 실내 진입 오버레이 위에서 매장 폴리곤을 탭하면 실내 화면과 동일한 매장
    // 정보 시트를 띄운다. 픽셀 좌표(pointPx)로 벡터 타일의 stores fill을
    // hit-test 하고 feature id로 FloorPlan에서 실제 매장을 되찾는다. 매장이
    // 아닌 곳(복도·footprint)을 탭하면 features가 비어 있어 아래 건물 진입
    // 처리로 자연스럽게 흘러간다.
    if (_indoorEntered && await _tryHandleStoreTap(pointPx)) return;

    // 폴리곤 히트 검사만 하고, 나머지 탭은 흡수하지 않아 지도 pan/zoom 제스처를
    // 방해하지 않는다(단일 탭이 여기 오면 그건 pan이 아닌 명시적 탭).
    if (!_isInsideBuilding(point)) return;

    // 폴리곤을 잠깐 진하게 반짝여 "인식됐다"는 시각 피드백을 준 뒤, 야외 지도
    // 위에 실내 UI 오버레이(층 chip, 위치 지정 버튼 등)를 켠다. 화면 모드는
    // 그대로 야외로 유지된다.
    final controller = _mapController;
    if (controller == null) return;
    await controller.setLayerProperties(
      _buildingFillLayerId,
      const FillLayerProperties(fillOpacity: _buildingFillOpacityPressed),
    );
    await Future<void>.delayed(const Duration(milliseconds: _buildingPressedHoldMs));
    if (!mounted) return;
    await controller.setLayerProperties(
      _buildingFillLayerId,
      const FillLayerProperties(fillOpacity: _buildingFillOpacityDefault),
    );
    _triggerIndoorEntry();
  }

  /// 실내 진입 트리거 — 건물 탭·줌 임계값 초과·GPS 근접 감지 중 하나로 호출.
  /// 화면 모드는 바꾸지 않고 야외 지도 위에 얹는 실내 UI 오버레이만 켠다.
  /// 사용자가 축소해 임계값 아래로 내려가면 [_handleCameraIdle]이 오버레이를
  /// 다시 끄고 트리거를 재무장한다.
  void _triggerIndoorEntry() {
    if (!_autoIndoorEntryArmed) return;
    _autoIndoorEntryArmed = false;
    if (_indoorEntered) return;
    setState(() => _indoorEntered = true);
    widget.onIndoorEnteredChanged?.call(true);
  }

  void _handleCameraIdle() {
    final controller = _mapController;
    if (controller == null) return;
    final zoom = controller.cameraPosition?.zoom;
    if (zoom == null) return;
    if (zoom >= _indoorEntryZoomThreshold) {
      _triggerIndoorEntry();
    } else {
      // 사용자가 다시 축소했으므로 오버레이를 접고 다음 확대에서 재발화할 수
      // 있게 무장한다. 배치 대기 중이면 종료해 하단 바 표시도 함께 초기화한다.
      _autoIndoorEntryArmed = true;
      if (_indoorEntered) {
        if (_placingPdrAnchor) _setPlacingAnchor(false);
        setState(() => _indoorEntered = false);
        widget.onIndoorEnteredChanged?.call(false);
      }
    }
  }

  // 실내 MVT 소스·레이어는 스타일 로드와 활성 건물 로드 둘 다 되면 한 번만 등록.
  bool _indoorTilesRegistered = false;
  Future<void> _ensureIndoorTilesRegistered() async {
    final controller = _mapController;
    final building = _building;
    if (controller == null || !_styleReady || building == null) {
      debugPrint(
        '[outdoor overlay] skip register: controller=${controller != null} '
        'styleReady=$_styleReady building=${building != null}',
      );
      return;
    }
    if (_indoorTilesRegistered) return;
    final floor = _activeFloor ?? building.initialFloor;
    if (floor == null) {
      debugPrint('[outdoor overlay] skip register: no active floor');
      return;
    }

    final tileUrl =
        '$apiBaseUrl/buildings/${building.id}/floors/$floor/tiles/{z}/{x}/{y}.mvt';
    debugPrint(
      '[outdoor overlay] registering MVT source url=$tileUrl '
      'apiBaseUrl=$apiBaseUrl',
    );
    // 소스/레이어 등록은 native 쪽에서 조용히 예외를 던지고 pending 상태로 남을
    // 때가 있어(스타일 미준비·잘못된 expression 등) 부분 실패 시 flag가 false로
    // 남아 다음 호출이 addSource를 다시 시도하며 "source already exists"로
    // 폭발하는 문제가 있었다. try/catch로 격리해 에러를 로그로 남기고, 이미
    // 소스가 추가돼 있으면 다음 호출 전 정리부터 시도한다.
    try {
      await controller.addSource(
        _indoorTilesSourceId,
        VectorSourceProperties(
          tiles: [tileUrl],
          // minzoom 미만에서는 타일 요청·캐시 자체를 막아, 저-zoom 부모 타일이
          // over-scale된 채 잠깐 보이면서 도면이 회전한 것처럼 보이는 문제를
          // 예방한다. 근거는 _indoorTilesMinZoom 정의 위 주석 참고.
          minzoom: _indoorTilesMinZoom,
          // maxzoom 이상에서는 MapLibre가 maxzoom 타일을 over-scale해 그린다.
          // 백엔드의 mapbox_vector_tile.encode는 요청 zoom이 커질수록 tile 경계
          // 사각형도 미세해지는데(z=21이면 20m 남짓), 이 좁은 사각형을 4096 유닛에
          // quantize할 때 부동소수점 오차가 상대적으로 커져 사용자가 극한 확대를
          // 하면 도면이 잠깐 뒤틀린 것처럼 보이는 원인이 됐다. z=18을 상한으로
          // 잡으면 tile 경계가 ~150m로 충분히 넓어 quantize precision이 0.04m/유닛
          // 이라 어떤 확대 배율에서도 sub-pixel로 안정된다.
          maxzoom: _indoorTilesMaxZoom,
        ),
      );
      // POI/시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록한다. 층을
      // 바꿔도 이미지는 그대로 재사용되므로 반복 렌더를 피한다.
      await _ensureFacilityIconImagesRegistered(controller);
      // 실내 도면은 확대에 따라 자연스럽게 나타나야 한다(Google Maps의 건물 내부
      // 표시와 같은 패턴): 줌 16.5 미만은 완전히 안 보이고 17.5부터 완전히 보이며
      // 사이는 부드럽게 페이드인. MapLibre의 zoom-interpolate 표현식으로 처리해
      // 카메라 이동 중 실시간으로 부드럽게 반영된다(수동 setLayerProperties 호출
      // 없이). 아래는 [interpolate, linear, [zoom], stop0_zoom, stop0_val, ...]
      // 형태의 style expression.
      const fadeExpr = [
        'interpolate',
        ['linear'],
        ['zoom'],
        _indoorOverlayFadeInStartZoom,
        0,
        _indoorOverlayFadeInEndZoom,
        1,
      ];
      // POI/시설 아이콘은 오버레이가 페이드인되는 구간에서는 살짝 작게, 사용자가
      // 실내로 더 확대해 들어갈수록 실내 화면과 비슷한 크기로 커지도록 zoom
      // 기반 iconSize로 준다. 아이콘 캔버스 96px 기준으로 실내 화면은 0.28
      // 고정이지만, 야외 오버레이는 화면 시야가 훨씬 넓어 그대로 두면 라벨을
      // 가릴 만큼 크게 보인다.
      const iconSizeExpr = [
        'interpolate',
        ['linear'],
        ['zoom'],
        _indoorOverlayFadeInEndZoom,
        0.22,
        20,
        0.42,
      ];
      // 실내 오버레이 레이어를 route casing 바로 아래에 삽입한다. 안 그러면
      // _onStyleLoaded가 먼저 그린 경로선/GPS 마커/PDR dot이 나중에 얹힌 stores
      // fill(줌 17.5+에서 fillOpacity=1) 밑으로 깔려 화면에서 완전히 사라진다.
      // stores 레이어는 매장 탭 검출용으로 상호작용을 유지한다(중복 발화는
      // MapLibreMap.featureTapsTriggersMapClick=true로 onMapClick에 흡수됨).
      // footprint/label은 탭 반응이 없어도 되므로 명시적으로 꺼서 시각 부작용을
      // (footprint 폴리곤 반짝임 등) 없앤다.
      await controller.addFillLayer(
        _indoorTilesSourceId,
        _indoorFootprintLayerId,
        FillLayerProperties(
          fillColor: '#FFFFFF',
          fillOutlineColor: '#00000088',
          fillOpacity: fadeExpr,
        ),
        sourceLayer: 'footprint',
        belowLayerId: _routeCasingLayerId,
        enableInteraction: false,
      );
      await controller.addFillLayer(
        _indoorTilesSourceId,
        _indoorStoresFillLayerId,
        FillLayerProperties(
          fillColor: '#F3F1EF',
          fillOutlineColor: '#D8D4D1',
          fillOpacity: fadeExpr,
        ),
        sourceLayer: 'stores',
        belowLayerId: _routeCasingLayerId,
      );
      // 수직이동 구조물(에스컬레이터/엘리베이터) 전용 오버레이. 일반 매장 fill
      // 바로 위, 라벨/POI 아이콘보다 아래에 깔아서 초록 아이콘과 한 덩어리로
      // 읽히게 한다. 필터가 어긋나면(백엔드 name 변경 등) 이 레이어만 비고
      // 아래 일반 매장 스타일로 자연스럽게 폴백된다. 필터는 실내 화면과 같은
      // 형식(any + 개별 ==)을 유지한다.
      await controller.addFillLayer(
        _indoorTilesSourceId,
        _indoorVerticalTransportFillLayerId,
        FillLayerProperties(
          fillColor: '#DCEBD4',
          fillOutlineColor: '#6FA167',
          fillOpacity: fadeExpr,
        ),
        sourceLayer: 'stores',
        belowLayerId: _routeCasingLayerId,
        filter: [
          'any',
          for (final name in kVerticalTransportStoreNames)
            [
              '==',
              ['get', 'name'],
              name,
            ],
        ],
        enableInteraction: false,
      );
      await controller.addSymbolLayer(
        _indoorTilesSourceId,
        _indoorStoresLabelLayerId,
        SymbolLayerProperties(
          textField: ['get', 'name'],
          textFont: const ['Noto Sans KR Regular'],
          textSize: 11,
          textColor: '#333333',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1,
          textMaxWidth: 6,
          textOpacity: fadeExpr,
        ),
        sourceLayer: 'stores',
        belowLayerId: _routeCasingLayerId,
        enableInteraction: false,
      );
      // POI(엘리베이터·에스컬레이터·화장실 등) 심볼 레이어. `pois` 소스 레이어에
      // 있는 feature의 type 속성으로 아이콘을 골라 얹는다. iconOpacity를 fadeExpr
      // 로 묶어 오버레이와 같은 줌 구간에서 함께 페이드인된다.
      await controller.addSymbolLayer(
        _indoorTilesSourceId,
        _indoorPoiIconLayerId,
        SymbolLayerProperties(
          iconImage: [
            'match',
            ['get', 'type'],
            for (final entry in kPoiIconByType.entries) ...[
              entry.key,
              poiIconImageName(entry.value),
            ],
            poiIconImageName(kDefaultPoiIcon),
          ],
          iconSize: iconSizeExpr,
          iconOpacity: fadeExpr,
          iconAllowOverlap: true,
        ),
        sourceLayer: 'pois',
        belowLayerId: _routeCasingLayerId,
        enableInteraction: false,
      );
      // 편의시설 아이콘: `stores` 소스에 있는 화장실·정수기 같은 시설물은 POI
      // 레이어를 타지 않으므로 아이콘이 안 붙는다. 매장 이름을 기준으로 심볼을
      // 하나 더 얹어 라벨 바로 위에 아이콘이 뜨게 한다. iconOffset을 y=-18로
      // 줘 라벨(centroid)과 위/아래로 겹치지 않는다.
      await controller.addSymbolLayer(
        _indoorTilesSourceId,
        _indoorStoreFacilityIconLayerId,
        SymbolLayerProperties(
          iconImage: [
            'match',
            ['get', 'name'],
            for (final entry in kStoreFacilityStyleByName.entries) ...[
              entry.key,
              facilityIconImageName(entry.key),
            ],
            poiIconImageName(kDefaultPoiIcon),
          ],
          iconSize: iconSizeExpr,
          iconOpacity: fadeExpr,
          iconAllowOverlap: true,
          iconOffset: [0, -18],
        ),
        sourceLayer: 'stores',
        belowLayerId: _routeCasingLayerId,
        filter: [
          'any',
          for (final name in kStoreFacilityStyleByName.keys)
            [
              '==',
              ['get', 'name'],
              name,
            ],
        ],
        enableInteraction: false,
      );
      _indoorTilesRegistered = true;
      debugPrint('[outdoor overlay] MVT source+layers registered ($floor)');
    } catch (error, stack) {
      debugPrint('[outdoor overlay] MVT register FAILED: $error\n$stack');
      // 부분 추가된 소스/레이어를 정리해 다음 호출이 깨끗한 상태에서 다시
      // 시도할 수 있게 한다. 각 remove가 실패해도(안 붙어있어서) 조용히 넘긴다.
      for (final id in _indoorOverlayLayerIds) {
        try {
          await controller.removeLayer(id);
        } catch (_) {}
      }
      try {
        await controller.removeSource(_indoorTilesSourceId);
      } catch (_) {}
      _indoorTilesRegistered = false;
    }
  }

  /// 실내 오버레이의 소스/레이어 제거 순서. 레이어는 반드시 소스보다 먼저
  /// 빠져야 native가 dangling reference로 실패하지 않는다. 위→아래(=최상단
  /// 심볼부터 밑바닥 footprint까지) 순으로 나열해 두면 remove 순서를 그대로
  /// 재사용할 수 있다.
  static const _indoorOverlayLayerIds = <String>[
    _indoorStoreFacilityIconLayerId,
    _indoorPoiIconLayerId,
    _indoorStoresLabelLayerId,
    _indoorVerticalTransportFillLayerId,
    _indoorStoresFillLayerId,
    _indoorFootprintLayerId,
  ];

  /// POI/편의시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록한다.
  /// [_ensureIndoorTilesRegistered]가 층 전환마다 소스/레이어를 다시 붙일 때
  /// 매번 렌더를 반복하지 않도록 [_facilityIconImagesRegistered]로 게이팅한다.
  /// 스타일이 바뀌면(개발 hot restart 등) MapLibre가 이미지를 잃을 수 있어
  /// 그때는 [_onStyleLoaded]에서 다시 false로 리셋된다.
  Future<void> _ensureFacilityIconImagesRegistered(
    MapLibreMapController controller,
  ) async {
    if (_facilityIconImagesRegistered) return;
    for (final icon in {...kPoiIconByType.values, kDefaultPoiIcon}) {
      await controller.addImage(
        poiIconImageName(icon),
        await renderPoiIconPng(icon),
      );
    }
    for (final entry in kStoreFacilityStyleByName.entries) {
      await controller.addImage(
        facilityIconImageName(entry.key),
        await renderFacilityIconPng(entry.value),
      );
    }
    _facilityIconImagesRegistered = true;
  }

  Future<void> _syncCurrentLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) {
      _pendingCenterOnPosition = _position != null;
      return;
    }
    final pos = _position;
    if (pos == null) {
      await controller.setGeoJsonSource(_currentSourceId, _emptyCollection());
      return;
    }
    await controller.setGeoJsonSource(
      _currentSourceId,
      _collection([
        _pointFeature(ll.LatLng(pos.latitude, pos.longitude)),
      ]),
    );
  }

  Future<void> _syncDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final target = _userDestination ?? _entrance;
    if (target == null) {
      await controller.setGeoJsonSource(_destSourceId, _emptyCollection());
      return;
    }
    await controller.setGeoJsonSource(
      _destSourceId,
      _collection([_pointFeature(target)]),
    );
  }

  Future<void> _syncRouteLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    // 실내 경로가 활성이면 그걸 우선 그린다(GPS 걷기 경로와 동시에 표시하지
    // 않는다 — 사용자는 지금 실내에 있고 실내 경로가 유일한 관심사).
    final indoor = _indoorRouteSegment;
    if (indoor != null && indoor.points.length >= 2) {
      await controller.setGeoJsonSource(
        _routeSourceId,
        _collection([_lineFeature(indoor.points)]),
      );
      return;
    }
    final route = _route;
    if (route == null || route.points.length < 2) {
      await controller.setGeoJsonSource(_routeSourceId, _emptyCollection());
      return;
    }
    await controller.setGeoJsonSource(
      _routeSourceId,
      _collection([_lineFeature(route.points)]),
    );
  }

  /// 실내/야외 경로 중 하나라도 활성이면 true. ETA 카드 노출과 하단 바 리프트
  /// 판정에 쓴다.
  bool get _hasAnyRouteVisible =>
      _route != null ||
      _indoorRouteSegment != null ||
      _indoorMultiFloorRoute != null;

  /// 상위(MapShellScreen)의 하단 바 리프트/ETA 카드 표시가 어긋나지 않도록
  /// 실내 경로 변경 후 이 헬퍼로 방문 상태 변화만 통보한다. 걷기 경로 쪽
  /// [_applyRoute]와 같은 규칙(변화가 있을 때만 콜백)을 쓴다.
  bool _lastRouteVisibleNotified = false;
  void _notifyRouteVisibilityIfChanged() {
    final visible = _hasAnyRouteVisible;
    if (visible == _lastRouteVisibleNotified) return;
    _lastRouteVisibleNotified = visible;
    widget.onRouteVisibleChanged?.call(visible);
  }

  /// 실내 오버레이 stores 폴리곤을 탭했는지 확인하고, 맞으면 상위에 매장 정보
  /// 시트 노출을 요청한다. 매장이 아니거나 오버레이가 준비되지 않아 처리하지
  /// 않았으면 false를 돌려줘 호출자가 다음 흐름(건물 진입 flash)으로 넘어가게
  /// 한다. 매장 탭 실패는 조용히 무시한다(예: 타일 파싱 지연 중 짧은 순간).
  Future<bool> _tryHandleStoreTap(Point<double> pointPx) async {
    final controller = _mapController;
    final onStoreTap = widget.onStoreTap;
    final plan = _floorPlan;
    final floor = _activeFloor;
    if (controller == null ||
        onStoreTap == null ||
        plan == null ||
        floor == null ||
        !_indoorTilesRegistered) {
      return false;
    }
    List<dynamic> features;
    try {
      features = await controller.queryRenderedFeatures(
        pointPx,
        [_indoorStoresFillLayerId],
        null,
      );
    } catch (_) {
      return false;
    }
    if (features.isEmpty) return false;
    final properties = (features.first as Map)['properties'] as Map?;
    final id = properties?['id'] as String?;
    if (id == null) return false;
    final store = plan.stores.where((s) => s.id == id).firstOrNull;
    if (store == null) return false;
    setState(() => _highlightedStoreId = store.id);
    _syncHighlightLayer();
    onStoreTap(
      PoiSearchResult(
        name: store.name,
        floor: floor,
        point: store.centroid,
        nodeId: store.entranceNodeId,
        category: store.category,
        subcategory: store.subcategory,
      ),
    );
    return true;
  }

  Future<void> _syncPdrCurrentLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final location = _pdrCurrentWgs84();
    if (location == null) {
      await controller.setGeoJsonSource(_pdrCurrentSourceId, _emptyCollection());
      return;
    }
    final heading = _pdrCurrentHeadingDeg;
    await controller.setGeoJsonSource(
      _pdrCurrentSourceId,
      _collection([
        {
          'type': 'Feature',
          'properties': <String, dynamic>{
            'heading': ?heading,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [location.longitude, location.latitude],
          },
        },
      ]),
    );
  }

  /// 사용자의 PDR 위치를 WGS84로 돌려준다. 확정된 실시간 스냅샷이 있으면
  /// 그것을, 아직 걷지 않아 스냅샷이 없으면 앵커 위치를 폴백으로 쓴다. 그
  /// 어느 것도 없거나 활성 층과 다른 층에 앵커가 있으면 null(→ 마커 숨김).
  ll.LatLng? _pdrCurrentWgs84() {
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return null;
    final transform = fitFloorGeoTransform(graph.nodes);
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != _activeFloor) return null;

    if (snapshot != null) {
      final pdrToFloor = FloorCoordinateTransform(anchor);
      final points = snapshot.path.map(pdrToFloor.toFloor).toList();
      final matched = FloorMapMatcher(graph).matchRoutedPath(points);
      final last = matched.isNotEmpty ? matched.last : null;
      if (last != null) {
        final wgs84 = transform.apply(last.eastM, last.northM);
        return ll.LatLng(wgs84.$1, wgs84.$2);
      }
    }
    final wgs84 = transform.apply(
      anchor.anchorLocalM.eastM,
      anchor.anchorLocalM.northM,
    );
    return ll.LatLng(wgs84.$1, wgs84.$2);
  }

  /// 사용자가 바라보는 방향(true north 기준, 시계방향 도). PDR 세션이 heading을
  /// 아직 못 얻은 상태(예: 자북 못 잡음 + 수동 방향 보정 아직 안 함, 첫 걸음
  /// 전)에는 null을 돌려주고, 이 경우 마커도 heading 원뿔 없이 도트만 뜬다.
  /// 계산식은 실내와 동일하다(pdr snapshot의 걷기 heading + anchor의 회전 오프셋).
  double? get _pdrCurrentHeadingDeg {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    if (snapshot == null || anchor == null || !snapshot.hasHeading) return null;
    return normalizePdrBearing(snapshot.walkingHeadingDeg + anchor.rotationDeg);
  }

  /// 강조 매장 폴리곤을 highlight 소스에 채운다. null 또는 미매치면 비운다.
  Future<void> _syncHighlightLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final storeId = _highlightedStoreId;
    final plan = _floorPlan;
    final store = (storeId == null || plan == null)
        ? null
        : plan.stores.where((s) => s.id == storeId).firstOrNull;
    if (store == null || store.polygon.length < 3) {
      await controller.setGeoJsonSource(_highlightSourceId, _emptyCollection());
      return;
    }
    final ring = [
      for (final p in store.polygon) [p.longitude, p.latitude],
    ];
    if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
      ring.add(ring.first);
    }
    await controller.setGeoJsonSource(
      _highlightSourceId,
      _collection([
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [ring],
          },
        },
      ]),
    );
  }

  /// 상위(MapShellScreen)가 매장 정보 시트가 닫힐 때 호출해 강조를 지운다.
  void clearHighlight() {
    if (_highlightedStoreId == null) return;
    setState(() => _highlightedStoreId = null);
    _syncHighlightLayer();
  }

  /// 앵커 배치 대기 상태 전환. 상위(MapShellScreen)에 알려 하단 바 "위치 지정"
  /// 버튼의 활성 톤을 함께 갱신한다.
  void _setPlacingAnchor(bool value) {
    if (_placingPdrAnchor == value) return;
    setState(() => _placingPdrAnchor = value);
    widget.onPlacingLocationChanged?.call(value);
  }

  /// 하단 바 "위치 지정" 버튼 진입점. PDR 세션이 꺼져 있으면 활성 층으로 시작
  /// 하고, 이미 켜져 있으면(다른 층에서 이어서 진입 등) 앵커만 다시 잡도록
  /// 대기 상태로 넘긴다. 실제 탭 처리는 [_onMapPressedForPdr]가 맡는다.
  Future<void> startLocationPlacement() async {
    if (!_indoorEntered) {
      // 실내 진입 오버레이가 아직 열리지 않은 상태에서 호출되면 (예: 사용자가
      // 하단 세그먼트에서 실내로 갔다가 다시 야외로 온 뒤 눌렀을 때) 오버레이를
      // 먼저 켜서 다음 동작을 알린다.
      setState(() => _indoorEntered = true);
      _autoIndoorEntryArmed = false;
      widget.onIndoorEnteredChanged?.call(true);
    }
    final floor = _activeFloor;
    final graph = _floorGraph;
    if (floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      _showSnack('이 층은 위치 지정에 필요한 지도 정보가 아직 없습니다.');
      return;
    }
    if (indoorNavigationDriver.currentRuntimeStatus.state ==
        PdrRuntimeState.idle) {
      setState(() => _pdrTrailState.beginNewSession());
      await indoorNavigationDriver.startGuidance(floorId: floor);
      if (!mounted) return;
    }
    _setPlacingAnchor(true);
    _showSnack('지도에서 현재 서 있는 위치를 탭해 지정해주세요.');
  }

  Future<void> _onMapPressedForPdr(ll.LatLng point) async {
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) {
      _showSnack('이 층의 지도 정보가 아직 없습니다.');
      _setPlacingAnchor(false);
      return;
    }
    final local = fitFloorGeoTransform(
      graph.nodes,
    ).invert(point.latitude, point.longitude);
    if (local == null) {
      _showSnack('이 층 좌표를 계산하지 못했습니다.');
      return;
    }
    final tapped = PdrLocalPoint(local.$1, local.$2);
    final snapped = FloorMapMatcher(graph).snapToWalkableNetwork(tapped);
    if (snapped == null) {
      _showSnack('이 층의 통로 위치를 찾지 못했습니다. 다시 시도해주세요.');
      return;
    }
    if (snapped.distanceToGraphM > _maxPdrAnchorSnapDistanceM) {
      // 매번 같은 문구만 나오면 어디가 문제인지 알 수 없다. 실측 거리를 함께
      // 노출해서 "탭이 건물에서 얼마나 떨어진지" 사용자·개발자가 즉시 확인할
      // 수 있게 한다.
      final gapM = snapped.distanceToGraphM.toStringAsFixed(1);
      _showSnack('가장 가까운 통로에서 약 ${gapM}m 떨어져 있습니다. 건물 안쪽 복도를 탭해주세요.');
      return;
    }
    await _confirmPdrAnchor(snapped.point);
  }

  Future<void> _confirmPdrAnchor(PdrLocalPoint floorPoint) async {
    final graph = _floorGraph;
    final axes = graph == null
        ? const PdrToFloorAxes.identity()
        : fitPdrToFloorAxes(graph.nodes);
    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: floorPoint,
      axes: axes,
    );
    if (!mounted) return;
    if (indoorNavigationDriver.currentCalibration.phase ==
        CalibrationPhase.awaitingHeading) {
      final screenDirection = await _askScreenDirection();
      if (screenDirection == null || !mounted) return;
      final cameraBearing = _mapController?.cameraPosition?.bearing ?? 0;
      final floorDirection = floorDirectionForScreenDirection(
        cameraBearingDeg: cameraBearing,
        screenClockwiseOffsetDeg: screenDirection,
        axes: axes,
      );
      await indoorNavigationDriver.confirmAnchorByFloorDirection(
        floorDirection: floorDirection,
      );
    }
    if (!mounted) return;
    _setPlacingAnchor(false);
    _syncPdrCurrentLayer();
    _showSnack('시작점을 통로에 맞췄습니다.');
  }

  Future<double?> _askScreenDirection() {
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('진행 방향 보정'),
        content: const Text(
          '이 기기는 절대 북쪽 기준 heading을 얻지 못했습니다. 현재 휴대폰이 향한 지도 방향을 선택해주세요.',
        ),
        actions: [
          for (final entry in const [
            (label: '위쪽', value: 0.0),
            (label: '오른쪽', value: 90.0),
            (label: '아래쪽', value: 180.0),
            (label: '왼쪽', value: 270.0),
          ])
            TextButton(
              onPressed: () => Navigator.of(context).pop(entry.value),
              child: Text(entry.label),
            ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => _buildBody();

  Widget _buildBody() {
    final position = _position;
    final accuracy = position?.accuracy ?? 0;
    final lowAccuracy = position == null || accuracy > _lowAccuracyThresholdMeters;
    final route = _route;
    final userDestination = _userDestination;
    final indoorRouteDestination = _indoorRouteDestination;
    final indoorRouteVisible = _hasAnyRouteVisible;
    final initialCenter = position == null
        ? _fallbackLocation
        : ll.LatLng(position.latitude, position.longitude);

    return Stack(
      children: [
        if (_isMapSupportedOnThisPlatform)
          MapLibreMap(
            styleString: _baseMapStyle(),
            initialCameraPosition: CameraPosition(
              target: _toGl(initialCenter),
              zoom: 17,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _handleMapClick,
            onCameraIdle: _handleCameraIdle,
            // _handleCameraIdle이 실내 진입/이탈을 판정하려면 현재 줌을 읽어야
            // 하는데, 이 값은 trackCameraPosition이 true일 때만 사용자의
            // pan/zoom을 따라 갱신된다(기본값 false면 초기 zoom 17에 고정 또는
            // 실기기에서 null). 그 상태에선 사용자가 축소해도 exit 조건이
            // 판정되지 않아 층 선택기·위치 지정 버튼이 계속 남는다. 실내 지도의
            // FloorPlanView도 같은 이유로 이 값을 명시적으로 켜고 있다.
            trackCameraPosition: true,
            // 웹의 maplibre_gl은 기본값(false)이면 상호작용 가능한 벡터 레이어
            // (실내 오버레이의 stores/footprint fill 등)을 탭한 순간 별도 feature
            // -tap만 발화하고 onMapClick은 삼켜버린다. 그러면 사용자가 실내
            // 진입 오버레이 위에서 "위치 지정" → 건물 안 매장 폴리곤을 탭했을
            // 때 _handleMapClick이 아예 호출되지 않아 PDR 앵커 배치가 조용히
            // 실패한다. 이 값을 켜서 feature-tap이 있어도 onMapClick도 함께
            // 오게 만든다(실내 지도의 FloorPlanView가 같은 이유로 이미 켜둠).
            featureTapsTriggersMapClick: true,
            compassEnabled: false,
            myLocationEnabled: false,
            logoEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            scrollGesturesEnabled: _interactive,
            zoomGesturesEnabled: _interactive,
            rotateGesturesEnabled: _interactive,
            tiltGesturesEnabled: _interactive,
            dragEnabled: _interactive,
          )
        else
          const ColoredBox(color: AppColors.surface),

        if (lowAccuracy)
          const Positioned(
            top: 76,
            left: 12,
            child: StatusBadge(
              label: 'GPS 신호 약함',
              color: AppColors.warning,
              icon: Icons.warning_amber_rounded,
            ),
          ),

        // 실내 진입 오버레이 — 야외 지도 위 좌측 하단에 세로 층 선택기를 얹어
        // 실내 화면과 동일한 위치·디자인으로 층을 훑을 수 있게 한다. 하단 바가
        // 경로 ETA로 위로 리프트되면 pill도 같이 올라가 시각 정렬을 유지한다.
        if (_indoorEntered &&
            _building != null &&
            _activeFloor != null &&
            _building!.floors.isNotEmpty)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom: _floorSelectorBottomOffset +
                (indoorRouteVisible ? _bottomBarLiftPx : 0),
            child: SafeArea(
              top: false,
              child: FloorSelector(
                floors: _building!.floors,
                selectedFloor: _activeFloor!,
                onSelectFloor: _switchOverlayFloor,
              ),
            ),
          ),

        if (_indoorEntered && _placingPdrAnchor)
          const Positioned(
            top: 128,
            left: 12,
            right: 12,
            child: _PlacingAnchorHint(),
          ),

        if (indoorRouteDestination != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: EtaCard(
                  distanceMeters: _indoorEtaDistanceMeters(),
                  minutes:
                      (_indoorEtaDistanceMeters() /
                              _indoorWalkingSpeedMetersPerSecond /
                              60)
                          .ceil()
                          .clamp(1, 999),
                  label: _indoorEtaLabel(indoorRouteDestination),
                  onClose: _clearIndoorRoute,
                ),
              ),
            ),
          )
        else if (route != null)
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

// AppColors 는 Color 인스턴스라 CircleLayerProperties가 요구하는 문자열 색상으로
// 자주 변환해 쓰기 편하도록 확장으로 감싼다.
extension _ColorHex on Color {
  String toHexString() {
    final rgb =
        (r * 255).round() << 16 | (g * 255).round() << 8 | (b * 255).round();
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// PDR 앵커 배치 대기 중임을 상단에 짧게 알려주는 배지. 하단 바 버튼의 활성
/// 톤과 함께 사용자에게 "지금 지도 탭이 다음 액션을 소비한다"는 상태를 전한다.
class _PlacingAnchorHint extends StatelessWidget {
  const _PlacingAnchorHint();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.indoor,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '지도를 탭해 현재 서 있는 위치를 지정해주세요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

