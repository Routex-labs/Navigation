import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show Point, pi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../domain/geo_transform.dart';
import '../../features/debug_mode/debug_mode.dart';
import '../../features/indoor_navigation/application/floor_map_matcher.dart';
import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';
import '../../features/indoor_navigation/debug/pdr_debug_device_info.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_share.dart';
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
import 'floor_outline.dart';
import 'indoor_entry_proximity.dart';
import 'indoor_entry_zoom.dart';
import 'indoor_overlay_layers.dart';

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
// 현재 층의 외곽선. 건물 폴리곤 소스와 **분리한** 전용 소스를 쓴다 — 지하층에서는
// 건물 외곽선이 아니라 그 층 도면의 외곽선을 따라가야 해서 지오메트리가 서로
// 다르고(규칙은 floor_outline.dart), 실내 도면 위에 얹혀야 보이므로 레이어 순서도
// 건물 fill과 다르다.
const _floorOutlineSourceId = 'outdoor-floor-outline';
const _floorOutlineLayerId = 'outdoor-floor-outline-line';
// 실내 오버레이 소스·레이어 ID **베이스 이름**. 층을 바꿀 때마다 세대(generation)
// 카운터를 이 뒤에 붙여 매번 다른 실제 ID를 만든다 — 같은 ID로 removeSource →
// addSource를 반복하면 maplibre_gl native(Android/iOS)가 이전 소스 정리를
// 스케줄만 한 채 리턴해 곧이은 addSource가 "source already exists"로 조용히
// 실패하는 사례가 있었다(특정 층으로 전환 시 아무것도 안 그려지는 증상). 세대
// 카운터로 실제 ID를 유일하게 만들면 native cleanup 경쟁이 사라진다.
const _indoorTilesSourceIdBase = 'outdoor-indoor-tiles';
const _indoorFootprintLayerIdBase = 'outdoor-indoor-footprint';
const _indoorStoresFillLayerIdBase = 'outdoor-indoor-stores-fill';
// 수직이동(에스컬레이터/엘리베이터) 구조물 폴리곤을 초록톤으로 덧칠하는 fill.
// _indoorStoresFillLayerIdBase 위, 라벨/아이콘보다 아래에 삽입해 초록 배경 + 라벨/
// 아이콘이 한 덩어리로 읽히게 한다. 실내 화면의 _verticalTransportFillLayerId와
// 시각 언어를 맞춘다.
const _indoorVerticalTransportFillLayerIdBase =
    'outdoor-indoor-vertical-transport-fill';
const _indoorStoresLabelLayerIdBase = 'outdoor-indoor-stores-label';
// POI(엘리베이터·에스컬레이터·화장실 등 `pois` 소스 레이어) 위 아이콘 심볼과
// `stores` 소스 레이어에 이름으로 매칭되는 편의시설(화장실·정수기·수유실 등)
// 위 아이콘 심볼. 실내 화면과 같은 아이콘/색을 써 두 화면 사이에서 위치를
// 이어보아도 시설 표기가 흔들리지 않는다.
const _indoorPoiIconLayerIdBase = 'outdoor-indoor-pois-icon';
const _indoorStoreFacilityIconLayerIdBase =
    'outdoor-indoor-store-facility-icons';
const _routeSourceId = 'outdoor-route';
const _routeCasingLayerId = 'outdoor-route-casing';
const _routeLineLayerId = 'outdoor-route-line';
const _currentSourceId = 'outdoor-current';
const _accuracyLayerId = 'outdoor-accuracy';
const _currentDotLayerId = 'outdoor-current-dot';
const _destSourceId = 'outdoor-destination';
const _destLayerId = 'outdoor-destination-pin';
// 실내 경로의 도착 노드에 찍는 물방울 핀. 야외 GPS 목적지 원(_destLayerId)과
// **소스를 나눈다** — 같은 소스에 넣으면 원 레이어 필터가 없어 실내 도착
// 노드에도 빨간 원이 함께 그려져 핀 밑에 원이 비어져 나온다.
const _indoorDestSourceId = 'outdoor-indoor-destination';
const _indoorDestLayerId = 'outdoor-indoor-destination-pin';
// 도착 핀 비트맵의 addImage 등록 키. 실내 지도(floor_plan_view.dart)의 핀과
// 같은 물방울 모양이지만 흰 원과 "도착" 텍스트가 없는 단색 빨강이라, 이름을
// 나눠 두 디자인이 섞이지 않게 한다. 웹 addImage는 같은 이름이 이미 있으면
// 새 비트맵을 버리므로(위 _pdrLocationImageName 주석 참고) 디자인을 바꿀 땐
// 이름도 같이 바꿔야 살아 있는 지도에 반영된다.
const _destinationPinImageName = 'outdoor-destination-pin-solid-v1';
// 도착 핀 iconSize의 zoom 보간 구간(z16 → z20). 원본 비트맵이 128x172px이라
// 화면 높이는 172 x iconSize다.
//
// 기준은 현재 위치 마커다 — 그쪽은 zoom과 무관하게 42px 고정 도트인데
// (_pdrLocationRimRadius 21의 지름), 이전 값(0.115/0.25)에서는 실내 오버레이를
// 실제로 보는 zoom 18에서 핀이 31px밖에 안 돼 "저기가 목적지"를 가리키는
// 랜드마크가 사용자 위치 도트보다 작았다. 지금 값은 z18 ≈ 48px, z20 ≈ 65px로
// 도트보다 확실히 크다. 위쪽(z20) 상한은 확대했을 때 핀이 도착 매장 폴리곤을
// 통째로 덮지 않는 선에서 잡았다.
const _destinationPinIconSizeZ16 = 0.18;
const _destinationPinIconSizeZ20 = 0.38;
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
// 이름 끝에 코어 반지름을 박아 둔다 — 웹 addImage는 같은 이름이 이미 있으면
// 새 비트맵을 버리고 건너뛰고, removeImage도 없어서 디자인을 바꿔도 살아 있는
// 지도에는 예전 크기가 남는다(floor_plan_view.dart의 같은 주석 참고).
const _pdrLocationImageName = 'outdoor-pdr-location-r$_pdrLocationCoreRadius';
const _pdrLocationDotImageName =
    'outdoor-pdr-location-dot-r$_pdrLocationCoreRadius';
// 아래 세 값은 floor_plan_view.dart의 _currentLocationIcon* 상수와 같은 뜻이고
// 같은 값이어야 한다. 코어 지름(반지름 16 → 32px)이 이 마커의 체감 크기를
// 정한다 — 야외 GPS 도트(18px)보다 크고 정확도 원 테두리(44px)보다 작게 잡았다.
const _pdrLocationIconPixelRatio = 2.0;
const _pdrLocationCoreRadius = 16.0;
const _pdrLocationRimRadius = _pdrLocationCoreRadius + 5;
// 실내 오버레이에서 매장 폴리곤을 탭했을 때 그 매장 하나만 옅은 파란색 + 진한
// 테두리로 강조 표시하는 전용 소스·레이어. 실내 지도의 highlight와 같은 톤
// (#1A73E8, 옅은 fill + 얇은 line)으로 맞춰 두 화면 사이 UX가 흔들리지 않게 한다.
const _highlightSourceId = 'outdoor-highlight';
const _highlightFillLayerId = 'outdoor-highlight-fill';
const _highlightLineLayerId = 'outdoor-highlight-line';
// 실내 진입 오버레이가 켜지면 건물 밖만 어둡게 덮어 실내 도면에 시선을 모으는
// dim scrim. 위젯 트리 스크림이 아니라 MapLibre fill 레이어라, 세계를 덮는
// outer ring + 건물 footprint를 hole로 뚫은 폴리곤으로 그려도 건물 안쪽은 그대로
// 밝게 남는다. 삽입 순서를 야외 building outline 위 / 실내 MVT 오버레이 아래로
// 잡아, 실내 오버레이가 스크림 위에 얹혀 스포트라이트처럼 보이게 한다.
const _dimScrimSourceId = 'outdoor-dim-scrim';
const _dimScrimFillLayerId = 'outdoor-dim-scrim-fill';

// 디버그 모드 전용 PDR 진단 레이어. 실내 지도(floor_plan_view.dart)가 이미
// 같은 세 경로를 그리고 있어서, **색·굵기·점선 패턴을 그대로 맞춘다** — 두
// 화면에서 같은 선이 다른 색으로 보이면 진단 자체를 믿을 수 없게 된다.
//
// 세 경로를 따로 두는 이유는 PDR 파이프라인의 단계를 눈으로 분리해 보기
// 위해서다. raw(주황 점선)는 걸음 추정이 만든 날것의 궤적, confirmed(초록)는
// 그중 확정된 걸음만, matched(보라)는 confirmed를 통행 그래프 간선에 스냅한
// 결과다. 셋이 갈라지는 지점이 곧 어느 단계에서 틀어졌는지를 가리킨다.
const _debugGraphSourceId = 'outdoor-debug-graph';
const _debugGraphEdgeLayerId = 'outdoor-debug-graph-edges';
const _debugGraphActiveEdgeLayerId = 'outdoor-debug-graph-active-edges';
const _debugGraphNodeLayerId = 'outdoor-debug-graph-nodes';
const _debugGraphActiveNodeLayerId = 'outdoor-debug-graph-active-nodes';
const _pdrRawTrailSourceId = 'outdoor-pdr-raw-trail';
const _pdrRawTrailLayerId = 'outdoor-pdr-raw-trail-line';
const _pdrConfirmedTrailSourceId = 'outdoor-pdr-confirmed-trail';
const _pdrConfirmedTrailCasingLayerId = 'outdoor-pdr-confirmed-trail-casing';
const _pdrConfirmedTrailLayerId = 'outdoor-pdr-confirmed-trail-line';
const _pdrMatchedTrailSourceId = 'outdoor-pdr-matched-trail';
const _pdrMatchedTrailCasingLayerId = 'outdoor-pdr-matched-trail-casing';
const _pdrMatchedTrailLayerId = 'outdoor-pdr-matched-trail-line';

// 건물 폴리곤의 기본/눌린 상태 fill opacity. 기본은 옅게 존재만 알리고,
// 사용자가 탭한 순간 잠깐 진하게 반짝여서 "인식됐다"는 시각 피드백을 준다.
const _buildingFillOpacityDefault = 0.15;
const _buildingFillOpacityPressed = 0.45;
// 탭 후 오버레이 페이드인이 완료되는 시간 감각. 시각 피드백이 잠깐 이어져야
// "인식됐다" 느낌을 준다.
const _buildingPressedHoldMs = 220;

// 실내 진입/이탈 임계값·오버레이 페이드 구간은 서로 얽혀 있어 한 곳에서만
// 정의한다 — indoor_entry_zoom.dart 참고. 값 하나만 옮겨도 "도면이 다 보이기
// 전에 실내에서 튕겨 나가는" 증상이나 "이탈 순간 도면이 툭 끊기는" 증상이
// 조용히 되살아나므로, 관계를 함수로 고정하고 테스트로 지킨다.

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

// 홈/실내 세그먼트의 왼쪽에 8px 간격으로 PDR 제어를 붙이는 right inset.
// indoor_map_screen.dart의 동명 상수와 같은 값이어야 실내 탭과 야외 실내 진입
// 오버레이에서 PDR 버튼이 같은 자리에 놓인다.
const _pdrControlRightInsetPx = 184.0;

// PDR 안내 토스트를 하단 바(+ETA 카드) 위로 띄우기 위한 오프셋. 실내 화면의
// _mapShellBottomChromePx/_etaCardHeightPx와 같은 값을 쓴다.
const _mapShellBottomChromePx = 112.0;
const _etaCardHeightPx = 130.0;

// 위치 지정 안내를 상단 chrome 아래에 놓기 위한 오프셋. MapShellScreen의
// 검색창(top 0)과 그 아래 카테고리 chip 열(top 78, 높이 ≈32) 밑으로 내려야
// 안내가 chip에 가려지지 않는다. 이 오버레이는 chip 열과 **다른 Stack**에
// 있으므로 Positioned만으로는 겹침을 피할 수 없다 — SafeArea로 감싸 노치
// 기기에서 chip 열이 상태바만큼 내려앉는 것까지 같이 따라가야 한다.
// 실내 화면의 동명 상수와 같은 값이어야 두 화면에서 안내가 같은 자리에 뜬다.
const _placingHintTopPx = 132.0;

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
  const pixelSize = canvasSize * _pdrLocationIconPixelRatio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, pixelSize, pixelSize),
  );
  canvas.scale(_pdrLocationIconPixelRatio);

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
    _pdrLocationRimRadius + 3,
    Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
  canvas.drawCircle(
    center,
    _pdrLocationRimRadius,
    Paint()..color = Colors.white,
  );

  const blue = Color(0xFF1976D2);
  canvas.drawCircle(center, _pdrLocationCoreRadius, Paint()..color = blue);
  // 코어 크기를 바꿔도 비율이 유지되도록 코어 반지름에서 파생시킨다
  // (원본 디자인의 코어 18 / offset 5 / 반지름 4.5 비율).
  const glossOffset = _pdrLocationCoreRadius * 0.28;
  canvas.drawCircle(
    center - const Offset(glossOffset, glossOffset),
    _pdrLocationCoreRadius * 0.25,
    Paint()..color = const Color(0x66FFFFFF),
  );

  final image = await recorder.endRecording().toImage(
    pixelSize.toInt(),
    pixelSize.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// 실내 경로 도착 노드에 찍는 물방울 핀을 오프스크린 렌더링해 PNG 바이트로
/// 돌려준다. 위쪽 원 + 아래쪽 삼각 꼬리를 같은 빨강으로 합쳐 물방울을 만들고,
/// 꼬리의 두 밑변은 원의 접선에 정확히 맞물리도록 tangentAngle(중심-끝점 축과
/// 접점 사이의 각도, acos(r/d))로 계산해 이음매가 매끄럽게 이어진다. 모양·크기는
/// 실내 지도의 [floor_plan_view.dart:_renderDestinationPinIcon]과 같은 값이다.
///
/// 다른 점은 두 가지다 — 안쪽 흰 원을 그리지 않아 **단색 빨강**이고, "도착"
/// 텍스트를 얹지 않는다. 그래서 실내 핀이 텍스트를 심볼 레이어 textField로
/// 올리며 감수했던 제약(웹 CanvasKit에서 한글 글리프가 두부로 깨지는 문제,
/// textOffset을 아이콘 흰 원 중심에 맞추는 계산)이 여기서는 아예 없다.
Future<Uint8List> _renderDestinationPinIcon() async {
  const canvasWidth = 128.0;
  const canvasHeight = 172.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
  );

  const cx = canvasWidth / 2;
  const headRadius = 54.0;
  const headCenterY = headRadius + 6;
  const tipY = canvasHeight - 6;
  const centerToTipDistance = tipY - headCenterY;

  final tangentAngle = math.acos(headRadius / centerToTipDistance);
  final tangentDx = headRadius * math.sin(tangentAngle);
  final tangentDy = headRadius * math.cos(tangentAngle);

  final pinPaint = Paint()..color = AppColors.dest;
  canvas.drawCircle(const Offset(cx, headCenterY), headRadius, pinPaint);
  final tail = Path()
    ..moveTo(cx, tipY)
    ..lineTo(cx + tangentDx, headCenterY + tangentDy)
    ..lineTo(cx - tangentDx, headCenterY + tangentDy)
    ..close();
  canvas.drawPath(tail, pinPaint);

  final image = await recorder.endRecording().toImage(
    canvasWidth.toInt(),
    canvasHeight.toInt(),
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
      // **여기 background 레이어가 없으면 지도가 검게 뜬다.**
      // MapLibre GL의 WebGL 캔버스는 base color 없이 clear되면 검정으로 남는데,
      // OSM/VWorld raster 타일이 도착하기 전(첫 진입)이나 캐시에 없는 zoom을
      // 갔다 오면(z<15까지 축소 후 다시 확대) 그 사이가 통째로 검게 보인다.
      // 실내 초기 스타일(_initialStyle)이 이미 같은 이유로 background를 깔고
      // 있다. 색은 OSM의 land 기본색에 가까운 옅은 회백색.
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#EDECE8'},
      },
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
    this.active = true,
    this.onRouteVisibleChanged,
    this.onPlacingLocationChanged,
    this.onIndoorEnteredChanged,
    this.onStoreTap,
  });

  /// 이 야외 지도가 지금 화면에 보이는지. [MapShellScreen]은 야외/실내를
  /// IndexedStack으로 겹쳐 두므로, 사용자가 실내 탭으로 넘어가도 이 위젯은
  /// 살아 있다. 알려주지 않으면 보이지도 않는 야외 지도가 GPS를 계속 구독한다 —
  /// 실내에 들어간 뒤에는 GPS를 쓰지 않는다는 규칙을 지키려면 이 값이 필요하다.
  final bool active;

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

  // 실내 오버레이 소스·레이어의 세대 카운터. 층 전환마다 [_bumpIndoorIds]가
  // 이 값을 올려 새로운 실제 ID를 만든다. 상수 대신 인스턴스 필드로 두는 이유는
  // 파일 상단 상수 블록의 주석 참고(native remove/add 경쟁 회피).
  int _indoorIdGeneration = 0;
  late String _indoorTilesSourceId = _idFor(_indoorTilesSourceIdBase);
  late String _indoorFootprintLayerId = _idFor(_indoorFootprintLayerIdBase);
  late String _indoorStoresFillLayerId = _idFor(_indoorStoresFillLayerIdBase);
  late String _indoorVerticalTransportFillLayerId =
      _idFor(_indoorVerticalTransportFillLayerIdBase);
  late String _indoorStoresLabelLayerId = _idFor(_indoorStoresLabelLayerIdBase);
  late String _indoorPoiIconLayerId = _idFor(_indoorPoiIconLayerIdBase);
  late String _indoorStoreFacilityIconLayerId =
      _idFor(_indoorStoreFacilityIconLayerIdBase);

  String _idFor(String base) => '$base-g$_indoorIdGeneration';

  /// 다음 실내 오버레이 등록에 쓸 소스·레이어 실제 ID를 새 세대(generation)로
  /// 갈아 끼운다. 층을 바꿀 때 remove가 완전히 끝나기 전 add가 같은 ID로 오면
  /// maplibre_gl native가 조용히 실패하는 문제를 회피한다. 반드시 이전 세대의
  /// remove 이후, 다음 세대의 add 전에 호출한다.
  void _bumpIndoorIds() {
    _indoorIdGeneration++;
    _indoorTilesSourceId = _idFor(_indoorTilesSourceIdBase);
    _indoorFootprintLayerId = _idFor(_indoorFootprintLayerIdBase);
    _indoorStoresFillLayerId = _idFor(_indoorStoresFillLayerIdBase);
    _indoorVerticalTransportFillLayerId =
        _idFor(_indoorVerticalTransportFillLayerIdBase);
    _indoorStoresLabelLayerId = _idFor(_indoorStoresLabelLayerIdBase);
    _indoorPoiIconLayerId = _idFor(_indoorPoiIconLayerIdBase);
    _indoorStoreFacilityIconLayerId =
        _idFor(_indoorStoreFacilityIconLayerIdBase);
  }

  /// 현재 세대의 실내 오버레이 레이어 ID 목록(위→아래 순). removeLayer 순서로
  /// 그대로 재사용할 수 있다 — 레이어는 반드시 소스보다 먼저 제거해야 한다.
  List<String> get _indoorOverlayLayerIds => [
        _indoorStoreFacilityIconLayerId,
        _indoorPoiIconLayerId,
        _indoorStoresLabelLayerId,
        _indoorVerticalTransportFillLayerId,
        _indoorStoresFillLayerId,
        _indoorFootprintLayerId,
      ];

  /// 실내 진입 오버레이 상태. true면 층 chip과 위치 지정 버튼 등 실내 UI를
  /// 야외 지도 위에 그린다. 건물 폴리곤 탭, 줌 임계값 초과, GPS 근접 감지
  /// 중 하나로 켜지고, 사용자가 지도를 축소해 임계값 아래로 내려가면 자동으로
  /// 꺼진다 — 실내에서 벗어난 시점에는 오버레이가 시야를 방해하지 않아야 한다.
  bool _indoorEntered = false;

  /// PDR 앵커 배치 대기 중인지. true면 다음 지도 탭은 건물 진입 처리가 아닌
  /// PDR 시작점 지정으로 소비된다.
  bool _placingPdrAnchor = false;

  /// 실내 진입 오버레이에서 위치 보정 버튼을 누른 횟수. 실내 탭과 같은 규칙으로
  /// 홀수 번째(1·3·5…) 탭은 실내 위치 중앙 정렬, 짝수 번째(2·4·6…) 탭은 방향
  /// 회전을 수행한다. 순수 야외(GPS) 보정은 이 카운터를 쓰지 않는다.
  int _recalibrateTapCount = 0;
  late final DebugPdrTrailState _pdrTrailState;
  StreamSubscription<PdrSnapshot>? _pdrSnapshotSub;
  StreamSubscription<CalibrationStatus>? _pdrCalibrationSub;

  /// 디버그 설정은 실내 지도와 공유한다 — 어느 화면에서 켜든 같은 상태를 본다.
  final DebugModeController _debugModeController = debugModeController;

  /// 이번 PDR 세션의 기록기. "PDR 시작"에서 새로 만들고 종료 시 JSON으로
  /// 내보낸다. 실내 화면과 같은 포맷이라 두 화면에서 받은 로그를 같은 분석
  /// 스크립트로 비교할 수 있다.
  PdrDebugSessionRecorder? _pdrDebugRecorder;
  bool _exportingPdrDebugJson = false;

  /// 활성 층 GeoJSON의 map_calibration_version. 내보낸 세션이 어떤 보정본
  /// 도면 위에서 측정된 것인지 구분하는 데 쓴다.
  String _mapCalibrationVersion = 'unversioned';

  // 지도 위 Flutter 오버레이(PDR 제어·디버그 설정 버튼) 영역. MapLibre는
  // PlatformView라 이 위젯들 위의 탭도 native 지도까지 흘러들어가 onMapClick이
  // 함께 발화한다 — 버튼을 눌렀을 뿐인데 뒤의 매장이 열리거나 앵커가 버튼
  // 아래에 찍히는 것을 막기 위해 좌표로 걸러낸다(실내 화면의 overlayHitTest와
  // 같은 목적).
  final GlobalKey _pdrControlKey = GlobalKey();
  final GlobalKey _debugModeSettingsKey = GlobalKey();
  final GlobalKey _pdrShareButtonKey = GlobalKey();

  /// 위치 지정 안내 배너. 오른쪽 상단 X를 누른 탭이 지도까지 새어들어가 배너
  /// 아래 지점에 앵커가 찍히는 것을 막는다 — 취소했는데 위치가 지정되면
  /// 사용자 입장에선 취소가 안 먹은 것으로 보인다.
  final GlobalKey _placingHintKey = GlobalKey();

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
  }

  /// 실내 진입 오버레이에서 지금 보고 있는 층. 상위(MapShellScreen)가 상단
  /// 검색·길찾기 시트를 "현재 층 우선"으로 좁힐 때 쓴다 — 실내 화면의
  /// [IndoorMapBodyState.currentFloor]와 같은 계약이라 상위가 두 화면을
  /// 동일하게 다룰 수 있다.
  String? get currentFloor => _activeFloor;

  @override
  void initState() {
    super.initState();
    _pdrTrailState = DebugPdrTrailState.fromCurrent(
      snapshot: indoorNavigationDriver.currentSnapshot,
      calibration: indoorNavigationDriver.currentCalibration,
    );
    _debugModeController.addListener(_onDebugModeChanged);
    _pdrSnapshotSub = indoorNavigationDriver.snapshots.listen((snapshot) {
      _pdrDebugRecorder?.recordSnapshot(snapshot);
      if (!mounted) return;
      setState(() => _pdrTrailState.recordSnapshot(snapshot));
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
    });
    _pdrCalibrationSub = indoorNavigationDriver.calibration.listen((status) {
      _pdrDebugRecorder?.recordCalibration(status);
      if (!mounted) return;
      setState(() => _pdrTrailState.recordCalibration(status));
      if (status.phase == CalibrationPhase.calibrated ||
          status.phase == CalibrationPhase.uncalibrated) {
        _setPlacingAnchor(false);
      }
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
    });
    _loadBuildingEntrance();
    _syncGpsSubscription();
  }

  @override
  void didUpdateWidget(covariant OutdoorMapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 실내 탭으로 넘어가면(active=false) GPS 구독을 끊고, 돌아오면 다시 붙인다.
    if (oldWidget.active != widget.active) _syncGpsSubscription();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    // 앱 전역 인스턴스라 dispose하지 않는다 — 실내 화면이 같은 컨트롤러를
    // 계속 구독한다.
    _debugModeController.removeListener(_onDebugModeChanged);
    super.dispose();
  }

  /// 디버그 모드를 끄면 PDR 진입점이 화면에서 사라진다. 세션이 켜져 있는 채로
  /// 버튼만 없어지면 센서가 계속 돌면서 종료할 방법이 없으므로 함께 정리한다.
  /// (실내 화면도 같은 처리를 하며, [stopGuidance]는 이미 idle이면 즉시
  /// 리턴하므로 두 화면이 같이 호출해도 안전하다.)
  void _onDebugModeChanged() {
    if (!_debugModeController.enabled &&
        indoorNavigationDriver.currentRuntimeStatus.state !=
            PdrRuntimeState.idle) {
      unawaited(_stopPdrWhenDebugModeTurnsOff());
    }
    // 디버그 시트에서 개별 경로 토글을 켜고 끄면 여기로 들어온다. 레이어는
    // 이미 등록돼 있으므로 데이터만 다시 채우면 즉시 반영된다.
    unawaited(_syncDebugPdrLayers());
    if (mounted) setState(() {});
  }

  Future<void> _stopPdrWhenDebugModeTurnsOff() async {
    await indoorNavigationDriver.stopGuidance();
    if (mounted) _setPlacingAnchor(false);
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
        _mapCalibrationVersion =
            geojson?['map_calibration_version'] as String? ?? 'unversioned';
      });
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
      // 지하층 외곽선은 방금 받은 도면에서 나온다. 도면이 도착한 이 시점에
      // 한 번 더 그려야 층을 바꾼 직후의 빈 외곽선이 채워진다.
      unawaited(_syncFloorOutlineLayer());
      _syncDimScrimLayer();
    } catch (_) {
      // 로드 실패 시 앵커 배치·매장 탭은 안내로 막고 나머지 야외 지도 동작은
      // 그대로 유지한다.
      if (mounted) {
        setState(() {
          _floorGraph = null;
          _floorPlan = null;
          _mapCalibrationVersion = 'unversioned';
        });
        unawaited(_syncFloorOutlineLayer());
        _syncDimScrimLayer();
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
      _mapCalibrationVersion = 'unversioned';
      if (multiRoute == null) {
        _indoorRouteSegment = null;
      } else {
        _indoorRouteSegment = nextSegmentRoute;
      }
      // 층이 바뀌면 그 층에 강조하던 매장은 지도에 없다. 강조도 초기화.
      _highlightedStoreId = null;
    });
    // 층이 바뀐 순간 이전 층의 외곽선은 더 이상 맞지 않는다. 새 도면이 도착할
    // 때까지(지하 → 다른 층) 선을 지워 둔다 — 틀린 경계를 보여주지 않는다.
    unawaited(_syncFloorOutlineLayer());
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
      // 다음 등록은 새 세대 ID로. 같은 ID로 즉시 addSource를 다시 부르면
      // native(Android/iOS)가 이전 remove의 정리를 아직 못 끝내 조용히 실패하는
      // 경우가 있다(특정 층으로 전환 시 아무것도 안 그려지는 원인이었음).
      _bumpIndoorIds();
    }
    await _ensureIndoorTilesRegistered();
    await _loadFloorGraph(building.id, floor);
    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    _syncRouteLayer();
    // 층이 바뀌면 도착 핀도 다시 판정한다 — 다층 경로에서 도착지 층을 벗어나면
    // 핀이 사라지고, 다시 그 층으로 돌아오면 살아난다.
    _syncIndoorDestinationLayer();
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
  /// - 카메라 zoom이 이탈 임계값 미만(=도면이 사실상 안 보임)이면 진입 임계값
  ///   + 건물 중심으로 이동.
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

    // 이탈 임계값 기준으로 판정한다. 진입 임계값(17.5)으로 재면, 넓은 지하층
    // 전체를 담으려고 z≈16.05까지 축소해 둔 사용자가 층 chip을 누르는 순간
    // 카메라가 다시 17.5로 튀어올라 방금 맞춘 view를 빼앗긴다.
    final needZoomIn = cam.zoom < indoorExitZoomThreshold;
    // 건물 중심에서 카메라까지 대략적인 거리. 위경도 도 단위지만 근사적으로
    // 계산해 "화면 밖" 판정에만 쓴다 — 정확한 거리 계산은 필요 없다.
    final distDeg = math.sqrt(
      math.pow(cam.target.latitude - center.latitude, 2) +
          math.pow(cam.target.longitude - center.longitude, 2),
    );
    // 대략 300m 이상 떨어져 있으면 화면 밖으로 간주(37°에서 0.003° ≈ 300m).
    final farFromBuilding = distDeg > 0.003;

    if (!needZoomIn && !farFromBuilding) return;

    // 확대해 줄 때의 목표 zoom도 화면 폭에 맞춘 임계값을 쓴다. 고정 17.5로
    // 올리면 폰에서는 건물이 화면 밖으로 넘치게 확대돼, 포커스를 맞췄는데
    // 오히려 건물이 안 보이게 된다.
    final targetZoom = needZoomIn ? _entryZoomThreshold() : cam.zoom;
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

  /// 지금 GPS를 써도 되는 상태인지. 건물 안에서는 GPS를 아예 쓰지 않는다 —
  /// 실내에서는 신호가 튀어 위치가 건물 밖으로 날아가고, 실내 위치는 PDR(위치
  /// 지정 + 걸음 추적)이 담당하기 때문이다. 그래서 다음 두 경우에는 구독 자체를
  /// 끊는다.
  ///   - 실내 진입 오버레이가 켜진 상태([_indoorEntered])
  ///   - 사용자가 하단 세그먼트로 실내 탭에 가 있어 이 화면이 안 보이는 상태
  ///     (`widget.active == false`)
  /// "마커만 숨기기"가 아니라 구독을 끊는 이유: 화면에 안 보여도 스트림이 살아
  /// 있으면 위치가 계속 들어와 자동 경로 재계산·카메라 이동을 트리거한다.
  bool get _gpsTrackingWanted => widget.active && !_indoorEntered;

  /// GPS 구독을 [_gpsTrackingWanted] 상태에 맞춘다. 구독 시작/해제의 유일한
  /// 진입점이라 중복 구독이나 해제 누락이 생기지 않는다.
  void _syncGpsSubscription() {
    if (_gpsTrackingWanted) {
      if (_positionSubscription != null) return;
      _positionSubscription = watchPosition().listen(
        _handlePosition,
        onError: (Object _) => _handlePositionError(),
      );
      return;
    }
    if (_positionSubscription == null) return;
    unawaited(_positionSubscription!.cancel());
    _positionSubscription = null;
    // 마지막으로 알던 GPS 위치도 버린다. 남겨두면 실내에 들어간 뒤에도 마커가
    // 그려지거나(“GPS 기반 위치가 보이면 안 된다”), 다시 야외로 나왔을 때 옛
    // 좌표가 잠깐 현재 위치인 것처럼 보인다.
    _pendingCenterOnPosition = false;
    if (!mounted) return;
    setState(() {
      _position = null;
      _previousAccuracy = null;
    });
    _syncCurrentLayer();
  }

  void _handlePositionError() {
    if (!mounted) return;
    setState(() => _position = null);
    _syncCurrentLayer();
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    // 실내 진입 직전에 이미 큐에 들어간 이벤트가 진입 후 도착할 수 있다.
    // 구독은 끊겼어도 이 한 건이 새어들어오면 위치 마커가 다시 켜지므로 막는다.
    if (!_gpsTrackingWanted) return;
    setState(() => _position = position);
    _syncCurrentLayer();
    _maybeAutoEnter(position);
    // 이번 위치로 자동 실내 진입이 발동했다면 GPS 기반 걷기 경로는 더 이상
    // 계산하지 않는다 — 사용자는 이미 건물 안이다.
    if (_indoorEntered) return;
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

  /// 위치 보정 버튼.
  ///
  /// 실내 진입 오버레이가 켜져 있으면 GPS를 아예 건드리지 않고 실내(PDR) 위치를
  /// 기준으로 카메라를 맞춘다 — 건물 안에서 GPS를 다시 찍으면 지도가 건물 밖
  /// 좌표로 튀어 방금 지정한 실내 위치를 잃는다. 동작은 실내 탭
  /// ([IndoorMapBodyState.recalibrate])과 동일하게 탭마다 번갈아 수행한다:
  /// 홀수 번째 탭은 실내 위치를 화면 정중앙에, 짝수 번째 탭은 바라보는 방향을
  /// 화면 위쪽에 오도록 회전.
  ///
  /// 순수 야외 상태에서만 예전처럼 새 GPS 위치를 한 번 더 조회해 마커·지도
  /// 중심을 갱신한다.
  Future<void> recalibrate() async {
    if (_indoorEntered) {
      await _recalibrateIndoor();
      return;
    }
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

  /// 실내 진입 오버레이에서의 위치 보정. GPS를 호출하지 않고 PDR이 알고 있는
  /// 실내 위치·방향만 쓴다.
  ///
  /// 실제로 동작을 수행한 탭만 카운트를 올린다 — 위치나 heading을 아직 몰라
  /// 안내만 띄운 탭까지 세면, 사용자가 위치를 잡은 뒤 누른 다음 탭이 "회전"
  /// 차례로 밀려 정작 중앙 정렬이 안 된다.
  Future<void> _recalibrateIndoor() async {
    if (_recalibrateTapCount.isEven) {
      // 홀수 번째 탭 — 실내 위치를 화면 정중앙으로. 앵커가 다른 층에 있거나
      // 층 그래프가 아직 없으면 null이라 여기서 걸린다. 지도가 아직 준비되지
      // 않았더라도 "위치를 먼저 지정하라"는 안내는 먼저 띄운다.
      final target = _pdrCurrentWgs84();
      if (target == null) {
        _showSnack('아직 현재 위치가 없습니다. 위치 지정 버튼으로 먼저 위치를 잡아주세요.');
        return;
      }
      final controller = _mapController;
      if (controller == null || !_styleReady) return;
      await controller.animateCamera(CameraUpdate.newLatLng(_toGl(target)));
    } else {
      // 짝수 번째 탭 — 바라보는 방향이 화면 위쪽에 오도록 회전. 이때 내 실내
      // 위치도 함께 화면 정중앙에 놓는다. 중앙 정렬 후 조금 걸어간 뒤 회전을
      // 누르면 화면 중심과 내 위치가 이미 어긋나 있어, 중심을 그대로 두고
      // 돌리면 내 위치가 화면 가장자리로 밀려나기 때문이다. 줌·tilt는 유지.
      final heading = _pdrCurrentHeadingDeg;
      if (heading == null) {
        _showSnack('아직 바라보는 방향을 알 수 없습니다. 위치 지정 후 조금 걸어 방향을 잡아주세요.');
        return;
      }
      final controller = _mapController;
      if (controller == null || !_styleReady) return;
      final camera = controller.cameraPosition;
      // 위치를 아직 모르면(앵커가 다른 층 등) 지금 보고 있는 중심을 그대로 둔다.
      final myLocation = _pdrCurrentWgs84();
      final center = myLocation != null
          ? _toGl(myLocation)
          : camera?.target ?? _toGl(_entrance ?? _fallbackLocation);
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: center,
            zoom: camera?.zoom ?? indoorEntryZoomThreshold,
            bearing: heading,
            tilt: camera?.tilt ?? 0,
          ),
        ),
      );
    }
    _recalibrateTapCount++;
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
  /// [origin]을 주면 PDR 앵커 대신 그 매장을 출발지로 쓴다 — 상단 길찾기 시트에서
  /// 매장을 출발지로 고른 경우다. 이때 앵커(위치 지정)가 없어도 경로를 그릴 수
  /// 있어야 하므로, 앵커 필수 검사는 origin이 없을 때만 적용한다.
  Future<void> showIndoorRouteTo(
    PoiSearchResult destination, {
    PoiSearchResult? origin,
  }) async {
    final anchor = _pdrTrailState.anchor;
    // 명시적 출발지는 노드 id와 층이 둘 다 있어야 그래프 탐색을 시작할 수 있다.
    // 하나라도 비면 앵커 경로로 폴백해, 사용자가 "출발지를 골랐는데 아무 일도
    // 안 일어나는" 상태에 빠지지 않게 한다.
    final originNodeId = origin?.nodeId;
    final originFloor = origin?.floor;
    final hasExplicitOrigin =
        originNodeId != null && originFloor != null && originFloor.isNotEmpty;
    if (!hasExplicitOrigin && anchor == null) {
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
    final startFloor = hasExplicitOrigin ? originFloor : anchor!.floorId;
    final explicitStartNodeId = hasExplicitOrigin ? originNodeId : null;
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
    // 경로 계산 전에도 도착지 centroid에 핀을 먼저 띄운다 — 사용자가 고른
    // 매장이 어디인지 즉시 보이고, 계산이 끝나면 도착 노드로 옮겨 붙는다.
    _syncIndoorDestinationLayer();
    _notifyRouteVisibilityIfChanged();

    if (startFloor == endFloor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: building.id,
        floor: endFloor,
        endNodeId: endNodeId,
        startNodeId: explicitStartNodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: building.id,
        startFloor: startFloor,
        endFloor: endFloor,
        endNodeId: endNodeId,
        startNodeId: explicitStartNodeId,
      );
    }
  }

  /// 같은 층 안에서 계산한 실내 경로를 지도에 얹는다. 활성 층이 목적지 층과
  /// 다르면 먼저 그 층으로 오버레이를 전환해 필요한 그래프를 다시 로드한다.
  /// [startNodeId]가 주어지면(길찾기 시트에서 매장을 출발지로 고른 경우) 그
  /// 노드에서 바로 출발하고, null이면 PDR 앵커 주변 최근접 통로 노드를 찾는다.
  Future<void> _computeAndShowSingleFloorIndoorRoute({
    required String buildingId,
    required String floor,
    required String endNodeId,
    String? startNodeId,
  }) async {
    if (floor != _activeFloor) {
      await _switchOverlayFloor(floor);
      if (!mounted) return;
    }
    final graph = _floorGraph;
    if (graph == null) {
      _showSnack('경로 계산에 필요한 층 정보를 불러오지 못했습니다.');
      return;
    }
    if (startNodeId == null) {
      final anchor = _pdrTrailState.anchor;
      if (anchor == null || anchor.floorId != floor) {
        _showSnack('경로 계산에 필요한 층 정보를 불러오지 못했습니다.');
        return;
      }
      startNodeId = _nearestNodeId(
        graph.nodes,
        anchor.anchorLocalM.eastM,
        anchor.anchorLocalM.northM,
        excludingNodeId: endNodeId,
      );
    }
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
    _syncIndoorDestinationLayer();
    _notifyRouteVisibilityIfChanged();
    _fitCameraToIndoorRoute(route);
  }

  /// 층이 다른 매장까지의 층 간 경로를 계산해 층별 세그먼트로 나누고, 현재
  /// 화면(_activeFloor)에 해당하는 세그먼트를 지도에 얹는다. 층 chip으로
  /// 다른 층을 훑으면 [_switchOverlayFloor]가 그 층 세그먼트로 갈아탄다.
  /// 시작 층부터 훑도록 활성 층을 자동으로 시작 층으로 전환한다.
  /// [startNodeId]가 주어지면(길찾기 시트에서 매장을 출발지로 고른 경우) 그
  /// 노드에서 바로 출발하고, null이면 PDR 앵커 기준으로 시작 노드를 고른다.
  Future<void> _computeAndShowMultiFloorIndoorRoute({
    required String buildingId,
    required String startFloor,
    required String endFloor,
    required String endNodeId,
    String? startNodeId,
  }) async {
    final buildingGraph = await buildingRepository.getBuildingGraph(buildingId);
    if (!mounted) return;
    if (buildingGraph == null || buildingGraph.nodes.isEmpty) {
      _showSnack('층 간 경로 계산에 필요한 그래프를 불러오지 못했습니다.');
      _clearIndoorRoute();
      return;
    }
    startNodeId ??= _pickStartNodeIdInBuildingGraph(
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
    _syncIndoorDestinationLayer();
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
    _syncIndoorDestinationLayer();
    _notifyRouteVisibilityIfChanged();
  }

  // --- MapLibre 스타일/레이어 설정 ---

  Future<void> _onStyleLoaded() async {
    final controller = _mapController;
    if (controller == null) return;

    // 새 스타일에는 이전 스타일이 갖고 있던 addImage 비트맵이 넘어오지 않는다.
    // 다음 _ensureIndoorTilesRegistered 호출이 아이콘을 다시 등록하도록 리셋.
    _facilityIconImagesRegistered = false;

    // 건물 폴리곤: 옅은 반투명 fill. "이 건물이 탭 가능하다"는 시각 힌트가 되고,
    // 사용자가 탭하면 opacity를 잠깐 올려 인식됐다는 피드백을 준다. 다른
    // 레이어(경로선·위치 점)가 위에 오도록 가장 먼저 추가한다. 외곽선은 여기
    // 붙이지 않는다 — 실내 진입 상태에서만, 층에 따라 다른 링을 그리므로 아래
    // 전용 소스로 뺐다.
    await controller.addSource(
      _buildingSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addFillLayer(
      _buildingSourceId,
      _buildingFillLayerId,
      buildingFillProps(_buildingFillOpacityDefault),
    );

    // 실내 진입 dim scrim. 건물 fill 바로 위에 두어 이후 등록되는 route/실내
    // MVT 오버레이보다 아래에 오게 한다 — 실내 도면은 스크림 위에 그려져 밝게
    // 남고, 야외 base만 어두워진다. 초기 opacity=0, geometry는 _syncDimScrimLayer
    // 가 footprint 로드 후 세계 outer + 건물 hole 폴리곤으로 채운다.
    await controller.addSource(
      _dimScrimSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addFillLayer(
      _dimScrimSourceId,
      _dimScrimFillLayerId,
      dimScrimProps(0),
      enableInteraction: false,
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

    // 현재 층 외곽선. **경로선 다음에** 등록하는 것이 핵심이다 — 실내 MVT
    // 오버레이는 나중에 `belowLayerId: _routeCasingLayerId`로 삽입되므로, 경로선
    // 앞(=건물 fill·dim scrim 옆)에 두면 불투명한 흰색 footprint fill 밑으로
    // 깔려 선이 반쯤 먹힌다. 도면 위에 얹혀야 경계가 그대로 보인다.
    //
    // 페이드 표현식은 **진입 상태 램프로 고정**한다. 이 레이어는 진입했을 때만
    // 지오메트리를 갖고(그 외에는 빈 소스), 진입 상태에서만 보이므로 진입 전
    // 램프가 쓰일 일이 없다. 덕분에 상태가 바뀔 때 setLayerProperties를 다시
    // 부를 필요가 없다(전체 교체 규칙에 걸릴 여지도 사라진다).
    await controller.addSource(
      _floorOutlineSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _floorOutlineSourceId,
      _floorOutlineLayerId,
      floorOutlineProps(
        indoorOverlayFadeExpr(entered: true, maxOpacity: 0.9),
      ),
      enableInteraction: false,
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
    // PDR 진단 레이어를 현재 위치 마커보다 **먼저** 등록해, 마커가 항상 경로
    // 위에 오게 한다. 진단 선이 현재 위치를 덮으면 정작 어디에 서 있는지가
    // 안 보인다.
    await _registerDebugPdrLayers(controller);

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
        // 야외 GPS 마커(CircleLayer 상수 반지름)가 zoom과 무관하게 고정이므로
        // 이쪽도 고정으로 둔다 — 디자인 1px = 화면 1px.
        iconSize: 1.0 / _pdrLocationIconPixelRatio,
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

    // 실내 경로 도착 핀 — 현재 위치 마커보다 **나중에** 등록해, 도착 노드와
    // 사용자 위치가 겹칠 때 도착 핀이 위에 오게 한다(실내 지도와 같은 순서).
    // 핀 바닥(tip)이 도착 노드 좌표에 오도록 iconAnchor는 bottom이고, 크기는
    // zoom 보간식으로 걸어 축소했을 때 핀이 도면을 다 덮지 않게 한다.
    // allowOverlap을 켜 매장 라벨과 겹쳐도 핀은 항상 보인다.
    await controller.addImage(
      _destinationPinImageName,
      await _renderDestinationPinIcon(),
    );
    await controller.addSource(
      _indoorDestSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addSymbolLayer(
      _indoorDestSourceId,
      _indoorDestLayerId,
      const SymbolLayerProperties(
        iconImage: _destinationPinImageName,
        iconSize: [
          'interpolate',
          ['linear'],
          ['zoom'],
          16,
          _destinationPinIconSizeZ16,
          20,
          _destinationPinIconSizeZ20,
        ],
        iconAnchor: 'bottom',
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
    _syncIndoorDestinationLayer();
    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    _syncHighlightLayer();
    _syncDimScrimLayer();
    _ensureIndoorTilesRegistered();
    // 스타일이 뜨기 전에 받아둔 첫 GPS 위치로의 카메라 이동. 그 사이에 실내로
    // 들어갔다면(줌 임계값·건물 탭) 실행하지 않는다 — 실내 도면을 보고 있는데
    // 카메라가 GPS 좌표로 튀면 안 된다.
    if (_pendingCenterOnPosition && _position != null && _gpsTrackingWanted) {
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
    final ring = _closedRing(footprint);
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
    // 건물 footprint가 바뀌면 dim scrim의 hole과 층 외곽선도 함께 갱신해야 한다.
    _syncDimScrimLayer();
    _syncFloorOutlineLayer();
  }

  /// 지금 "층 경계"로 삼아야 하는 링. 지상층이면 건물 외곽선, 지하층이면 그 층
  /// 도면의 외곽선이고, 실내에 들어가 있지 않으면 null이다. 규칙과 근거는
  /// [floorOutlineRing] 참고.
  ///
  /// 외곽선·dim scrim hole·건물 안 탭 판정이 **모두 이 하나를 본다.** 셋이 서로
  /// 다른 링을 쓰면 사용자가 보는 선 안쪽이 어두워지거나(scrim), 선 안쪽을
  /// 탭했는데 야외로 튕겨 나가는(탭 판정) 모순이 생긴다.
  List<ll.LatLng>? _activeFloorOutlineRing() => floorOutlineRing(
    indoorEntered: _indoorEntered,
    floor: _activeFloor,
    buildingFootprint: _buildingFootprint,
    floorFootprint: _floorPlan?.footprint,
  );

  /// 현재 층 외곽선 갱신. 그릴 링이 없으면 소스를 비워 선을 지운다 — 레이어
  /// 속성은 건드리지 않는다(등록 시 넣은 값 그대로 쓴다).
  Future<void> _syncFloorOutlineLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final ring = _activeFloorOutlineRing();
    if (ring == null) {
      await controller.setGeoJsonSource(
        _floorOutlineSourceId,
        _emptyCollection(),
      );
      return;
    }
    await controller.setGeoJsonSource(
      _floorOutlineSourceId,
      _collection([
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [_closedRing(ring)],
          },
        },
      ]),
    );
  }

  /// GeoJSON Polygon linear ring은 첫 점과 마지막 점이 같아야 한다. 백엔드가
  /// 이미 닫아 보내주면 중복 추가하지 않는다.
  static List<List<double>> _closedRing(List<ll.LatLng> points) {
    final ring = <List<double>>[
      for (final p in points) [p.longitude, p.latitude],
    ];
    if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
      ring.add(ring.first);
    }
    return ring;
  }

  /// dim scrim 갱신. 건물 footprint가 있으면 세계 전체를 덮는 outer ring +
  /// 건물 hole 폴리곤을 넣고, 실내 진입 상태에 따라 fillOpacity를 실내 오버레이와
  /// 같은 zoom 페이드 구간(16.5~17.5)에 맞춰 0 → 0.35로 켠다. 실내 진입이 꺼져
  /// 있을 땐 opacity=0으로 완전히 사라진다. 이렇게 하면 건물 밖만 반투명 검정으로
  /// 덮이고 실내 오버레이는 그대로 밝게 보인다.
  Future<void> _syncDimScrimLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    // hole은 외곽선과 **같은 링**을 쓴다. 지하층에서 건물 외곽선으로 뚫으면
    // 건물 밖으로 뻗어 나간 지하 도면이 스크림에 덮여, 사용자가 보는 외곽선
    // 안쪽이 어두워지는 모순이 생긴다. 링이 아직 없으면(지하 도면 로딩 중)
    // 건물 외곽선으로 폴백해 스크림 자체는 유지한다 — 스포트라이트가 한 프레임
    // 통째로 꺼지는 것보다 낫다.
    final footprint = _activeFloorOutlineRing() ?? _buildingFootprint;
    if (footprint == null || footprint.length < 3) {
      await controller.setGeoJsonSource(_dimScrimSourceId, _emptyCollection());
    } else {
      // 세계 전체를 덮는 outer ring(웹 메르카토르 상하한). 어떤 위치·줌에서도
      // 화면 밖까지 확실히 덮어 가장자리가 새어나오지 않는다.
      const worldRing = [
        [-180.0, -85.05112878],
        [180.0, -85.05112878],
        [180.0, 85.05112878],
        [-180.0, 85.05112878],
        [-180.0, -85.05112878],
      ];
      // GeoJSON 폴리곤 hole은 outer와 반대 방향(CW)이 표준. 백엔드 순회 방향에
      // 상관없이 안전하게 hole로 처리되도록 reversed로 뒤집는다.
      final holeRing = _closedRing(footprint.reversed.toList());
      await controller.setGeoJsonSource(
        _dimScrimSourceId,
        _collection([
          {
            'type': 'Feature',
            'properties': const <String, dynamic>{},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [worldRing, holeRing],
            },
          },
        ]),
      );
    }

    if (_indoorEntered) {
      // 실내 MVT 오버레이 페이드 구간과 동일한 zoom 창을 쓴다 — 오버레이가
      // 뜨는 것과 동시에 스크림도 자연스럽게 짙어진다. 최대치 0.35는 기존 위젯
      // 스크림(#40000000 = 0.25)보다 살짝 진하게 잡아 실내 vs 야외의 밝기
      // 대비를 조금 더 명확히 준다.
      // fillColor를 반드시 함께 넘긴다 — setLayerProperties는 patch가 아니라
      // 전체 교체다(indoor_overlay_layers.dart 상단 주석 참고).
      await controller.setLayerProperties(
        _dimScrimFillLayerId,
        dimScrimProps(_fadeExpr(maxOpacity: 0.35)),
      );
    } else {
      await controller.setLayerProperties(
        _dimScrimFillLayerId,
        dimScrimProps(0),
      );
    }
  }

  /// 현재 진입 상태에 맞는 오버레이 페이드 표현식.
  /// 구간이 진입 전후로 왜 다른지는 [indoorOverlayFadeExpr] 쪽 주석 참고.
  List<Object> _fadeExpr({double maxOpacity = 1}) =>
      indoorOverlayFadeExpr(entered: _indoorEntered, maxOpacity: maxOpacity);

  /// 실내 진입/이탈로 페이드 구간이 바뀌었을 때 이미 등록된 오버레이 레이어의
  /// opacity 표현식을 갈아 끼운다. 레이어가 아직 등록되지 않았으면
  /// [_ensureIndoorTilesRegistered]가 등록 시점의 상태로 넣어주므로 아무것도
  /// 하지 않아도 된다.
  ///
  /// **각 레이어의 전체 속성을 매번 다시 넘긴다.** opacity만 넘기면 안 된다 —
  /// 이유는 indoor_overlay_layers.dart 상단 주석 참고.
  Future<void> _syncIndoorOverlayFade() async {
    final controller = _mapController;
    if (controller == null || !_styleReady || !_indoorTilesRegistered) return;
    final fadeExpr = _fadeExpr();
    // 이미 제거된 레이어에 대한 setLayerProperties가 native에서 예외를 던지는
    // 구현이 있어(층 전환과 겹치는 순간) 각각 감싼다.
    for (final (id, props) in [
      (_indoorFootprintLayerId, indoorFootprintProps(fadeExpr)),
      (_indoorStoresFillLayerId, indoorStoresFillProps(fadeExpr)),
      (
        _indoorVerticalTransportFillLayerId,
        indoorVerticalTransportProps(fadeExpr),
      ),
      (_indoorStoresLabelLayerId, indoorStoresLabelProps(fadeExpr)),
      (_indoorPoiIconLayerId, indoorPoiIconProps(fadeExpr)),
      (_indoorStoreFacilityIconLayerId, indoorFacilityIconProps(fadeExpr)),
    ]) {
      try {
        await controller.setLayerProperties(id, props);
      } catch (_) {}
    }
  }

  /// 지도에서 탭한 위경도가 건물 footprint 내부인지 판정한다.
  /// 판정 자체는 [isPointInPolygon]에 있다 — 실내 진입 근접 판정
  /// ([isIndoorBuildingNearCamera])과 같은 계산을 써야 "탭은 건물 안인데 근접은
  /// 아니다" 같은 모순이 생기지 않는다.
  ///
  /// 실내 진입 중인 지하층에서는 그 층 외곽선 안쪽도 "건물 안"으로 본다. 화면에
  /// 그려진 외곽선 안을 탭했는데 야외로 튕겨 나가면(지하는 건물 외곽선 밖까지
  /// 뻗어 있다) 사용자 입장에서는 도면 위를 눌렀을 뿐이다. 두 링의 **합집합**을
  /// 보므로 지상층·야외에서의 판정은 지금까지와 같다.
  bool _isInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint != null && isPointInPolygon(point, footprint)) return true;
    final ring = _activeFloorOutlineRing();
    return ring != null && isPointInPolygon(point, ring);
  }

  /// 지도 탭 처리의 테스트 진입점.
  ///
  /// MapLibre 플랫폼 뷰는 위젯 테스트에 없어 `onMapClick`이 아예 발화하지
  /// 않는다. 그래서 실기기에서 쓰이는 것과 **같은 함수**를 직접 부른다 —
  /// 테스트용 축약 경로를 따로 두면 정작 검증하려는 분기(건물 밖 탭 → 야외
  /// 전환)를 우회해 버린다.
  @visibleForTesting
  Future<void> handleMapClickForTest(ll.LatLng point) => _handleMapClick(
    const Point<double>(0, 0),
    LatLng(point.latitude, point.longitude),
  );

  Future<void> _handleMapClick(Point<double> pointPx, LatLng coords) async {
    final point = ll.LatLng(coords.latitude, coords.longitude);

    // 지도 위에 얹은 PDR 제어·디버그 설정 버튼을 누른 탭은 여기서 끊는다.
    // 그러지 않으면 "PDR 시작"을 누른 손가락이 버튼 아래의 매장까지 함께
    // 선택하거나, 앵커 배치 대기 중에 버튼 위치에 앵커가 찍힌다.
    if (_isTapOnMapOverlay(Offset(pointPx.x, pointPx.y))) return;

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
    if (!_isInsideBuilding(point)) {
      // 실내 모드에서 건물 밖을 탭한 것 — 사용자가 야외로 나가겠다는 뜻이다.
      // 축소해서 나가는 것보다 훨씬 직관적인 탈출 경로다.
      if (_indoorEntered) _exitIndoorByOutsideTap();
      return;
    }

    // 폴리곤을 잠깐 진하게 반짝여 "인식됐다"는 시각 피드백을 준 뒤, 야외 지도
    // 위에 실내 UI 오버레이(층 chip, 위치 지정 버튼 등)를 켠다. 화면 모드는
    // 그대로 야외로 유지된다.
    //
    // 반짝임은 장식이라 컨트롤러가 아직 없으면 건너뛴다. 진입을 컨트롤러 유무에
    // 걸어 두면(예전 `if (controller == null) return;`) 스타일 로드 전에 건물을
    // 탭한 사용자에게 아무 반응도 없다.
    final controller = _mapController;
    if (controller != null) {
      // fillColor를 매번 함께 넘긴다 — 빼면 검정으로 되돌아간다
      // (indoor_overlay_layers.dart 상단 주석 참고).
      await controller.setLayerProperties(
        _buildingFillLayerId,
        buildingFillProps(_buildingFillOpacityPressed),
      );
      await Future<void>.delayed(
        const Duration(milliseconds: _buildingPressedHoldMs),
      );
      if (!mounted) return;
      await controller.setLayerProperties(
        _buildingFillLayerId,
        buildingFillProps(_buildingFillOpacityDefault),
      );
    }
    _triggerIndoorEntry(explicit: true);
  }

  /// 실내 진입 트리거 — 건물 탭·줌 임계값 초과·GPS 근접 감지 중 하나로 호출.
  /// 화면 모드는 바꾸지 않고 야외 지도 위에 얹는 실내 UI 오버레이만 켠다.
  /// 사용자가 축소해 임계값 아래로 내려가면 [_handleCameraIdle]이 오버레이를
  /// 다시 끄고 트리거를 재무장한다.
  ///
  /// [explicit]는 사용자가 건물 폴리곤을 **직접 탭**한 경우다. 이때는
  /// [_autoIndoorEntryArmed]를 무시한다. 무장 플래그는 "같은 줌에서 자동 진입이
  /// 반복 발화하지 않게" 하려고 있는 것이라, 명시적 탭까지 막으면 건물 밖을 탭해
  /// 야외로 나온 사용자가 같은 줌에서 건물을 다시 탭해도 들어갈 수 없게 된다.
  void _triggerIndoorEntry({bool explicit = false}) {
    if (!explicit && !_autoIndoorEntryArmed) return;
    _autoIndoorEntryArmed = false;
    if (_indoorEntered) return;
    _setIndoorEntered(true);
  }

  /// 실내 모드에서 건물 바깥 야외 지도를 탭했을 때의 이탈.
  ///
  /// 재무장([_autoIndoorEntryArmed])은 **하지 않는다.** 탭으로 나온 시점의 줌은
  /// 보통 진입 임계값 위이므로, 재무장하면 다음 카메라 정지에서 곧바로 다시
  /// 실내로 끌려 들어가 "나갈 수 없는" 상태가 된다. 다시 들어오는 경로는 두
  /// 가지가 열려 있다 — 건물을 직접 탭하거나(위 [_triggerIndoorEntry]의
  /// `explicit`), 이탈 임계값 아래로 축소했다가 다시 확대하는 것.
  void _exitIndoorByOutsideTap() {
    // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
    // (배치 대기 중인 탭은 위에서 이미 소비되므로 방어적 처리다.)
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _setIndoorEntered(false);
  }

  /// [_indoorEntered] 상태 변경을 한 곳으로 모은 헬퍼. setState + 상위 콜백 통지에
  /// 더해 dim scrim의 fillOpacity도 함께 갱신해, 실내 진입/이탈에 스포트라이트
  /// 효과가 즉시 반영되게 한다.
  void _setIndoorEntered(bool value) {
    if (_indoorEntered == value) return;
    setState(() => _indoorEntered = value);
    widget.onIndoorEnteredChanged?.call(value);
    // 실내로 들어가면 GPS 구독을 끊고 마커를 지운다. 다시 나가면 재구독한다.
    _syncGpsSubscription();
    _syncDimScrimLayer();
    // 외곽선은 실내 진입 상태에서만 그린다 — 이탈하면 여기서 소스가 비워진다.
    unawaited(_syncFloorOutlineLayer());
    // 진입/이탈로 페이드 구간 자체가 바뀌므로 이미 붙어 있는 오버레이 레이어의
    // opacity 표현식도 함께 갈아 끼운다.
    unawaited(_syncIndoorOverlayFade());
  }

  /// 지금 화면 폭에서 쓸 실내 진입 임계값.
  ///
  /// 고정값 [indoorEntryZoomThreshold]는 화면이 좁을수록 "더 깊이 확대해야
  /// 닿는" 값이라, 폰에서는 건물이 화면 밖으로 넘칠 때까지 확대해야 진입이
  /// 발화했다. 근거와 보정식은 [indoorEntryZoomThresholdFor] 참고.
  ///
  /// 확대 진입 판정([_handleCameraIdle])과 건물 포커스
  /// ([_recenterOnBuildingIfNeeded])가 **같은 값을 봐야 한다.** 둘이 어긋나면
  /// 포커스가 맞춰 준 zoom이 진입 임계값에 못 미쳐, 건물로 포커스는 됐는데
  /// 정작 실내로는 들어가지 않는 상태가 만들어진다.
  double _entryZoomThreshold() {
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) {
      return indoorEntryZoomThreshold;
    }
    return indoorEntryZoomThresholdFor(
      buildingWidthMeters: polygonWidthMeters(footprint),
      // 이 화면의 지도는 Stack을 꽉 채우고, MapShellScreen도 Scaffold body
      // 전체를 내주므로 지도 폭 == 화면 폭이다.
      viewportWidthPx: MediaQuery.sizeOf(context).width,
      latitude: _buildingCenter(footprint)?.latitude ?? referenceLatitude,
    );
  }

  void _handleCameraIdle() {
    // 카메라 콜백은 위젯이 사라진 뒤에도 한 박자 늦게 도착할 수 있다.
    // _entryZoomThreshold가 context를 읽으므로 먼저 걸러낸다.
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null) return;
    // zoom과 target은 같은 CameraPosition에서 나오고 둘 다 non-nullable이므로,
    // 카메라를 받았다면 중심 좌표도 항상 있다.
    final camera = controller.cameraPosition;
    if (camera == null) return;
    // 확대만으로는 실내로 들어가지 않는다. 카메라 중심이 실내 도면이 있는 건물
    // 근처일 때만 진입을 허용한다 — 건물이 없는 지역을 확대했을 때 도면 없이
    // 층 선택기·위치 지정 버튼만 뜨는 것을 막는다.
    final buildingNearby = isIndoorBuildingNearCamera(
      camera: ll.LatLng(camera.target.latitude, camera.target.longitude),
      footprint: _buildingFootprint,
    );
    switch (indoorEntryTransitionForZoom(
      camera.zoom,
      buildingNearby: buildingNearby,
      entryZoom: _entryZoomThreshold(),
    )) {
      case IndoorEntryTransition.enter:
        _triggerIndoorEntry();
      case IndoorEntryTransition.exit:
        // 사용자가 건물을 벗어날 만큼 축소했으므로 오버레이를 접고 다음 확대에서
        // 재발화할 수 있게 무장한다. 배치 대기 중이면 종료해 하단 바 표시도 함께
        // 초기화한다.
        _autoIndoorEntryArmed = true;
        if (_indoorEntered) {
          if (_placingPdrAnchor) _setPlacingAnchor(false);
          _setIndoorEntered(false);
        }
      case IndoorEntryTransition.keep:
        // 히스테리시스 밴드 — 현재 상태를 그대로 유지한다.
        break;
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
          // 예방한다. 근거는 indoorTilesMinZoom 정의 위 주석 참고.
          minzoom: indoorTilesMinZoom,
          // maxzoom 이상에서는 MapLibre가 maxzoom 타일을 over-scale해 그린다.
          // 백엔드의 mapbox_vector_tile.encode는 요청 zoom이 커질수록 tile 경계
          // 사각형도 미세해지는데(z=21이면 20m 남짓), 이 좁은 사각형을 4096 유닛에
          // quantize할 때 부동소수점 오차가 상대적으로 커져 사용자가 극한 확대를
          // 하면 도면이 잠깐 뒤틀린 것처럼 보이는 원인이 됐다. z=18을 상한으로
          // 잡으면 tile 경계가 ~150m로 충분히 넓어 quantize precision이 0.04m/유닛
          // 이라 어떤 확대 배율에서도 sub-pixel로 안정된다.
          maxzoom: indoorTilesMaxZoom,
        ),
      );
      // POI/시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록한다. 층을
      // 바꿔도 이미지는 그대로 재사용되므로 반복 렌더를 피한다.
      await _ensureFacilityIconImagesRegistered(controller);
      // 실내 도면은 확대에 따라 자연스럽게 나타나야 한다(Google Maps의 건물 내부
      // 표시와 같은 패턴). 페이드 구간은 진입 상태에 따라 달라지므로
      // [indoorOverlayFadeExpr]가 만들어 준다. zoom-interpolate 표현식이라
      // 카메라 이동 중에는 setLayerProperties 없이도 실시간으로 반영되고,
      // 진입/이탈로 구간 자체가 바뀔 때만 [_syncIndoorOverlayFade]가 갱신한다.
      final fadeExpr = _fadeExpr();
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
        indoorFootprintProps(fadeExpr),
        sourceLayer: 'footprint',
        belowLayerId: _routeCasingLayerId,
        enableInteraction: false,
      );
      await controller.addFillLayer(
        _indoorTilesSourceId,
        _indoorStoresFillLayerId,
        indoorStoresFillProps(fadeExpr),
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
        indoorVerticalTransportProps(fadeExpr),
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
        indoorStoresLabelProps(fadeExpr),
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
        indoorPoiIconProps(fadeExpr),
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
        indoorFacilityIconProps(fadeExpr),
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

  /// GPS 현재 위치 마커. 실내에서는 [_gpsTrackingWanted]가 false라 항상 빈
  /// 소스로 밀어 넣어 마커가 지도에서 사라진다 — [_syncGpsSubscription]이
  /// `_position`을 비우는 것과 이중으로 막아, 어느 경로로 들어와도 건물 안에서
  /// GPS 기반 위치가 보이지 않게 한다.
  Future<void> _syncCurrentLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) {
      _pendingCenterOnPosition = _gpsTrackingWanted && _position != null;
      return;
    }
    final pos = _gpsTrackingWanted ? _position : null;
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

  /// 실내 경로의 도착 노드에 물방울 핀을 찍는다.
  ///
  /// 핀을 찍는 좌표는 매장 중심(centroid)이 아니라 **경로의 마지막 점**이다 —
  /// 그래프 도착 노드는 매장 입구라 centroid와 몇 미터 어긋나고, 그 상태로
  /// centroid에 찍으면 경로선이 핀에 닿지 않고 끊긴 것처럼 보인다. 경로가 아직
  /// 계산되기 전 짧은 순간에는 경로가 없으므로 centroid로 폴백해 핀이 아예
  /// 안 보이는 구간을 만들지 않는다(실내 화면의 _destinationPinForCurrentFloor와
  /// 같은 규칙).
  ///
  /// 다층 경로에서는 **도착지 층을 보고 있을 때만** 찍는다. 중간 층은 지나가는
  /// 층이라 그 층 좌표에 도착 핀이 있으면 "여기가 목적지"로 잘못 읽힌다.
  Future<void> _syncIndoorDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final target = _indoorDestinationPinForActiveFloor();
    if (target == null) {
      await controller.setGeoJsonSource(
        _indoorDestSourceId,
        _emptyCollection(),
      );
      return;
    }
    await controller.setGeoJsonSource(
      _indoorDestSourceId,
      _collection([_pointFeature(target)]),
    );
  }

  ll.LatLng? _indoorDestinationPinForActiveFloor() {
    final destination = _indoorRouteDestination;
    if (destination == null) return null;
    final multi = _indoorMultiFloorRoute;
    if (multi != null) {
      if (multi.destinationSegment.floorName != _activeFloor) return null;
      final points = multi.destinationSegment.route.points;
      return points.isNotEmpty ? points.last : destination.point;
    }
    final segment = _indoorRouteSegment;
    if (segment != null && segment.points.isNotEmpty) return segment.points.last;
    // 단일 층 경로는 목적지 층에서만 그려진다. 층을 옮기면 _switchOverlayFloor가
    // 세그먼트를 비우므로, 그때는 목적지 층이 아닌 곳에 centroid 폴백 핀이
    // 남지 않도록 층을 직접 확인한다.
    return destination.floor == _activeFloor ? destination.point : null;
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

  /// 디버그 PDR 진단 소스·레이어를 한 번 등록한다. 색·굵기·점선은 실내 지도
  /// (floor_plan_view.dart)와 같은 값을 쓴다 — 근거는 소스 ID 정의 위 주석 참고.
  Future<void> _registerDebugPdrLayers(MapLibreMapController controller) async {
    await controller.addSource(
      _debugGraphSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _debugGraphSourceId,
      _debugGraphEdgeLayerId,
      const LineLayerProperties(
        lineColor: '#607D8B',
        lineWidth: 2,
        lineOpacity: 0.72,
        lineDasharray: [2, 1.5],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: ['==', ['get', 'kind'], 'edge'],
      enableInteraction: false,
    );
    // 현재 PDR이 올라타 있다고 판정된 간선만 굵은 청록으로 덧그린다.
    await controller.addLineLayer(
      _debugGraphSourceId,
      _debugGraphActiveEdgeLayerId,
      const LineLayerProperties(
        lineColor: '#00ACC1',
        lineWidth: 5,
        lineOpacity: 0.88,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        'all',
        ['==', ['get', 'kind'], 'edge'],
        ['==', ['get', 'active'], true],
      ],
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _debugGraphSourceId,
      _debugGraphNodeLayerId,
      const CircleLayerProperties(
        circleRadius: 4,
        circleColor: '#FFFFFF',
        circleStrokeColor: '#455A64',
        circleStrokeWidth: 2,
      ),
      filter: ['==', ['get', 'kind'], 'node'],
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _debugGraphSourceId,
      _debugGraphActiveNodeLayerId,
      const CircleLayerProperties(
        circleRadius: 6,
        circleColor: '#00ACC1',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
      filter: [
        'all',
        ['==', ['get', 'kind'], 'node'],
        ['==', ['get', 'active'], true],
      ],
      enableInteraction: false,
    );

    // raw: 걸음 추정이 만든 날것의 궤적. 점선이라 확정 경로와 겹쳐도 구분된다.
    await controller.addSource(
      _pdrRawTrailSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _pdrRawTrailSourceId,
      _pdrRawTrailLayerId,
      const LineLayerProperties(
        lineColor: '#F57C00',
        lineWidth: 3.25,
        lineOpacity: 0.95,
        lineDasharray: [1.5, 1.5],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    // confirmed: 확정된 걸음만. 흰 casing을 깔아 어두운 배경에서도 읽힌다.
    await controller.addSource(
      _pdrConfirmedTrailSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _pdrConfirmedTrailSourceId,
      _pdrConfirmedTrailCasingLayerId,
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 6.25,
        lineOpacity: 0.82,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _pdrConfirmedTrailSourceId,
      _pdrConfirmedTrailLayerId,
      const LineLayerProperties(
        lineColor: '#2E7D32',
        lineWidth: 3.25,
        lineOpacity: 0.96,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    // matched: confirmed를 통행 그래프에 스냅한 결과. 셋이 갈라지는 지점이
    // 어느 단계에서 틀어졌는지를 가리킨다.
    await controller.addSource(
      _pdrMatchedTrailSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _pdrMatchedTrailSourceId,
      _pdrMatchedTrailCasingLayerId,
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 6.5,
        lineOpacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _pdrMatchedTrailSourceId,
      _pdrMatchedTrailLayerId,
      const LineLayerProperties(
        lineColor: '#7E57C2',
        lineWidth: 3.25,
        lineOpacity: 0.96,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
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

  /// PDR 스냅샷의 층 로컬 좌표 경로들. 실내 지도와 같은 계산을 쓴다 — 두
  /// 화면이 다른 값을 그리면 진단이 서로를 반박하게 된다.
  ///
  /// 앵커가 없거나 지금 보고 있는 층과 다른 층에 찍혀 있으면 빈 경로다.
  /// 층을 바꾸면 그 층 경로만 보여야 하기 때문이다.
  List<PdrLocalPoint> get _pdrConfirmedFloorPath {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    final graph = _floorGraph;
    if (snapshot == null ||
        anchor == null ||
        anchor.floorId != _activeFloor ||
        graph == null ||
        graph.nodes.isEmpty) {
      return const [];
    }
    final pdrToFloor = FloorCoordinateTransform(anchor);
    return snapshot.path.map(pdrToFloor.toFloor).toList(growable: false);
  }

  /// 확정 전 미리보기(preview)까지 포함한 날것의 궤적.
  List<PdrLocalPoint> get _pdrRawFloorPath {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    final graph = _floorGraph;
    if (snapshot == null ||
        anchor == null ||
        anchor.floorId != _activeFloor ||
        graph == null ||
        graph.nodes.isEmpty) {
      return const [];
    }
    final pdrToFloor = FloorCoordinateTransform(anchor);
    return snapshot.preview.path
        .map(pdrToFloor.toFloor)
        .toList(growable: false);
  }

  /// confirmed 경로를 통행 간선에 스냅한 결과. 단순 스냅 점을 직선으로 잇지
  /// 않고 간선이 바뀌는 구간은 그래프 경로로 펼친다(matchRoutedPath).
  List<PdrLocalPoint> get _pdrMatchedFloorPath {
    final graph = _floorGraph;
    final confirmed = _pdrConfirmedFloorPath;
    if (graph == null || confirmed.isEmpty) return const [];
    return FloorMapMatcher(graph).matchRoutedPath(confirmed);
  }

  /// PDR이 올라타 있다고 판정된 간선들. 세션 시작 직후 원점 하나만 투영돼
  /// 아직 걷지도 않은 간선이 강조되는 것을 막으려고 실제 이동이 생긴 뒤에만
  /// 채운다.
  Set<String> get _pdrMatchedEdgeIds {
    final graph = _floorGraph;
    final confirmed = _pdrConfirmedFloorPath;
    if (graph == null || !_hasMeaningfulPdrMovement(confirmed)) return const {};
    return FloorMapMatcher(
      graph,
    ).matchPath(confirmed).map((point) => point.edgeId).toSet();
  }

  /// 세션 시작 직후에는 원점 한 개만 가장 가까운 간선에 투영되면서, 아직 걷지도
  /// 않았는데 그 간선 전체가 청록색으로 강조될 수 있다. 실내 지도와 같은 기준
  /// (누적 이동 0.2 m)을 쓴다 — 두 화면이 다른 기준을 쓰면 같은 세션에서 활성
  /// 간선이 한쪽에만 뜬다.
  bool _hasMeaningfulPdrMovement(List<PdrLocalPoint> path) {
    if (path.length < 2) return false;
    var distanceM = 0.0;
    for (var index = 1; index < path.length; index++) {
      final dx = path[index].eastM - path[index - 1].eastM;
      final dy = path[index].northM - path[index - 1].northM;
      distanceM += math.sqrt(dx * dx + dy * dy);
      if (distanceM >= 0.2) return true;
    }
    return false;
  }

  List<ll.LatLng> _floorPathToWgs84(List<PdrLocalPoint> path) {
    final graph = _floorGraph;
    if (graph == null || path.isEmpty) return const [];
    final floorToWgs84 = fitFloorGeoTransform(graph.nodes);
    return path
        .map((point) {
          final wgs84 = floorToWgs84.apply(point.eastM, point.northM);
          return ll.LatLng(wgs84.$1, wgs84.$2);
        })
        .toList(growable: false);
  }

  /// 디버그 모드의 PDR 진단 레이어(그래프 노드·간선 + 세 경로)를 갱신한다.
  ///
  /// 디버그 모드가 꺼져 있거나 개별 토글이 꺼져 있으면 해당 소스를 비운다 —
  /// 레이어를 지웠다 다시 만들지 않고 데이터만 비우는 편이 층 전환·스타일
  /// 재로드와 경쟁하지 않아 안전하다.
  Future<void> _syncDebugPdrLayers() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final debug = _debugModeController;
    final on = debug.enabled;

    // 그래프 노드·간선은 실내 지도와 같은 공용 변환기를 쓴다. 직접 from→to
    // 직선을 긋지 않는 것이 중요하다 — 간선에 geometryLocalM(꺾인 복도)이 있으면
    // 그 형상을 따라야 하고, 활성 간선에 물린 노드도 함께 강조돼야 한다.
    final overlay = on
        ? buildDebugMapOverlay(
            _floorGraph,
            showNodes: debug.showGraphNodes,
            showEdges: debug.showGraphEdges,
            activeEdgeIds: _pdrMatchedEdgeIds,
          )
        : const DebugMapOverlay();
    final features = <Map<String, dynamic>>[
      for (final edge in overlay.edges)
        {
          'type': 'Feature',
          'properties': {'kind': 'edge', 'active': edge.active},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final p in edge.points) [p.longitude, p.latitude],
            ],
          },
        },
      for (final node in overlay.nodes)
        {
          'type': 'Feature',
          'properties': {'kind': 'node', 'active': node.active},
          'geometry': {
            'type': 'Point',
            'coordinates': [node.position.longitude, node.position.latitude],
          },
        },
    ];
    await controller.setGeoJsonSource(
      _debugGraphSourceId,
      _collection(features),
    );

    await _setTrail(
      controller,
      _pdrRawTrailSourceId,
      on && debug.showRawPdrPath ? _floorPathToWgs84(_pdrRawFloorPath) : const [],
    );
    await _setTrail(
      controller,
      _pdrConfirmedTrailSourceId,
      on && debug.showConfirmedPdrPath
          ? _floorPathToWgs84(_pdrConfirmedFloorPath)
          : const [],
    );
    await _setTrail(
      controller,
      _pdrMatchedTrailSourceId,
      on && debug.showMapMatchedPdrPath
          ? _floorPathToWgs84(_pdrMatchedFloorPath)
          : const [],
    );
  }

  /// 점 2개 미만이면 LineString이 성립하지 않아 소스를 비운다.
  Future<void> _setTrail(
    MapLibreMapController controller,
    String sourceId,
    List<ll.LatLng> points,
  ) async {
    await controller.setGeoJsonSource(
      sourceId,
      points.length < 2 ? _emptyCollection() : _collection([_lineFeature(points)]),
    );
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
      _autoIndoorEntryArmed = false;
      _setIndoorEntered(true);
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

  /// 디버그 모드의 "PDR 시작/종료" 버튼. 실내 지도 탭의 _togglePdr와 같은
  /// 계약이다 — 시작하면 이번 세션 기록기를 새로 열고 앵커 배치 대기로 넘기며,
  /// 종료하면 마지막 스냅샷까지 기록한 뒤 JSON 내보내기를 안내한다.
  ///
  /// 야외에서는 "활성 층"이 층 chip으로 정해지므로, 사용자가 지금 보고 있는
  /// 층의 그래프가 없으면(타일만 있고 navigation_graph가 없는 층) 시작하지
  /// 않는다 — 그래프가 없으면 PDR 좌표를 층 좌표로 옮길 수 없어 측정이
  /// 무의미하다.
  Future<void> _togglePdr() async {
    final floor = _activeFloor;
    final graph = _floorGraph;
    if (indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle) {
      final recorder = _pdrDebugRecorder;
      final snapshot = indoorNavigationDriver.currentSnapshot;
      if (snapshot != null) recorder?.recordSnapshot(snapshot);
      await indoorNavigationDriver.stopGuidance();
      recorder?.recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
      if (!mounted) return;
      _setPlacingAnchor(false);
      if (recorder?.hasSnapshot ?? false) {
        _showPdrMessageWithExport('PDR 세션이 종료됐습니다. JSON으로 내보내 분석할 수 있습니다.');
      }
      return;
    }
    if (floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      _showSnack('이 층은 PDR 좌표 변환용 navigation graph가 아직 없습니다.');
      return;
    }
    setState(() => _pdrTrailState.beginNewSession());
    _pdrDebugRecorder = PdrDebugSessionRecorder()
      ..recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    await indoorNavigationDriver.startGuidance(floorId: floor);
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    if (!mounted) return;
    _setPlacingAnchor(true);
    _showSnack('현재 서 있는 위치를 지도에서 한 번 탭해 PDR 시작점을 맞춰주세요.');
  }

  void _showPdrMessageWithExport(String message) {
    if (!mounted) return;
    showDebugToast(
      context,
      message: message,
      bottomOffset:
          _mapShellBottomChromePx +
          (_hasAnyRouteVisible ? _etaCardHeightPx : 0) +
          12,
      actionLabel: 'JSON 공유',
      onAction: () => unawaited(_exportPdrDebugJson()),
    );
  }

  Future<void> _exportPdrDebugJson() async {
    final recorder = _pdrDebugRecorder;
    if (recorder == null || !recorder.hasSnapshot || _exportingPdrDebugJson) {
      _showSnack('내보낼 PDR 세션이 없습니다.');
      return;
    }
    setState(() => _exportingPdrDebugJson = true);
    try {
      final device = await PdrDebugDeviceInfo.load();
      final session = recorder.buildJson(
        buildingId: _building?.id ?? demoBuildingId,
        selectedFloor: _activeFloor,
        mapCalibrationVersion: _mapCalibrationVersion,
        graph: _floorGraph,
        device: device,
      );
      await const PdrDebugSessionShare().share(
        session,
        sharePositionOrigin: _pdrSharePositionOrigin(),
      );
    } on Object catch (error) {
      if (mounted) _showSnack('PDR JSON을 내보내지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _exportingPdrDebugJson = false);
    }
  }

  /// iOS 공유 시트는 popover 기준 사각형이 필요하다. 전달하지 않으면
  /// share_plus가 `{0, 0, 0, 0}`을 보내 iOS에서 공유를 거부한다.
  Rect? _pdrSharePositionOrigin() {
    final box =
        _pdrShareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && !box.size.isEmpty) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  /// [localPoint]가 지도 위 Flutter 오버레이(PDR 제어·디버그 설정) 영역이면
  /// true. 인자는 MapLibre가 준 지도 위젯 로컬 좌표라 전역 좌표로 바꿔 비교한다.
  bool _isTapOnMapOverlay(Offset localPoint) {
    final mapBox = context.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.attached) return false;
    final globalPoint = mapBox.localToGlobal(localPoint);
    for (final key in [
      _pdrControlKey,
      _debugModeSettingsKey,
      _placingHintKey,
    ]) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if ((box.localToGlobal(Offset.zero) & box.size).contains(globalPoint)) {
        return true;
      }
    }
    return false;
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
    unawaited(_syncDebugPdrLayers());
    // 배치가 끝났다는 안내는 따로 띄우지 않는다. 지도에 위치 마커가 바로
    // 찍히고 안내 배너가 사라지는 것으로 이미 결과가 보이는데, 토스트까지
    // 겹치면 방금 지정한 지점을 가린다.
  }

  /// 안내 오른쪽 상단 X — 위치 지정을 취소한다.
  ///
  /// 배치 대기만 끄는 게 아니라 PDR 세션까지 함께 멈춘다.
  /// [startLocationPlacement]가 idle이던 세션을 켠 뒤 대기로 넘기므로, 대기만
  /// 끄면 센서는 계속 돌면서 앵커 없는 세션이 남는다(실내 화면의 동명 함수와
  /// 같은 계약).
  Future<void> _cancelPdrAnchor() async {
    if (!_placingPdrAnchor) return;
    await indoorNavigationDriver.stopGuidance();
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    if (mounted) _setPlacingAnchor(false);
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
    // GPS를 쓰지 않는 실내 상태에서는 신호 품질 배지도 띄우지 않는다. 위치가
    // 비어 있다는 이유로 "GPS 신호 약함"이 뜨면, 실내에서 GPS를 기다리는 중인
    // 것처럼 읽혀 실제 동작(PDR 기반)과 어긋난다.
    final lowAccuracy = _gpsTrackingWanted &&
        (position == null || accuracy > _lowAccuracyThresholdMeters);
    final route = _route;
    final userDestination = _userDestination;
    final indoorRouteDestination = _indoorRouteDestination;
    final indoorRouteVisible = _hasAnyRouteVisible;
    final debugEnabled = _debugModeController.enabled;
    final pdrActive =
        indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle;
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

        // 실내 진입 시 야외만 어둡게 덮는 dim scrim은 위젯 트리가 아니라
        // MapLibre fill 레이어(_dimScrimFillLayerId)로 처리한다. 위젯 스크림은
        // PlatformView 위에 얹혀 야외 base와 실내 MVT 오버레이를 한꺼번에 덮어
        // 실내까지 어두워지는 문제가 있었다. 지금은 세계를 덮는 outer ring +
        // 건물 footprint를 hole로 뚫은 폴리곤을 스크림 레이어로 그리고, 실내
        // 오버레이 아래에 삽입해 건물 안쪽만 밝게 스포트라이트된다.

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

        // PDR 제어 — 실내 지도 탭과 같은 자리(하단 홈/실내 세그먼트 왼쪽,
        // 층 선택기 옆)에 같은 위젯으로 놓는다. 두 화면에서 버튼이 옮겨 다니면
        // 실측 중에 "지금 어느 화면인지"를 먼저 확인해야 해서 테스트가 끊긴다.
        //
        // 노출 조건에 pdrActive를 함께 두는 이유: 세션이 도는 중에 사용자가
        // 지도를 축소하면 _handleCameraIdle이 실내 진입 오버레이를 끄는데,
        // 그때 버튼까지 사라지면 센서는 계속 돌면서 종료·내보내기 수단이
        // 없어진다. 진행 중인 세션은 언제나 끌 수 있어야 한다.
        if (debugEnabled && (_indoorEntered || pdrActive))
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            right: _pdrControlRightInsetPx,
            bottom: indoorRouteVisible ? _bottomBarLiftPx : 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: _bottomBarInnerBottomPaddingPx,
                ),
                child: PdrMapControl(
                  key: _pdrControlKey,
                  active: pdrActive,
                  onPressed: () => unawaited(_togglePdr()),
                  canExport:
                      !pdrActive && (_pdrDebugRecorder?.hasSnapshot ?? false),
                  exporting: _exportingPdrDebugJson,
                  onExport: () => unawaited(_exportPdrDebugJson()),
                  shareButtonKey: _pdrShareButtonKey,
                ),
              ),
            ),
          ),

        // 디버그 설정 진입점도 실내 탭과 같은 왼쪽 하단에 둔다. 야외에서
        // 실내로 진입한 상태에서만 노출해 일반 야외 지도 화면은 그대로 둔다.
        if (_indoorEntered)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 12,
            bottom: indoorRouteVisible ? _bottomBarLiftPx : 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: _bottomBarInnerBottomPaddingPx,
                ),
                child: DebugModeSettingsButton(
                  key: _debugModeSettingsKey,
                  controller: _debugModeController,
                  onPressed: () =>
                      showDebugModeSettingsSheet(context, _debugModeController),
                ),
              ),
            ),
          ),

        if (_indoorEntered && _placingPdrAnchor)
          Positioned(
            top: _placingHintTopPx,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: _PlacingAnchorHint(
                key: _placingHintKey,
                onCancel: () => unawaited(_cancelPdrAnchor()),
              ),
            ),
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

/// PDR 앵커 배치 대기 중임을 상단에 짧게 알려주는 배지. 하단 바 버튼의 활성
/// 톤과 함께 사용자에게 "지금 지도 탭이 다음 액션을 소비한다"는 상태를 전한다.
///
/// 배치 대기는 지도 탭을 통째로 가져가는 상태라(건물 진입·매장 선택이 모두
/// 막힌다) **빠져나올 길이 안내 안에 있어야 한다.** 예전에는 축소해 실내
/// 오버레이를 접거나 세그먼트를 옮기는 우회로밖에 없었다.
class _PlacingAnchorHint extends StatelessWidget {
  const _PlacingAnchorHint({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.indoor,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          // X는 문구 오른쪽 **상단**에 고정한다. 좁은 화면에서 문구가 두 줄로
          // 접혀도 취소 버튼이 세로 중앙으로 밀려나지 않아, 눌러야 할 자리가
          // 문구 길이에 따라 흔들리지 않는다.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Icon(Icons.touch_app, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '지도를 탭해 현재 서 있는 위치를 지정해주세요',
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _HintCancelButton(onPressed: onCancel, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// 안내 배너 오른쪽 상단의 취소(X).
///
/// Material `IconButton`을 쓰지 않는 이유: 기본 최소 탭 영역이 48x48이라
/// 한 줄짜리 안내 pill 높이를 두 배 이상으로 늘려 카테고리 chip 열까지
/// 밀어 올린다. 여기서는 26x26으로 줄이되 아이콘보다 넓은 탭 영역은 남긴다.
class _HintCancelButton extends StatelessWidget {
  const _HintCancelButton({required this.onPressed, required this.color});

  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '위치 지정 취소',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Center(
            child: Icon(Icons.close_rounded, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

