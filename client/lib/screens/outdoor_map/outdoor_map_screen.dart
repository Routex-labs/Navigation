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
import '../../core/floor_switch_progress.dart';
import '../../core/map_palette.dart';
import '../../core/map_picked_point.dart';
import '../../core/service_locator.dart';
import '../../core/tile_url.dart';
import '../../domain/building_entrances.dart';
import '../../domain/geo_transform.dart';
import '../../domain/guidance_chrome.dart';
import '../../features/debug_mode/debug_mode.dart';
import '../../domain/dijkstra.dart';
import '../../domain/route_endpoint_fill.dart';
import '../../domain/route_guidance.dart';
import '../../features/indoor_navigation/application/corridor_position_tracker.dart';
import '../../features/indoor_navigation/application/escalator_arrival.dart';
import '../../features/indoor_navigation/application/escalator_node_naming.dart';
import '../../features/indoor_navigation/application/escalator_transition_detector.dart';
import '../../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../../features/indoor_navigation/application/floor_map_matcher.dart';
import '../../features/indoor_navigation/application/indoor_guidance_position.dart';
import '../../features/indoor_navigation/application/indoor_guidance_session.dart';
import '../../features/indoor_navigation/application/indoor_location_estimate.dart';
import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';
import '../../features/indoor_navigation/debug/pdr_debug_device_info.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_share.dart';
import '../../domain/multi_floor_router.dart';
import '../../domain/transfer_route_geometry.dart';
import '../../models/building.dart';
import '../../models/building_graph.dart';
import '../../models/directions_route.dart';
import '../../models/floor_graph.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../models/transit_route.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eta_card.dart';
import '../../widgets/transit_summary_card.dart';
import '../../widgets/transit_style.dart';
import '../../models/store_index_entry.dart';
import '../../widgets/floor_camera_bounds.dart';
import '../../core/map_route_style.dart';
import '../../widgets/destination_pin.dart';
import '../../widgets/category_map_filter.dart';
import '../../widgets/category_map_icon.dart';
import '../../widgets/floor_facility_style.dart';
import '../../widgets/floor_selector.dart';
import '../../widgets/floor_switch_escalator_motif.dart';
import '../../widgets/guidance_recenter_button.dart';
import '../../widgets/route_steps_sheet.dart';
import '../../widgets/map_icon_cache.dart';
import '../../widgets/map_overlay_tap_guard.dart';
import '../../widgets/status_badge.dart';
import 'floor_outline.dart';
import 'indoor_entry_gps.dart';
import 'building_orientation.dart';
import 'indoor_entry_proximity.dart';
import 'indoor_entry_zoom.dart';
import 'route_recompute_policy.dart';
import 'indoor_overlay_layers.dart';

// 위치 조회 실패 시 대체 좌표 (서울시청). 저장·전달은 latlong2 타입으로 하고
// MapLibre API에 넘길 때만 [_toGl]로 변환한다 — 이 파일 외부(Building.entrance,
// DirectionsRoute.points)가 latlong2를 쓰고 있어 그 타입을 저장 형식으로 유지한다.
const _fallbackLocation = ll.LatLng(37.5665, 126.9780);
// 'GPS 신호 약함' 배지 임계값.
//
// 진입 판정이 쓰는 [decisiveAccuracyMeters](20 m)보다 느슨하다. 배지는 "이 좌표를
// 믿지 말라"는 경고이고 판정은 "이 좌표로 결론을 내도 되는가"라, 후자가 더
// 엄격한 것이 맞다 — 20~30 m 구간에서는 배지 없이 판정만 보류한다.
const _lowAccuracyThresholdMeters = 30.0;
// 실내 경로 ETA 분 계산에 쓰는 평균 걷기 속도. 실내 화면 상수와 일치시켜야
// 같은 목적지 라우팅에서 두 화면 사이 표시가 어긋나지 않는다.
const _indoorWalkingSpeedMetersPerSecond = 1.2;

// 건물 진입/이탈 판정 정책은 indoor_entry_gps.dart가 소유한다. 임계값과 그 근거,
// "왜 직전 값 대비 비율이 아닌가"는 전부 그쪽 주석에 있다.

// 자동 진입 직후 입구를 기준으로 실내 위치(PDR 앵커)를 잡을 때, 입구 좌표에서
// 통행 그래프까지 허용하는 최대 거리(m).
//
// 사용자가 손으로 찍는 경우(_maxPdrAnchorSnapDistanceM, 40 m)보다 좁게 잡는다.
// 그쪽은 "화면에서 건물이 작게 보여 탭이 빗나가는" 오차를 감싸야 하지만, 여기서
// 비교하는 두 좌표는 백엔드가 내려준 입구와 같은 백엔드가 내려준 통행 그래프라
// 둘이 크게 벌어졌다면 그건 손 떨림이 아니라 **데이터 정합이 깨진 상태**다.
// 그런 상태에서 억지로 스냅하면 건물 반대편 복도에 위치를 찍어 놓고 거기서부터
// 걸음을 쌓는다 — 위치가 없는 것보다 나쁘다.
// 자동차 안내를 시작할 때 현재 위치로 내려가며 맞추는 zoom. 다음 교차로가
// 화면에 들어오는 정도이고, 실내 진입 임계값 위라 건물 근처에서 눌러도 도면이
// 끼어들지 않는다.
const _carGuidanceZoom = 17.5;

const _maxEntranceAnchorSnapDistanceM = 25.0;

// 자동 진입 때 GPS 좌표를 통로에 붙일 수 있는 최대 거리(m).
//
// 문 폴백([_maxEntranceAnchorSnapDistanceM])보다 조인다. 문은 "여기로 들어왔다"가
// 확실한 지점이지만 GPS 좌표는 오차 반경을 달고 오므로, 통로에서 멀면 매장
// 한가운데를 가리키고 있을 가능성이 크다. 그때는 억지로 붙이지 않고 문으로
// 떨어지는 편이 낫다.
const _maxIndoorGpsSnapDistanceM = 15.0;

// 자동 앵커를 확정하기 전에 센서 세션의 첫 보고를 기다리는 최대 시간.
// 근거는 [_awaitSensorWarmup] 주석 참고.
const _sensorWarmupTimeout = Duration(seconds: 2);

// GPS course(진행 방향)를 신뢰할 수 있다고 보는 최소 속도(m/s). 이보다 느리면
// 플랫폼이 채워 넣는 0°를 "정북으로 걸어 들어왔다"로 오독하게 된다.
const _entryCourseMinSpeedMps = 0.5;

// 검색 결과에서 고른 야외 장소로 옮길 때의 zoom. 건물 하나가 화면에 들어오는
// 정도이고, 실내 진입 임계보다 낮게 둬 위치만 확인하는 이동이 실내 진입으로
// 읽히지 않게 한다.
const _poiFocusZoom = 17.0;

// TMAP POI 좌표가 이만큼 안에 있으면 그 건물의 가게로 본다.
//
// 엄격한 폴리곤 판정으로는 안 된다 — TMAP이 주는 좌표는 대표점이 아니라
// **도로에서 들어오는 접근점**(frontLat/frontLon)이라 백화점 입점 매장도
// 건물 벽 바깥 인도에 찍힌다. 여유가 남의 가게를 삼킬 여지는 좁다. 이 판정만으로
// 두 줄을 합치는 것이 아니라 브랜드 이름까지 맞아야 하기 때문이다.
const _poiBuildingProximityMeters = 40.0;

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
// 카테고리 필터로 고른 매장만 파란톤으로 덧칠하는 fill. 일반 매장 fill 위,
// 수직이동 오버레이 아래에 넣어 실내 화면(_categoryHighlightFillLayerId)과
// 레이어 순서를 맞춘다 — 순서가 어긋나면 같은 선택인데 두 화면에서 강조가
// 다른 것에 가려진다.
const _indoorCategoryHighlightFillLayerIdBase =
    'outdoor-indoor-category-highlight-fill';
// 수직이동(에스컬레이터/엘리베이터) 구조물 폴리곤을 초록톤으로 덧칠하는 fill.
// _indoorStoresFillLayerIdBase 위, 라벨/아이콘보다 아래에 삽입해 초록 배경 + 라벨/
// 아이콘이 한 덩어리로 읽히게 한다. 실내 화면의 _verticalTransportFillLayerId와
// 시각 언어를 맞춘다.
const _indoorVerticalTransportFillLayerIdBase =
    'outdoor-indoor-vertical-transport-fill';
const _indoorStoresLabelLayerIdBase = 'outdoor-indoor-stores-label';
// 편의시설(화장실·정수기 등)의 텍스트 전용 라벨. 매장명 라벨에는 대분류 아이콘이
// 붙는데, 시설은 이미 전용 아이콘 레이어가 있어 두 아이콘이 겹친다. 그래서 이름만
// 따로 그린다(실내 화면의 floor-store-facility-label과 같은 이유).
const _indoorFacilityLabelLayerIdBase = 'outdoor-indoor-store-facility-label';
// POI(엘리베이터·에스컬레이터·화장실 등 `pois` 소스 레이어) 위 아이콘 심볼과
// `stores` 소스 레이어에 이름으로 매칭되는 편의시설(화장실·정수기·수유실 등)
// 위 아이콘 심볼. 실내 화면과 같은 아이콘/색을 써 두 화면 사이에서 위치를
// 이어보아도 시설 표기가 흔들리지 않는다.
const _indoorPoiIconLayerIdBase = 'outdoor-indoor-pois-icon';
const _indoorStoreFacilityIconLayerIdBase =
    'outdoor-indoor-store-facility-icons';
const _routeSourceId = 'outdoor-route';
const _transferRouteSourceId = 'outdoor-transfer-route';
const _transferRouteLayerId = 'outdoor-transfer-route-line';
const _routeCasingLayerId = 'outdoor-route-casing';
const _routeLineLayerId = 'outdoor-route-line';
// 진행 방향 화살표. 본선 위에 얹혀 선을 따라 흐른다.
const _routeWalkLayerId = 'outdoor-route-walk';
const _routeIndoorLayerId = 'outdoor-route-indoor';
const _routeArrowLayerId = 'outdoor-route-arrow';
// 대중교통 경로. 도보 경로와 소스를 나누는 이유는 **선의 성격이 다르기**
// 때문이다. 도보는 한 가지 색 한 줄이지만 대중교통은 구간마다 노선색이 다르고
// 도보 구간만 점선이라, 하나의 소스에 넣고 feature 속성으로 색·패턴을 갈라야
// 한다. 같은 소스를 쓰면 도보 안내가 켜질 때마다 이 선의 색 표현식까지 다시
// 계산되어, 안내를 바꿀 때 잠깐 엉뚱한 색으로 깜빡인다.
const _transitSourceId = 'outdoor-transit';
const _transitRideLayerId = 'outdoor-transit-ride';
const _transitWalkLayerId = 'outdoor-transit-walk';
// 구간 시작점에 얹는 수단 배지(도보·버스·지하철).
const _transitBadgeSourceId = 'outdoor-transit-badge';
const _transitBadgeLayerId = 'outdoor-transit-badge-icon';
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
// 도착 핀 비트맵의 addImage 등록 키. 실내 지도와 같은 도형을
// ([destination_pin.dart]) 공유하지만 등록 키는 화면마다 따로 둔다. 웹 addImage는
// 같은 이름이 이미 있으면 새 비트맵을 버리므로(위 _pdrLocationImageName 주석 참고)
// 디자인을 바꿀 땐 이름의 버전도 같이 올려야 살아 있는 지도에 반영된다.
// v3: "도착" 글씨를 비트맵에 구워 넣었다(심볼 텍스트에서 이동).
const _destinationPinImageName = 'outdoor-destination-pin-v3';
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
// 실내 오버레이에서 매장 폴리곤을 탭했을 때 그 매장 하나만 파란색으로 채우고
// 테두리를 두르는 전용 소스·레이어. 색은 앱의 선택 색(mapSelectionColor =
// AppColors.primary) 하나를 쓴다.
//
// **fill 0.16은 사실상 안 보였다.** 매장 바닥(#F1EEEA)이 밝은 회색이라 16%
// 파랑을 얹어도 "눌렀는데 아무 일도 안 일어난 것 같다"는 인상이었다. 0.35면
// 어느 매장을 골랐는지 한눈에 들어오고, 매장 이름은 흰 헤일로를 두르고 그 위
// 심볼 레이어에 찍히므로 여전히 읽힌다. 더 올리면 이름이 배경에 먹히기
// 시작하므로 여기가 상한에 가깝다.
const _highlightFillOpacity = 0.35;
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

/// 건물을 탭해 실내로 들어갈 때 카메라가 확대되는 시간.
///
/// 너무 빠르면(≤400ms) 한 번에 갈아 낀 것과 구분이 안 되고, 너무 느리면
/// (≥1.5s) 탭에 대한 반응이 굼떠 두 번 누르게 된다. 900ms면 확대되는 과정이
/// 눈에 남으면서도 기다린다는 느낌은 들지 않는다.
///
/// 반짝임([_buildingPressedHoldMs] 220ms)이 끝난 **뒤에** 시작하므로, 탭부터
/// 도면이 자리 잡기까지는 약 1.1초다.
const _indoorZoomInDuration = Duration(milliseconds: 900);

/// 층을 갈아탈 때 카메라가 새 층 외곽선에 다시 맞춰지는 시간.
///
/// 진입([_indoorZoomInDuration])보다 짧다. 진입은 "밖에서 안으로 들어간다"는
/// 큰 장면 전환이라 과정을 보여 줘야 하지만, 층 전환은 이미 같은 건물 안에서
/// 도면만 갈아 끼우는 것이라 같은 900ms를 쓰면 층을 훑을 때마다 지도가 느릿하게
/// 따라와 답답하다.
const _floorSwitchZoomDuration = Duration(milliseconds: 500);

/// 안내를 시작할 때 경로 전체를 담으러 물러서는 시간.
///
/// 진입(900ms)보다 짧고 층 전환(500ms)보다 길다. 진입만큼 큰 장면 전환은
/// 아니지만 "지금부터 이 길로 간다"를 읽을 시간은 줘야 한다.
const _routeOverviewDuration = Duration(milliseconds: 700);

/// 개요 연출을 하지 않는 경로 길이(m).
///
/// 바로 옆 매장이면 담을 것이 없다. 물러섰다 돌아오는 동작만 남아 화면이
/// 까닭 없이 출렁인다. 걷기 경로 쪽 [_fitCameraToRoute]의 5m 가드와 같은 취지다.
const _routeOverviewMinDistanceM = 5.0;

/// 경로 상자의 변 길이 하한(m).
///
/// **없으면 zoom이 발산한다.** 곧게 뻗은 복도 경로는 최소 넓이 상자의 짧은 변이
/// 0에 수렴하는데, [zoomToFitWidth]는 `log(가용폭 / 폭)`이라 폭이 0이면 무한대를
/// 돌려준다. 12m는 복도 폭 남짓이라, 곧은 경로도 양옆이 조금 보이는 배율에서
/// 멈춘다.
const _routeFitMinSideM = 12.0;

/// 경로 개요가 확대해 들어가는 상한.
///
/// 하한([_routeFitMinSideM])만으로는 짧은 세그먼트에서 배율이 지나치게
/// 올라간다 — 층 전환 직후 15m짜리 B1 세그먼트가 복도 하나만 꽉 채운 화면이
/// 됐다. 경로가 화면에 다 들어와도 **주변 매장 몇 개는 함께 보여야** 여기가
/// 어디인지 읽힌다. 타일이 더 세밀해지지 않는 상한(18)보다 반 단계 아래로
/// 잡아 짧은 경로에서도 맥락이 남게 한다.
const _routeFitMaxZoom = 17.5;

/// "내 위치로" 버튼이 되돌아가는 배율의 하한.
///
/// 개요 연출이 물러선 자리에서 누르면 이만큼 다시 당겨 온다. 실내 타일이 더
/// 세밀해지지 않는 상한([indoorTilesMaxZoom])을 그대로 쓴다 — 그 위로 확대해도
/// 도면은 같은 그림을 늘린 것뿐이다.
///
/// 이미 이보다 확대해 둔 사용자에게는 **적용하지 않는다.** 무언가를 들여다보려
/// 당겨 둔 배율을 버튼 한 번에 되돌리면, 위치로 돌아가는 대신 방금 보던 것을
/// 잃는다.
const _walkingViewZoom = indoorTilesMaxZoom;

/// "내 위치로" 카메라 이동 시간. 층 전환 재정렬(500ms)보다 짧다 — 사용자가 직접
/// 누른 조작이라 과정을 보여 줄 이유가 없고, 즉시 반응하는 편이 낫다.
const _recenterDuration = Duration(milliseconds: 300);

// 사람 조작 층 전환 크로스페이드의 근거·타이밍 정책(즉시 교체 임계, 페이드
// 길이, 에스컬레이터 모티프 임계)은 core/floor_switch_progress.dart가 단일
// 출처다.

/// 도면을 화면에 맞출 때 실제로 채우는 비율.
///
/// 1.0이면 외곽선이 화면 가장자리에 딱 붙는다 — 도면이 답답해 보이고 가장자리
/// 매장 라벨이 잘린다. 0.86이면 사방에 7%씩 남아, 건물이 어디서 끝나는지가
/// 보이면서도 도면은 충분히 크다.
const _floorFitFillRatio = 0.86;

/// 도면을 맞출 때 화면 위·아래에서 비워 두는 chrome 높이(논리 px).
///
/// 이걸 빼지 않으면 도면 한가운데가 화면 한가운데에 오는데, 위쪽은 검색창과
/// 카테고리 줄이 덮고 있어서 **도면 윗부분 매장이 칩에 가린다.** 아래 chrome이
/// 위보다 얇으므로, 가려지지 않는 띠의 한가운데로 도면을 내려 놓아야 한다.
const _floorFitTopChromePx = _placingHintTopPx;
const _floorFitBottomChromePx = _mapShellBottomChromePx;

/// 안내 중에 화면 위·아래에서 비워 두는 chrome 높이(논리 px).
///
/// **층 도면용 값([_floorFitTopChromePx])을 그대로 쓰면 안 된다.** 그 132는
/// 검색창 + 카테고리 칩 줄 기준인데, 안내가 시작되면 칩 줄은 통째로 접히고
/// (map_shell_screen의 `_guidanceActive` 분기) 상단 바도 도착지 한 줄로 줄어든다.
/// 없는 줄만큼 위를 비우면 경로가 필요 이상으로 화면 아래에 눌려 놓인다.
/// 132에서 칩 줄(높이 ≈32 + 간격 8)을 뺀 값이다.
///
/// 아래도 마찬가지다. 하단 바는 안내 중 아예 그려지지 않고([_guidanceActive])
/// ETA 카드만 화면 맨 아래에 도킹하므로, 카드 높이만 비우면 된다.
const _guidanceFitTopChromePx = 92.0;
const _guidanceFitBottomChromePx = _bottomBarLiftPx;

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

// 층 선택기와 하단 바 사이 baseline 계산에 쓰이는 MapBottomBar 내부 여백
// (map_bottom_bar.dart의 outer padding).
const _bottomBarInnerBottomPaddingPx = 14.0;
// pill 하단을 하단 바의 맨 아래 줄(홈/실내 세그먼트)과 같은 baseline에 앉힌다.
// 세그먼트는 우측, pill은 좌측이라 같은 줄에 내려도 겹치지 않는다. 실내 화면과
// 동일한 계산이어야 두 화면 사이 pill 위치가 어긋나지 않는다.
const _floorSelectorBottomOffset = _bottomBarInnerBottomPaddingPx;
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
// 실내 화면의 동명 상수(184)와 **일부러 다르다.** 홈에서는 카테고리 칩을 아예
// 노출하지 않기로 해서 여기 상단 오버레이는 장소 pill 한 줄뿐인 반면, 실내는
// 대분류·소분류·개수 안내까지 3단이라 그만큼 더 내려야 한다.
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

/// 경로선 feature 하나. [style]이 어느 레이어가 이 선을 그릴지 가른다 —
/// `drive`(실선·파랑), `walk`(점선·회색), `indoor`(실선·야외 본선과 같은 파랑).
Map<String, dynamic> _lineFeature(
  List<ll.LatLng> points, {
  String style = 'walk',
}) {
  return {
    'type': 'Feature',
    'properties': {'style': style},
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final p in points) [p.longitude, p.latitude],
      ],
    },
  };
}

Map<String, dynamic> _emptyCollection() => {
  'type': 'FeatureCollection',
  'features': const <Map<String, dynamic>>[],
};

Map<String, dynamic> _collection(List<Map<String, dynamic>> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

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
    this.onGuidanceDismissed,
    this.onGuidanceActiveChanged,
    this.onPlacingLocationChanged,
    this.onIndoorEnteredChanged,
    this.onStoreTap,
    this.onMapPointPicked,
    this.pickingOnMap = false,
    this.onLocationAnchored,
    this.categorySelection,
    this.onFloorChanged,
    this.onFloorTransitionChanged,
    this.outerOverlayKeys = const [],
  });

  /// 이 야외 지도가 지금 화면에 보이는지. [MapShellScreen]은 야외/실내를
  /// IndexedStack으로 겹쳐 두므로, 사용자가 실내 탭으로 넘어가도 이 위젯은
  /// 살아 있다. 알려주지 않으면 보이지도 않는 야외 지도가 GPS를 계속 구독한다 —
  /// 실내에 들어간 뒤에는 GPS를 쓰지 않는다는 규칙을 지키려면 이 값이 필요하다.
  final bool active;

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  /// 사용자가 **"안내 종료"를 눌러** 길안내를 끝냈을 때 호출된다.
  ///
  /// [onRouteVisibleChanged]와 반드시 구분해야 한다. 그쪽은 경로선이 있는지
  /// 없는지라 재계산·수단 변경처럼 안내가 계속되는 중에도 오르내리지만, 이쪽은
  /// "사용자가 그만두겠다고 눌렀다" 하나뿐이다. 상위는 이 신호로 상단 길찾기
  /// 바까지 함께 닫는다 — 안 그러면 경로만 사라지고 출발/도착 칸이 남아,
  /// 안내를 껐는데 화면은 아직 길찾기 중인 상태가 된다.
  final VoidCallback? onGuidanceDismissed;

  /// 사용자가 **직접 고른** 목적지로 안내가 시작/종료될 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 검색창·카테고리 줄·하단 바를 접는다.
  ///
  /// [onRouteVisibleChanged]와 반드시 구분해서 쓴다 — 이유는 [_guidanceActive].
  final ValueChanged<bool>? onGuidanceActiveChanged;

  /// 층 전환 배너·스크림 상태를 셸에 넘긴다.
  ///
  /// 이 화면이 직접 그리지 않는 이유: 검색창·카테고리 줄·하단 바가 셸 Stack의
  /// 형제라, 지도 안에서 그린 배너는 그 뒤에 깔린다.
  final FloorTransitionUiChanged? onFloorTransitionChanged;

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

  /// 길찾기의 "지도에서 선택"이 켜져 있는지. 계약과 근거는 실내 화면의 동명
  /// 필드([IndoorMapBody.pickingOnMap])와 같다 — 두 화면이 같은 조작을 제공해야
  /// 하므로 규칙도 같은 것을 쓴다.
  final bool pickingOnMap;

  /// [pickingOnMap]인 동안 실내 오버레이 위에서 **매장이 아닌 곳**을 눌렀을 때,
  /// 통행 그래프에 스냅해 만든 후보를 상위에 넘긴다.
  ///
  /// 이 화면에서 특히 중요한 이유가 하나 더 있다. 실내 오버레이를 보는 중에
  /// 빈 곳을 누르면 원래 [_exitIndoorByOutsideTap]/[_triggerIndoorEntry]로
  /// 흘러가 오버레이가 닫히거나 다시 열린다. 고르는 중에 그 경로를 타면 사용자는
  /// 복도를 눌렀는데 실내 화면이 통째로 닫히는 것을 본다.
  final ValueChanged<PoiSearchResult>? onMapPointPicked;

  /// 사용자의 현재 위치가 새로 잡혔을 때 호출된다 — "위치 지정"으로 지도를
  /// 탭했을 때와 입구 자동 배치가 여기에 해당한다.
  ///
  /// 상위(MapShellScreen)는 이 신호로 **기억해둔 출발지 매장을 버린다.** 그러지
  /// 않으면 매장을 출발지로 지정해 길찾기를 한 뒤 위치를 다시 잡아도, 다음
  /// 길찾기가 방금 잡은 위치가 아니라 예전에 고른 매장에서 출발한다.
  final VoidCallback? onLocationAnchored;

  /// 지금 카테고리 필터에서 고른 값. 실내 진입 오버레이의 매장 강조에 쓴다.
  ///
  /// **실내 화면과 같은 값을 받아야 한다.** 야외 지도는 건물을 탭하거나 줌
  /// 임계값을 넘기면 그 자리에서 실내 도면을 띄우는데(=실내 탭으로 넘어가지
  /// 않는다), 이 값을 안 받으면 사용자가 보고 있는 도면은 실내 화면과 똑같은데
  /// 카테고리를 눌러도 아무것도 강조되지 않는다.
  final CategorySelection? categorySelection;

  /// 지금 보고 있는 층이 바뀔 때 호출된다. 실내 오버레이가 꺼져 있으면 층 개념이
  /// 없으므로 null을 올린다.
  ///
  /// [IndoorMapBody.onFloorChanged]와 같은 계약이다. 카테고리 필터의 "이 층 N곳"
  /// 안내가 이 값을 쓰는데, 안 올리면 실내 탭에 들렀다 온 사용자에게 **옛 층
  /// 기준 개수**가 남는다.
  final ValueChanged<String?>? onFloorChanged;

  /// 상위(MapShellScreen)가 지도 위에 얹은 오버레이(검색창·저장한 장소 pill·
  /// 카테고리 chip 열·하단 공용 바 등)의 GlobalKey들. 이 영역 안의 탭은
  /// [_handleMapClick]에서 제외한다 — MapLibre 플랫폼 뷰가 Flutter gesture
  /// arena를 우회해 오버레이를 누른 탭도 지도 탭으로 함께 도착하기 때문이다.
  /// 실내 화면(IndoorMapBody)이 같은 목적으로 쓰는 것과 같은 목록이다.
  final List<GlobalKey> outerOverlayKeys;

  @override
  State<OutdoorMapBody> createState() => OutdoorMapBodyState();
}

class OutdoorMapBodyState extends State<OutdoorMapBody> {
  /// GPS 기반 자동 실내 진입이 지금 켜져 있는지.
  ///
  /// 예전에는 `_autoNavigated`라는 **되돌릴 수 없는** 1회성 플래그였다. 그래서
  /// 입구 앞을 지나가다 한 번 잘못 발동하면, 사용자가 건물 밖을 탭해 나온 뒤
  /// 진짜로 들어가도 자동 진입이 다시는 동작하지 않았다 — 오탐 한 번이 그 화면의
  /// 자동 진입 기능 자체를 죽였다.
  ///
  /// 지금은 [IndoorEntryGpsDecision.rearm]이 다시 켠다. 조건은 "신뢰할 수 있는
  /// 좌표가 입구에서 충분히 떨어진 곳에서 잡힘"이라, 실내에 그대로 있는 동안에는
  /// 켜지지 않는다. **건물 밖을 탭한 것만으로는 켜지 않는 것이 중요하다** — 그건
  /// "바깥 지도를 보여줘"라는 화면 조작이지 "내가 밖에 있다"가 아니라서, 그걸로
  /// 다시 켜면 실내에 있는 사용자가 곧바로 되끌려 들어간다.
  bool _gpsEntryArmed = true;

  Position? _position;
  ll.LatLng? _entrance;
  Building? _building;
  List<ll.LatLng>? _buildingFootprint;
  DirectionsRoute? _route;
  // 실내 진입 오버레이 위에 그리는 실내 경로. 현재 보고 있는 층에 해당하는
  // 세그먼트만 지도에 그려지고, 층 chip으로 다른 층을 훑으면 해당 층 세그먼트로
  // 갈아탄다. 다층 경로일 때는 [_indoorMultiFloorRoute]에 전체가 남아 있어
  // ETA 총 거리도 유지된다.
  /// 지금 이 층에 그려진 실내 경로 세그먼트. 실내 탭과 같은 세션이 소유한다 —
  /// 진행률이 이 값에 투영되므로 두 곳에 두면 남은거리가 갈라진다.
  IndoorRoute? get _indoorRouteSegment => _guidance.routeSegment;
  MultiFloorRoute? _indoorMultiFloorRoute;
  PoiSearchResult? _indoorRouteDestination;

  // 야외에서 실내 매장까지 안내하는 한 번의 여정은 두 구간으로 나뉜다:
  //   1) 현재 위치 → 가장 가까운 지상 출입구  (TMAP 도보 경로, [_route])
  //   2) 그 출입구 노드 → 목적지 매장         (온디바이스 다익스트라, 아래 pending)
  // 2번은 **건물에 들어가기 전에 미리 계산해 두고** 승격만 미룬다. 문 앞에
  // 도착한 순간 계산을 시작하면 그래프를 받아오는 동안 안내가 비고, 하필 그
  // 순간은 실내라 통신이 가장 불안한 지점이다.

  /// 1층 지상 출입구 목록. 못 받았거나 없는 건물이면 빈 목록이고, 그때는 문을
  /// 경유하지 않는 기존 안내로 폴백한다.
  List<BuildingEntrance> _groundEntrances = const [];

  /// 지금 안내 기준으로 쥐고 있는 문. GPS가 갱신될 때마다 히스테리시스를 거쳐
  /// 다시 고른다([_syncSelectedEntrance]).
  BuildingEntrance? _selectedEntrance;

  /// 지금 그려진 야외 구간이 향하고 있는 문. [_selectedEntrance]와 달라지는
  /// 순간이 곧 경로를 갈아 끼울 순간이다([_retargetJourneyEntrance]).
  ///
  /// 좌표가 아니라 id로 비교하려고 문 객체를 따로 들고 있다 — 좌표 비교는 같은
  /// 지점을 다른 값으로 만드는 부동소수 왕복에 걸리기 쉽다.
  BuildingEntrance? _journeyEntrance;

  /// 문 경유 안내가 쓰는 건물 그래프. 문이 바뀔 때마다 서버에 다시 묻지 않으려고
  /// 들고 있는다 — 신호가 나쁜 건물 앞에서 정확히 실패하기 때문이다.
  BuildingGraph? _journeyBuildingGraph;

  /// 건물에 들어가면 그릴 실내 구간과 그 목적지. 진입이 판정되면
  /// [_activatePendingIndoorRoute]가 실제 실내 경로 상태로 옮긴다.
  MultiFloorRoute? _pendingIndoorRoute;
  PoiSearchResult? _pendingIndoorDestination;

  /// 지금 그려진 경로가 자동차 경로인지. 선 모양이 이 값으로 갈린다 —
  /// 자동차는 실선, 걷기는 점선이다([_lineFeature]).
  bool _routeIsDriving = false;

  /// 지금 그려진 대중교통 안내. null이면 대중교통 경로가 없다.
  TransitItinerary? _transitItinerary;

  /// 대중교통 요약 카드에 적을 목적지 이름.
  String? _transitLabel;

  /// 이번 안내의 출발점을 GPS가 아니라 이 좌표로 못박는다. 길찾기가 그린
  /// **계획 경로**는 걷는 동안 다시 계산되면 안 된다 — 사용자가 비교하려고
  /// 보고 있는 선이 GPS 틱마다 흔들린다.
  ll.LatLng? _fixedRouteOrigin;

  /// 자동차 안내가 시작돼 카메라가 사용자 위치를 따라가는 중인지.
  ///
  /// setState를 쓰지 않는다 — 이 값으로 갈리는 위젯이 없고, 위치가 올 때마다
  /// 카메라만 움직인다. rebuild를 걸면 GPS 틱마다 지도 위 오버레이가 통째로
  /// 다시 그려진다.
  bool _followingUser = false;

  /// 계획 상태로 그려 둔 자동차 경로가 있어서 "안내 시작"을 권해야 하는지.
  ///
  /// 자동차 경로를 그린 직후에는 카메라가 **경로 전체**에 맞춰져 있다. 사용자가
  /// 어디로 어떻게 가는지 한 번 보고 나서 출발하도록, 위치로 내려가는 조작은
  /// 버튼 하나로 분리했다([EtaCard.onStartGuidance]).
  bool _offerStartGuidance = false;

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
  late String _indoorCategoryHighlightFillLayerId = _idFor(
    _indoorCategoryHighlightFillLayerIdBase,
  );
  late String _indoorVerticalTransportFillLayerId = _idFor(
    _indoorVerticalTransportFillLayerIdBase,
  );
  late String _indoorStoresLabelLayerId = _idFor(_indoorStoresLabelLayerIdBase);
  late String _indoorFacilityLabelLayerId = _idFor(
    _indoorFacilityLabelLayerIdBase,
  );
  late String _indoorPoiIconLayerId = _idFor(_indoorPoiIconLayerIdBase);
  late String _indoorStoreFacilityIconLayerId = _idFor(
    _indoorStoreFacilityIconLayerIdBase,
  );

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
    _indoorCategoryHighlightFillLayerId = _idFor(
      _indoorCategoryHighlightFillLayerIdBase,
    );
    _indoorVerticalTransportFillLayerId = _idFor(
      _indoorVerticalTransportFillLayerIdBase,
    );
    _indoorStoresLabelLayerId = _idFor(_indoorStoresLabelLayerIdBase);
    _indoorFacilityLabelLayerId = _idFor(_indoorFacilityLabelLayerIdBase);
    _indoorPoiIconLayerId = _idFor(_indoorPoiIconLayerIdBase);
    _indoorStoreFacilityIconLayerId = _idFor(
      _indoorStoreFacilityIconLayerIdBase,
    );
  }

  /// 현재 세대의 실내 오버레이 레이어 ID 목록(위→아래 순). removeLayer 순서로
  /// 그대로 재사용할 수 있다 — 레이어는 반드시 소스보다 먼저 제거해야 한다.
  List<String> get _indoorOverlayLayerIds => [
    _indoorStoreFacilityIconLayerId,
    _indoorPoiIconLayerId,
    _indoorFacilityLabelLayerId,
    _indoorStoresLabelLayerId,
    _indoorVerticalTransportFillLayerId,
    _indoorCategoryHighlightFillLayerId,
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

  /// 실내 안내의 위치·층 판정. 실내 탭과 **같은 구현**을 쓴다.
  ///
  /// 예전에는 이 화면이 복도 보정을 따로 돌려 놓고 결과를 읽지 않은 채 앵커를
  /// 고정 표시했다 — 홈에서 실내 길안내를 하면 마커가 움직이지 않았던 이유다.
  final IndoorGuidanceSession _guidance = IndoorGuidanceSession();
  StreamSubscription<PdrSnapshot>? _pdrSnapshotSub;
  StreamSubscription<CalibrationStatus>? _pdrCalibrationSub;
  StreamSubscription<AltitudeSample>? _pdrAltitudeSub;
  StreamSubscription<RawMotionActivity>? _pdrRawMotionSub;

  // --- 자동 층 전환 ---
  //
  // 실내 탭과 같은 상태 기계를 쓴다. 다른 것은 도면을 갈아 끼우는 방법뿐이다 —
  // 실내 탭은 자체 렌더러의 카메라를 인계하고, 홈은 MapLibre 오버레이 소스를
  // 통째로 바꾼다([_switchOverlayFloor]).

  /// 조기 전환으로 목적 층을 이미 열어 둔 이동. 하차 확정 전까지 유지된다.
  EscalatorTransition? _escalatorRide;

  /// 확정 직후 잠깐 "도착" 배너를 띄우는 이동. 되돌리기를 여기에 붙인다.
  EscalatorTransition? _escalatorArrival;
  Timer? _escalatorArrivalTimer;

  /// 배너만 띄우는 접근·수직이동 단계. 층 지도는 아직 안 바꾼다.
  EscalatorPhaseChange? _escalatorStage;

  /// 탑승 때문에 걸음 적용을 멈춘 상태인지. pause/resume 짝을 한 곳에서 센다.
  bool _stepsPausedForRide = false;

  /// 전환 직전 상태. 되돌리기와 취소 복원이 이 값을 쓴다.
  String? _preTransferFloor;
  PdrAnchor? _preTransferAnchor;
  IndoorRoute? _preTransferRoute;
  MultiFloorRoute? _preTransferMultiRoute;
  PoiSearchResult? _preTransferDestination;
  GraphNode? _pendingArrivalNode;

  /// 도면 교체 구간을 덮는 정도. 0이 아니면 셸이 스크림을 그린다.
  double _floorSwapVeil = 0;

  // 사람 조작 층 전환이 오래 걸릴 때 뜨는 에스컬레이터 모티프. 안내용
  // [_floorSwapVeil](셸이 chrome까지 덮는 불투명 스크림)과 달리 이쪽은 아무것도
  // 덮지 않는다 — 이전 층 도면이 그대로 보이는 위에 카드 하나만 뜬다. 언제
  // 띄우고 걷을지(모티프 임계·최소 표시)는 컨트롤러가 정한다.
  bool _floorSwitchMotifVisible = false;

  /// 모티프가 마지막으로 흘렀던 방향. 숨김 전환(AnimatedSwitcher 페이드아웃)
  /// 중에도 위젯이 잠깐 더 그려지므로, 방향 없는 프레임이 생기지 않게 마지막
  /// 값을 들고 있는다.
  FloorSwitchDirection _floorSwitchMotifDirection = FloorSwitchDirection.up;

  late final FloorSwitchProgressController _floorSwitchProgress =
      FloorSwitchProgressController(onChanged: _onFloorSwitchMotifChanged);

  void _onFloorSwitchMotifChanged(FloorSwitchDirection? direction) {
    if (!mounted) return;
    setState(() {
      _floorSwitchMotifVisible = direction != null;
      if (direction != null) _floorSwitchMotifDirection = direction;
    });
  }

  /// 실내 오버레이 레이어 전체에 곱해지는 크로스페이드 계수(0=투명, 1=원래
  /// 불투명도). 크로스페이드 중이 아니면 항상 1이다. 페이드 갱신·카테고리
  /// 필터 등 오버레이 속성을 다시 쓰는 **모든** 경로가 이 계수를 거친
  /// [_overlayFadeExpr]를 써야, 페이드 도중 끼어든 갱신이 반쯤 페이드된 새
  /// 도면을 갑자기 불투명하게 되돌리지 않는다.
  double _indoorOverlayFadeFactor = 1;

  /// 크로스페이드가 끝나기를 기다리며 화면에 남아 있는 이전 층 소스·레이어
  /// 묶음(은퇴 블록). 새 도면 페이드인이 끝나면 [_removeRetiringIndoorBlocks]가
  /// 지운다. 연타로 크로스페이드가 겹치면 블록이 잠시 여러 개 쌓일 수 있고,
  /// 마지막 전환의 마무리가 한꺼번에 정리한다.
  final List<({List<String> layerIds, String sourceId})> _retiringIndoorBlocks =
      [];

  /// 도면을 갈아 끼운 뒤 완전 불투명을 유지하는 시간. 실내 탭과 같은 값이다.
  static const _indoorFloorSwapVeilHold = Duration(milliseconds: 400);

  /// 층 이동 확정 뒤 "아니에요"를 띄워 두는 시간.
  static const _indoorArrivalBannerHold = Duration(seconds: 6);

  /// 층 전환 작업을 직렬화한다. 겹쳐 돌면 층과 경로가 서로 다른 시점을 가리킨다.
  Future<void> _floorTransitionQueue = Future<void>.value();
  bool _applyingFloorTransition = false;

  // 셸에 마지막으로 알린 층 전환 UI 상태. 같은 값이면 다시 알리지 않는다.
  FloorTransitionUiState? _reportedFloorTransition;
  double _reportedFloorScrimOpacity = 0;

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

  // 지도 위 Flutter 오버레이(PDR 제어 등) 영역. MapLibre는 PlatformView라 이
  // 위젯들 위의 탭도 native 지도까지 흘러들어가 onMapClick이 함께 발화한다 —
  // 버튼을 눌렀을 뿐인데 뒤의 매장이 열리거나 앵커가 버튼 아래에 찍히는 것을
  // 막기 위해 좌표로 걸러낸다(실내 화면의 overlayHitTest와 같은 목적).
  final GlobalKey _pdrControlKey = GlobalKey();
  final GlobalKey _pdrShareButtonKey = GlobalKey();
  final GlobalKey _etaCardKey = GlobalKey();
  final _mapOverlayTapGuard = MapOverlayTapGuard();
  Offset? _etaClosePointerDown;

  /// 층 선택기. **가장 중요한 항목이다.** 이 열은 실내 진입 상태에서만 뜨는데,
  /// 그 상태에서 chip을 누른 탭이 지도까지 새어들어가면 그 좌표가 건물 밖으로
  /// 판정돼 `_exitIndoorByOutsideTap`이 걸린다 — 층을 바꿨을 뿐인데 야외로
  /// 튕겨 나간다. 지도를 크게 확대해 두면 chip 자리도 건물 안이라 증상이 숨고,
  /// 건물이 화면 일부만 차지할 만큼 축소했을 때만 재현된다.
  final GlobalKey _floorSelectorKey = GlobalKey();

  /// 위치 지정 안내 배너. 오른쪽 상단 X를 누른 탭이 지도까지 새어들어가 배너
  /// 아래 지점에 앵커가 찍히는 것을 막는다 — 취소했는데 위치가 지정되면
  /// 사용자 입장에선 취소가 안 먹은 것으로 보인다.
  final GlobalKey _placingHintKey = GlobalKey();

  /// 건물 로드 실패 배지("다시 시도"). 이 탭이 지도까지 새어들어가면 재시도를
  /// 누른 손가락이 배지 아래 지점의 건물 진입·앵커 배치까지 함께 발화시킨다.
  final GlobalKey _buildingLoadFailedKey = GlobalKey();

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

  /// 마지막으로 상위에 알린 층. 같은 값을 반복해서 올리면 상위가 매번 setState를
  /// 돌게 되므로 여기서 걸러 낸다.
  String? _notifiedFloor;

  /// 지금 보고 있는 층을 상위에 알린다. 실내 오버레이가 꺼져 있으면 층 개념이
  /// 없으므로 null이다 — 층·진입 상태 둘 중 하나만 바뀌어도 결과가 달라지므로
  /// 양쪽 변경 지점에서 모두 부른다.
  void _notifyActiveFloor() {
    final floor = _indoorEntered ? _activeFloor : null;
    if (_notifiedFloor == floor) return;
    _notifiedFloor = floor;
    widget.onFloorChanged?.call(floor);
  }

  /// 화면 배율. `icon-size`가 **물리 픽셀**에 곱해지는 값이라 논리 px으로 잡은
  /// 마커 크기를 여기로 환산한다([indoorMarkerIconSize]).
  ///
  /// 레이어를 등록하는 코드가 여러 번의 `await` 뒤라 그 자리에서
  /// `MediaQuery.devicePixelRatioOf(context)`를 읽으면 위젯이 그 사이 사라졌을 때
  /// 터진다. 실내 화면([FloorPlanViewState])과 같은 이유로 의존성이 잡히는
  /// 시점에 한 번 받아 둔다.
  double _devicePixelRatio = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

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
      setState(() {
        _pdrTrailState.recordSnapshot(snapshot);
        _syncCorridorTracking(snapshot);
      });
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
    });
    _pdrCalibrationSub = indoorNavigationDriver.calibration.listen((status) {
      _pdrDebugRecorder?.recordCalibration(status);
      if (!mounted) return;
      setState(() {
        _pdrTrailState.recordCalibration(status);
        _syncCorridorTracking(_pdrTrailState.snapshot);
      });
      if (status.phase == CalibrationPhase.calibrated ||
          status.phase == CalibrationPhase.uncalibrated) {
        _setPlacingAnchor(false);
      }
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
    });
    // 층 전환 판정. 실내 탭에만 있던 구독을 여기에도 둔다 — 이게 없으면 홈에서
    // 에스컬레이터를 타도 층이 그대로라, 마커가 이전 층 도면 위를 걸어간다.
    _pdrAltitudeSub = indoorNavigationDriver.altitudeSamples.listen(
      _onAltitudeSample,
    );
    _pdrRawMotionSub = indoorNavigationDriver.rawMotion.listen(
      _guidance.onRawMotion,
    );
    unawaited(_loadBuildingEntrance());
    _syncGpsSubscription();
  }

  /// 기압 샘플 한 건을 세션에 넣고, 확정이 나오면 층을 옮긴다.
  void _onAltitudeSample(AltitudeSample sample) {
    if (!mounted) return;
    // 스냅샷이 아직 없거나(PDR 시작 직후) 서 있어서 멈춘 동안에도 판정기는
    // 층 그래프를 알아야 에스컬레이터 노드에 허가가 걸린다. 기압은 걸음과
    // 무관하게 흐르므로 여기서도 컨텍스트를 준다.
    _guidance.setContext(
      floorId: _activeFloor,
      graph: _floorGraph,
      floorLabels: _building?.floors ?? const [],
    );
    final outcome = _guidance.onAltitude(sample);
    final recorder = _pdrDebugRecorder;
    if (recorder != null) {
      recorder.recordAltimeterStatus(indoorNavigationDriver.altimeterStatus);
      recorder.recordAltitudeSample(
        sample,
        smoothedM: _guidance.escalator.smoothedAltitudeM,
        baselineM: _guidance.escalator.baselineM,
        deltaM: _guidance.escalator.deltaM,
        armed: _guidance.escalator.isArmed,
        candidate: _guidance.escalator.hasCandidate,
      );
    }
    if (outcome.events.isNotEmpty) {
      recorder?.recordFloorTransitionEvents(outcome.events);
    }
    _handleEscalatorPhaseChanges();

    // 순서가 중요하다. 시작 → 취소 → 확정 순으로 큐에 넣어야 층·경로 복원이
    // 어긋나지 않는다.
    if (outcome.started != null) {
      _enqueueFloorTransition(
        () => _beginEscalatorTransition(outcome.started!),
      );
    }
    if (outcome.cancelled != null) {
      _enqueueFloorTransition(
        () => _cancelEscalatorTransition(outcome.cancelled!),
      );
    }
    if (outcome.confirmed != null) {
      _enqueueFloorTransition(
        () => _completeEscalatorTransition(outcome.confirmed!),
      );
    }
  }

  /// 판정기의 단계 전이를 화면 동작으로 옮긴다.
  ///
  /// 단계마다 하는 일이 다르다. 배너는 근거가 약해도 띄우고(되돌리기 비용이
  /// 없다), 걸음 pause는 실제 수직 이동에서 시작하며, 목적 층 지도는 midpoint
  /// 근거에서만 연다. 층 전환과 하차 확정은 started/confirmed 경로가 담당한다.
  void _handleEscalatorPhaseChanges() {
    final changes = _guidance.takePhaseChanges();
    if (changes.isEmpty) return;
    for (final change in changes) {
      switch (change.phase) {
        case EscalatorPhase.boardingDetected:
        case EscalatorPhase.verticalMotionDetected:
          if (!mounted) return;
          setState(() => _escalatorStage = change);
          if (change.phase == EscalatorPhase.verticalMotionDetected) {
            _enqueueFloorTransition(_pauseStepsForRide);
          }
        case EscalatorPhase.cancelled:
        case EscalatorPhase.failed:
          if (!mounted) return;
          setState(() => _escalatorStage = null);
          // 후보가 열린 뒤의 취소는 층·경로 복원까지 해야 하므로 cancelled
          // 경로가 처리한다. 여기서는 배너만 띄운 단계에서 멈춘 걸음을
          // 되살리는 것만 책임진다.
          if (change.transition == null) {
            _enqueueFloorTransition(_endEscalatorRide);
          }
        case EscalatorPhase.midpointReached:
        case EscalatorPhase.landed:
          // 여기서 단계를 비우지 않는다. 층 전환은 큐를 거쳐 다음 프레임 이후에
          // 적용되므로, 지금 비우면 그 사이 배너가 한 번 깜빡였다가 다시 뜬다.
          break;
        case EscalatorPhase.idle:
          if (!mounted) return;
          setState(() => _escalatorStage = null);
      }
    }
  }

  /// 층 전환 작업을 직렬화한다.
  ///
  /// 겹쳐 돌면 층과 경로가 서로 다른 시점을 가리킨다. 오류가 나도 탑승 상태를
  /// 화면에 남기지 않는다 — 큐가 오류만 찍고 끝나면 걸음이 멈춘 채 배너가
  /// 영구히 남고 사용자가 복구할 방법이 없다.
  void _enqueueFloorTransition(Future<void> Function() action) {
    _floorTransitionQueue = _floorTransitionQueue
        .then((_) => mounted ? action() : Future<void>.value())
        .onError(_recoverFloorTransitionFailure);
  }

  Future<void> _recoverFloorTransitionFailure(
    Object error,
    StackTrace stackTrace,
  ) async {
    debugPrint('floor transition failed: $error\n$stackTrace');
    if (!mounted) return;
    await _endEscalatorRide();
    if (!mounted) return;
    setState(() => _pendingArrivalNode = null);
    _showSnack('층 전환을 완료하지 못했습니다. 현재 층과 위치를 다시 확인해주세요.');
  }

  /// 위치에 반영하는 걸음만 멈춘다. 센서·기압·방향은 계속 흐른다.
  Future<void> _pauseStepsForRide() async {
    if (_stepsPausedForRide) return;
    _stepsPausedForRide = true;
    await indoorNavigationDriver.pauseStepTracking();
    if (mounted) return;
    // pause Future가 끝나기 직전에 화면이 닫히면 dispose는 pause된 사실을 볼 수
    // 없다. 여기서 직접 되돌려 전역 PDR 세션을 살려 둔다.
    _stepsPausedForRide = false;
    await indoorNavigationDriver.resumeStepTracking();
  }

  /// 탑승 상태를 끝낸다. 걸음 누적을 다시 켜고 배너·스크림을 지운다.
  ///
  /// 확정·취소·되돌리기 **모든 출구**가 이걸 지나야 한다. 한 경로라도 빠뜨리면
  /// 배너가 남고 걸음이 영영 멈춘 상태로 사용자가 복구할 방법이 없어진다.
  Future<void> _endEscalatorRide() async {
    if (_escalatorRide == null &&
        _escalatorStage == null &&
        !_stepsPausedForRide &&
        _floorSwapVeil == 0) {
      return;
    }
    _stepsPausedForRide = false;
    await indoorNavigationDriver.resumeStepTracking();
    if (!mounted) return;
    setState(() {
      _escalatorRide = null;
      _escalatorStage = null;
      _floorSwapVeil = 0;
    });
    _guidance.clearBoardingHold();
  }

  /// 스크림으로 덮은 뒤 오버레이 층을 갈아 끼운다.
  ///
  /// 실내 탭은 자체 렌더러의 카메라를 인계하지만, 홈은 MapLibre 소스를 통째로
  /// 바꾸므로 카메라가 그대로 유지된다. 덮개만 같은 타이밍으로 맞춘다 — 셸의
  /// 페이드와 여기 대기 시간이 어긋나면 교체 장면이 그대로 보인다.
  ///
  /// **새 층 경로에 카메라를 다시 맞추는 것도 여기서, 스크림이 덮인 동안 한다.**
  /// 층마다 경로가 놓인 자리와 방향이 달라서 이전 층 배율·bearing 그대로 두면
  /// 걷힌 화면에 경로가 비스듬히 눕거나 아예 밖으로 나가 있다. 그렇다고 걷힌
  /// **뒤에** 움직이면 층이 바뀔 때마다 지도가 크게 도는 연출이 반복돼 피로하다.
  /// 덮여 있는 동안 옮겨 두면 사용자는 새 층을 이미 맞춰진 상태로 만난다 —
  /// 움직임을 못 봤으니 "순간이동"으로도 읽히지 않는다.
  Future<bool> _swapIndoorFloorSmoothly(String floor) async {
    if (!(_building?.floors.contains(floor) ?? false)) return false;
    setState(() => _floorSwapVeil = 1);
    await Future<void>.delayed(floorTransitionScrimFadeIn);
    if (!mounted) return false;
    await _switchOverlayFloor(floor);
    if (!mounted) return false;
    // 덮인 동안이라 애니메이션 시간을 줄 이유가 없다. 사용자는 과정을 볼 수
    // 없고, 기다리는 만큼 스크림만 길어진다.
    final segment = _indoorRouteSegment;
    if (segment != null) {
      await _fitCameraToRouteSegment(segment, duration: Duration.zero);
      if (!mounted) return false;
    }
    // 새 도면이 첫 프레임을 그릴 시간을 준 뒤에 걷는다.
    await Future<void>.delayed(_indoorFloorSwapVeilHold);
    if (!mounted) return false;
    setState(() => _floorSwapVeil = 0);
    return _activeFloor == floor;
  }

  /// 디버그 모드에서 강제로 태울 수 있는 다음 환승(지금 층 세그먼트 + 도착 층).
  /// 없으면 null.
  ///
  /// 지금 층 세그먼트에 **에스컬레이터** 환승이 붙어 있을 때만이다. 판정기
  /// ([EscalatorTransitionDetector])가 에스컬레이터 전용이라, 엘리베이터 환승을
  /// 강제로 태우면 실제로는 나올 수 없는 화면을 검증하게 된다.
  ({IndoorRouteSegment segment, String nextFloorLabel})?
  get _debugForceableTransfer {
    final multi = _indoorMultiFloorRoute;
    final floor = _activeFloor;
    if (multi == null || floor == null) return null;
    final i = multi.segments.indexWhere((s) => s.floorName == floor);
    if (i < 0 || i + 1 >= multi.segments.length) return null;
    final seg = multi.segments[i];
    if (seg.transferModeToNext != 'escalator') return null;
    if (seg.transferFromNodeId == null) return null;
    return (segment: seg, nextFloorLabel: multi.segments[i + 1].floorName);
  }

  /// 디버그 전용 — 실제 탑승 없이 층 전환 시퀀스를 태운다.
  ///
  /// **판정기를 흉내 내는 것이지 우회하는 것이 아니다.** 판정기가 확정을 냈을 때
  /// 타는 경로(시작 → 확정, [_beginEscalatorTransition] →
  /// [_completeEscalatorTransition])에 합성 transition을 그대로 넣는다. 스크림,
  /// 스크림 뒤 카메라 재배치([_swapIndoorFloorSmoothly]), 새 층 앵커 복원,
  /// 재탐색까지 전부 프로덕션 코드가 돈다 — 여기서 따로 그리는 화면이 없으므로
  /// 이 버튼으로 본 연출이 곧 실기기에서 에스컬레이터를 탔을 때의 연출이다.
  ///
  /// 도착 노드는 경로가 지목한 노드([IndoorRouteSegment.transferToNodeId])를
  /// 그대로 쓴다. 실제 판정도 활성 경로가 있으면 같은 값을 우선한다
  /// ([findEscalatorArrivalNode]의 1단계).
  ///
  /// 판정기 자체([EscalatorTransitionDetector])는 건드리지 않는다 — 수직 전이
  /// 알고리즘은 재작성이 예정돼 있어, 거기 디버그 주입구를 뚫으면 재작성 때
  /// 같이 갈아엎어야 할 표면만 는다.
  void _debugForceFloorTransition() {
    final transfer = _debugForceableTransfer;
    final floor = _activeFloor;
    if (transfer == null || floor == null) return;
    final (:segment, :nextFloorLabel) = transfer;
    // 층 라벨 → 순위 비교는 층 전환 연출 정책과 같은 함수를 쓴다
    // (floor_switch_progress).
    final goingUp = floorSwitchRank(nextFloorLabel) > floorSwitchRank(floor);
    final transition = EscalatorTransition(
      // 도착 노드를 경로 지목으로 찾으므로 그룹 매칭까지 갈 일이 없지만,
      // 진단 JSON에 남는 값이라 강제 전환임을 알아볼 수 있게 적는다.
      group: 'DEBUG',
      direction: goingUp ? EscalatorDirection.up : EscalatorDirection.down,
      fromFloorLabel: floor,
      toFloorLabel: nextFloorLabel,
      deltaM: goingUp ? 5.0 : -5.0,
      durationMs: 0,
      stepsDuring: 0,
      boardingNodeId: segment.transferFromNodeId!,
      boardingNodeName: null,
      boardingDistanceM: 0,
      boardingEvidence: 'debug-forced',
      expectedArrivalNodeId: segment.transferToNodeId,
    );
    _enqueueFloorTransition(() => _beginEscalatorTransition(transition));
    // 시작과 확정 사이를 벌린다. 실제 에스컬레이터는 탑승부터 하차 감지까지
    // 10초를 넘게 타는데, 처음 1.2초로 뒀더니 "이동 중" 상태가 실제보다 훨씬
    // 짧아 보였다 — 이 버튼으로 본 리듬이 곧 실기기 리듬이어야 하므로 실제
    // 탑승 시간에 가깝게 둔다. (실기기에서는 이 대기가 없다 — 판정기가 실제
    // 하차를 기다리므로 몸이 시간을 정한다.)
    _enqueueFloorTransition(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    _enqueueFloorTransition(() => _completeEscalatorTransition(transition));
  }

  /// 반 층을 지났다. 목적 층 지도를 먼저 연다(하차는 아직).
  Future<void> _beginEscalatorTransition(EscalatorTransition transition) async {
    if (_applyingFloorTransition) return;
    final building = _building;
    if (building == null) return;
    if (!building.floors.contains(transition.toFloorLabel)) return;
    if (_activeFloor != transition.fromFloorLabel) {
      // 판정 중에 사용자가 층 선택기로 다른 층을 열었다. 어느 층 기준인지
      // 모호해졌으므로 적용하지 않는다.
      return;
    }

    _applyingFloorTransition = true;
    try {
      _preTransferFloor = _activeFloor;
      _preTransferAnchor = _pdrTrailState.anchor;
      _preTransferRoute = _indoorRouteSegment;
      _preTransferMultiRoute = _indoorMultiFloorRoute;
      _preTransferDestination = _indoorRouteDestination;

      // 보통은 verticalMotionDetected에서 이미 멈췄다. 수직 속도 근거 없이
      // 누적 고도만으로 여기 도달한 경우를 위해 한 번 더 보장한다(idempotent).
      await _pauseStepsForRide();
      if (!mounted) return;
      setState(() {
        _escalatorRide = transition;
        _escalatorStage = null;
      });

      if (!await _swapIndoorFloorSmoothly(transition.toFloorLabel)) {
        await _endEscalatorRide();
        if (mounted) {
          _showSnack('${transition.toFloorLabel} 지도를 불러오지 못했습니다. 현재 층을 유지합니다.');
        }
        return;
      }
      final arrival = findEscalatorArrivalNode(_floorGraph, transition);
      if (arrival != null) setState(() => _pendingArrivalNode = arrival);
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 하차가 확정됐다. 새 층 도착 노드로 앵커를 옮기고 경로를 다시 잡는다.
  Future<void> _completeEscalatorTransition(
    EscalatorTransition transition,
  ) async {
    if (_applyingFloorTransition) return;
    _applyingFloorTransition = true;
    try {
      if (_activeFloor != transition.toFloorLabel) {
        // 조기 전환 없이 바로 확정된 경우(후보와 확정이 거의 동시).
        if (!await _swapIndoorFloorSmoothly(transition.toFloorLabel)) {
          await _endEscalatorRide();
          if (mounted) {
            _showSnack(
              '${transition.toFloorLabel} 지도를 불러오지 못했습니다. 현재 층을 유지합니다.',
            );
          }
          return;
        }
      }
      final graph = _floorGraph;
      final arrival =
          _pendingArrivalNode ?? findEscalatorArrivalNode(graph, transition);
      if (graph == null || arrival == null) {
        // 도착 지점을 못 찾아도 **탑승 상태는 반드시 끝낸다.** 안 그러면 배너가
        // 남고 걸음 누적이 영영 멈춘 채로 사용자가 복구할 방법이 없다.
        await _endEscalatorRide();
        if (!mounted) return;
        setState(() => _pendingArrivalNode = null);
        _showSnack(
          '${transition.toFloorLabel} 도착 지점을 찾지 못했습니다. '
          '하단 "위치 지정"으로 현재 위치를 찍어주세요.',
        );
        return;
      }

      setState(() {
        // 이전 층 궤적과 복도 보정 상태는 새 층에서 이어지지 않는다.
        _pdrTrailState.beginNewSession();
        _guidance.resetTracking();
      });
      await indoorNavigationDriver.applyVerticalTransfer(
        floorId: transition.toFloorLabel,
        anchorLocalM: PdrLocalPoint(arrival.xM, arrival.yM),
        axes: fitPdrToFloorAxes(graph.nodes),
      );
      if (!mounted) return;
      // 하차했으므로 걸음 누적을 다시 켠다. applyVerticalTransfer가 경로 원점을
      // 옮긴 **뒤에** 켜야 탑승 중 걸음이 새 층 원점에 붙지 않는다.
      await _endEscalatorRide();
      if (!mounted) return;
      setState(() => _pendingArrivalNode = null);

      await _rerouteAfterVerticalTransfer(
        arrivalNodeId: arrival.id,
        floor: transition.toFloorLabel,
      );
      if (!mounted) return;

      // 별도 토스트를 띄우지 않는다. 배너가 이미 같은 자리에서 같은 사실을
      // 말하고 있어서, 확정 순간에 토스트가 겹치면 같은 내용이 두 벌이 된다.
      _escalatorArrivalTimer?.cancel();
      setState(() => _escalatorArrival = transition);
      _escalatorArrivalTimer = Timer(_indoorArrivalBannerHold, () {
        if (!mounted) return;
        setState(() => _escalatorArrival = null);
      });
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 반 층 후보가 되돌아가거나 타임아웃되면 화면·경로를 탑승 전으로 복원한다.
  Future<void> _cancelEscalatorTransition(
    EscalatorTransition transition,
  ) async {
    final floor = _preTransferFloor;
    await _endEscalatorRide();
    if (!mounted) return;
    if (floor == null) return;
    if (_activeFloor != floor) {
      // 사용자가 "아니에요"로 되돌린 직후다. [_endEscalatorRide]가 불투명
      // 스크림을 이미 걷었으므로, 여기 층 복귀는 베일이 덮는다.
      await _switchOverlayFloorCrossfaded(floor);
      if (!mounted) return;
    }
    setState(() {
      _guidance
        ..setRouteSegment(_preTransferRoute)
        ..clearProgress()
        ..setRoute(_preTransferMultiRoute);
      _indoorMultiFloorRoute = _preTransferMultiRoute;
      _indoorRouteDestination = _preTransferDestination;
      _pendingArrivalNode = null;
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _clearTransferRouteBackups(keepUndoAnchor: false);
  }

  /// 새 층에서 목적지까지 경로를 다시 뽑는다.
  Future<void> _rerouteAfterVerticalTransfer({
    required String arrivalNodeId,
    required String floor,
  }) async {
    final destination = _preTransferDestination ?? _indoorRouteDestination;
    final destinationNodeId = destination?.nodeId;
    final buildingId = _building?.id;
    if (destination == null ||
        destinationNodeId == null ||
        buildingId == null) {
      _clearTransferRouteBackups(keepUndoAnchor: true);
      return;
    }
    setState(() => _indoorRouteDestination = destination);
    // 여기도 연출을 붙이지 않는다. 카메라는 이미 [_swapIndoorFloorSmoothly]가
    // 스크림 뒤에서 새 층 경로에 맞춰 뒀고, 이 재계산은 그 자리를 실제 하차
    // 노드 기준으로 다듬는 것뿐이다. 스크림이 걷힌 뒤에 또 움직이면 사용자는
    // 방금 자리 잡은 화면이 한 번 더 흔들리는 것을 본다.
    if (destination.floor == floor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: buildingId,
        floor: floor,
        endNodeId: destinationNodeId,
        playOverview: false,
        startNodeId: arrivalNodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: buildingId,
        startFloor: floor,
        endFloor: destination.floor,
        endNodeId: destinationNodeId,
        playOverview: false,
        startNodeId: arrivalNodeId,
      );
    }
    if (!mounted) return;
    _clearTransferRouteBackups(keepUndoAnchor: true);
  }

  void _clearTransferRouteBackups({required bool keepUndoAnchor}) {
    _preTransferRoute = null;
    _preTransferMultiRoute = null;
    _preTransferDestination = null;
    if (!keepUndoAnchor) {
      _preTransferFloor = null;
      _preTransferAnchor = null;
    }
  }

  /// 지금 화면이 그려야 하는 층 전환 배너 상태.
  FloorTransitionUiState? get _floorTransitionUiState => floorTransitionUiState(
    arrival: _escalatorArrival,
    ride: _escalatorRide,
    stage: _escalatorStage,
    canUndo: _preTransferFloor != null && _preTransferAnchor != null,
  );

  /// 배너·스크림 상태가 바뀌면 셸에 알린다. 같은 값이면 알리지 않는다.
  ///
  /// 값 비교로 막지 않으면 매 스냅샷마다 부모 setState가 돌아, 지도 전체가
  /// 초당 수 회 다시 그려진다.
  void _reportFloorTransitionUi() {
    final banner = _floorTransitionUiState;
    final scrim = _floorSwapVeil;
    if (banner == _reportedFloorTransition &&
        scrim == _reportedFloorScrimOpacity) {
      return;
    }
    _reportedFloorTransition = banner;
    _reportedFloorScrimOpacity = scrim;
    final notify = widget.onFloorTransitionChanged;
    if (notify == null) return;
    // build 중에는 부모 setState를 호출할 수 없다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify(banner, scrim);
    });
  }

  /// 배너의 `아니에요`. 셸이 호출한다.
  void undoFloorTransition() {
    _escalatorArrivalTimer?.cancel();
    setState(() => _escalatorArrival = null);
    _enqueueFloorTransition(_undoFloorTransition);
  }

  /// 자동 전환을 되돌린다. 층과 앵커를 전환 직전 값으로 복원한다.
  ///
  /// 되돌린 뒤 위치는 "에스컬레이터를 타기 직전 지점"이다. 그 사이 걸은 거리는
  /// 복원하지 않는다 — 잘못된 전환이었다면 그 구간의 걸음은 어차피 어느 층
  /// 기준인지 알 수 없다.
  Future<void> _undoFloorTransition() async {
    final floor = _preTransferFloor;
    final anchor = _preTransferAnchor;
    if (floor == null || anchor == null) return;
    _preTransferFloor = null;
    _preTransferAnchor = null;
    if (_applyingFloorTransition) return;
    _applyingFloorTransition = true;
    try {
      await _endEscalatorRide();
      if (!mounted) return;
      await _switchOverlayFloorCrossfaded(floor);
      if (!mounted) return;
      setState(() {
        _pdrTrailState.beginNewSession();
        _guidance.resetTracking();
      });
      await indoorNavigationDriver.applyVerticalTransfer(
        floorId: floor,
        anchorLocalM: anchor.anchorLocalM,
        axes: anchor.axes,
      );
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 건물 로드가 실패한 상태인지. 배지를 띄우는 유일한 근거이며, 재시도가
  /// 성공하면 [_loadBuildingEntrance]가 다시 false로 되돌린다.
  bool _buildingLoadFailed = false;

  /// 재시도 요청이 아직 도는 중인지. 연타로 요청이 겹치는 것을 막고, 배지
  /// 문구를 "다시 불러오는 중"으로 바꿔 사용자가 눌린 걸 알 수 있게 한다.
  bool _retryingBuildingLoad = false;

  /// 실패했을 때 스스로 다시 시도하는 간격.
  ///
  /// **한 번 실패하면 영영 복구되지 않는 것이 실제 문제였다.** 이 로드는
  /// initState에서 딱 한 번 돌고, 실패하면 사람이 배지를 누를 때까지 그대로
  /// 남는다. 그런데 개발 중에는 `uvicorn --reload`가 백엔드 코드를 고칠 때마다
  /// 서버를 잠깐 내리므로, 하필 그 순간 화면이 열려 있으면 층 선택기·위치
  /// 지정·실내 진입·실내 도면이 통째로 죽은 채 남는다. 클라이언트를 hot
  /// reload해도 initState는 다시 돌지 않아 그대로다.
  ///
  /// 간격을 늘려 가는 이유는 두 경우를 한 사다리로 덮기 위해서다 — 서버가
  /// 리로드 중이라 곧 살아나는 경우(앞쪽 짧은 간격)와, 아직 뜨지도 않아 한참
  /// 걸리는 경우(뒤쪽 긴 간격). 다 쓰면 약 1분간 6번 시도한다.
  ///
  /// **무한히 재시도하지는 않는다.** 백엔드가 아예 없는 환경(기기에서 서버
  /// 없이 실행)에서 영원히 요청을 날리면 배터리와 로그만 태운다. 사다리를 다
  /// 쓴 뒤에는 배지의 "다시 시도"에 맡긴다.
  static const _buildingRetryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  int _buildingRetryAttempt = 0;
  Timer? _buildingRetryTimer;

  /// 다음 자동 재시도를 예약한다. 이미 예약돼 있거나 사다리를 다 썼으면 아무
  /// 것도 하지 않는다.
  void _scheduleBuildingRetry() {
    if (_buildingRetryTimer != null) return;
    if (_buildingRetryAttempt >= _buildingRetryDelays.length) return;
    final delay = _buildingRetryDelays[_buildingRetryAttempt++];
    _buildingRetryTimer = Timer(delay, () {
      _buildingRetryTimer = null;
      // 사람이 누른 재시도가 도는 중이면 그 결과를 기다린다. 실패하면 그쪽이
      // 다시 사다리를 이어 준다.
      if (!mounted || _retryingBuildingLoad) return;
      unawaited(_loadBuildingEntrance());
    });
  }

  Future<void> _retryBuildingLoad() async {
    if (_retryingBuildingLoad) return;
    // 사람이 직접 눌렀다는 것은 "지금은 될 것 같다"는 신호다. 사다리를 처음
    // 부터 다시 쓸 수 있게 되돌려, 이번에도 실패하면 짧은 간격부터 다시 시도한다.
    _buildingRetryTimer?.cancel();
    _buildingRetryTimer = null;
    _buildingRetryAttempt = 0;
    setState(() => _retryingBuildingLoad = true);
    await _loadBuildingEntrance();
    if (!mounted) return;
    setState(() => _retryingBuildingLoad = false);
  }

  @override
  void didUpdateWidget(covariant OutdoorMapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 실내 탭으로 넘어가면(active=false) GPS 구독을 끊고, 돌아오면 다시 붙인다.
    if (oldWidget.active != widget.active) _syncGpsSubscription();
    // 카테고리 선택이 바뀌면 강조 레이어의 필터만 갈아 끼운다. 레이어를 지웠다
    // 다시 만들지 않는 이유는 kCategoryHighlightNoneFilter 주석 참고.
    if (oldWidget.categorySelection != widget.categorySelection) {
      unawaited(_applyCategoryFilter());
    }
  }

  /// MapLibre 지도는 PlatformView라 hot reload로도 살아남고, 스타일이 이미 로드된
  /// 상태에서는 `onStyleLoadedCallback`이 다시 불리지 않는다. 레이어 등록이 전부
  /// [_onStyleLoaded] 안에 있으므로, 이 훅이 없으면 **핀 디자인이나 레이어 속성을
  /// 고쳐도 hot reload 화면은 그대로다.**
  ///
  /// 위젯 코드(예: 하단 바 아이콘)는 hot reload가 즉시 반영하기 때문에, 같은
  /// 수정 세션에서 "버튼 아이콘은 바뀌었는데 지도 마커만 안 바뀐다"는 모습이
  /// 나온다 — 코드를 의심하게 만드는 함정이라 훅으로 막아 둔다(실내 화면
  /// `FloorPlanViewState.reassemble`과 같은 이유).
  @override
  void reassemble() {
    super.reassemble();
    unawaited(_refreshIndoorDestinationPin());
  }

  Future<void> _refreshIndoorDestinationPin() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    try {
      await controller.removeLayer(_indoorDestLayerId);
      await _addIndoorDestinationPinLayer(controller);
      await _syncIndoorDestinationLayer();
    } catch (error, stackTrace) {
      // hot reload 편의 기능이라 실패해도 앱을 죽이지 않는다.
      debugPrint('destination pin refresh failed: $error\n$stackTrace');
    }
  }

  /// 실내 경로 도착 핀 레이어를 얹는다. 실내 화면과 **같은 함수**로 속성을
  /// 만든다 — 두 화면이 각자 정의를 베껴 들고 있던 탓에 둘 다 `text-font`를
  /// 빠뜨렸던 이력이 있다([destination_pin.dart] 주석).
  Future<void> _addIndoorDestinationPinLayer(
    MapLibreMapController controller,
  ) async {
    await controller.addSymbolLayer(
      _indoorDestSourceId,
      _indoorDestLayerId,
      destinationPinSymbolProps(
        imageName: _destinationPinImageName,
        iconSizeZ16: _destinationPinIconSizeZ16,
        iconSizeZ20: _destinationPinIconSizeZ20,
      ),
      enableInteraction: false,
    );
  }

  @override
  void dispose() {
    _buildingRetryTimer?.cancel();
    _positionSubscription?.cancel();
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    _pdrAltitudeSub?.cancel();
    _pdrRawMotionSub?.cancel();
    _escalatorArrivalTimer?.cancel();
    _floorSwitchProgress.dispose();
    // 탑승 중 화면이 닫히면 걸음이 멈춘 채로 전역 PDR 세션이 남는다. 다음
    // 화면에서 아무리 걸어도 위치가 갱신되지 않는다.
    if (_stepsPausedForRide) {
      _stepsPausedForRide = false;
      unawaited(indoorNavigationDriver.resumeStepTracking());
    }
    // 앱 전역 인스턴스라 dispose하지 않는다 — 실내 화면이 같은 컨트롤러를
    // 계속 구독한다.
    _debugModeController.removeListener(_onDebugModeChanged);
    _gpsVerdictDebugText.dispose();
    super.dispose();
  }

  /// 디버그 모드는 이제 **표시만** 바꾼다.
  ///
  /// 예전에는 디버그를 끄면 PDR 진입점(시작/종료 버튼)이 사라지므로 세션을 함께
  /// 정지시켰다. PDR이 실내 진입 중 상시 실행이 된 뒤에는 끌 대상이 없고, 여기서
  /// 정지시키면 "선을 숨기려다 위치 추적이 끊기는" 결과가 된다.
  void _onDebugModeChanged() {
    // 디버그 시트에서 개별 경로 토글을 켜고 끄면 여기로 들어온다. 레이어는
    // 이미 등록돼 있으므로 데이터만 다시 채우면 즉시 반영된다.
    unawaited(_syncDebugPdrLayers());
    // 디버그를 끄면 마지막 판정 문구를 버린다. 남겨 두면 다시 켰을 때 몇 분 전
    // 좌표의 숫자가 지금 값인 것처럼 떠 있고, 현장에서는 그걸 구분할 수 없다.
    if (!_debugModeController.enabled) _gpsVerdictDebugText.value = null;
    if (mounted) setState(() {});
  }

  /// 실내 진입 중에는 PDR 세션을 켜 둔다.
  ///
  /// anchor가 없으면 위치를 도면에 놓을 수 없지만, 센서를 미리 돌려두면 사용자가
  /// 위치를 지정하는 순간 heading이 이미 수렴한 상태다. 권한이 거부돼 있으면
  /// 자동 시작을 시도하지 않는다 — 진입마다 재시도하면 degraded warning만 쌓인다.
  Future<void> _startPdrIfIdle() async {
    final floor = _activeFloor;
    final graph = _floorGraph;
    if (floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      return;
    }
    if (indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle) {
      return;
    }
    if (!await isPedometerPermissionGranted()) return;
    if (!mounted || _activeFloor != floor) return;
    if (indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle) {
      return;
    }
    await indoorNavigationDriver.startGuidance(floorId: floor);
  }

  /// 건물(입구·footprint·층 목록)을 로드한다.
  ///
  /// **실패를 조용히 삼키면 안 된다.** 이 화면의 실내 기능은 전부 [_building]과
  /// [_buildingFootprint]에 걸려 있다 — 층 선택기, 위치 지정, 확대/탭 실내 진입
  /// 판정, 실내 도면 오버레이 등록이 모두 그렇다. 요청이 던지면 아래 setState가
  /// 아예 실행되지 않아 그 전부가 **아무 표시 없이** 사라진다. 예전에는 이
  /// 호출이 await도 catch도 없이 initState에서 발사돼 예외가 unhandled async
  /// error로만 남았고, 화면에는 "야외 지도는 멀쩡한데 실내 기능만 없는" 상태가
  /// 원인을 짚을 단서 하나 없이 남았다.
  ///
  /// 야외 지도 자체는 건물 없이도 쓸 수 있으므로, 실내 화면([IndoorMapBody])
  /// 처럼 전체 화면 에러로 덮지 않는다. 지도는 그대로 두고 재시도가 달린 배지만
  /// 띄워, 사용자가 왜 실내 기능이 없는지 알고 그 자리에서 복구할 수 있게 한다.
  Future<void> _loadBuildingEntrance() async {
    final Building? building;
    try {
      building = await buildingRepository.getBuilding(demoBuildingId);
    } catch (_) {
      if (!mounted) return;
      if (!_buildingLoadFailed) setState(() => _buildingLoadFailed = true);
      _scheduleBuildingRetry();
      return;
    }
    if (!mounted) return;
    // 성공했으면 예약된 재시도는 필요 없다. 사다리도 되돌려, 나중에 다시
    // 끊겼을 때 짧은 간격부터 새로 시작하게 한다.
    _buildingRetryTimer?.cancel();
    _buildingRetryTimer = null;
    _buildingRetryAttempt = 0;
    setState(() {
      _buildingLoadFailed = false;
      _building = building;
      _entrance = building?.entrance;
      _buildingFootprint = building?.footprintWgs84;
      _activeFloor = building?.initialFloor;
    });
    _notifyActiveFloor();
    _syncDestinationLayer();
    _syncBuildingLayer();
    // 스타일이 이미 로드된 뒤 건물이 늦게 도착한 케이스(테스트/느린 네트워크)를
    // 위해 실내 MVT 소스도 여기서 한 번 더 등록 시도.
    _ensureIndoorTilesRegistered();
    final floor = _activeFloor;
    if (building != null && floor != null) {
      // 지상 출입구는 층 그래프와 **독립적으로** 필요하다. 사용자가 층 chip으로
      // 다른 층을 훑는 순간 [_floorPlan]은 그 층 것으로 갈리는데, 문 목록은
      // 그동안에도 남아 있어야 야외 안내가 끊기지 않는다.
      unawaited(_loadGroundEntrances(building.id, floor));
      await _loadFloorGraph(building.id, floor);
    }
  }

  /// 지상 출입구 목록을 받아 [_groundEntrances]를 채운다.
  ///
  /// 실패는 조용히 넘긴다. 문을 못 받으면 문을 경유하지 않는 예전 안내(목적지
  /// 좌표로 바로 걷기 경로)로 폴백하는 것이 맞고, 여기서 에러를 띄우면 야외
  /// 지도를 쓰던 사용자에게 아무 조치도 못 할 경고만 남는다.
  ///
  /// [floor]는 건물의 기본 층(=출입구가 있는 지상층)이다. 백엔드가
  /// `default_floor`로 "출입구가 있는 지상 1층"을 내려주므로 그 값을 그대로 쓴다.
  Future<void> _loadGroundEntrances(String buildingId, String floor) async {
    final Map<String, dynamic>? geojson;
    try {
      geojson = await buildingRepository.getFloorGeoJson(buildingId, floor);
    } catch (_) {
      return;
    }
    if (!mounted || geojson == null) return;
    final entrances = groundEntrancesFrom(FloorPlan.fromJson(geojson));
    if (entrances.isEmpty) return;
    setState(() => _groundEntrances = entrances);
    _syncSelectedEntrance();
  }

  /// 현재 위치에서 가장 가까운 문을 다시 고르고, 바뀌었으면 상태에 반영한다.
  ///
  /// 여기서 [_entrance]도 함께 갱신한다. 그 값은 이 화면의 **실내 진입/이탈
  /// 판정 전체**가 보는 기준점이다. 백엔드 건물 응답에는 출입구 좌표가 없어
  /// 지금까지 이 값이 계속 null이었고, 그래서 GPS 자동 진입은 조건을 아무리
  /// 만족해도 발화하지 못했다. 문 좌표가 생긴 지금이 그 기준점을 채울 자리다.
  ///
  /// 위치를 아직 못 잡았으면 건물 중심을 대신 쓴다 — 문 하나라도 골라 둬야
  /// 진입 판정이 살아 있고, 실제 위치가 들어오면 곧바로 다시 고른다.
  void _syncSelectedEntrance() {
    if (_groundEntrances.isEmpty) return;
    final position = _position;
    final reference = position != null
        ? ll.LatLng(position.latitude, position.longitude)
        : _buildingCenter(_buildingFootprint ?? const []);
    if (reference == null) return;

    final picked = nearestEntrance(
      _groundEntrances,
      reference,
      current: _selectedEntrance,
    );
    if (picked == null || picked.id == _selectedEntrance?.id) return;
    setState(() {
      _selectedEntrance = picked;
      _entrance = picked.point;
    });
  }

  /// 진행 중인 층 그래프 로드. 자동 실내 진입은 GPS 이벤트를 따라 발화하므로
  /// 건물이 막 도착한 직후, 즉 층 그래프 요청이 아직 도는 중에 걸릴 수 있다.
  /// 그 순간 [_floorGraph]만 보면 "그래프 없음"으로 오판해 자동 앵커를 포기하게
  /// 되므로, [_startTrackingFromEntrance]가 이 future를 먼저 기다린다.
  Future<void>? _floorGraphLoad;

  /// 활성 층의 통행 그래프와 매장 목록(FloorPlan)을 함께 로드한다.
  /// - 그래프: PDR 앵커 배치·스냅과 마커 렌더링에 쓰인다.
  /// - 평면도: 실내 오버레이 위 매장 폴리곤 탭으로 벡터 타일 feature id를
  ///   실제 매장 정보로 되돌리는 데 쓴다.
  /// 실패는 조용히 넘겨 그래프/평면도 없이 층 시각화만 유지한다.
  Future<void> _loadFloorGraph(String buildingId, String floor) =>
      _floorGraphLoad = _fetchFloorGraph(buildingId, floor);

  Future<void> _fetchFloorGraph(String buildingId, String floor) async {
    try {
      final geojson = await buildingRepository.getFloorGeoJson(
        buildingId,
        floor,
      );
      // **추월당한 응답은 버린다.** 층을 연달아 바꾸면 요청이 겹치는데,
      // 저장소가 층별 future를 캐시하므로 이미 가 본 층은 즉시, 처음 가는
      // 층은 네트워크 시간 뒤에 도착한다 — 나중에 도착한 이전 층 응답이
      // 지금 층의 도면·그래프를 덮어쓰면, 화면에 그려진 층과 [_floorPlan]이
      // 어긋난다. 그 상태로는 카메라 fit이 엉뚱한 외곽선에 맞고(지하층 정렬
      // 이상), 매장 탭이 feature id를 다른 층 목록에서 찾다 실패하며(탭 불능
      // + 건물 파란 반짝임만 남음), 검색 포커스도 매장을 못 찾는다.
      if (!mounted || _activeFloor != floor) {
        debugPrint(
          '[outdoor overlay] 층 도면 버림: 요청=$floor 지금=$_activeFloor '
          'mounted=$mounted',
        );
        return;
      }
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
      _syncCorridorTracking(_pdrTrailState.snapshot);
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
      // 층 외곽선은 방금 받은 도면에서 나온다(어느 층이든 — [floorOutlineRing]).
      // 도면이 도착한 이 시점에 한 번 더 그려야 층을 바꾼 직후의 빈 외곽선이
      // 채워진다.
      unawaited(_syncFloorOutlineLayer());
      _syncDimScrimLayer();
      // 도면이 없어서 미뤄 둔 카메라 fit이 이 층 것이면 지금 실행한다
      // ([_pendingFloorFit]). 이 자리가 "그 층 외곽선이 처음으로 존재하는"
      // 시점이라, 여기서 맞춰야 배율이 정확히 한 번에 잡힌다.
      final pending = _pendingFloorFit;
      if (pending != null && pending.floor == floor) {
        _pendingFloorFit = null;
        // 이 함수 자체가 `_floorGraphLoad`라서, 기다리는 껍데기를 부르면
        // 자기 자신을 기다린다 — 몸통을 직접 부른다.
        unawaited(_fitCameraToLoadedFloor(pending.duration));
      }
    } catch (error, stackTrace) {
      // 로드 실패 시 앵커 배치·매장 탭은 안내로 막고 나머지 야외 지도 동작은
      // 그대로 유지한다. 성공 경로와 같은 이유로, 추월당한 요청의 실패가
      // 지금 층의 도면을 지우면 안 된다.
      //
      // **삼키되 조용하지는 않게 한다.** 여기서 터지면 층 외곽선·매장 탭·카메라
      // fit이 한꺼번에 죽는데, 화면에는 "실내 기능만 없는" 상태로만 보여서
      // 원인을 화면 밖에서 찾을 단서가 하나도 없다.
      debugPrint('[outdoor overlay] 층 도면 로드 실패($floor): $error\n$stackTrace');
      if (mounted && _activeFloor == floor) {
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

  /// 층 선택기에서 사용자가 직접 층을 골랐을 때.
  ///
  /// 층을 갈아 끼운 뒤 **그 층 외곽선에 카메라를 다시 맞춘다.** 층마다 크기가
  /// 달라서(지상 약 180 x 190 m ↔ B3·B4 286 x 305 m) 이전 층에 맞춰 둔 배율이
  /// 새 층에는 안 맞는다 — 지하로 내려가면 도면이 화면 밖으로 잘리고, 올라오면
  /// 여백만 남는다.
  ///
  /// **자동 층 전환에는 붙이지 않는다.** 안내 중 층이 바뀌는 순간
  /// ([_enqueueFloorTransition])에는 카메라가 사용자를 따라가야지 층 전체를
  /// 담으려 물러서면 안 된다. 그래서 재정렬을 [_switchOverlayFloor] 안이 아니라
  /// 이 사용자 조작 경로에만 둔다. (안내 중에는 층 선택기 자체가 접혀 있어
  /// 이 경로로 들어올 수도 없다.)
  Future<void> _onFloorChipSelected(String floor) async {
    if (floor == _activeFloor) return;
    // 크로스페이드 마무리(타일 대기 → 페이드인)는 떼어 둔 채 곧바로 돌아오므로
    // 카메라 재정렬(500ms)이 이전 층 도면이 아직 보이는 동안 시작된다 — 새
    // 도면은 카메라가 움직이는 위로 준비되는 대로 페이드인돼 하나의 전환으로
    // 읽힌다. 재정렬을 페이드 뒤로 미루면 전환이 두 박자("바뀌고, 그 다음
    // 움직이고")로 쪼개진다.
    await _switchOverlayFloorCrossfaded(floor, recenterIfNeeded: false);
    // 연타로 이 탭이 추월당했으면 카메라를 만지지 않는다 — 여기서 fit하면
    // 사용자가 마지막으로 고른 층 화면을 이전 탭의 층 외곽선에 맞춰 버린다
    // (지하층처럼 층마다 크기가 크게 다르면 정렬이 눈에 띄게 어긋난다).
    // 카메라는 마지막 탭의 이 함수 호출이 맞춘다.
    if (!mounted || _activeFloor != floor) return;
    // 층 그래프가 도착한 뒤라 [_activeFloorOutlineRing]이 새 층 외곽선을 준다
    // (`_switchOverlayFloor`가 `_loadFloorGraph`까지 기다린다).
    await _fitCameraToActiveFloor(duration: _floorSwitchZoomDuration);
  }

  /// [_switchOverlayFloor]를 크로스페이드로 돈다. **사람 조작으로 층이 바뀌는
  /// 모든 경로**(층 선택기, 검색·카테고리에서 타 층 매장, 경로 계산의 층 이동,
  /// 자동 전환 취소·되돌리기)가 이걸 쓴다 — 크로스페이드 없이 직접
  /// [_switchOverlayFloor]를 부르면 타일 교체가 "지워졌다 다시 그려지는"
  /// 장면으로 드러난다. 예외는 안내 중 자동 전환([_swapIndoorFloorSmoothly])
  /// 하나 — 거긴 셸의 불투명 스크림이 이미 같은 일을 한다.
  ///
  /// 이전 층 도면은 새 층 타일이 실제로 도착할 때까지 그대로 남고, 도착하면
  /// 새 도면이 그 위로 페이드인된다(오래 걸리면 그동안 에스컬레이터 모티프가
  /// 뜬다 — 판단은 [FloorSwitchProgressController]). 마무리(타일 대기 →
  /// 페이드인 → 이전 블록 제거)는 [_finalizeIndoorFloorCrossfade]가 떼어져
  /// 돌므로 이 함수는 층 그래프 로드까지만 기다린다. 연타 시 모티프의 주인은
  /// 마지막 호출이다(토큰).
  Future<void> _switchOverlayFloorCrossfaded(
    String floor, {
    bool recenterIfNeeded = true,
  }) async {
    final token = _floorSwitchProgress.begin(
      floorSwitchDirectionBetween(_activeFloor, floor),
    );
    var handedOff = false;
    try {
      handedOff = await _switchOverlayFloor(
        floor,
        recenterIfNeeded: recenterIfNeeded,
        crossfade: true,
        progressToken: token,
      );
    } finally {
      // 크로스페이드 마무리가 예약됐으면 완료 통지도 거기서 한다(타일이 아직
      // 오는 중인데 여기서 finish하면 모티프가 "로딩 중"에 걷힌다). 예약까지
      // 못 갔으면(같은 층, 지도 미준비, 예외) 여기서 반드시 알린다 — 안
      // 그러면 모티프가 영영 안 걷힌다.
      if (!handedOff) _floorSwitchProgress.finish(token);
    }
  }

  /// 층 도면을 갈아 끼운다. 실내 MVT 오버레이 소스를 새 층 타일로 바꾸고,
  /// PDR 스냅용 층 그래프도 함께 갱신한다.
  /// [recenterIfNeeded]가 false면 마지막의 [_recenterOnBuildingIfNeeded]를
  /// 건너뛴다. 호출자가 곧바로 카메라를 다시 맞출 때 쓴다 — 두 애니메이션이
  /// 겹치면 지도가 한 번 움찔했다가 다시 움직인다.
  ///
  /// [crossfade]가 false(안내 중 자동 전환 — 셸의 불투명 스크림이 교체를
  /// 가린다)면 이전 층 소스·레이어를 지우고 새 층을 등록하는 즉시 교체다.
  /// true(사람 조작, [_switchOverlayFloorCrossfaded])면 이전 층 블록을 화면에
  /// 남긴 채 새 층 블록을 **투명하게** 위에 등록하고, 타일 도착을 기다렸다가
  /// 페이드인하는 마무리([_finalizeIndoorFloorCrossfade])를 떼어서 예약한다.
  /// 반환값은 그 마무리가 예약됐는지 — 예약됐다면 [progressToken]의 finish도
  /// 마무리가 맡는다.
  Future<bool> _switchOverlayFloor(
    String floor, {
    bool recenterIfNeeded = true,
    bool crossfade = false,
    int? progressToken,
  }) async {
    if (floor == _activeFloor) return false;
    final controller = _mapController;
    final building = _building;
    if (building == null) return false;
    // **컨트롤러가 없어도 층 상태와 그래프는 바꾼다.** 예전에는 여기서 통째로
    // 빠져나갔는데, 그러면 스타일이 아직 안 올라온 사이에 온 층 전환(자동 층
    // 이동이 대표적이다)이 조용히 사라진다. 지도 레이어를 만지는 부분만
    // 컨트롤러가 있을 때 한다.
    final canDrawLayers = controller != null && _styleReady;

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
      // 세그먼트가 갈아타면 진행거리 기준점도 새 세그먼트 기준으로 다시 잡아야
      // 한다. 남겨두면 층을 바꾼 순간 남은거리가 튄다.
      _guidance
        ..setRouteSegment(multiRoute == null ? null : nextSegmentRoute)
        ..seedProgress(null);
      // 층이 바뀌면 그 층에 강조하던 매장은 지도에 없다. 강조도 초기화.
      _highlightedStoreId = null;
    });
    // **세션에도 지금 알린다.** 다음 스냅샷까지 미루면 그 사이 세션은 이전 층
    // 기준 보정 위치를 들고 있고, 화면은 새 층 그래프로 좌표를 되돌린다 —
    // 마커가 새 층 도면 위 엉뚱한 자리에 찍힌다. 서 있으면 스냅샷이 몇 초씩
    // 안 오므로 한 프레임이 아니라 눈에 보이는 시간 동안 어긋난다.
    _guidance.setContext(
      floorId: floor,
      graph: _floorGraph,
      floorLabels: building.floors,
    );
    _notifyActiveFloor();
    // 층이 바뀐 순간 이전 층의 외곽선은 더 이상 맞지 않는다. 새 도면이 도착할
    // 때까지(지하 → 다른 층) 선을 지워 둔다 — 틀린 경계를 보여주지 않는다.
    unawaited(_syncFloorOutlineLayer());
    // 크로스페이드면 이전 층 블록을 지우지 않고 은퇴 목록으로 넘긴다 — 새 층
    // 타일이 도착할 때까지 이전 도면이 그대로 보이는 것이 연출의 핵심이다.
    // 제거는 페이드인이 끝난 뒤 [_finalizeIndoorFloorCrossfade]가 한다.
    var retiredForCrossfade = false;
    if (canDrawLayers && _indoorTilesRegistered) {
      if (crossfade) {
        _retiringIndoorBlocks.add((
          layerIds: _indoorOverlayLayerIds,
          sourceId: _indoorTilesSourceId,
        ));
        retiredForCrossfade = true;
        _indoorTilesRegistered = false;
        _bumpIndoorIds();
      } else {
        // 앞선 크로스페이드가 마무리 전에 이 경로(안내 중 자동 전환)로
        // 끊겼으면 은퇴 블록이 남아 있을 수 있다 — 여기서 함께 지운다.
        await _removeRetiringIndoorBlocks(controller);
        // 순서 중요: 레이어부터 지워야 소스를 지울 수 있다(레이어가 붙어있으면
        // 오류). 이미 없는 레이어에 대해 removeLayer가 예외를 던지는 native
        // 구현도 있어 각 항목을 try/catch로 감싼다.
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
        // native(Android/iOS)가 이전 remove의 정리를 아직 못 끝내 조용히
        // 실패하는 경우가 있다(특정 층으로 전환 시 아무것도 안 그려지는
        // 원인이었음).
        _bumpIndoorIds();
      }
    }
    // 은퇴 블록이 있으면 새 블록은 투명(계수 0)하게 얹는다 — 타일이 도착해도
    // 페이드인 전까지는 이전 도면이 보인다. 은퇴 블록이 없으면(첫 등록) 가릴
    // 이전 도면 자체가 없으므로 원래 불투명도로 바로 얹는다.
    await _ensureIndoorTilesRegistered(fadeFactor: retiredForCrossfade ? 0 : 1);
    var crossfadeScheduled = false;
    if (crossfade && canDrawLayers && _indoorTilesRegistered) {
      crossfadeScheduled = true;
      unawaited(
        _finalizeIndoorFloorCrossfade(
          generation: _indoorIdGeneration,
          progressToken: progressToken,
        ),
      );
    }
    await _loadFloorGraph(building.id, floor);
    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    _syncRouteLayer();
    // 층이 바뀌면 도착 핀도 다시 판정한다 — 다층 경로에서 도착지 층을 벗어나면
    // 핀이 사라지고, 다시 그 층으로 돌아오면 살아난다.
    _syncIndoorDestinationLayer();
    _syncHighlightLayer();
    _notifyRouteStateIfChanged();
    // 층 chip을 눌렀는데 카메라가 건물 밖을 보거나 실내 오버레이가 페이드인되기
    // 전 zoom(<17.5)에 있으면 사용자는 새 층 도면을 볼 수 없다 — "5F/6F를 골랐는데
    // 아무것도 안 나온다"는 인상을 준다. 층 chip 탭은 명시적으로 "그 층을 보고
    // 싶다"는 신호이므로, 이 경우 건물 중심으로 카메라를 옮겨 오버레이가 확실히
    // 화면에 뜨게 한다. 이미 건물이 잘 보이는 상태에서 층만 바꾼 경우에는 카메라를
    // 건드리지 않는다 — 그 상황에서 강제로 재정렬하면 사용자의 view가 불필요하게
    // 튀어 조작감이 나빠진다.
    if (recenterIfNeeded) await _recenterOnBuildingIfNeeded();
    return crossfadeScheduled;
  }

  /// 크로스페이드 마무리 — 새 층 타일 도착을 기다렸다가 새 도면을 페이드인하고
  /// 이전 층 블록을 지운다. [_switchOverlayFloor]가 새 블록을 등록한 직후
  /// 떼어서(unawaited) 부른다 — 호출자는 타일을 기다릴 필요가 없고, 카메라
  /// 재정렬이 로드와 겹쳐서 돈다.
  ///
  /// "타일 도착"은 고정 딜레이가 아니라 **실제 로드 신호**다: 새 소스의
  /// `footprint`를 [MapLibreMapController.querySourceFeatures]로 폴링해, 로드된
  /// 타일에 feature가 잡히는 순간을 준비 완료로 본다. 주차구역 폴리곤이 수백
  /// 개라 로드에 수 초 걸리는 층(B3·5F·6F)에서도 이전 도면이 끝까지 유지되는
  /// 근거다. 화면 밖·minzoom 미만이라 타일 요청 자체가 없으면 feature가 영영
  /// 안 잡히므로 [floorSwitchTilesReadyTimeout]에서 끊고 그냥 교체한다(그
  /// 줌에서는 오버레이가 어차피 안 보여 교체 장면도 없다).
  ///
  /// [generation]은 이 마무리가 맡은 소스 세대다. 기다리는 사이 새 전환이
  /// 시작되면(세대 불일치) 즉시 물러난다 — 은퇴 블록 정리까지 포함해 마지막
  /// 전환의 마무리가 이어받는다. [progressToken]이 있으면 어떤 경로로 끝나든
  /// 에스컬레이터 모티프 컨트롤러에 완료를 알린다(추월당한 토큰의 finish는
  /// 컨트롤러가 무시한다).
  Future<void> _finalizeIndoorFloorCrossfade({
    required int generation,
    int? progressToken,
  }) async {
    try {
      final elapsed = Stopwatch()..start();
      while (true) {
        if (!mounted || _indoorIdGeneration != generation) return;
        final controller = _mapController;
        if (controller == null) return;
        List<dynamic> features = const [];
        try {
          features = await controller.querySourceFeatures(
            _indoorTilesSourceId,
            'footprint',
            null,
          );
        } catch (_) {}
        if (features.isNotEmpty ||
            elapsed.elapsed >= floorSwitchTilesReadyTimeout) {
          break;
        }
        await Future<void>.delayed(floorSwitchTilesPollInterval);
      }
      if (!mounted || _indoorIdGeneration != generation) return;
      final controller = _mapController;
      if (controller == null) return;

      // 즉시 교체 임계 안에 준비된 전환(캐시된 층)은 페이드 없이 바로 보여
      // 준다 — 빠른 층 훑기에 페이드 잔상이 끌리지 않게. 계수가 이미 1이면
      // (첫 등록이라 은퇴 블록이 없던 경우) 페이드할 것도 없다.
      final animate =
          _indoorOverlayFadeFactor < 1 &&
          elapsed.elapsed >= floorSwitchInstantSwapThreshold;
      if (animate) {
        final stepInterval =
            floorSwitchCrossfadeDuration ~/ floorSwitchCrossfadeSteps;
        for (var step = 1; step <= floorSwitchCrossfadeSteps; step++) {
          _indoorOverlayFadeFactor = Curves.easeOut.transform(
            step / floorSwitchCrossfadeSteps,
          );
          await _applyOverlayFillFadeFactor(controller);
          if (step < floorSwitchCrossfadeSteps) {
            await Future<void>.delayed(stepInterval);
          }
          if (!mounted || _indoorIdGeneration != generation) return;
        }
      }
      // 최종 상태: 계수 1로 전체 레이어(심볼 포함)를 원래 불투명도로 되돌린다.
      // 심볼(라벨·아이콘)은 단계 페이드에서 뺐다 — 성긴 점 요소라 fill이 다
      // 올라온 끝에 한 번에 켜져도 팝이 안 읽히고, 단계마다 보내는 전체 속성
      // 교체(플랫폼 채널 호출)를 절반으로 줄인다.
      _indoorOverlayFadeFactor = 1;
      await _syncIndoorOverlayFade();
      if (!mounted || _indoorIdGeneration != generation) return;
      // 새 도면이 완전히 올라왔으니 이전 층 블록(연타로 쌓인 것 포함)을 지운다.
      await _removeRetiringIndoorBlocks(controller);
    } finally {
      if (progressToken != null) {
        _floorSwitchProgress.finish(progressToken);
      }
    }
  }

  /// 크로스페이드 뒤에 남은 이전 층 소스·레이어 묶음을 전부 지운다. 이미 없는
  /// 레이어에 removeLayer가 예외를 던지는 native 구현이 있어 각각 삼킨다.
  Future<void> _removeRetiringIndoorBlocks(
    MapLibreMapController controller,
  ) async {
    while (_retiringIndoorBlocks.isNotEmpty) {
      final block = _retiringIndoorBlocks.removeLast();
      for (final id in block.layerIds) {
        try {
          await controller.removeLayer(id);
        } catch (_) {}
      }
      try {
        await controller.removeSource(block.sourceId);
      } catch (_) {}
    }
  }

  /// 크로스페이드 단계마다 현재 계수([_indoorOverlayFadeFactor])를 fill 레이어
  /// 4종에 적용한다. **opacity만 보내면 안 되고 전체 속성을 다시 보낸다** —
  /// setLayerProperties는 patch가 아니라 전체 교체다(indoor_overlay_layers.dart
  /// 상단 규칙).
  Future<void> _applyOverlayFillFadeFactor(
    MapLibreMapController controller,
  ) async {
    final fadeExpr = _overlayFadeExpr();
    for (final (id, props) in [
      (_indoorFootprintLayerId, indoorFootprintProps(fadeExpr)),
      (_indoorStoresFillLayerId, indoorStoresFillProps(fadeExpr)),
      (
        _indoorCategoryHighlightFillLayerId,
        indoorCategoryHighlightProps(fadeExpr),
      ),
      (
        _indoorVerticalTransportFillLayerId,
        indoorVerticalTransportProps(fadeExpr),
      ),
    ]) {
      try {
        await controller.setLayerProperties(id, props);
      } catch (_) {}
    }
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

  /// 직전 좌표를 기기가 찍은 시각. 좌표 사이 간격을 진단 칩에 띄우는 데만 쓴다.
  DateTime? _lastFixAt;

  /// 마지막으로 TMAP 도보 경로를 요청한 좌표.
  ///
  /// 위치 스트림이 1초에 한 번으로 빨라졌기 때문에 필요해졌다. 예전에는 스트림
  /// 자체가 5 m마다 왔으므로 좌표 한 건 = 요청 한 번이어도 됐다.
  ll.LatLng? _lastRouteRequestOrigin;

  /// 디버그 모드에서 지도 위에 띄우는 GPS 진입 판정 근거 한 줄.
  ///
  /// `setState`가 아니라 [ValueNotifier]인 이유는 갱신 빈도다. 좌표는 5 m마다
  /// 들어오는데 그때마다 이 화면 전체(지도·오버레이·바)를 다시 그리면, 진단을
  /// 켰다는 이유로 측정 대상인 성능이 달라진다. 칩만 다시 그린다.
  ///
  /// null이면 칩을 그리지 않는다 — 디버그 모드가 꺼져 있거나 아직 좌표가 한 건도
  /// 안 들어온 상태다.
  final ValueNotifier<String?> _gpsVerdictDebugText = ValueNotifier<String?>(
    null,
  );

  /// 이번 실내 상태가 **자동 진입**으로 켜졌는지.
  ///
  /// 자동 이탈은 자동 진입을 되돌리기 위한 것이다. 사용자가 건물을 직접 탭해서
  /// 도면을 연 경우까지 자동으로 닫으면, 입구 앞에 서서 층 도면을 보려던 사람의
  /// 화면이 신호가 잡히는 순간 제멋대로 닫힌다.
  bool _indoorEnteredByGps = false;

  /// GPS 구독을 붙여 둘 상태인지.
  ///
  /// **실내에서도 끊지 않는다.** 진입/이탈 판정의 유일한 입력이 GPS 좌표라
  /// ([judgeBuildingFromGps]), 끊으면 사용자가 아무 조작 없이 걸어 나갔을 때
  /// 알 방법이 없다. 유일하게 끊는 경우는 이 화면이 안 보일 때다
  /// (`widget.active == false`).
  ///
  /// 실내에서 들어온 좌표를 **화면에 쓰지 않는 것**은 별개의 게이트가 맡는다
  /// ([_outdoorGpsVisible]). 두 값을 겸하게 하면 실내 도면 위에 건물 밖으로 튄
  /// 파란 점이 찍히던 예전 문제가 돌아온다.
  bool get _gpsTrackingWanted => widget.active;

  /// GPS 기반 **표시**를 화면에 써도 되는 상태인지 — 현재 위치 마커, 'GPS 신호
  /// 약함' 배지, 첫 위치로 카메라를 옮기는 동작이 여기에 걸린다.
  ///
  /// [_gpsTrackingWanted]와 반드시 구분해야 한다. 그쪽은 "구독이 붙어 있어야
  /// 하는가"이고 실내 이탈 확인용 구독까지 포함하는데, 그 구독으로 들어온 위치는
  /// 화면에 쓰면 안 된다. 둘을 같은 값으로 쓰면 실내 도면 위에 건물 밖 GPS 점이
  /// 찍히고(예전 버그), 위치가 비어 있다는 이유만으로 신호 배지가 뜬다.
  bool get _outdoorGpsVisible => widget.active && !_indoorEntered;

  /// 실내(PDR) 위치를 화면과 길찾기에 써도 되는 상태인지 — [_outdoorGpsVisible]의
  /// 반대쪽 짝이다. 두 값은 **동시에 true가 되지 않는다**: 실내 오버레이가 켜져
  /// 있으면 PDR만, 야외 상태면 GPS만 쓴다.
  ///
  /// 이 구분이 없으면 실내에서 위치를 지정한 뒤 축소해 야외로 나왔을 때, 야외
  /// 지도 위에 실내 위치 아이콘이 그대로 남고(도면은 페이드로 사라졌는데 파란
  /// 점만 공중에 떠 있는 상태) 길찾기 출발지도 그 실내 앵커로 잡힌다. 야외에서는
  /// GPS가 위치의 유일한 출처여야 한다.
  bool get _indoorLocationVisible => _indoorEntered;

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
    setState(() => _position = null);
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
    // 좌표가 얼마 만에 왔는지는 **기기가 찍은 시각**으로 잰다. 앱이 받은 시각을
    // 쓰면 프레임이 밀린 시간까지 섞여, 스트림이 느린 것인지 화면이 느린 것인지
    // 구분되지 않는다. 진단 칩에만 쓰이는 값이다.
    final sinceLastFix = _lastFixAt == null
        ? null
        : position.timestamp.difference(_lastFixAt!);
    _lastFixAt = position.timestamp;
    // 실내에서도 좌표는 **들고 있는다.** 진입/이탈 판정의 유일한 입력이고,
    // 화면에 그릴지는 [_outdoorGpsVisible]이 따로 가른다([_syncCurrentLayer]).
    setState(() => _position = position);
    _syncCurrentLayer();
    // 안내 중이면 카메라가 사용자를 따라간다. 판정보다 먼저 두는 이유는, 이번
    // 위치로 실내에 들어가면 따라가기가 꺼지기 때문이다 — 그때는 카메라의
    // 주인이 실내 위치(PDR)로 바뀐다.
    if (_followingUser) unawaited(_moveCameraToUser(position));
    // 문 선택은 진입 판정보다 **먼저** 갱신한다. 진입 직후 실내 위치를 잡을 때
    // 폴백으로 쓰는 문이 이 선택의 결과라, 순서를 뒤집으면 사용자가 이미 다른
    // 문으로 들어왔는데 폴백은 한 박자 전 문을 가리킨다.
    if (!_indoorEntered) _syncSelectedEntrance();
    _applyBuildingVerdict(position, sinceLastFix: sinceLastFix);
    // 여기서부터는 야외 전용이다. 건물 안에서 GPS로 걷기 경로를 다시 그리면,
    // 실내 도면 위에 건물을 관통하는 선이 얹힌다.
    if (_indoorEntered) return;
    _updateRoute(position, fromPositionStream: true);
  }

  /// 위치 한 건이 말하는 건물 안팎을 상태에 반영한다.
  ///
  /// 판정 자체는 [judgeBuildingFromGps]가 하고, 여기서는 **그 판정으로 무엇을
  /// 할지**만 정한다. 셋으로 갈린다.
  ///
  ///   - 안 + 야외 상태 + 자동 진입 무장 → 실내로 들어가고 위치를 잡는다.
  ///   - 밖 → 자동 진입을 다시 무장한다. 그리고 자동으로 들어온 실내 상태였다면
  ///     야외로 되돌린다.
  ///   - 모름 → 아무것도 하지 않는다.
  ///
  /// 자동 이탈을 [_indoorEnteredByGps]로 막는 것이 중요하다. 사용자가 건물을 직접
  /// 탭해 도면을 열어 둔 경우까지 닫으면, 길 건너에서 층 도면을 훑어보려던 사람의
  /// 화면이 좌표가 들어오는 순간 제멋대로 닫힌다.
  void _applyBuildingVerdict(Position position, {Duration? sinceLastFix}) {
    final judgement = judgeBuildingFromGps(
      fix: GpsFix(
        point: ll.LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
      ),
      footprint: _buildingFootprint,
    );
    // 진단 칩은 아래 switch가 상태를 바꾸기 **전에** 채운다. 무장 여부는 이 판정을
    // 내릴 때의 값이어야 하는데, switch가 그 값을 갱신하기 때문이다.
    _gpsVerdictDebugText.value = _debugModeController.enabled
        ? describeGpsBuildingJudgement(
            judgement,
            armed: _gpsEntryArmed,
            sinceLastFix: sinceLastFix,
          )
        : null;
    switch (judgement.verdict) {
      case GpsBuildingVerdict.inside:
        if (_indoorEntered || !_gpsEntryArmed) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('건물 감지 중...')));
        // _setIndoorEntered가 이 표식을 보므로 **먼저** 세운다.
        _indoorEnteredByGps = true;
        _setIndoorEntered(true);
        unawaited(_startTrackingFromGpsFix(position));
      case GpsBuildingVerdict.outside:
        // 건물을 확실히 벗어났다. 다음 진입을 다시 자동으로 잡을 수 있게 한다.
        _gpsEntryArmed = true;
        if (!_indoorEntered || !_indoorEnteredByGps) return;
        // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
        if (_placingPdrAnchor) _setPlacingAnchor(false);
        _setIndoorEntered(false);
      case GpsBuildingVerdict.unclear:
        break;
    }
  }

  /// 자동 실내 진입 직후, 실내 위치(PDR 앵커)를 잡고 센서 추적을 시작한다.
  ///
  /// **시작점은 방금 그 GPS 좌표에서 가장 가까운 통로 지점이다.** 진입 판정
  /// 자체가 "믿을 수 있는 좌표가 건물 안"이라는 근거로 났으므로, 그 좌표가 지금
  /// 사용자가 서 있는 곳에 가장 가까운 값이다. 스냅이 안 되면(통로에서
  /// [_maxIndoorGpsSnapDistanceM]보다 멀거나 층 좌표로 못 옮기면) 방금 지나온
  /// 문으로 폴백한다 — 건물에 들어온 사람은 어느 문이든 통과했다.
  ///
  /// 예전에는 트리거가 층 오버레이만 켜고 끝났다. 그래서 건물에 들어와도 지도에는
  /// 내 위치가 없었고, 하단 바 "위치 지정"을 눌러 복도를 직접 탭해야 비로소 걸음
  /// 추적이 시작됐다.
  ///
  /// **먼저 실패 조건부터.** 아래 중 하나라도 걸리면 자동 앵커를 포기하고 기존
  /// 수동 경로를 안내한다 — 틀린 위치를 찍는 것보다 위치가 없는 편이 낫다.
  ///   - 이미 확정된 앵커가 있다 → 사용자가 직접 잡아 둔 위치를 덮지 않는다.
  ///   - 층 그래프가 없다 → WGS84를 층 좌표로 옮길 수 없다.
  ///   - GPS 스냅도 문 폴백도 실패 → 시작점을 정할 근거가 없다.
  Future<void> _startTrackingFromGpsFix(Position position) async {
    if (indoorNavigationDriver.currentCalibration.canRenderPosition) return;

    // 건물이 막 도착한 직후라면 층 그래프 요청이 아직 도는 중이다.
    await _floorGraphLoad;
    if (!mounted || !_indoorEntered) return;

    final floor = _activeFloor;
    final graph = _floorGraph;
    final buildingId = _building?.id;
    if (buildingId == null ||
        floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      _replaceSnack('이 층의 지도 정보가 없어 실내 위치를 자동으로 잡지 못했습니다. 위치 지정으로 직접 지정해주세요.');
      return;
    }

    final transform = fitFloorGeoTransform(graph.nodes);
    final matcher = FloorMapMatcher(graph);

    /// [point](WGS84)를 층 좌표로 옮겨 통로에 붙인다. 옮기지 못했거나 통로에서
    /// [maxGapM]보다 멀면 null — 그 자리는 걸을 수 있는 곳이 아니다.
    ({PdrLocalPoint point, double gapM})? snap(
      ll.LatLng point,
      double maxGapM,
    ) {
      final local = transform.invert(point.latitude, point.longitude);
      if (local == null) return null;
      final snapped = matcher.snapToWalkableNetwork(
        PdrLocalPoint(local.$1, local.$2),
      );
      if (snapped == null || snapped.distanceToGraphM > maxGapM) return null;
      return (point: snapped.point, gapM: snapped.distanceToGraphM);
    }

    // 1순위는 GPS 좌표다. 진입 판정을 통과한 좌표라 이미 "믿을 수 있고 건물 안"
    // 이며, 사용자가 실제로 서 있는 곳에 가장 가깝다.
    var snapped = snap(
      ll.LatLng(position.latitude, position.longitude),
      _maxIndoorGpsSnapDistanceM,
    );
    var estimateSource = 'gps';
    if (snapped == null) {
      // 2순위는 방금 지나온 문. 건물에 들어온 사람은 어느 문이든 통과했으므로,
      // GPS 점이 매장 한가운데에 찍혀 통로를 못 찾은 경우의 안전한 폴백이다.
      final entrance = _entrance;
      snapped = entrance == null
          ? null
          : snap(entrance, _maxEntranceAnchorSnapDistanceM);
      estimateSource = 'entrance';
    }
    if (snapped == null) {
      // 실측 거리를 함께 노출하고 싶지만, 여기까지 왔다는 것은 두 좌표 모두
      // 스냅에 실패했다는 뜻이라 적을 거리 자체가 없다. 사용자가 할 수 있는 일만
      // 알린다 — 수동 지정은 탭한 자리를 그대로 쓰므로 이 실패와 무관하다.
      _replaceSnack('실내 위치를 자동으로 잡지 못했습니다. 위치 지정으로 직접 지정해주세요.');
      return;
    }

    final estimatedPoint = snapped.point;
    final estimatedWgs84 = transform.apply(
      estimatedPoint.eastM,
      estimatedPoint.northM,
    );
    indoorLocationEstimateController.update(
      IndoorLocationEstimate(
        buildingId: buildingId,
        floorId: floor,
        localM: estimatedPoint,
        wgs84: ll.LatLng(estimatedWgs84.$1, estimatedWgs84.$2),
        accuracyMeters: position.accuracy,
        observedAt: position.timestamp,
        source: estimateSource,
      ),
    );
    unawaited(_syncPdrCurrentLayer());

    // GPS로 건물 안임을 이미 확인했으므로 권한 게이트를 다시 두지 않는다. 세션이
    // 다른 층에서 돌고 있으면 이 층으로 옮겨야 앵커가 이 층으로 기록된다.
    if (!await _bindPdrSessionToFloor(floor, gatePermission: false)) return;
    await _awaitSensorWarmup();
    if (!mounted || !_indoorEntered) return;

    final axes = fitPdrToFloorAxes(graph.nodes);
    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: estimatedPoint,
      axes: axes,
    );
    if (!mounted) return;

    // 자북 heading을 못 얻는 기기는 여기서 방향 보정을 기다린다. 수동 배치는
    // 사용자에게 다이얼로그로 물어보지만, 자동 진입에서 아무 조작 없이 모달이
    // 튀어나오면 사용자는 자기가 뭘 눌러 띄운 건지 알 수 없다. 대신 진입 방향을
    // 추정해 그 자리에서 확정한다([_entryFloorDirection]).
    if (indoorNavigationDriver.currentCalibration.phase ==
        CalibrationPhase.awaitingHeading) {
      final direction = _entryFloorDirection(
        position: position,
        anchorFloorPoint: estimatedPoint,
        graph: graph,
        axes: axes,
      );
      if (direction == null) {
        _replaceSnack('진입 방향을 알 수 없습니다. 위치 지정으로 직접 지정해주세요.');
        return;
      }
      await indoorNavigationDriver.confirmAnchorByFloorDirection(
        floorDirection: direction,
      );
      if (!mounted) return;
    }

    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    // 입구에서 위치를 새로 잡았으므로, 건물에 들어오기 전에 골라둔 출발지 매장은
    // 더 이상 "지금 내가 있는 곳"이 아니다. 상위가 그 값을 버리게 알린다.
    widget.onLocationAnchored?.call();
    _replaceSnack('입구를 기준으로 실내 위치를 잡았습니다. 걸음 추적을 시작합니다.');
  }

  /// 센서 세션이 첫 이벤트를 보고할 때까지(최대 [_sensorWarmupTimeout]) 기다린다.
  ///
  /// [IndoorNavigationDriver.confirmAnchorByPin]은 **호출 시점의** heading
  /// reference로 분기한다. 자북 heading을 이미 받았으면 회전 0으로 즉시 확정하고,
  /// 아직 아무 heading도 못 받았으면 arbitrary로 보고 수동 방향 보정을 요구한다.
  /// 수동 배치에서는 사용자가 지도를 보고 탭하는 몇 초가 자연스러운 유예였지만,
  /// 자동 배치는 startGuidance 직후 곧바로 찍으므로 그 유예가 없다. 기다리지
  /// 않으면 나침반이 멀쩡한 기기까지 전부 방향 보정 분기로 빠져, 추정한 진입
  /// 방향이 회전각으로 박히고 이후 궤적 전체가 그만큼 돌아간다.
  Future<void> _awaitSensorWarmup() async {
    bool reported(PdrRuntimeState state) =>
        state == PdrRuntimeState.running || state == PdrRuntimeState.degraded;
    if (reported(indoorNavigationDriver.currentRuntimeStatus.state)) return;
    try {
      await indoorNavigationDriver.runtimeStatuses
          .firstWhere((status) => reported(status.state))
          .timeout(_sensorWarmupTimeout);
    } on Object {
      // 센서가 끝내 조용해도(권한 거부·미지원 기기·타임아웃) 앵커는 찍는다 —
      // 걸음이 쌓이지 않더라도 "어느 입구로 들어왔는지"는 지도에 보여야 한다.
    }
  }

  /// arbitrary reference 기기에서 쓸 "진입 방향"을 층 좌표 벡터로 만든다.
  /// 층 좌표계는 데이터셋마다 축이 뒤집혀 있을 수 있어, 나침반 각도는 반드시
  /// [axes]를 거쳐 층 벡터로 바꾼다.
  PdrLocalPoint? _entryFloorDirection({
    required Position position,
    required PdrLocalPoint anchorFloorPoint,
    required FloorGraph graph,
    required PdrToFloorAxes axes,
  }) {
    // 1순위: GPS course. 실제로 측정된 이동 방향이라 가장 정확하다. 다만 멈춰
    // 있을 때는 값이 의미 없고 플랫폼이 0으로 채우므로 속도로 먼저 거른다.
    final course = position.heading;
    if (position.speed >= _entryCourseMinSpeedMps &&
        course > 0 &&
        course < 360) {
      return axes.apply(pdrDirectionForBearing(course));
    }
    // 2순위: 입구 → 층 그래프 중심. 입구를 통과한 사람은 건물 안쪽을 향한다.
    // GPS course보다 거칠지만, 방향을 몰라 awaitingHeading에 멈춰 서면 앵커가
    // 확정되지 않아 위치 아이콘도 걸음 추적도 아예 없다. 회전이 어긋나면
    // 사용자가 "위치 지정"으로 다시 잡을 수 있으므로 되돌릴 수 있는 오차다.
    var sumX = 0.0;
    var sumY = 0.0;
    for (final node in graph.nodes) {
      sumX += node.xM;
      sumY += node.yM;
    }
    final dx = sumX / graph.nodes.length - anchorFloorPoint.eastM;
    final dy = sumY / graph.nodes.length - anchorFloorPoint.northM;
    // 입구가 그래프 중심과 사실상 같은 점이면 방향 벡터가 0이 된다.
    if (dx * dx + dy * dy < 1e-6) return null;
    return PdrLocalPoint(dx, dy);
  }

  /// [fromPositionStream]이 true면 **마지막으로 요청한 지점에서 충분히 움직였을
  /// 때만** TMAP을 다시 부른다([shouldRecomputeRouteAfterMove]). 위치 스트림이
  /// 1초에 한 번 오게 된 뒤로, 걸으면서 이 함수를 부를 때마다 요청을 내보내면
  /// 초당 한 번씩 외부 API를 두드린다.
  ///
  /// **사용자가 목적지를 고른 호출(false)은 절대 거르지 않는다.** 제자리에 서서
  /// 도착지를 눌렀을 때 "아무 일도 일어나지 않는" 화면이 되기 때문이다. 문 재선택
  /// ([_retargetJourneyEntrance])은 네트워크를 타지 않으므로 거르는 쪽에 두지
  /// 않는다 — 좌표가 올 때마다 그대로 돈다.
  Future<void> _updateRoute(
    Position position, {
    bool fromPositionStream = false,
  }) async {
    // 문 경유 안내 중이면 이번 위치로 다시 고른 문이 목적지다. 걸어가는 동안
    // 더 가까운 문이 생기면([_syncSelectedEntrance]가 이미 갱신했다) 야외 구간의
    // 도착점과 실내 구간의 시작점을 함께 갈아 끼운다 — 한쪽만 바꾸면 도보 경로는
    // 새 문으로 가는데 실내 경로는 옛 문에서 시작하는 화면이 된다.
    if (_pendingIndoorDestination != null) _retargetJourneyEntrance();

    // 길찾기가 그린 **계획 경로**는 출발점이 못박혀 있다. GPS가 갱신될 때마다
    // 다시 계산하면 사용자가 비교하려고 보고 있는 선이 걸음마다 흔들린다.
    if (_fixedRouteOrigin != null) return;

    // 야외 걷기 경로는 **사용자가 목적지를 고른 경우에만** 그린다.
    //
    // 예전에는 목적지가 없으면 [_entrance]로 폴백했지만, 백엔드가 건물 출입구
    // 좌표를 내려주지 않아 그 값이 늘 null이었고 폴백은 한 번도 실행되지 않았다.
    // 이제 [_syncSelectedEntrance]가 실제 문 좌표로 그 값을 채우므로, 폴백을
    // 그대로 두면 앱을 켜고 GPS가 잡히는 것만으로 아무도 요청하지 않은
    // "가장 가까운 문까지" 경로가 그려지고, 위치가 갱신될 때마다 TMAP 요청이
    // 나간다. [_entrance]는 진입/이탈 판정의 기준점이지 목적지가 아니다.
    final target = _userDestination;
    if (target == null) return;

    final origin = ll.LatLng(position.latitude, position.longitude);
    if (fromPositionStream &&
        !shouldRecomputeRouteAfterMove(
          origin: origin,
          lastRequestedOrigin: _lastRouteRequestOrigin,
        )) {
      return;
    }
    _lastRouteRequestOrigin = origin;

    final route = await directionsRepository.getWalkingRoute(
      origin: origin,
      destination: target,
    );
    if (!mounted) return;
    // 도착점이 문이면 TMAP 선이 문 앞에서 끊기거나, 아예 문에 닿지 못한 채
    // 엉뚱한 곳으로 돌아간다([extendRouteToDestination]).
    _applyRoute(extendRouteToDestination(route, target));
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
    _notifyRouteStateIfChanged();
    final isVisible = route != null;
    if (!wasVisible && isVisible) {
      // **자동으로 생긴 경로는 카메라를 가져가지 않는다.**
      //
      // 야외에서 GPS가 잡히면 사용자가 부탁한 적 없어도 건물 입구까지의 걷기
      // 경로를 계산한다([_updateRoute]의 `_userDestination ?? _entrance`).
      // 그 경로가 처음 생기는 순간 여기서 전체를 화면에 맞추면, 사용자가 지금
      // 무엇을 보고 있든 **내 위치부터 건물까지**가 다 들어오는 배율로 튕겨
      // 나간다. 멀리 있을수록 심해서, 검색으로 건물을 찾아 막 확대한 화면이
      // 도시 전체 축척으로 바뀌고 정작 건물은 점이 된다 — "건물 위치가 안
      // 나온다"의 정체가 이것이다.
      //
      // 사용자가 직접 고른 목적지([_userDestination])면 그대로 맞춘다. 그건
      // "이 경로를 보여 달라"는 요청이라 화면을 가져가는 것이 맞다.
      if (_userDestination != null) _fitCameraToRoute(route);
    }
  }

  void _fitCameraToRoute(DirectionsRoute route) {
    // 출발점과 도착점이 사실상 같은 좌표면(예: 건물 입구 바로 앞) 경계 상자
    // 폭이 0에 가까워져 줌 계산이 발산한다 — 이 경우엔 화면에 맞출 "경로"랄
    // 게 없으니 자동 줌은 건너뛴다.
    if (route.points.length < 2 || route.distanceMeters < 5) return;
    _fitCameraToPoints(route.points);
  }

  /// 좌표열 전체가 화면에 들어오도록 카메라를 맞춘다. 도보 경로와 대중교통
  /// 경로가 같은 여백 규칙을 쓰도록 뽑아 두었다 — 값이 갈리면 안내를 바꿀
  /// 때마다 경로가 화면에서 다른 크기로 잡힌다.
  void _fitCameraToPoints(List<ll.LatLng> points) {
    if (points.length < 2) return;
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    var minLng = double.infinity;
    var maxLng = double.negativeInfinity;
    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    // 경계 상자가 한 점으로 수렴하면(모든 좌표가 같음) 줌 계산이 발산한다.
    if (maxLat - minLat < 1e-7 && maxLng - minLng < 1e-7) return;
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _handlePosition(position);
      final controller = _mapController;
      if (controller != null && _styleReady) {
        await controller.animateCamera(
          CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
        );
      }
    } catch (_) {
      _showSnack('위치를 다시 확인하지 못했습니다');
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
    bool keepPendingIndoorRoute = false,
  }) async {
    // 문 경유 안내가 스스로를 부를 때만 pending을 지키고, 그 밖의 새 안내는
    // 이전 여정을 걷어낸다. 남겨 두면 사용자가 다른 곳으로 안내를 바꾼 뒤에
    // 건물에 들어갔을 때 지웠어야 할 실내 경로가 혼자 되살아난다.
    if (!keepPendingIndoorRoute) _clearPendingIndoorRoute();
    // 새 도보 목적지를 받으면 이전 대중교통 안내는 끝난 것이다. 남겨 두면
    // 다른 곳으로 걸어가는 화면 위에 예전 버스 노선이 계속 그려진다.
    clearTransitRoute();
    // 새 안내는 새 계획이다. 이전 자동차 안내의 따라가기를 남기면 경로 전체를
    // 보여 줘야 할 화면이 사용자 위치에 붙들린다.
    _stopFollowingUser();
    setState(() {
      // 이번 안내의 출발지가 무엇인지 여기서 확정한다. origin이 없으면 GPS로
      // 되돌아가야 하므로 반드시 null로 지워야 한다 — 안 지우면 예전에 찍어 둔
      // 지점이 계속 출발지로 남아, 현재 위치에서 출발하는 안내가 영영 안 된다.
      _fixedRouteOrigin = origin;
      // 이 경로는 걷는 안내다. 자동차에서 넘어왔으면 실선으로 남지 않게 되돌린다.
      _routeIsDriving = false;
      _offerStartGuidance = false;
      _userDestination = destination;
      _userDestinationLabel = label;
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면
      // _applyRoute가 "새로 생김"으로 보고 카메라를 다시 맞추게 한다.
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    // 여기서는 아직 chrome이 접히지 않는다 — `_route`를 방금 null로 되돌렸고,
    // 안내 chrome은 경로가 실제로 그려진 뒤에야 접힌다([shouldFoldGuidanceChrome]).
    // 그래도 통보한다: 앞선 안내가 돌고 있었다면 그게 여기서 끝나므로 접혀 있던
    // chrome을 되돌려야 하고, 아래 경로 계산이 실패해 그대로 return하는 경로에서도
    // 화면이 접힌 채 남지 않는다.
    _notifyRouteStateIfChanged();

    if (origin != null) {
      final route = await directionsRepository.getWalkingRoute(
        origin: origin,
        destination: destination,
      );
      if (!mounted) return;
      _applyRoute(extendRouteToDestination(route, destination));
      return;
    }

    // 야외 길찾기의 출발지는 GPS 현재 위치뿐이다(실내 앵커는 쓰지 않는다).
    // 아직 신호를 못 잡았으면 경로를 계산할 수 없으므로, 조용히 끝내지 않고
    // 이유를 알린다 — 안내가 없으면 "도착을 눌렀는데 아무 일도 안 일어남"이 된다.
    final position = _position;
    if (position == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인해주세요.');
      return;
    }
    await _updateRoute(position);
  }

  /// 길찾기가 **미리 계산해 온** 도로 경로(자동차·도보)를 그대로 그린다.
  ///
  /// [showRouteTo]와 나눈 이유는 경로를 누가 계산하느냐가 다르기 때문이다.
  /// showRouteTo는 목적지만 받아 이 화면이 직접 TMAP을 부르지만, 길찾기는 요약
  /// 카드에 적을 거리·시간이 필요해 이미 응답을 손에 쥐고 있다. 여기서 다시
  /// 부르면 같은 구간을 두 번 조회하고, 두 응답이 미묘하게 달라지면 카드와
  /// 지도가 다른 경로를 말하게 된다.
  ///
  /// 출발점을 [_fixedRouteOrigin]으로 박는 것이 중요하다. 이건 걷는 동안 따라가는
  /// 안내가 아니라 **한 번 그려 놓고 비교하는 계획 화면**이라, GPS가 갱신될
  /// 때마다 경로가 다시 계산되면 사용자가 보던 선이 흔들린다.
  ///
  /// [offerStartGuidance]가 참이면 하단 카드에 "안내 시작"을 붙인다.
  Future<void> showPlannedRoadRoute(
    DirectionsRoute route, {
    required ll.LatLng origin,
    required ll.LatLng destination,
    required String label,
    bool offerStartGuidance = false,
    bool driving = false,
  }) async {
    _clearPendingIndoorRoute();
    clearTransitRoute();
    // 경로를 **다시 그리는** 중이다(수단 변경·끝점 변경). 아직 "안내 시작" 전
    // 이므로 카메라는 경로 전체를 보여 줘야 한다.
    _stopFollowingUser();
    setState(() {
      _offerStartGuidance = offerStartGuidance;
      _routeIsDriving = driving;
      _fixedRouteOrigin = origin;
      _userDestination = destination;
      _userDestinationLabel = label;
      // 먼저 비워야 [_applyRoute]가 "새로 생김"으로 보고 카메라를 경로 전체에
      // 맞춘다. 안 비우면 수단을 바꿔도 카메라가 옛 경로 자리에 머문다.
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    _applyRoute(route);
  }

  /// 자동차 안내를 시작한다 — 카메라를 현재 위치로 확대하고, 이후 위치가 갱신될
  /// 때마다 그 자리를 따라간다.
  ///
  /// 위치를 아직 못 잡았어도 **켜 둔다.** 신호가 잡히는 순간 첫 위치가 카메라를
  /// 데려가므로, 여기서 포기하면 터널을 나오며 안내를 시작한 사용자가 영영
  /// 따라가지 못한다. 대신 지금 아무 일도 안 일어나는 이유는 알린다.
  Future<void> startFollowingCurrentLocation() async {
    _followingUser = true;
    // 버튼을 눌렀으면 이제 안내 중이다. 계획 상태로 되돌리는 길은 안내 종료뿐.
    if (_offerStartGuidance) setState(() => _offerStartGuidance = false);
    final position = _position;
    if (position == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. 신호가 잡히면 그 자리로 지도를 옮깁니다.');
      return;
    }
    await _moveCameraToUser(position, zoom: _carGuidanceZoom);
  }

  /// 따라가기를 멈춘다. 안내가 끝나거나(경로 삭제) 카메라의 주인이 바뀌는
  /// 지점(새 경로 계산)에서 부른다 — 안 멈추면 사용자가 지도를 옮겨도 다음 위치
  /// 한 건이 곧바로 되돌려 놓아 지도를 조작할 수 없다.
  void _stopFollowingUser() => _followingUser = false;

  /// 카메라를 [position]으로 옮긴다. [zoom]을 주면 그 값으로 확대하고, 없으면
  /// 지금 배율을 유지한다 — 따라가는 동안 사용자가 맞춘 배율을 빼앗지 않는다.
  Future<void> _moveCameraToUser(Position position, {double? zoom}) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final target = LatLng(position.latitude, position.longitude);
    await controller.animateCamera(
      zoom == null
          ? CameraUpdate.newLatLng(target)
          : CameraUpdate.newLatLngZoom(target, zoom),
    );
  }

  /// 이 화면이 아는 "지금 출발할 자리". 지도에서 찍어 둔 출발 지점이 있으면 그
  /// 값을, 없으면 GPS를 쓴다.
  ///
  /// **실내 PDR 앵커는 쓰지 않는다.** 건물 안 좌표를 도로 경로의 출발지로 보내면
  /// TMAP이 건물 반대편 도로로 스냅한다.
  ll.LatLng? get routeOriginPoint {
    final fixed = _fixedRouteOrigin;
    if (fixed != null) return fixed;
    final position = _position;
    if (position == null) return null;
    return ll.LatLng(position.latitude, position.longitude);
  }

  /// [point]가 우리 실내 도면이 있는 건물 **안**이면, 그 건물의 지상 출입구
  /// 좌표를 돌려준다. 밖이거나 건물을 아직 못 받았으면 null.
  ///
  /// TMAP POI 중에는 건물 **안** 매장이 섞여 있다(예: 백화점 입점 브랜드).
  /// 그 좌표를 도로 안내의 끝점으로 그대로 쓰면 도착점이 건물 내부라, TMAP이
  /// 가장 가까운 도로로 스냅하면서 실제로 들어갈 수 있는 문과 다른 면에
  /// 사용자를 내려놓는다.
  ///
  /// 여기는 **엄격한** 판정을 쓴다. 묻는 것이 "이 좌표를 안내의 끝점으로 써도
  /// 되는가"이고, 그게 못 쓰는 좌표가 되는 건 정말로 건물 안일 때뿐이다.
  /// [isAtIndoorBuilding]처럼 여유를 주면 건물 옆 노점까지 건물 문으로 안내한다.
  ll.LatLng? entranceIfInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    final inside = footprint != null && isPointInPolygon(point, footprint);
    if (!inside) return null;
    final building = _building;
    return building == null ? null : entrancePointFor(building.id);
  }

  /// 야외(GPS)에서 건물 안 매장까지 한 번에 안내한다.
  ///
  /// 야외 구간만 그리고, 실내 구간은 계산해 두었다가 건물에 들어간 순간
  /// [_activatePendingIndoorRoute]가 이어 붙인다.
  ///
  /// **폴백을 먼저 정한다.** 아래 중 하나라도 걸리면 문을 경유하지 않고 예전처럼
  /// 목적지 좌표로 곧장 걷기 경로를 그린다. 문 경유가 안 되는 것이 길안내가
  /// 아예 안 되는 것보다 낫다.
  ///   - 목적지에 실내 노드가 없다 → 실내 구간을 만들 수 없다.
  ///   - 지상 출입구 데이터가 없다 → 경유할 문이 없다.
  ///   - 건물 그래프를 못 받았거나 경로가 안 풀린다 → 야외 구간까지는 안내한다.
  ///
  /// [origin]을 주면 GPS 대신 그 지점에서 출발한다 — 사용자가 지도에서 출발
  /// 위치를 직접 찍은 경우다. 문 선택도 그 지점 기준으로 바뀐다. 현재 위치가
  /// 아니라 **출발 지점**에서 가까운 문으로 들어가는 것이 맞기 때문이다.
  Future<void> showOutdoorToIndoorRouteTo(
    PoiSearchResult destination, {
    ll.LatLng? origin,
  }) async {
    // **실내 오버레이가 켜져 있으면 먼저 접는다.**
    //
    // 이 메서드는 "사용자가 건물 밖에 있다"는 전제 위에 서 있다 — 안에 있으면
    // 호출부가 실내 라우팅으로 보낸다. 그런데 오버레이는 확대·건물 탭·검색의
    // "건물 안에서 매장 고르기"만으로도 켜지므로, 밖에 선 사용자가 도면을 펴
    // 놓은 채로 여기 들어오는 경로가 실제로 있다.
    //
    // 접지 않으면 실내 구간이 **영영 안 그려진다.** 아래에서 쌓아 두는
    // [_pendingIndoorRoute]를 실제 안내로 올리는 트리거가 "실내로 들어가는
    // 순간"([_setIndoorEntered])인데, 이미 들어와 있으면 그 순간이 다시 오지
    // 않는다. 화면에는 도면 위에 야외 구간만 얹힌 채로 남는다.
    //
    // 접어 두면 두 가지가 동시에 맞는다 — 지금 필요한 안내(문까지 걸어가기)가
    // 야외 지도에 제대로 보이고, 사용자가 실제로 건물에 들어가거나 다시 확대하는
    // 순간 그 트리거가 정상으로 발화해 실내 구간이 이어 붙는다.
    await returnToOutdoorView();
    if (!mounted) return;

    final building = _building;
    final endNodeId = destination.nodeId;
    if (building == null || endNodeId == null || destination.floor.isEmpty) {
      await showRouteTo(
        destination.point,
        label: destination.name,
        origin: origin,
      );
      return;
    }
    // 문은 출발 지점에서 가까운 것을 고른다. 지도에서 찍은 출발지가 있으면 그
    // 좌표가, 없으면 GPS가 기준이다. 둘 다 없으면 경로 자체를 못 만드는데,
    // showRouteTo가 그 안내를 이미 갖고 있으므로 거기로 흘려보낸다.
    final position = _position;
    final reference =
        origin ??
        (position == null
            ? null
            : ll.LatLng(position.latitude, position.longitude));
    if (reference == null) {
      await showRouteTo(destination.point, label: destination.name);
      return;
    }
    // [_selectedEntrance]가 아니라 [_journeyEntrance]를 이력으로 넘긴다. 앞의
    // 값은 **GPS 기준**으로 진입 판정이 쓰는 문이라, 멀리 찍은 출발지로 안내할
    // 때 그 값을 섞으면 두 판단이 서로를 끌어당긴다.
    final entrance = nearestEntrance(
      _groundEntrances,
      reference,
      current: _journeyEntrance,
    );
    if (entrance == null) {
      await showRouteTo(
        destination.point,
        label: destination.name,
        origin: origin,
      );
      return;
    }

    // 실내 구간을 **먼저** 푼다. 그래야 야외 경로를 그리기 전에 "이 문으로
    // 들어가면 목적지까지 갈 수 있는가"가 확정된다.
    final graph =
        _journeyBuildingGraph ??
        await buildingRepository.getBuildingGraph(building.id);
    if (!mounted) return;
    final leg = graph == null
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);

    setState(() {
      _journeyBuildingGraph = graph;
      _journeyEntrance = entrance;
      _pendingIndoorDestination = destination;
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
      // 실내 경로가 남아 있으면 [_syncRouteLayer]가 야외 구간 대신 그것을 그린다.
      _guidance
        ..setRouteSegment(null)
        ..clearProgress()
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
      _indoorRouteDestination = null;
    });
    _syncDestinationLayer();
    _syncIndoorDestinationLayer();

    if (leg == null || leg.isEmpty) {
      // 문까지는 안내하되 침묵하지 않는다 — 안내가 문 앞에서 끝나는 이유를
      // 사용자가 알아야 그 자리에서 다른 방법을 찾을 수 있다.
      _showSnack('건물 안 경로를 계산하지 못했습니다. 출입구까지만 안내합니다.');
    }
    await showRouteTo(
      entrance.point,
      label: _journeyEtaLabel(destination, entrance),
      origin: origin,
      keepPendingIndoorRoute: true,
    );
  }

  /// 문 경유 안내의 ETA 카드 라벨. 목적지와 경유하는 문을 함께 적어, 왜 경로가
  /// 목적지가 아니라 건물 모서리로 향하는지 사용자가 화면에서 바로 알 수 있게 한다.
  String _journeyEtaLabel(
    PoiSearchResult destination,
    BuildingEntrance entrance,
  ) {
    final label = entranceDirectionLabel(
      entrance,
      _buildingCenter(_buildingFootprint ?? const []),
    );
    return '${destination.name}까지 · $label 경유';
  }

  /// 안내 중인 문이 바뀌었으면 야외 도착점과 실내 구간을 새 문 기준으로 다시 맞춘다.
  ///
  /// 실내 구간은 서버에 다시 묻지 않고 들고 있던 그래프로 그 자리에서 푼다 —
  /// 문 선택은 GPS를 따라 여러 번 바뀔 수 있고, 그때마다 네트워크를 타면 신호가
  /// 나쁜 건물 앞에서 정확히 실패한다.
  void _retargetJourneyEntrance() {
    final entrance = _selectedEntrance;
    final destination = _pendingIndoorDestination;
    if (entrance == null || destination == null) return;
    // 이미 이 문을 향하고 있으면 할 일이 없다.
    if (entrance.id == _journeyEntrance?.id) return;

    final graph = _journeyBuildingGraph;
    final endNodeId = destination.nodeId;
    final leg = (graph == null || endNodeId == null)
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);
    setState(() {
      _journeyEntrance = entrance;
      _userDestination = entrance.point;
      _userDestinationLabel = _journeyEtaLabel(destination, entrance);
      // 새 문에서 경로가 안 풀리면 옛 구간을 남기지 않는다. 남기면 사용자는
      // 남쪽 문으로 걸어가는데 실내 안내만 서쪽 문에서 시작하는 상태가 된다.
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
    });
  }

  /// 건물에 들어간 순간, 미리 풀어 둔 실내 구간을 실제 안내로 승격한다.
  ///
  /// **야외 구간은 지우지 않고 들고 있는다.** 예전에는 지웠는데, 그러면 건물에
  /// 들어갔다가 다시 밖으로 나온 사용자에게 아무 경로도 안 남는다 — 안내가
  /// 통째로 사라진 것처럼 보이고, 처음부터 다시 검색해야 한다.
  Future<void> _activatePendingIndoorRoute() async {
    final route = _pendingIndoorRoute;
    final destination = _pendingIndoorDestination;
    if (route == null || destination == null) return;

    final startFloor = route.segments.first.floorName;
    if (_activeFloor != startFloor) {
      await _switchOverlayFloor(startFloor);
      if (!mounted) return;
    }
    setState(() {
      // _route·_userDestination(야외 구간)은 그대로 둔다. 밖으로 나오면 다시
      // 그려야 하는 값이다.
      _pendingIndoorRoute = null;
      _pendingIndoorDestination = null;
      _journeyEntrance = null;
      _indoorRouteDestination = destination;
      _indoorMultiFloorRoute = route;
      // 층별 구간은 공용 세션이 소유한다 — 진행률이 그 값에 투영되므로 여기서
      // 따로 들면 남은거리가 갈라진다([_indoorRouteSegment]). 같은 층 경로를
      // 얹는 자리와 같은 순서를 쓴다.
      _guidance
        ..setRouteSegment(route.segmentForFloor(startFloor)?.route)
        ..seedProgress(null)
        ..setRoute(route);
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    final segment = route.segmentForFloor(startFloor);
    if (segment != null && segment.route.points.length >= 2) {
      _fitCameraToIndoorRoute(segment.route);
    }
    _beginRouteRecordingSession();
  }

  /// 문 경유 안내를 접는다. 야외 구간이 사라지는 모든 경로에서 함께 불린다 —
  /// 남겨 두면 사용자가 안내를 끈 뒤에 건물에 들어갔을 때 지웠던 실내 경로가
  /// 혼자 되살아난다.
  void _clearPendingIndoorRoute() {
    if (_pendingIndoorRoute == null && _pendingIndoorDestination == null) {
      return;
    }
    setState(() {
      _pendingIndoorRoute = null;
      _pendingIndoorDestination = null;
      _journeyEntrance = null;
    });
    // 문 경유가 끝나면 목적지 핀의 조건도 바뀐다([_syncDestinationLayer]).
    unawaited(_syncDestinationLayer());
  }

  /// "이 건물까지" 안내할 때 쓸 도착 좌표.
  ///
  /// 지상 출입구를 **먼저** 고른다. 건물 중심을 도착점으로 주면 TMAP 보행자
  /// 경로가 건물 안쪽을 향하다가 가장 가까운 도로로 스냅해, 실제로 들어갈 수
  /// 있는 문과 다른 면에 사용자를 내려놓는다. 문은 출발 지점에서 가까운 것을
  /// 고른다 — [showOutdoorToIndoorRouteTo]가 매장 안내에서 쓰는 규칙과 같다.
  ///
  /// 문 데이터가 없는 건물이면 [_entrance](백엔드 출입구 좌표)로, 그것도 없으면
  /// 외곽선 중심으로 떨어진다. 셋 다 없으면 null이고, 호출부는 그때 도착·출발
  /// 버튼 자체를 감춘다.
  ///
  /// [buildingId]를 받는 이유는 이 화면이 **한 채**의 건물만 로드하기
  /// 때문이다(demoBuildingId). 인자 없이 좌표만 돌려주면, 호출부가 다른 건물을
  /// 물었을 때도 이 건물의 문을 돌려줘 엉뚱한 좌표가 그 건물의 도착지로 박힌다.
  ll.LatLng? entrancePointFor(String buildingId) {
    if (_building?.id != buildingId) return null;
    final position = _position;
    final reference = position == null
        ? null
        : ll.LatLng(position.latitude, position.longitude);
    if (reference != null) {
      final door = nearestEntrance(_groundEntrances, reference);
      if (door != null) return door.point;
    }
    final known = _entrance;
    if (known != null) return known;
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.isEmpty) return null;
    return _buildingCenter(footprint);
  }

  /// 이 화면에 그려진 안내를 **전부** 지운다 — 야외 도보 구간과 실내 구간까지.
  ///
  /// 상단 길찾기 바의 X처럼 "길찾기 자체를 끝낸다"는 뜻일 때 쓴다. 재계산 직전에
  /// 옛 선만 치우는 경로와 나누지 않으면, 수단을 바꿀 때마다 문 경유 안내의
  /// 실내 뒷부분이 함께 날아가 문 앞에서 안내가 끊긴다.
  void clearAllRoutes() {
    _clearUserDestination();
    _clearIndoorRoute();
  }

  void _clearUserDestination() {
    clearTransitRoute();
    // 안내가 여기서 끝난다. 따라가기를 남기면 카메라가 계속 사용자를 쫓아다녀
    // 지도를 훑어볼 수 없다.
    _stopFollowingUser();
    _clearPendingIndoorRoute();
    setState(() {
      _userDestination = null;
      _userDestinationLabel = null;
      _route = null;
      _fixedRouteOrigin = null;
      // 그릴 경로가 없으면 시작할 안내도 없다. 안 지우면 다음에 뜨는 도보 카드에
      // 자동차용 "안내 시작"이 얹힌다.
      _offerStartGuidance = false;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    _notifyRouteStateIfChanged();
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
    bool announceOriginAnchor = true,
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
    // 매장을 출발지로 골랐으면 현재 위치도 그 매장으로 옮긴다. 이걸 안 하면
    // 경로는 그 매장에서 뻗어 나가는데 위치 아이콘만 예전 자리(또는 아무 데도)
    // 남아, 사용자는 자기가 어디 있다고 표시되는지와 경로가 어긋난 화면을 본다.
    if (hasExplicitOrigin) {
      await _anchorAtStoreOrigin(
        floor: originFloor,
        nodeId: originNodeId,
        storePoint: origin!.point,
        storeName: origin.name,
        announce: announceOriginAnchor,
      );
      if (!mounted) return;
    }
    // 이전 걷기 경로가 남아 있으면 함께 지워, 실내 경로만 화면에 뜨도록 한다.
    setState(() {
      _route = null;
      _userDestination = null;
      _userDestinationLabel = null;
      _indoorRouteDestination = destination;
      // 새 경로를 그리기 전에 초기화 — 아래 compute가 성공하면 다시 채운다.
      _guidance.setRouteSegment(null);
      _indoorMultiFloorRoute = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    // 경로 계산 전에도 도착지 centroid에 핀을 먼저 띄운다 — 사용자가 고른
    // 매장이 어디인지 즉시 보이고, 계산이 끝나면 도착 노드로 옮겨 붙는다.
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();

    // 사용자가 목적지를 고른 **이 순간**이 개요 연출을 하는 유일한 자리다.
    // 여기서만 켜 두면 "안내당 한 번"이 별도 플래그 없이 지켜진다 — 재탐색은
    // 아래 [_rerouteIndoorFromCurrentPosition]에서 끄고, 층 전환은 스크림 뒤에서
    // 조용히 처리한다([_swapIndoorFloorSmoothly]).
    if (startFloor == endFloor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: building.id,
        floor: endFloor,
        endNodeId: endNodeId,
        playOverview: true,
        startNodeId: explicitStartNodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: building.id,
        startFloor: startFloor,
        endFloor: endFloor,
        endNodeId: endNodeId,
        playOverview: true,
        startNodeId: explicitStartNodeId,
      );
    }
  }

  /// 출발지로 고른 매장 자리에 PDR 앵커를 다시 찍어, 현재 위치 아이콘을 그
  /// 매장으로 옮긴다.
  ///
  /// 사용자가 "이 매장에서 출발한다"고 말한 것은 곧 "나는 지금 여기 있다"는
  /// 뜻이므로, 지도를 탭해 직접 지정한 것과 같은 취급을 한다 — 그래서 배치도
  /// 수동 배치와 **같은 함수**([_confirmPdrAnchor])를 쓴다. 자북 heading을 주는
  /// 기기는 그 자리에서 조용히 확정되고, 그렇지 못한 기기는 수동 배치와 똑같이
  /// 진행 방향을 한 번 물어본다. 방향을 0으로 가정해 조용히 넘어가면 이후
  /// 걸음 궤적 전체가 그만큼 돌아간 채로 쌓인다.
  ///
  /// 실패는 조용히 넘긴다. 위치 아이콘을 못 옮기더라도 경로 자체는 그려져야
  /// 한다 — 여기서 return해 버리면 길찾기가 통째로 죽는다.
  /// [announce]가 false면 "여기서 출발하는 것으로 봤다"는 안내를 띄우지 않는다.
  ///
  /// 그 안내는 앱이 사용자의 현재 위치를 **말없이** 옮겼을 때 알리려는 것이다.
  /// 출발↔도착 맞바꾸기처럼 사용자가 방금 그 이동을 직접 시킨 경우에는 알릴
  /// 것이 없다 — 누를 때마다 되돌리기 손잡이가 뜨면 조작을 방해하기만 한다.
  Future<void> _anchorAtStoreOrigin({
    required String floor,
    required String nodeId,
    required ll.LatLng storePoint,
    required String storeName,
    bool announce = true,
  }) async {
    // [_confirmPdrAnchor]가 축 변환(axes)을 [_floorGraph]에서 가져오므로,
    // 앵커를 찍기 전에 그 층 그래프가 화면에 올라와 있어야 한다.
    if (floor != _activeFloor) {
      await _switchOverlayFloorCrossfaded(floor);
      if (!mounted) return;
    }
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return;

    // 매장의 입구 노드를 그대로 쓴다. 그 노드는 이미 통로 위에 있으므로 스냅이
    // 필요 없고, 경로 탐색이 시작하는 지점과도 정확히 같은 자리가 된다.
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    final PdrLocalPoint floorPoint;
    if (node != null) {
      floorPoint = PdrLocalPoint(node.xM, node.yM);
    } else {
      // 노드를 못 찾는 경우(그래프 갱신 시차 등)는 매장 좌표를 층 좌표로 되돌려
      // 가장 가까운 통로에 붙인다 — 수동 배치가 탭 좌표에 하는 것과 같다.
      final local = fitFloorGeoTransform(
        graph.nodes,
      ).invert(storePoint.latitude, storePoint.longitude);
      if (local == null) return;
      final snapped = FloorMapMatcher(
        graph,
      ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
      if (snapped == null) return;
      floorPoint = snapped.point;
    }

    if (!await _bindPdrSessionToFloor(floor)) return;
    await _confirmPdrAnchor(floorPoint, notifyLocationChanged: false);
    if (!mounted) return;
    if (!indoorNavigationDriver.currentCalibration.canRenderPosition) return;
    if (!announce) return;
    // 되돌릴 손잡이를 함께 띄운다. 출발지가 실제 위치와 다르면 조용히 틀린
    // 지점에서 안내가 시작되는데, 그건 사용자가 알아챌 수 있어야 한다.
    showDebugToast(
      context,
      message: '$storeName에서 출발하는 것으로 보고 현재 위치를 잡았습니다.',
      bottomOffset:
          _mapShellBottomChromePx +
          (_hasAnyRouteVisible ? _etaCardHeightPx : 0) +
          12,
      actionLabel: '위치 다시 지정',
      onAction: () => unawaited(_resetAnchorForManualPlacement(floor)),
    );
  }

  /// 자동으로 잡은 앵커를 버리고 사용자 지정 흐름으로 되돌린다.
  Future<void> _resetAnchorForManualPlacement(String floor) async {
    // changeFloor는 같은 층으로 불러도 걸음 세션과 앵커를 초기화하고
    // awaitingPin으로 되돌린다 — 앵커만 버리는 전용 명령이 따로 없다.
    await indoorNavigationDriver.changeFloor(floorId: floor);
    if (!mounted) return;
    await startLocationPlacement();
  }

  /// 같은 층 안에서 계산한 실내 경로를 지도에 얹는다. 활성 층이 목적지 층과
  /// 다르면 먼저 그 층으로 오버레이를 전환해 필요한 그래프를 다시 로드한다.
  /// [startNodeId]가 주어지면(길찾기 시트에서 매장을 출발지로 고른 경우) 그
  /// 노드에서 바로 출발하고, null이면 PDR 앵커 주변 최근접 통로 노드를 찾는다.
  ///
  /// [playOverview]는 경로를 그린 뒤 개요 연출([_fitCameraToRouteSegment])을 할지다.
  /// **기본값을 두지 않는다** — 안내 시작이냐 재탐색이냐에 따라 답이 정반대라,
  /// 빠뜨리면 조용히 틀린 쪽으로 굴러간다.
  Future<void> _computeAndShowSingleFloorIndoorRoute({
    required String buildingId,
    required String floor,
    required String endNodeId,
    required bool playOverview,
    String? startNodeId,
  }) async {
    if (floor != _activeFloor) {
      // 목적지 층으로 화면을 옮기는 사람 조작 흐름이다. 새 도면 페이드인은
      // 이어지는 경로 개요 연출(playOverview)과 겹쳐 하나의 전환으로 읽힌다.
      await _switchOverlayFloorCrossfaded(floor);
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
      _guidance
        ..setRouteSegment(route)
        ..seedProgress(null)
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    if (playOverview) unawaited(_fitCameraToRouteSegment(route));
    // 이 경로 한 건이 진단 세션 하나가 된다. 이전 세션 데이터는 여기서
    // 버려지므로 내보내기 안내는 띄우지 않는다 — 길안내가 끝난 게 아니라
    // 목적지가 바뀐 것이고, 안내를 눌러도 꺼낼 게 없다.
    if (_pdrDebugRecorder != null) {
      _endRouteRecordingSession(announceExport: false);
    }
    _beginRouteRecordingSession();
  }

  /// 층이 다른 매장까지의 층 간 경로를 계산해 층별 세그먼트로 나누고, 현재
  /// 화면(_activeFloor)에 해당하는 세그먼트를 지도에 얹는다. 층 chip으로
  /// 다른 층을 훑으면 [_switchOverlayFloor]가 그 층 세그먼트로 갈아탄다.
  /// 시작 층부터 훑도록 활성 층을 자동으로 시작 층으로 전환한다.
  /// [startNodeId]가 주어지면(길찾기 시트에서 매장을 출발지로 고른 경우) 그
  /// 노드에서 바로 출발하고, null이면 PDR 앵커 기준으로 시작 노드를 고른다.
  /// [playOverview]의 뜻은 [_computeAndShowSingleFloorIndoorRoute]와 같다.
  Future<void> _computeAndShowMultiFloorIndoorRoute({
    required String buildingId,
    required String startFloor,
    required String endFloor,
    required String endNodeId,
    required bool playOverview,
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
      await _switchOverlayFloorCrossfaded(startFloor);
      if (!mounted) return;
    }
    final segment = route.segmentForFloor(startFloor);
    setState(() {
      _indoorMultiFloorRoute = route;
      _guidance
        ..setRouteSegment(segment?.route)
        ..seedProgress(null)
        ..setRoute(route);
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    if (playOverview && segment != null) {
      unawaited(_fitCameraToRouteSegment(segment.route));
    }
    if (_pdrDebugRecorder != null) {
      _endRouteRecordingSession(announceExport: false);
    }
    _beginRouteRecordingSession();
  }

  /// 현재 위치에서 건물 안 **모든 그래프 노드**까지의 거리·비용.
  ///
  /// 검색 결과 목록이 매장마다 "몇 m · 도보 몇 분"을 붙이는 데 쓴다. 목적지를
  /// 아직 고르지 않은 시점에 부르는 값이라 [showRouteTo]와 달리 도착 노드가
  /// 없고, 그래서 [reachableFrom]으로 한 번만 탐색해 전 노드 결과를 받는다.
  ///
  /// **null을 돌려주는 경우가 여러 가지다** — 위치(앵커)가 아직 없거나, 그래프를
  /// 못 받았거나, 앵커 층에 그래프 노드가 없을 때다. 호출부는 어느 쪽이든 거리
  /// 줄을 아예 그리지 않는다. 줄마다 "거리 알 수 없음"을 반복하면 목록이 읽히지
  /// 않고, 사용자가 할 수 있는 일도 어차피 "위치 지정" 하나뿐이다.
  Future<Map<String, NodeReach>?> reachFromCurrentPosition() async {
    final anchor = _pdrTrailState.anchor;
    final buildingId = _building?.id;
    if (anchor == null || buildingId == null) return null;

    final graph = await buildingRepository.getBuildingGraph(buildingId);
    if (!mounted || graph == null || graph.nodes.isEmpty) return null;

    // 경로 계산과 **같은 시작 노드**를 쓴다. 여기서 다른 규칙으로 고르면 목록에
    // 적힌 거리와 실제로 길찾기를 눌렀을 때 나오는 거리가 서로 달라진다.
    final startNodeId = _pickStartNodeIdInBuildingGraph(
      graph: graph,
      startFloorName: anchor.floorId,
    );
    if (startNodeId == null) return null;

    try {
      return reachableFrom(
        nodes: graph.nodes,
        edges: graph.edges,
        startNodeId: startNodeId,
      );
    } on ArgumentError {
      // 그래프가 깨져 있어도 목록 자체는 계속 떠야 한다 — 거리만 빠진다.
      return null;
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

  /// 야외 구간 ETA. 문 경유 안내 중이면 미리 풀어 둔 실내 구간까지 더한다.
  ///
  /// 더하지 않으면 카드가 "이솝까지"라고 적어 두고 실제로는 **문까지의** 거리와
  /// 시간만 보여 준다. 목적지가 위층 안쪽이면 실제의 절반에도 못 미치는 값이라,
  /// 사용자는 도착했다고 생각한 지점에서 안내가 다시 시작되는 경험을 한다.
  ///
  /// 시간은 실내 구간의 **비용**(costM)으로 잰다 — 엘리베이터 대기·탑승이 거기
  /// 들어 있어서다. 거리는 실거리로 더한다. 실내 ETA([_indoorEta])와 같은 규칙이다.
  ({double distanceM, int minutes}) _outdoorEta(DirectionsRoute route) {
    final leg = _pendingIndoorRoute;
    if (leg == null) {
      return (
        distanceM: route.distanceMeters,
        minutes: (route.durationSeconds / 60).ceil().clamp(1, 999),
      );
    }
    final indoorSeconds =
        leg.totalCostMeters / _indoorWalkingSpeedMetersPerSecond;
    return (
      distanceM: route.distanceMeters + leg.totalDistanceMeters,
      minutes: ((route.durationSeconds + indoorSeconds) / 60).ceil().clamp(
        1,
        999,
      ),
    );
  }

  /// ETA 카드에 쓸 거리와 비용. 다층 경로면 전 세그먼트 합, 단일 층이면 그 세그먼트
  /// 값. 실내 화면과 같은 규칙이다.
  ///
  /// `distanceM`은 실제 수평 거리만("m 남음"), `costM`은 탑승·대기 시간까지 담은 보행
  /// 등가값(소요 시간)이다. 한 값으로 겸하면 남은거리가 비용만큼 부풀어 보인다.
  ({double distanceM, double costM}) _indoorEta() {
    // 걸은 만큼 줄어든 값이 있으면 그것을 쓴다. 예전에는 항상 경로 전체 길이를
    // 돌려줘서, 목적지 앞에 서 있어도 "출발할 때와 같은 거리"가 떠 있었다.
    final remaining = _guidance.displayProgress?.remainingM;
    final multi = _indoorMultiFloorRoute;
    if (multi != null) {
      if (remaining == null) {
        return (
          distanceM: multi.totalDistanceMeters,
          costM: multi.totalCostMeters,
        );
      }
      // 이 층 세그먼트만 진행률을 갖는다. 남은 층들의 거리·비용은 그대로 더한다.
      final segmentM = _indoorRouteSegment?.distanceMeters ?? 0;
      final walkedM = (segmentM - remaining).clamp(0.0, segmentM);
      return (
        distanceM: (multi.totalDistanceMeters - walkedM).clamp(
          0.0,
          multi.totalDistanceMeters,
        ),
        costM: (multi.totalCostMeters - walkedM).clamp(
          0.0,
          multi.totalCostMeters,
        ),
      );
    }
    // 단층 경로에는 수직 이동이 없어 거리와 비용이 같다.
    final remainingM = remaining ?? _indoorRouteSegment?.distanceMeters ?? 0;
    return (distanceM: remainingM, costM: remainingM);
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
      buffer.write(
        index == 0 ? ' · ${segment.floorName}' : ' → ${segment.floorName}',
      );
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
      _guidance
        ..setRouteSegment(null)
        ..clearProgress()
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
      _indoorRouteDestination = null;
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    // 한 번의 길안내가 여기서 끝난다.
    _endRouteRecordingSession();
  }

  /// 안내 배너를 탭했을 때 — 경로 전체를 단계 목록으로 펴서 시트로 보여준다.
  ///
  /// 다층 경로면 **모든 층의 세그먼트**를 순서대로 편다. 화면에 그려지는 것은
  /// 지금 층 세그먼트뿐이지만, 목록의 존재 이유가 "이 다음에 뭐가 오는지"라
  /// 아직 안 간 층의 단계까지 있어야 한다.
  void _showIndoorRouteSteps(PoiSearchResult destination) {
    final multi = _indoorMultiFloorRoute;
    final List<RouteStepLeg> legs;
    if (multi != null && multi.isNotEmpty) {
      legs = [
        for (var i = 0; i < multi.segments.length; i++)
          (
            wgs84Points: multi.segments[i].route.points,
            localPoints: multi.segments[i].route.pointsLocalM,
            floorLabel: multi.segments[i].floorName,
            transferModeToNext: multi.segments[i].transferModeToNext,
            nextFloorLabel: i + 1 < multi.segments.length
                ? multi.segments[i + 1].floorName
                : null,
          ),
      ];
    } else {
      final segment = _indoorRouteSegment;
      final floor = _activeFloor;
      if (segment == null || floor == null) return;
      legs = [
        (
          wgs84Points: segment.points,
          localPoints: segment.pointsLocalM,
          floorLabel: floor,
          transferModeToNext: null,
          nextFloorLabel: null,
        ),
      ];
    }
    final steps = buildRouteStepList(legs);
    if (steps.isEmpty) return;
    showRouteStepsSheet(
      context,
      steps: steps,
      destinationName: destination.name,
    );
  }

  void _dismissUserDestinationFromEtaCard() {
    _retainEtaClosePointer();
    _clearUserDestination();
    widget.onGuidanceDismissed?.call();
  }

  void _dismissIndoorRouteFromEtaCard() {
    _retainEtaClosePointer();
    // 야외 구간도 함께 지운다. 실내 구간은 그 야외 구간의 뒷부분이라, 실내만
    // 지우면 밖으로 나갔을 때 방금 끝낸 안내의 앞부분이 혼자 되살아난다.
    _clearUserDestination();
    _clearIndoorRoute();
    widget.onGuidanceDismissed?.call();
  }

  void _retainEtaClosePointer() {
    final pointerDown = _etaClosePointerDown;
    _etaClosePointerDown = null;
    if (pointerDown != null) {
      _mapOverlayTapGuard.retainPointerDown(pointerDown);
    }
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

    // 경로선: 진한 파랑 casing + 파란 본선 + 흰 화살표. 값과 근거는
    // [map_route_style.dart]에 있다(실내 화면과 공유).
    await controller.addSource(
      _routeSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    // 테두리는 자동차 실선에만 깐다. 점선 아래에 테두리를 깔면 점 사이 빈틈이
    // 테두리 색으로 채워져 점선이 실선처럼 보인다.
    await controller.addLineLayer(
      _routeSourceId,
      _routeCasingLayerId,
      const LineLayerProperties(
        lineColor: kRouteCasingColor,
        lineWidth: kRouteCasingWidthExpr,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'style'],
        'drive',
      ],
    );
    // 자동차만 실선이다. 운전 경로는 도로를 그대로 따라가므로 선이 곧 길이지만,
    // 걷는 구간은 횡단보도·건물 앞 광장처럼 "이 근처로 가라"에 가까워 점선이 맞다.
    await controller.addLineLayer(
      _routeSourceId,
      _routeLineLayerId,
      const LineLayerProperties(
        lineColor: kRouteLineColor,
        lineWidth: kRouteLineWidthExpr,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'style'],
        'drive',
      ],
    );
    await controller.addLineLayer(
      _routeSourceId,
      _routeWalkLayerId,
      const LineLayerProperties(
        lineColor: kRouteWalkColor,
        lineWidth: kRouteLineWidthExpr,
        lineDasharray: kRouteWalkDashArray,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'style'],
        'walk',
      ],
    );
    await controller.addLineLayer(
      _routeSourceId,
      // 실내 구간은 **실선**이다. 건물 안에서는 복도가 정해져 있어 "대략 이쪽"이
      // 아니라 실제로 그 길로 걷는다 — 점선으로 그리면 밖의 도보 구간과 같은
      // 성격으로 읽힌다. 색은 야외 본선과 같다([kRouteIndoorLineColor] 주석).
      _routeIndoorLayerId,
      const LineLayerProperties(
        lineColor: kRouteIndoorLineColor,
        lineWidth: kRouteLineWidthExpr,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'style'],
        'indoor',
      ],
    );
    await controller.addImage(
      kRouteArrowImageName,
      await renderRouteArrowIcon(),
    );
    await controller.addSymbolLayer(
      _routeSourceId,
      _routeArrowLayerId,
      routeArrowProps(),
      enableInteraction: false,
    );
    // 대중교통 경로. 도보 경로 **바로 위**에 올려, 두 안내가 잠깐 겹치는
    // 순간에도 사용자가 방금 고른 대중교통 선이 가려지지 않게 한다.
    //
    // 색은 feature 속성에서 읽는다(`['get', 'color']`). 구간마다 노선색이 달라
    // 레이어를 노선 수만큼 만들 수는 없고, 만들었다면 경로를 바꿀 때마다
    // 레이어를 지웠다 다시 등록해야 한다.
    await controller.addSource(
      _transitSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _transitSourceId,
      _transitRideLayerId,
      const LineLayerProperties(
        lineColor: ['get', 'color'],
        lineWidth: 5.5,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      // 탈것 구간만. 도보는 아래 점선 레이어가 따로 그린다.
      filter: [
        '==',
        ['get', 'walk'],
        false,
      ],
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _transitSourceId,
      _transitWalkLayerId,
      // 걷는 구간은 **노선색을 따르지 않는다.** 정류장까지 걸어가는 길이 버스
      // 노선과 같은 색이면, 어디서 내려 걸어야 하는지를 점선 여부만으로 읽어야
      // 한다. 회색으로 빼 두면 "여기는 타는 구간이 아니다"가 색에서 먼저 온다.
      const LineLayerProperties(
        lineColor: kRouteWalkColor,
        lineWidth: 3.5,
        lineDasharray: kRouteWalkDashArray,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'walk'],
        true,
      ],
      enableInteraction: false,
    );

    // 구간 시작 배지. 선과 **소스를 나눈다** — 점 feature를 선 소스에 섞으면
    // 선 레이어 필터가 그 점까지 훑고, 반대로 배지 필터가 선을 훑는다.
    await controller.addSource(
      _transitBadgeSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addImage(
      kRouteWalkBadgeImageName,
      await renderModeBadgeIcon(
        Icons.directions_walk_rounded,
        const Color(0xFF8A9199),
      ),
    );
    await controller.addImage(
      kRouteBusBadgeImageName,
      await renderModeBadgeIcon(
        Icons.directions_bus_rounded,
        const Color(0xFF0068B7),
      ),
    );
    await controller.addImage(
      kRouteSubwayBadgeImageName,
      await renderModeBadgeIcon(Icons.subway_rounded, const Color(0xFF3A5DAE)),
    );
    // **아이콘 이름마다 레이어를 하나씩 둔다.** `iconImage`에 `['get', ...]`
    // 표현식을 넣는 방식은 이 바인딩에서 조용히 실패할 수 있어(아이콘이 아예 안
    // 뜨고 오류도 없다), 이름을 상수로 박고 필터로 가른다.
    for (final entry in const {
      kRouteWalkBadgeImageName: _transitBadgeLayerId,
      kRouteBusBadgeImageName: '$_transitBadgeLayerId-bus',
      kRouteSubwayBadgeImageName: '$_transitBadgeLayerId-subway',
    }.entries) {
      await controller.addSymbolLayer(
        _transitBadgeSourceId,
        entry.value,
        routeModeBadgeProps(entry.key),
        filter: [
          '==',
          ['get', 'icon'],
          entry.key,
        ],
        enableInteraction: false,
      );
    }
    await controller.addSource(
      _transferRouteSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await controller.addLineLayer(
      _transferRouteSourceId,
      _transferRouteLayerId,
      const LineLayerProperties(
        lineColor: kRouteLineColor,
        lineWidth: kRouteTransferWidthExpr,
        lineOpacity: 0.85,
        lineDasharray: [1.2, 1.1],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
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
      floorOutlineProps(indoorOverlayFadeExpr(entered: true, maxOpacity: 0.9)),
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
      const FillLayerProperties(
        fillColor: mapSelectionColor,
        fillOpacity: _highlightFillOpacity,
      ),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _highlightSourceId,
      _highlightLineLayerId,
      const LineLayerProperties(
        lineColor: mapSelectionColor,
        // fill이 진해진 만큼 테두리도 같이 올린다. 1.2px는 옅은 fill의 경계를
        // 겨우 알려 주던 굵기라, 채운 뒤에는 fill에 묻혀 보이지 않는다.
        lineWidth: 2,
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
      await renderDestinationPinIcon(),
    );
    await controller.addSource(
      _indoorDestSourceId,
      GeojsonSourceProperties(data: _emptyCollection()),
    );
    await _addIndoorDestinationPinLayer(controller);

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
    if (_pendingCenterOnPosition && _position != null && _outdoorGpsVisible) {
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

  /// 지금 "층 경계"로 삼아야 하는 링. 어느 층이든 그 층 도면의 외곽선이고,
  /// 실내에 들어가 있지 않거나 도면이 아직 없으면 null이다. 규칙과 근거(특히
  /// 지상층에서도 건물 외곽선을 쓰지 않는 이유)는 [floorOutlineRing] 참고.
  ///
  /// 외곽선·dim scrim hole·건물 안 탭 판정이 **모두 이 하나를 본다.** 셋이 서로
  /// 다른 링을 쓰면 사용자가 보는 선 안쪽이 어두워지거나(scrim), 선 안쪽을
  /// 탭했는데 야외로 튕겨 나가는(탭 판정) 모순이 생긴다.
  List<ll.LatLng>? _activeFloorOutlineRing() => floorOutlineRing(
    indoorEntered: _indoorEntered,
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
    // hole은 외곽선과 **같은 링**을 쓴다. 건물 외곽선으로 뚫으면 그 층 도면 중
    // 건물 외곽선 밖으로 나간 부분이 스크림에 덮여, 사용자가 보는 외곽선 안쪽이
    // 어두워지는 모순이 생긴다(지하가 특히 심하다). 링이 아직 없으면(층 도면
    // 로딩 중) 건물 외곽선으로 폴백해 스크림 자체는 유지한다 — 스포트라이트가
    // 한 프레임 통째로 꺼지는 것보다 낫다. 여기만 폴백을 허용하는 이유는
    // 스크림이 "경계선"이 아니라 밝기 대비이기 때문이다 — 선은 폴백하지 않는다
    // ([floorOutlineRing]).
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

  /// 지금 선택에 해당하는 MapLibre 필터 표현식. 선택이 없으면 아무것도 맞지
  /// 않는 필터를 돌려준다. 레이어 등록 시점과 갱신 시점이 같은 함수를 쓰게 해서
  /// 한쪽만 고쳐 어긋나는 일을 막는다(indoor_overlay_layers.dart의 "등록과
  /// 갱신이 같은 함수를 쓴다" 규칙과 같은 이유).
  List<Object> _categoryFilterExpression() {
    final selection = widget.categorySelection;
    if (selection == null) return kCategoryHighlightNoneFilter;
    return categoryHighlightFilter(selection);
  }

  /// 선택이 바뀌었을 때 오버레이에 그 선택을 반영한다.
  ///
  /// 실내 화면(`FloorPlanView._applyCategoryFilter`)과 같은 두 가지가 바뀐다 —
  /// **어느 매장이 색으로 강조되는가**(강조 fill의 필터)와 **어느 매장이 이름을
  /// 다는가**(라벨의 `text-field`).
  ///
  /// 강조 fill은 `setLayerProperties`가 아니라 `setFilter`를 쓴다 — 전자는 넘기지
  /// 않은 속성까지 null로 함께 보내 스펙 기본값(fill-color는 검정)으로 되돌리므로
  /// 실기기에서 지도가 검게 덮인다(indoor_overlay_layers.dart 상단 주석). 라벨은
  /// 바뀌는 것이 필터가 아니라 layout 속성이라 그 경로를 쓸 수 없고, 대신
  /// [indoorStoresLabelProps]·[indoorFacilityLabelProps]가 **전체 속성**을 다시
  /// 만들어 넘긴다.
  Future<void> _applyCategoryFilter() async {
    final controller = _mapController;
    if (controller == null || !_styleReady || !_indoorTilesRegistered) return;
    // 층 전환과 겹치면 이미 제거된 레이어를 가리킬 수 있다. 페이드 갱신과 같은
    // 이유로 삼킨다 — 다음 등록이 어차피 현재 선택으로 필터를 넣어 준다.
    try {
      await controller.setFilter(
        _indoorCategoryHighlightFillLayerId,
        _categoryFilterExpression(),
      );
    } catch (_) {}
    final fadeExpr = _overlayFadeExpr();
    for (final (id, props) in [
      (
        _indoorStoresLabelLayerId,
        indoorStoresLabelProps(
          fadeExpr,
          widget.categorySelection,
          _devicePixelRatio,
        ),
      ),
      (
        _indoorFacilityLabelLayerId,
        indoorFacilityLabelProps(fadeExpr, widget.categorySelection),
      ),
    ]) {
      try {
        await controller.setLayerProperties(id, props);
      } catch (_) {}
    }
  }

  /// 현재 진입 상태에 맞는 오버레이 페이드 표현식.
  /// 구간이 진입 전후로 왜 다른지는 [indoorOverlayFadeExpr] 쪽 주석 참고.
  List<Object> _fadeExpr({double maxOpacity = 1}) =>
      indoorOverlayFadeExpr(entered: _indoorEntered, maxOpacity: maxOpacity);

  /// 실내 오버레이 **레이어**용 페이드 표현식 — [_fadeExpr]에 층 전환
  /// 크로스페이드 계수([_indoorOverlayFadeFactor])를 곱한 것. 오버레이 레이어
  /// 속성을 쓰는 모든 경로(등록·페이드 갱신·카테고리 필터·크로스페이드 단계)가
  /// 이걸 써야 페이드 도중 끼어든 갱신이 계수를 되돌리지 않는다. 건물 단위
  /// dim scrim은 층 전환과 무관하므로 [_fadeExpr]를 그대로 쓴다.
  ///
  /// 곱셈을 `['*', ...]`로 감싸지 않고 램프 끝 스톱에 곱해 넣는 이유
  /// (native의 top-level zoom 제약)는 [indoorOverlayCrossfadeExpr]에 있다.
  List<Object> _overlayFadeExpr() {
    final factor = _indoorOverlayFadeFactor;
    if (factor >= 1) return _fadeExpr();
    return indoorOverlayCrossfadeExpr(
      entered: _indoorEntered,
      crossfadeFactor: factor,
    );
  }

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
    final fadeExpr = _overlayFadeExpr();
    // 이미 제거된 레이어에 대한 setLayerProperties가 native에서 예외를 던지는
    // 구현이 있어(층 전환과 겹치는 순간) 각각 감싼다.
    for (final (id, props) in [
      (_indoorFootprintLayerId, indoorFootprintProps(fadeExpr)),
      (_indoorStoresFillLayerId, indoorStoresFillProps(fadeExpr)),
      (
        _indoorCategoryHighlightFillLayerId,
        indoorCategoryHighlightProps(fadeExpr),
      ),
      (
        _indoorVerticalTransportFillLayerId,
        indoorVerticalTransportProps(fadeExpr),
      ),
      // 선택을 반드시 함께 넘긴다. 빼면 줌을 움직일 때마다 가려 뒀던 매장
      // 이름이 되살아난다([indoorStoresLabelProps] 주석).
      (
        _indoorStoresLabelLayerId,
        indoorStoresLabelProps(
          fadeExpr,
          widget.categorySelection,
          _devicePixelRatio,
        ),
      ),
      (
        _indoorFacilityLabelLayerId,
        indoorFacilityLabelProps(fadeExpr, widget.categorySelection),
      ),
      (_indoorPoiIconLayerId, indoorPoiIconProps(fadeExpr, _devicePixelRatio)),
      (
        _indoorStoreFacilityIconLayerId,
        indoorFacilityIconProps(fadeExpr, _devicePixelRatio),
      ),
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
  /// 실내 진입 중이면 그 층 외곽선 안쪽도 "건물 안"으로 본다. 화면에 그려진
  /// 외곽선 안을 탭했는데 야외로 튕겨 나가면(지하처럼 건물 외곽선 밖까지 뻗은
  /// 층이 있다) 사용자 입장에서는 도면 위를 눌렀을 뿐이다. 두 링의 **합집합**을
  /// 보므로 야외에서의 판정은 지금까지와 같다.
  bool _isInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint != null && isPointInPolygon(point, footprint)) return true;
    final ring = _activeFloorOutlineRing();
    return ring != null && isPointInPolygon(point, ring);
  }

  /// 실내 진입 오버레이를 켜는 테스트 진입점.
  ///
  /// 실기기에서는 GPS·줌·건물 탭이 [_setIndoorEntered]를 부르는데, 그 셋 다
  /// 건물 폴리곤과 입구 좌표가 있어야 한다. 그래프만 있는 fixture로 실내 동작을
  /// 검증하려는 테스트는 그 준비를 할 수 없으므로, 실기기가 지나는 것과 **같은
  /// 함수**를 직접 부른다.
  @visibleForTesting
  void enterIndoorForTest() => _setIndoorEntered(true);

  /// 지도 탭 처리의 테스트 진입점.
  ///
  /// MapLibre 플랫폼 뷰는 위젯 테스트에 없어 `onMapClick`이 아예 발화하지
  /// 않는다. 그래서 실기기에서 쓰이는 것과 **같은 함수**를 직접 부른다 —
  /// 테스트용 축약 경로를 따로 두면 정작 검증하려는 분기(건물 밖 탭 → 야외
  /// 전환)를 우회해 버린다.
  ///
  /// [screenPoint]는 지도 위젯 로컬 픽셀 좌표다. 오버레이(층 선택기 등) 위를
  /// 누른 탭이 지도 탭으로 새어들어가는 경우를 재현하려면 이 값이 필요하다 —
  /// 좌표가 늘 (0,0)이면 오버레이 배제 로직 자체가 검증되지 않는다.
  @visibleForTesting
  Future<void> handleMapClickForTest(
    ll.LatLng point, {
    Offset screenPoint = Offset.zero,
  }) => _handleMapClick(
    Point<double>(screenPoint.dx, screenPoint.dy),
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

    // 매장을 맞히지 못했고 길찾기에서 지도로 고르는 중이라면, 이 탭은 복도(또는
    // 빈 공간)를 고른 것이다. **아래 진입/이탈 처리보다 먼저** 소비해야 한다 —
    // 그러지 않으면 건물 안을 눌렀을 땐 진입 트리거로, 건물 밖을 눌렀을 땐
    // 오버레이 닫기로 먹혀서 사용자는 복도를 눌렀는데 화면만 바뀌는 것을 본다.
    if (_indoorEntered && widget.pickingOnMap && _handleMapPickTap(point)) {
      return;
    }

    // 폴리곤 히트 검사만 하고, 나머지 탭은 흡수하지 않아 지도 pan/zoom 제스처를
    // 방해하지 않는다(단일 탭이 여기 오면 그건 pan이 아닌 명시적 탭).
    if (!_isInsideBuilding(point)) {
      // 실내 모드에서 건물 밖을 탭한 것 — 사용자가 야외로 나가겠다는 뜻이다.
      // 축소해서 나가는 것보다 훨씬 직관적인 탈출 경로다.
      //
      // 단, **외곽선 바로 바깥은 이탈로 치지 않는다**
      // ([isTapOutsideBuildingForExit]). 벽에 붙은 매장을 누르다 손가락이 선을
      // 몇 미터 넘기는 일은 흔한데, 그때마다 실내가 닫히면 매장을 누르려던
      // 사용자가 건물에서 쫓겨난다. 여기서 그냥 흡수해 아무 일도 일어나지 않게
      // 두는 편이, 되돌리는 데 건물을 다시 찾아 탭해야 하는 것보다 낫다.
      if (_indoorEntered &&
          isTapOutsideBuildingForExit(
            point: point,
            footprint: _buildingFootprint,
          )) {
        _exitIndoorByOutsideTap();
      }
      return;
    }

    // 폴리곤을 잠깐 진하게 반짝여 "인식됐다"는 시각 피드백을 준 뒤, 야외 지도
    // 위에 실내 UI 오버레이(층 chip, 위치 지정 버튼 등)를 켠다. 화면 모드는
    // 그대로 야외로 유지된다.
    //
    // 반짝임은 장식이라 컨트롤러가 아직 없으면 건너뛴다. 진입을 컨트롤러 유무에
    // 걸어 두면(예전 `if (controller == null) return;`) 스타일 로드 전에 건물을
    // 탭한 사용자에게 아무 반응도 없다.
    await _flashBuildingFill();
    if (!mounted) return;
    _triggerIndoorEntry(ignoreZoomArming: true);
    // 오버레이만 켜면 도면이 지금 배율 그대로 뜬다 — 바깥에서 건물을 눌러
    // 들어온 경우 건물이 화면의 60% 남짓이라 "들어왔다"는 느낌이 안 난다.
    // 카메라도 함께 도면이 화면을 채우는 자리까지 끌어온다.
    if (_indoorEntered) unawaited(_fitCameraToActiveFloor());
  }

  /// 건물을 탭해 들어온 직후, 도면이 화면을 채우도록 카메라를 끌어온다.
  ///
  /// **한 번에 갈아 끼우지 않고 애니메이션으로 간다.** 배율이 즉시 튀면 지도가
  /// 다른 장소로 순간이동한 것처럼 보여서, 사용자가 방금 누른 건물과 지금 보는
  /// 도면이 같은 곳이라는 연결이 끊긴다. 확대되는 과정을 보여 주면 그 연결이
  /// 눈으로 이어진다.
  ///
  /// **지도도 함께 돌린다.** 건물은 정북 기준 아무 방향으로나 앉아 있어서(더현대
  /// 서울은 약 53도), 북쪽을 위로 둔 채 확대하면 도면이 화면에 비스듬히 누워
  /// 들어온다. 세로로 긴 폰 화면에 누운 사각형을 담는 꼴이라 좌우가 남고 도면은
  /// 그만큼 작아진다. 건물의 긴 축을 화면 세로에 맞추면 같은 배율에서 도면이
  /// 훨씬 크게 들어오고, 폰을 든 방향과 건물 축도 나란해진다.
  ///
  /// 배율은 **돌려 세운 상자**를 화면에 맞춘 값이다([zoomToFitRotatedBox]).
  /// 다만 진입 임계값보다 아래로는 내려가지 않게 잡는다 — 그 아래로 가면 도착한
  /// 뒤 [_handleCameraIdle]이 이탈로 판정해 방금 연 도면이 도로 닫힌다.
  /// 지금 보고 있는 **층 도면**이 화면을 채우도록 카메라를 맞춘다.
  ///
  /// 기준은 건물 외곽선이 아니라 **그 층의 외곽선**이다. 층마다 크기가 크게
  /// 다르기 때문이다 — 더현대 서울은 지상층이 약 180 x 190 m인데 B3·B4는
  /// 286 x 305 m다. 건물 외곽선 하나로 맞춰 두면 지상층에서는 여백이 남고
  /// 지하로 내려가면 도면이 화면 밖으로 잘린다.
  ///
  /// **건물 외곽선으로 폴백하지 않는다.** 예전에는 층 도면이 아직 없으면 건물
  /// 외곽선에 맞췄는데("한 프레임 어긋난 배율이 낫다"), 그 값은 시드 구조상
  /// **1F의 외곽선**이다([floorOutlineRing] 주석). 지상층끼리는 거의 같아서
  /// 티가 안 나지만 지하는 1.8배 크고 위치도 달라서, 그 배율로 굳으면 B1·B2는
  /// 한쪽이 잘리고 B3~B6은 사방이 잘려 층 전체가 화면에 안 들어온다. 그리고
  /// 이건 "한 프레임"이 아니다 — 뒤이어 다시 맞춰 주는 곳이 없어 그대로 남는다.
  ///
  /// 그래서 도면 로드를 **기다렸다가** 맞춘다.
  ///
  /// 기다려도 없으면 건물 외곽선으로 일단 맞추되(연출을 잃지 않는다) **다시
  /// 맞추기를 예약해 둔다**([_pendingFloorFit]). 폴백을 아예 없애 봤더니 "틀린
  /// 배율"이 "배율을 아예 안 잡음"이 됐고, 그건 더 나쁘다 — 실기기에서 건물에
  /// 들어가도 도면이 야외 지도 위 작은 사각형으로 남고 진입 줌인이 통째로
  /// 사라졌다. 예약해 두면 도면이 도착하는 순간 그 층 크기로 한 번 더 맞는다.
  Future<void> _fitCameraToActiveFloor({
    Duration duration = _indoorZoomInDuration,
  }) async {
    // 층을 막 바꾼 직후면 도면이 아직 오는 중이다. 여기서 기다려야 대부분의
    // 경우 예약까지 가지 않고 바로 맞는다.
    await _floorGraphLoad;
    if (!mounted) return;
    await _fitCameraToLoadedFloor(duration);
  }

  /// [_fitCameraToActiveFloor]의 몸통 — **도면 로드를 기다리지 않는다.**
  ///
  /// 예약분을 실행하는 쪽([_fetchFloorGraph])은 이미 그 로드 **안에** 있어서,
  /// 거기서 `_floorGraphLoad`를 기다리면 자기 자신을 기다리다 멈춘다. 그래서
  /// 기다리는 껍데기와 실제로 맞추는 몸통을 나눠 둔다.
  Future<void> _fitCameraToLoadedFloor(Duration duration) async {
    final ring = _activeFloorOutlineRing();
    // 층 도면이 없으면 건물 외곽선으로 **일단 맞춘다.** 그 값은 1F 외곽선이라
    // 지하에서는 크기가 안 맞지만, 안 맞추면 진입 줌인 연출이 통째로 사라진다 —
    // 실기기에서 확인했다. 대신 도면이 도착하면 그 층 크기로 다시 맞추도록
    // 예약해 둔다([_pendingFloorFit]).
    final footprint = ring ?? _buildingFootprint;
    if (footprint == null || footprint.length < 3) return;
    final floor = _activeFloor;
    if (ring == null) {
      if (floor != null) _pendingFloorFit = (floor: floor, duration: duration);
      debugPrint(
        '[outdoor overlay] fit 폴백(건물 외곽선): $floor 도면 없음 '
        '(entered=$_indoorEntered)',
      );
    } else {
      _pendingFloorFit = null;
    }
    // 화면에 그려지는 것은 외곽선만이 아니다 — 매장·POI까지 덮어야 "층 전체가
    // 보인다"가 된다([_activeFloorDrawnPoints]). 폴백 중이면 그 층 도면이 없으니
    // 덮을 점도 없다.
    final box = minAreaBoxFor(
      footprint,
      covering: ring == null ? const [] : _activeFloorDrawnPoints(),
    );
    if (box != null) {
      await _animateCameraToFitBox(
        box,
        topChromePx: _floorFitTopChromePx,
        bottomChromePx: _floorFitBottomChromePx,
        duration: duration,
      );
      return;
    }
    // 상자를 못 구하면(퇴화한 외곽선) 돌리지 않고 임계값까지만 간다.
    final center = _buildingCenter(footprint);
    final controller = _mapController;
    if (center == null || controller == null || !_styleReady) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(center), _entryZoomThreshold()),
      duration: duration,
    );
  }

  /// 지금 층에서 **실제로 그려지는** 좌표 전부 — 외곽선 + 매장 폴리곤·중심 +
  /// POI. 카메라를 맞출 때 덮어야 할 범위다.
  ///
  /// 외곽선만으로는 모자란다. 백엔드 층 footprint는 도면을 감싸라고 만든 값이지
  /// 매장을 다 덮는다는 보장이 없고, 실제로 더현대 서울 1F는 매장이 외곽선
  /// 위아래로 12 m·19 m 튀어나와 있어 외곽선에 맞추면 그만큼이 화면 밖에 남는다.
  /// 반대로 B2의 footprint는 매장보다 9 m 넓은 맨 사각형이라, 그 상자에 맞추면
  /// 도면이 프레임 안에서 한쪽으로 치우친다. 둘 다 "그려지는 것"을 기준으로
  /// 잡으면 사라진다.
  /// 층 도면이 아직 없어 미뤄 둔 카메라 fit. 도면이 도착하면
  /// [_fetchFloorGraph]가 이어서 실행한다. 층 이름을 함께 들고 있는 이유는,
  /// 기다리는 사이 사용자가 다른 층으로 가 버리면 이 예약은 남의 층 것이라
  /// 버려야 하기 때문이다.
  ({String floor, Duration duration})? _pendingFloorFit;

  List<ll.LatLng> _activeFloorDrawnPoints() {
    final plan = _floorPlan;
    if (plan == null) return const [];
    return <ll.LatLng>[
      ...plan.footprint,
      for (final store in plan.stores) ...[store.centroid, ...store.polygon],
      for (final poi in plan.pois) poi.point,
    ];
  }

  /// 안내가 시작된 순간, **지금 층 경로 전체**가 한눈에 들어오도록 카메라를 한 번
  /// 크게 움직인다.
  ///
  /// ## 왜 층 도면이 아니라 경로에 맞추나
  ///
  /// 안내를 시작한 사용자가 알고 싶은 것은 "이 층이 어떻게 생겼나"가 아니라
  /// "어디로 얼마나 가나"다. 층 전체를 담으면 경로는 그 안 한 귀퉁이의 짧은
  /// 선이 되어 진행 방향이 읽히지 않는다.
  ///
  /// ## 왜 지금 층 세그먼트만인가
  ///
  /// 다층 경로 전체를 담으려 하면 **화면에 없는 층의 좌표까지** 상자에 들어간다.
  /// 층마다 도면 위치가 어긋나 있으면 상자가 엉뚱하게 커지고, 그만큼 축소돼
  /// 지금 걸을 구간이 도리어 안 보인다. 층은 [_swapIndoorFloorSmoothly]가 바뀔
  /// 때마다 다시 맞춘다.
  ///
  /// ## 왜 newLatLngBounds를 안 쓰나
  ///
  /// 예전 `_fitCameraToIndoorRoute`가 그걸 썼는데, 그 API는 **항상 정북 정렬
  /// 기준으로 계산해 bearing을 0으로 되돌린다.** 진입·층 전환에서 애써 세로로
  /// 세워 둔 도면이 안내를 시작하는 순간 도로 비스듬히 누웠다
  /// (`widgets/floor_plan_view.dart`의 같은 주석 참고). 회전을 유지하려면
  /// [_animateCameraToFitPoints]처럼 `newCameraPosition`으로 직접 계산해야 한다.
  Future<void> _fitCameraToRouteSegment(
    IndoorRoute route, {
    Duration duration = _routeOverviewDuration,
  }) async {
    // 바로 옆 매장이면 담을 것이 없다 — 물러섰다 돌아오는 동작만 남는다.
    if (route.distanceMeters < _routeOverviewMinDistanceM) return;
    // 퇴화한 경로(점 2개, 일직선)를 견디는 몫은 [routeBoxFor]가 진다.
    final box = routeBoxFor(route.points, minSideM: _routeFitMinSideM);
    if (box == null) return;
    await _animateCameraToFitBox(
      box,
      topChromePx: _guidanceFitTopChromePx,
      bottomChromePx: _guidanceFitBottomChromePx,
      duration: duration,
      maxZoom: _routeFitMaxZoom,
    );
  }

  /// 안내 중 "내 위치로" 버튼([GuidanceRecenterButton]). 카메라를 지금 위치로
  /// 옮긴다.
  ///
  /// **bearing과 tilt는 건드리지 않는다.** 개요 연출이 경로 축에 맞춰 세워 둔
  /// 방향이 여기서 정북으로 돌아가면, 돌아온 화면의 위쪽이 갈 방향과 어긋난다.
  /// 배율도 [_walkingViewZoom]까지만 당기고 그보다 확대돼 있으면 그대로 둔다 —
  /// 자세한 설명은 그 상수에 있다.
  Future<void> _recenterOnCurrentPosition() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final here = _pdrCurrentWgs84();
    // 위치를 아직 못 그리는 상태면 되돌릴 자리도 없다. 버튼 노출 조건이 같은
    // 값을 보므로([_canRecenterOnCurrentPosition]) 보통은 여기 안 걸린다.
    if (here == null) return;
    final camera = controller.cameraPosition;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toGl(here),
          zoom: math.max(camera?.zoom ?? _walkingViewZoom, _walkingViewZoom),
          bearing: camera?.bearing ?? 0,
          tilt: camera?.tilt ?? 0,
        ),
      ),
      duration: _recenterDuration,
    );
  }

  /// "내 위치로" 버튼을 띄울지. 누를 자리가 없는 버튼을 띄우지 않기 위해
  /// [_recenterOnCurrentPosition]이 실제로 쓰는 값과 **같은 값**을 본다.
  bool get _canRecenterOnCurrentPosition =>
      _indoorLocationVisible && _pdrCurrentWgs84() != null;

  /// [box]를 **가려지지 않는 띠**에 맞춰 카메라를 움직인다. 컨트롤러가 아직
  /// 없으면 아무것도 하지 않고 false.
  ///
  /// 층 도면 fit([_fitCameraToActiveFloor])과 경로 개요([_fitCameraToRouteSegment])의
  /// **공통 몸통**이다. 둘을 한 함수로 묶는 이유는 chrome 보정과 줌 하한이 한
  /// 곳에만 있어야 하기 때문이다 — 각자 갖게 두면 한쪽만 고쳐져 도면을 맞춘
  /// 화면과 경로를 맞춘 화면에서 같은 지점이 다른 높이에 온다.
  ///
  /// 상자를 **어떻게 구하느냐**는 호출부가 정한다([minAreaBoxFor] / [routeBoxFor]).
  /// 퇴화 입력 방어처럼 입력 종류마다 다른 규칙이 여기 섞이면, 이 함수가 층
  /// 외곽선용인지 경로용인지 알 수 없게 된다.
  /// [maxZoom]은 확대해 들어가는 상한이다. 경로 개요만 준다([_routeFitMaxZoom])
  /// — 층 외곽선은 커서 그 배율까지 올라갈 일이 없다.
  Future<bool> _animateCameraToFitBox(
    BuildingBox box, {
    required double topChromePx,
    required double bottomChromePx,
    required Duration duration,
    double maxZoom = double.infinity,
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return false;

    // 중심은 **상자가 준다.** 호출부가 따로 구한 중심을 받던 시절에는 배율은
    // 돌아간 상자로, 위치는 정북 정렬 bbox로 재서 둘이 어긋났다(근거는
    // [BuildingBox.center]).
    final center = box.center;
    final bearing = portraitBearingFor(
      longAxisAzimuthDeg: box.longAxisAzimuthDeg,
      currentBearing: controller.cameraPosition?.bearing,
    );
    // 위아래 chrome이 덮는 만큼을 뺀 **실제로 보이는 띠**에 맞춘다. 전체 높이로
    // 맞추면 도면 윗부분이 카테고리 줄 뒤로 들어간다.
    final viewport = MediaQuery.sizeOf(context);
    final bandHeightPx = math.max(
      1.0,
      viewport.height - topChromePx - bottomChromePx,
    );
    final fitZoom = zoomToFitRotatedBox(
      // 상자를 비율만큼 부풀려 맞추면 그만큼 사방에 여백이 남는다.
      widthMeters: box.shortSideM / _floorFitFillRatio,
      heightMeters: box.longSideM / _floorFitFillRatio,
      viewportWidthPx: viewport.width,
      viewportHeightPx: bandHeightPx,
      latitude: center.latitude,
    );
    // 하한은 **이탈 임계값** 기준이다. 예전에는 진입 임계값까지 끌어올렸는데,
    // 그러면 위에서 준 여백이 도로 먹혔다. 실내 상태는 이탈 임계값 위이기만
    // 하면 유지된다([indoorEntryTransitionForZoom]은 그 아래에서만 exit를 낸다).
    //
    // 경로가 길어 이 배율에 다 담기지 않는 경우가 있는데, **그걸 받아들인다.**
    // 억지로 담으려 더 물러서면 [_handleCameraIdle]이 이탈로 판정해 도면이 닫히고
    // 야외로 튕긴다 — 경로 끝이 조금 잘리는 쪽이 낫다.
    final zoom = math.min(
      math.max(fitZoom, indoorExitZoomThreshold + 0.3),
      maxZoom,
    );

    // 상자 한가운데를 화면 한가운데가 아니라 **가려지지 않는 띠의 한가운데**에
    // 놓는다. 카메라 목표점은 늘 화면 중앙에 그려지므로, 목표점을 화면 위쪽
    // (=지금 bearing 방향)으로 그만큼 밀면 상자가 그만큼 내려온다.
    final shiftPx = (topChromePx - bottomChromePx) / 2;
    final metersPerPx = visibleWidthMeters(
      zoom: zoom,
      availablePx: 1,
      latitude: center.latitude,
    );
    final target = offsetByMeters(
      center,
      azimuthDeg: bearing,
      meters: shiftPx * metersPerPx,
    );

    final update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: _toGl(target),
        zoom: zoom,
        bearing: bearing,
        tilt: controller.cameraPosition?.tilt ?? 0,
      ),
    );
    // 즉시 이동은 moveCamera로 간다. animateCamera에 Duration.zero를 주면
    // Android MapLibre가 "Null duration"으로 예외를 던진다 — 층 전환 큐 안에서
    // 터지면 전환 전체가 실패 복구로 빠진다([_recoverFloorTransitionFailure]).
    if (duration <= Duration.zero) {
      await controller.moveCamera(update);
    } else {
      await controller.animateCamera(update, duration: duration);
    }
    return true;
  }

  /// 건물 폴리곤을 잠깐 진하게 칠했다 되돌린다 — "이 건물을 말하는 것"이라는
  /// 시각 피드백.
  ///
  /// 건물을 탭했을 때와 검색에서 골랐을 때가 **같은 신호**를 써야 한다. 탭에만
  /// 있으면, 검색으로 고른 사용자는 카메라만 슥 움직이고 아무것도 강조되지 않는
  /// 화면을 본다 — 옅은 파랑(0.15) 폴리곤은 배경 지도 위에서 눈에 잘 띄지 않아
  /// "골랐다"는 사실이 화면에 드러나지 않는다.
  ///
  /// 장식이라 컨트롤러가 아직 없으면 조용히 건너뛴다. 이 반짝임에 진입이나
  /// 카메라 이동을 걸어 두면 안 된다.
  Future<void> _flashBuildingFill() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
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

  /// 실내 진입 트리거 — 건물 탭·줌 임계값 초과·GPS 근접 감지 중 하나로 호출.
  /// 화면 모드는 바꾸지 않고 야외 지도 위에 얹는 실내 UI 오버레이만 켠다.
  /// 사용자가 축소해 임계값 아래로 내려가면 [_handleCameraIdle]이 오버레이를
  /// 다시 끄고 트리거를 재무장한다.
  ///
  /// [ignoreZoomArming]은 **자기 게이트를 따로 가진 호출자**가 쓴다.
  /// [_autoIndoorEntryArmed]는 "같은 줌에서 카메라가 멈출 때마다 반복 발화하지
  /// 않게" 하려는 zoom 트리거 전용 플래그이고, [_exitIndoorByOutsideTap]이 일부러
  /// 재무장하지 않는다(아래 주석 참고). 그래서 이 플래그로 다른 경로까지 막으면
  /// 두 가지가 조용히 죽는다.
  ///   - 건물 밖을 탭해 나온 사용자가 건물을 **직접 다시 탭**해도 안 들어감
  ///   - GPS 자동 진입이 [_gpsEntryArmed]로 다시 무장돼도 여기서 막힘
  /// 둘 다 자기 쪽 게이트를 이미 통과한 호출이므로 zoom 무장은 보지 않는다.
  void _triggerIndoorEntry({bool ignoreZoomArming = false}) {
    if (!ignoreZoomArming && !_autoIndoorEntryArmed) return;
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
  /// `ignoreZoomArming`), 이탈 임계값 아래로 축소했다가 다시 확대하는 것.
  ///
  /// **GPS 자동 진입도 함께 끈다**([_gpsEntryArmed]). 건물 안에 서서 밖을 탭해
  /// 나온 경우 GPS는 여전히 "건물 안"을 가리키므로, 안 끄면 다음 위치 한 건이
  /// 곧바로 다시 끌고 들어간다. 다시 자동으로 들어가는 것은 사용자가 실제로
  /// 건물을 벗어난 뒤다([GpsBuildingVerdict.outside]).
  void _exitIndoorByOutsideTap() {
    // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
    // (배치 대기 중인 탭은 위에서 이미 소비되므로 방어적 처리다.)
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _gpsEntryArmed = false;
    _setIndoorEntered(false);
  }

  /// 하단 바에서 '홈'(야외)을 눌러 이 화면으로 돌아왔을 때의 이탈. 상위
  /// (MapShellScreen)가 모드를 야외로 바꿀 때 호출한다.
  ///
  /// 여기서는 오버레이만 끄는 것으로 끝나지 않는다. 카메라가 건물을 크게 확대한
  /// 자리에 그대로 남아 있으면, 오버레이를 껐어도 도면은 진입 램프
  /// ([indoorOverlayFadeExpr])에 따라 그대로 보인다 — "홈을 눌렀는데 실내가
  /// 보이는" 상태다. 그래서 카메라도 야외 시야([outdoorReturnZoom])로 함께
  /// 축소한다.
  ///
  /// 실내 앵커에서 계산한 경로도 지운다. 야외에서 쓰는 위치는 GPS뿐이므로,
  /// 실내 위치에서 출발하던 경로만 남으면 화면의 위치 아이콘과 경로 시작점이
  /// 어긋난다.
  ///
  /// [_exitIndoorByOutsideTap]과 달리 **재무장한다**([_autoIndoorEntryArmed]).
  /// 축소까지 함께 하므로 곧바로 다시 끌려 들어갈 위험이 없고, 사용자가 건물로
  /// 다시 확대하면 예전처럼 자연스럽게 실내로 들어가야 한다.
  Future<void> returnToOutdoorView() async {
    if (!_indoorEntered) return;
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _clearIndoorRoute();
    _autoIndoorEntryArmed = true;
    _setIndoorEntered(false);
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await controller.animateCamera(CameraUpdate.zoomTo(outdoorReturnZoom));
  }

  /// [_indoorEntered] 상태 변경을 한 곳으로 모은 헬퍼. setState + 상위 콜백 통지에
  /// 더해 dim scrim의 fillOpacity도 함께 갱신해, 실내 진입/이탈에 스포트라이트
  /// 효과가 즉시 반영되게 한다.
  void _setIndoorEntered(bool value) {
    if (_indoorEntered == value) return;
    // 자동으로 들어왔다는 표식은 야외로 나가는 순간 내린다. 남겨 두면 다음에
    // 사용자가 건물을 직접 탭해 연 도면까지 GPS가 제멋대로 닫는다
    // ([_applyBuildingVerdict]의 outside 갈래).
    if (!value) _indoorEnteredByGps = false;
    // 실내 안내를 켜고 끄는 유일한 지점이다.
    //
    // 예전에는 오버레이가 꺼져도 복도 보정이 계속 돌았다 — 화면에 안 보일 뿐
    // 야외를 걸어 다닌 거리가 실내 좌표계에 누적되다가, 다시 들어오는 순간
    // 걸어 본 적 없는 자리에서 시작했다.
    if (value) {
      _ensureGuidanceAttached();
    } else {
      _guidance.detach();
      // 야외로 나가면 진행 중이던 층 전환도 끝난다. 남겨 두면 배너가 야외
      // 화면에 떠 있고 걸음이 멈춘 채로 유지된다.
      _enqueueFloorTransition(_endEscalatorRide);
    }
    setState(() => _indoorEntered = value);
    widget.onIndoorEnteredChanged?.call(value);
    // 진입/이탈로 "지금 보고 있는 층"의 유무 자체가 바뀐다.
    _notifyActiveFloor();
    // 실내로 들어가면 GPS 구독을 끊고 마커를 지운다. 다시 나가면 재구독한다.
    _syncGpsSubscription();
    // 위치 아이콘의 주인이 바뀌는 순간이다. 야외로 나가면 실내 위치 마커를
    // 지우고(GPS 마커가 그 역할을 받는다), 실내로 들어가면 다시 그린다.
    unawaited(_syncPdrCurrentLayer());
    _syncDimScrimLayer();
    // 외곽선은 실내 진입 상태에서만 그린다 — 이탈하면 여기서 소스가 비워진다.
    unawaited(_syncFloorOutlineLayer());
    // 진입/이탈로 페이드 구간 자체가 바뀌므로 이미 붙어 있는 오버레이 레이어의
    // opacity 표현식도 함께 갈아 끼운다.
    unawaited(_syncIndoorOverlayFade());
    // 실내로 들어온 시점이 PDR을 켤 지점이다. 야외로 나갈 때는 세션을 끄지
    // 않는다 — 실내/야외 오버레이를 오가는 동안 세션이 껐다 켜지면 anchor와
    // 걸음 누적이 매번 초기화된다.
    if (value) unawaited(_startPdrIfIdle());
    // 문 경유 안내로 여기까지 왔다면, 지금이 야외 구간을 실내 구간으로 넘길
    // 지점이다. 진입은 GPS·확대·탭 어느 쪽으로 판정되든 이 함수를 지나므로
    // 승격도 여기 한 곳에만 둔다.
    if (value) unawaited(_activatePendingIndoorRoute());
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

  /// [fadeFactor]는 등록되는 레이어에 곱할 층 전환 크로스페이드 계수다. 기본
  /// 1(원래 불투명도). 크로스페이드가 이전 층 위에 새 블록을 투명하게 얹을
  /// 때만 0을 넘긴다 — 이후 [_finalizeIndoorFloorCrossfade]가 1까지 올린다.
  Future<void> _ensureIndoorTilesRegistered({double fadeFactor = 1}) async {
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

    final tileUrl = indoorTileUrl(
      buildingId: building.id,
      floorName: floor,
      tileRevision: building.tileRevision,
    );
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
      _indoorOverlayFadeFactor = fadeFactor;
      final fadeExpr = _overlayFadeExpr();
      // 실내 오버레이 레이어를 route casing 바로 아래에 삽입한다. 안 그러면
      // _onStyleLoaded가 먼저 그린 경로선/GPS 마커/PDR dot이 나중에 얹힌 stores
      // fill(줌 17.5+에서 fillOpacity=1) 밑으로 깔려 화면에서 완전히 사라진다.
      // **전 레이어 인터랙션을 끈다** — 매장 탭 검출은 feature 탭 콜백이 아니라
      // [_handleMapClick]의 queryRenderedFeatures(현재 세대 stores 레이어 id로
      // 직접 질의)가 하고, onMapClick은 featureTapsTriggersMapClick=true라 어차피
      // 항상 온다. stores를 인터랙션으로 남기면 층 전환 크로스페이드 동안 은퇴
      // 목록([_retiringIndoorBlocks])에 남는 이전 층 stores 레이어까지 탭 대상이
      // 되어, native feature 탭 판정이 화면과 무관한 이전 층 폴리곤에 걸린다.
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
        enableInteraction: false,
      );
      // 카테고리 강조. 일반 매장 fill 바로 위에 얹어 선택한 매장만 파랗게
      // 덮는다. 선택이 없을 때도 레이어는 남겨 두고 아무것도 맞지 않는 필터를
      // 걸어 둔다 — 이유는 kCategoryHighlightNoneFilter 주석.
      await controller.addFillLayer(
        _indoorTilesSourceId,
        _indoorCategoryHighlightFillLayerId,
        indoorCategoryHighlightProps(fadeExpr),
        sourceLayer: 'stores',
        belowLayerId: _routeCasingLayerId,
        filter: _categoryFilterExpression(),
        // 탭은 아래 일반 매장 fill이 받는다. 여기서도 받으면 같은 폴리곤에
        // 두 번 반응한다(실내 화면과 같은 이유).
        enableInteraction: false,
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
        indoorStoresLabelProps(
          fadeExpr,
          widget.categorySelection,
          _devicePixelRatio,
        ),
        // **폴리곤이 아니라 라벨 전용 점 레이어를 본다.** MapLibre는 폴리곤
        // 심볼을 면적 무게중심에 찍는데, ㄱ자·길쭉한 매장에서 그 점이 눈에
        // 보이는 가운데가 아니다(백엔드 `label_point.py` 주석에 실측을 적었다).
        // 백엔드가 폴리곤마다 "라벨 놓을 자리"를 계산해 이 레이어로 내려준다.
        sourceLayer: 'store_labels',
        filter: storeLabelWithCategoryIconFilter(),
        belowLayerId: _routeCasingLayerId,
        enableInteraction: false,
      );
      // 편의시설은 이름만 — 아이콘은 아래 _indoorStoreFacilityIconLayerId가
      // 그린다. 위 레이어에 섞으면 아이콘이 두 개 뜬다.
      await controller.addSymbolLayer(
        _indoorTilesSourceId,
        _indoorFacilityLabelLayerId,
        indoorFacilityLabelProps(fadeExpr, widget.categorySelection),
        // 매장명 라벨과 같은 이유로 라벨 점 레이어를 본다.
        sourceLayer: 'store_labels',
        filter: facilityStoreLabelFilter(),
        belowLayerId: _routeCasingLayerId,
        enableInteraction: false,
      );
      // POI(엘리베이터·에스컬레이터·화장실 등) 심볼 레이어. `pois` 소스 레이어에
      // 있는 feature의 type 속성으로 아이콘을 골라 얹는다. iconOpacity를 fadeExpr
      // 로 묶어 오버레이와 같은 줌 구간에서 함께 페이드인된다.
      await controller.addSymbolLayer(
        _indoorTilesSourceId,
        _indoorPoiIconLayerId,
        indoorPoiIconProps(fadeExpr, _devicePixelRatio),
        sourceLayer: 'pois',
        belowLayerId: _routeCasingLayerId,
        enableInteraction: false,
      );
      // 편의시설 아이콘: 화장실·정수기 같은 시설물은 백엔드에서 `pois`가 아니라
      // 매장으로 들어오므로 POI 아이콘 레이어를 타지 않는다. 이름을 기준으로
      // 심볼을 하나 더 얹어 아이콘이 붙게 한다. 이름은 위 편의시설 라벨
      // 레이어가 같은 점에 아래로 그린다.
      await controller.addSymbolLayer(
        _indoorTilesSourceId,
        _indoorStoreFacilityIconLayerId,
        indoorFacilityIconProps(fadeExpr, _devicePixelRatio),
        // 이름과 아이콘이 **같은 점**에 놓여야 한다. 하나만 라벨 점 레이어로
        // 옮기면 아이콘과 이름이 매장 안 서로 다른 자리에 뜬다.
        sourceLayer: 'store_labels',
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
      final imageName = poiIconImageName(icon);
      await controller.addImage(
        imageName,
        // 실내 화면과 같은 비트맵 캐시를 공유한다([map_icon_cache.dart]).
        await cachedIconPng(imageName, () => renderPoiIconPng(icon)),
      );
    }
    for (final entry in kStoreFacilityStyleByName.entries) {
      final imageName = facilityIconImageName(entry.key);
      await controller.addImage(
        imageName,
        await cachedIconPng(
          imageName,
          () => renderFacilityIconPng(entry.value),
        ),
      );
    }
    // 매장명 라벨에 붙는 대분류 아이콘. 실내 화면과 같은 이름·같은 비트맵이라
    // 두 화면 사이를 오가도 같은 매장이 같은 아이콘을 단다.
    for (final category in storeCategoryIconKeys) {
      final imageName = storeCategoryIconImageName(category);
      await controller.addImage(
        imageName,
        await cachedIconPng(
          imageName,
          () => renderStoreCategoryIconPng(category),
        ),
      );
    }
    _facilityIconImagesRegistered = true;
  }

  /// GPS 현재 위치 마커. 실내에서는 [_outdoorGpsVisible]이 false라 항상 빈
  /// 소스로 밀어 넣어 마커가 지도에서 사라진다 — [_syncGpsSubscription]이
  /// `_position`을 비우는 것과 이중으로 막아, 어느 경로로 들어와도 건물 안에서
  /// GPS 기반 위치가 보이지 않게 한다.
  Future<void> _syncCurrentLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) {
      _pendingCenterOnPosition = _outdoorGpsVisible && _position != null;
      return;
    }
    final pos = _outdoorGpsVisible ? _position : null;
    if (pos == null) {
      await controller.setGeoJsonSource(_currentSourceId, _emptyCollection());
      return;
    }
    await controller.setGeoJsonSource(
      _currentSourceId,
      _collection([_pointFeature(ll.LatLng(pos.latitude, pos.longitude))]),
    );
  }

  /// 야외 목적지 핀.
  ///
  /// **[_entrance]로 폴백하지 않는다.** 그 값은 진입/이탈 판정의 기준점이지
  /// 목적지가 아니다. 문 좌표가 채워지면서([_syncSelectedEntrance]) 폴백이
  /// 되살아났고, 앱을 켜고 GPS가 잡히기만 하면 아무도 고르지 않은 문에 빨간
  /// 핀이 찍혔다 — 경로 쪽에서 같은 폴백을 걷어낸 것과 같은 이유다.
  ///
  /// **문을 경유하는 안내 중에도 찍지 않는다.** 그때 [_userDestination]은
  /// 목적지가 아니라 지나갈 문이고, 진짜 목적지는 건물 안이라 실내 도착 핀이
  /// 따로 찍힌다([_syncIndoorDestinationLayer]). 둘 다 찍으면 야외 선이 끝나는
  /// 자리에 "여기가 목적지"로 읽히는 핀이 하나 더 생긴다.
  Future<void> _syncDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final passingThroughDoor =
        _pendingIndoorRoute != null || _pendingIndoorDestination != null;
    final target = passingThroughDoor ? null : _userDestination;
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
    if (segment != null && segment.points.isNotEmpty) {
      return segment.points.last;
    }
    // 단일 층 경로는 목적지 층에서만 그려진다. 층을 옮기면 _switchOverlayFloor가
    // 세그먼트를 비우므로, 그때는 목적지 층이 아닌 곳에 centroid 폴백 핀이
    // 남지 않도록 층을 직접 확인한다.
    return destination.floor == _activeFloor ? destination.point : null;
  }

  /// 고른 대중교통 경로를 지도에 그린다.
  ///
  /// 도보 안내는 여기서 **지운다.** 두 선을 겹쳐 두면 어느 쪽이 지금 안내인지
  /// 알 수 없고, 하단 카드가 서로 다른 소요 시간을 말하게 된다.
  Future<void> showTransitRoute(
    TransitItinerary itinerary, {
    required ll.LatLng destination,
    required String label,
    ll.LatLng? origin,
  }) async {
    _clearPendingIndoorRoute();
    _stopFollowingUser();
    setState(() {
      _transitItinerary = itinerary;
      _transitLabel = label;
      _fixedRouteOrigin = origin;
      // 도보 경로와 그 목적지 핀은 접는다. 목적지 자체는 대중교통 경로의 끝점
      // 으로 그대로 남아 있다.
      _route = null;
      _offerStartGuidance = false;
      _userDestination = destination;
      _userDestinationLabel = label;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    await _syncTransitLayer();
    _notifyRouteStateIfChanged();
    _fitCameraToPoints(itinerary.points);
  }

  /// 대중교통 안내를 끈다. 경로선·요약 카드가 함께 사라진다.
  void clearTransitRoute() {
    if (_transitItinerary == null) return;
    setState(() {
      _transitItinerary = null;
      _transitLabel = null;
    });
    unawaited(_syncTransitLayer());
    _notifyRouteStateIfChanged();
  }

  /// [point]에서 가장 가까운 지상 출입구 좌표. 문 데이터가 없으면 null이다.
  ///
  /// 대중교통 안내가 **내린 자리 기준으로** 문을 고를 때 쓴다. 예전에는 이
  /// 판단이 없어 하차 지점과 무관하게 매장 좌표로 도보 경로를 그렸고, 그러면
  /// TMAP이 매장에서 가장 가까운 도로로 스냅해 **내린 곳 반대편 문**으로
  /// 데려가는 일이 실제로 있었다.
  ll.LatLng? entranceNearestTo(ll.LatLng point) =>
      nearestEntrance(_groundEntrances, point)?.point;

  /// 대중교통에서 내린 뒤 들어갈 문을 정하고, 그 문에서 매장까지의 실내 구간을
  /// 미리 풀어 둔다. 실제로 그리는 것은 [_syncRouteLayer]다(밖에서는 미리보기,
  /// 건물에 들어가면 [_activatePendingIndoorRoute]가 승격한다).
  ///
  /// [showTransitRoute]가 시작할 때 pending을 비우므로 **그 뒤에** 불러야 한다.
  /// 순서를 뒤집으면 여기서 쌓은 실내 구간이 곧바로 지워진다.
  Future<void> prepareIndoorLegFromDrop(
    PoiSearchResult destination, {
    required ll.LatLng dropPoint,
  }) async {
    final building = _building;
    final endNodeId = destination.nodeId;
    if (building == null || endNodeId == null || destination.floor.isEmpty) {
      return;
    }
    final entrance = nearestEntrance(_groundEntrances, dropPoint);
    if (entrance == null) return;

    final graph =
        _journeyBuildingGraph ??
        await buildingRepository.getBuildingGraph(building.id);
    if (!mounted) return;
    final leg = graph == null
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);
    setState(() {
      _journeyBuildingGraph = graph;
      _journeyEntrance = entrance;
      _pendingIndoorDestination = destination;
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
    });
    _syncRouteLayer();
    _syncDestinationLayer();
    _syncIndoorDestinationLayer();
  }

  /// 대중교통 경로선을 지도에 반영한다.
  ///
  /// 구간(leg)마다 feature를 나눠 색과 도보 여부를 속성으로 실어 보낸다 —
  /// 레이어 두 개(탈것 실선 / 도보 점선)가 그 속성으로 필터해 각자 그린다.
  Future<void> _syncTransitLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final itinerary = _transitItinerary;
    if (itinerary == null) {
      await controller.setGeoJsonSource(_transitSourceId, _emptyCollection());
      await controller.setGeoJsonSource(
        _transitBadgeSourceId,
        _emptyCollection(),
      );
      return;
    }
    final features = <Map<String, dynamic>>[];
    final badges = <Map<String, dynamic>>[];
    for (final leg in itinerary.legs) {
      if (leg.points.length < 2) continue;
      features.add({
        'type': 'Feature',
        'properties': {
          'color': transitLegColorHex(leg),
          'walk': leg.mode.isWalk,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in leg.points) [p.longitude, p.latitude],
          ],
        },
      });
      // 배지는 **구간이 시작하는 자리**에 찍는다. 끝점에 찍으면 다음 구간의
      // 시작점과 같은 자리라 두 아이콘이 겹치고, 사용자는 어느 쪽이 지금부터
      // 시작하는 수단인지 알 수 없다.
      final icon = _badgeImageFor(leg.mode);
      if (icon == null) continue;
      badges.add({
        'type': 'Feature',
        'properties': {'icon': icon},
        'geometry': {
          'type': 'Point',
          'coordinates': [
            leg.points.first.longitude,
            leg.points.first.latitude,
          ],
        },
      });
    }
    await controller.setGeoJsonSource(
      _transitSourceId,
      features.isEmpty ? _emptyCollection() : _collection(features),
    );
    await controller.setGeoJsonSource(
      _transitBadgeSourceId,
      badges.isEmpty ? _emptyCollection() : _collection(badges),
    );
  }

  /// 기차·고속버스·항공은 아이콘을 따로 굽지 않았다. 이 데모의 안내 범위(도심
  /// 대중교통)에서는 나오지 않고, 굳이 버스 아이콘을 돌려 쓰면 사용자가 버스로
  /// 읽는다 — 없는 것보다 나쁘다.
  static String? _badgeImageFor(TransitMode mode) => switch (mode) {
    TransitMode.walk => kRouteWalkBadgeImageName,
    TransitMode.bus => kRouteBusBadgeImageName,
    TransitMode.subway => kRouteSubwayBadgeImageName,
    _ => null,
  };

  Future<void> _syncRouteLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final transferSegment = _indoorMultiFloorRoute?.segmentForFloor(
      _activeFloor ?? '',
    );
    final transferPoints = transferSegment == null
        ? null
        : transferRoutePointsOnFloor(transferSegment, _floorPlan, _floorGraph);
    await controller.setGeoJsonSource(
      _transferRouteSourceId,
      transferPoints == null || transferPoints.length < 2
          ? _emptyCollection()
          : _collection([_lineFeature(transferPoints, style: 'indoor')]),
    );
    // 실내 경로가 활성이면 그걸 우선 그린다(GPS 걷기 경로와 동시에 표시하지
    // 않는다 — 사용자는 지금 실내에 있고 실내 경로가 유일한 관심사).
    final indoor = _indoorRouteSegment;
    if (indoor != null && indoor.points.length >= 2) {
      await controller.setGeoJsonSource(
        _routeSourceId,
        _collection([_lineFeature(indoor.points, style: 'indoor')]),
      );
      return;
    }
    final features = <Map<String, dynamic>>[];
    final route = _route;
    if (route != null && route.points.length >= 2) {
      features.add(
        _lineFeature(route.points, style: _routeIsDriving ? 'drive' : 'walk'),
      );
    }
    // **밖에서도 실내 구간을 미리 보여준다.** 아직 승격 전이라 상태는
    // [_pendingIndoorRoute]에 있다. 예전에는 건물에 들어가야 그려져서, 안내를
    // 받아 든 사용자가 "매장까지"라는 라벨만 보고 정작 건물 안 어디로 가는지는
    // 도착할 때까지 알 수 없었다.
    //
    // 지금 펼쳐 둔 층의 구간만 그린다. 여러 층을 한꺼번에 겹쳐 그리면 같은
    // 좌표 위에 선이 여러 겹 쌓여, 어느 것이 이 층의 길인지 알 수 없다 —
    // 층 chip을 넘기면 그 층의 구간이 이어서 보인다.
    final preview = _pendingIndoorRoute?.segmentForFloor(_activeFloor ?? '');
    if (preview != null && preview.route.points.length >= 2) {
      features.add(_lineFeature(preview.route.points, style: 'indoor'));
    }
    await controller.setGeoJsonSource(
      _routeSourceId,
      features.isEmpty ? _emptyCollection() : _collection(features),
    );
  }

  /// 실내/야외 경로 중 하나라도 활성이면 true. ETA 카드 노출과 하단 바 리프트
  /// 판정에 쓴다.
  bool get _hasAnyRouteVisible =>
      _route != null ||
      _transitItinerary != null ||
      _indoorRouteSegment != null ||
      _indoorMultiFloorRoute != null;

  /// 사용자가 **직접 고른** 목적지로 안내 중인지. 안내 chrome(검색창·카테고리
  /// 줄·층 선택기·하단 바)을 접을지의 유일한 판정 기준이다.
  ///
  /// 판정 규칙과 그렇게 나눈 이유는 [shouldFoldGuidanceChrome]에 있다. 요약하면
  /// **접는 조건은 종료 버튼이 있는 조건과 같아야 한다** — 아래 ETA 카드 두
  /// 분기가 `onClose`를 다는 조건과 이 getter가 정확히 맞물려야 하고, 어느
  /// 한쪽을 고치면 그 함수를 통해 다른 쪽도 같이 바뀐다.
  bool get _guidanceActive => shouldFoldGuidanceChrome(
    hasUserDestination: _userDestination != null,
    hasIndoorRouteDestination: _indoorRouteDestination != null,
    hasComputedRoute: _route != null,
  );

  /// 상위(MapShellScreen)의 하단 바 리프트/ETA 카드 표시와 안내 chrome 접기가
  /// 어긋나지 않도록, 경로·목적지를 건드린 뒤 이 헬퍼로 상태 변화만 통보한다.
  /// 걷기 경로 쪽 [_applyRoute]와 같은 규칙(변화가 있을 때만 콜백)을 쓴다.
  ///
  /// 두 신호를 한 함수에서 같이 본다. 호출 지점을 나누면 목적지만 바뀌고 경로는
  /// 그대로인 순간(예: [showRouteTo] 진입 직후)에 한쪽만 통보되기 쉽다.
  bool _lastRouteVisibleNotified = false;
  bool _lastGuidanceActiveNotified = false;
  void _notifyRouteStateIfChanged() {
    final visible = _hasAnyRouteVisible;
    if (visible != _lastRouteVisibleNotified) {
      _lastRouteVisibleNotified = visible;
      widget.onRouteVisibleChanged?.call(visible);
    }
    final guiding = _guidanceActive;
    if (guiding != _lastGuidanceActiveNotified) {
      _lastGuidanceActiveNotified = guiding;
      widget.onGuidanceActiveChanged?.call(guiding);
    }
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
      features = await controller.queryRenderedFeatures(pointPx, [
        _indoorStoresFillLayerId,
      ], null);
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
        placeId: store.id,
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
      filter: [
        '==',
        ['get', 'kind'],
        'edge',
      ],
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
        [
          '==',
          ['get', 'kind'],
          'edge',
        ],
        [
          '==',
          ['get', 'active'],
          true,
        ],
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
      filter: [
        '==',
        ['get', 'kind'],
        'node',
      ],
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
        [
          '==',
          ['get', 'kind'],
          'node',
        ],
        [
          '==',
          ['get', 'active'],
          true,
        ],
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

  /// 실내 위치(PDR) 마커. 야외 상태에서는 [_indoorLocationVisible]이 false라
  /// 항상 빈 소스를 밀어 넣어 마커가 사라진다 — 야외에서는 GPS 마커
  /// ([_syncCurrentLayer])만 보이고, 실내에서는 이쪽만 보인다.
  Future<void> _syncPdrCurrentLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final location = _indoorLocationVisible ? _pdrCurrentWgs84() : null;
    if (location == null) {
      await controller.setGeoJsonSource(
        _pdrCurrentSourceId,
        _emptyCollection(),
      );
      return;
    }
    final heading = _pdrCurrentHeadingDeg;
    await controller.setGeoJsonSource(
      _pdrCurrentSourceId,
      _collection([
        {
          'type': 'Feature',
          'properties': <String, dynamic>{'heading': ?heading},
          'geometry': {
            'type': 'Point',
            'coordinates': [location.longitude, location.latitude],
          },
        },
      ]),
    );
  }

  /// 지금 그려야 하는 실내 위치. 출처 판단은 [IndoorGuidanceSession]이 한다.
  ///
  /// 예전에는 여기서 **앵커만** 그렸다. 홈은 층 전환을 감지하지 못하니 걸음
  /// 누적 위치를 그리면 엉뚱한 층 도면 위에서 점이 걸어간다는 이유였는데,
  /// 이제 세션이 에스컬레이터 층 전환까지 판정하므로 그 전제가 사라졌다.
  GuidancePosition? get _indoorPosition => _guidance.position;

  ll.LatLng? _pdrCurrentWgs84() {
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return null;
    final position = _indoorPosition;
    if (position == null) return null;
    final wgs84 = fitFloorGeoTransform(
      graph.nodes,
    ).apply(position.localM.eastM, position.localM.northM);
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
    return snapshot.reconciledPreviewPath
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
      on && debug.showRawPdrPath
          ? _floorPathToWgs84(_pdrRawFloorPath)
          : const [],
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
      points.length < 2
          ? _emptyCollection()
          : _collection([_lineFeature(points)]),
    );
  }

  /// 사용자가 바라보는 방향(true north 기준, 시계방향 도). PDR 세션이 heading을
  /// 아직 못 얻은 상태(예: 자북 못 잡음 + 수동 방향 보정 아직 안 함, 첫 걸음
  /// 전)에는 null을 돌려주고, 이 경우 마커도 heading 원뿔 없이 도트만 뜬다.
  /// 계산식은 실내와 동일하며 walkOffset·복도 bias를 섞지 않는다.
  double? get _pdrCurrentHeadingDeg {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    if (snapshot == null || anchor == null || !snapshot.hasHeading) return null;
    final transform = FloorCoordinateTransform(anchor);
    final orientationFloorHeading = transform.toFloorBearing(
      snapshot.orientationHeadingDeg,
    );
    return transform.floorBearingToMapBearing(orientationFloorHeading);
  }

  /// 세션에 스냅샷을 넘기고, 나온 보정 결과를 로그에 남긴다.
  ///
  /// 층·그래프·앵커·경로는 세션이 들고 있으므로 여기서 다시 확인하지 않는다.
  /// 두 곳에서 같은 조건을 세면 반드시 한쪽이 먼저 낡는다.
  /// 실내 안내를 지금 건물에 붙인다.
  ///
  /// 진입 시점에 건물이 아직 로드되지 않았을 수 있다. 그때 빈 id로 붙여 두면
  /// GPS 추정점의 건물이 영원히 안 맞아 폴백 표시가 조용히 죽는다. 로드된 뒤
  /// 처음 오는 스냅샷에서 제대로 붙인다.
  void _ensureGuidanceAttached() {
    final buildingId = _building?.id;
    if (buildingId == null || _guidance.buildingId == buildingId) return;
    _guidance.attach(buildingId: buildingId);
  }

  void _syncCorridorTracking(PdrSnapshot? snapshot) {
    if (_indoorEntered) _ensureGuidanceAttached();
    _guidance
      ..setContext(
        floorId: _activeFloor,
        graph: _floorGraph,
        floorLabels: _building?.floors ?? const [],
      )
      ..setAnchor(_pdrTrailState.anchor)
      ..setEstimate(indoorLocationEstimateController.current)
      ..setRoute(_indoorMultiFloorRoute);
    final result = _guidance.onSnapshot(snapshot);
    // 탑승점 접근 배너와 마커 고정은 기압이 아니라 **걸음 갱신**에서 올라온다.
    // 여기서 비우지 않으면 다음 기압 샘플(iOS는 약 1초)까지 늦는다.
    if (result != null) _handleEscalatorPhaseChanges();
    _syncIndoorRouteProgress(result, snapshot);
    if (result == null) return;
    _pdrDebugRecorder?.recordCorridorCorrection(result);
    if (snapshot != null) {
      _pdrDebugRecorder?.recordTrackerInput(
        observation: _guidance.lastObservation,
        wasReset: _guidance.lastWasReset,
        result: result,
        snapshot: snapshot,
        previewTailPeakTimesMs: _guidance.corridor.previewTailPeakTimesMs(
          snapshot,
        ),
      );
    }
  }

  /// 실내 경로 진행률을 갱신한다. 계산은 세션이, 다시 그리기는 여기가 한다.
  ///
  /// 홈에도 이게 필요한 이유는 ETA 카드 때문이다. 예전에는 경로 전체 길이를
  /// 고정으로 보여줘서, 목적지 앞에 서 있어도 출발할 때와 같은 거리가 떠 있었다.
  void _syncIndoorRouteProgress(
    CorridorTrackingResult? result,
    PdrSnapshot? snapshot,
  ) {
    if (!_indoorEntered) return;
    final anchor = _pdrTrailState.anchor;
    final toFloor = anchor == null ? null : FloorCoordinateTransform(anchor);
    final update = _guidance.updateProgress(
      result,
      rerouteInFlight: _indoorRerouteInFlight,
      confirmedSteps: snapshot?.steps,
      previewSteps: snapshot?.preview.steps,
      orientationHeadingDeg: snapshot == null || toFloor == null
          ? null
          : toFloor.toFloorBearing(snapshot.orientationHeadingDeg),
      walkingHeadingDeg: snapshot == null || toFloor == null
          ? null
          : toFloor.toFloorBearing(snapshot.walkingHeadingDeg),
    );
    for (final advance in update.stepAdvances) {
      _pdrDebugRecorder?.recordRouteStepAdvance(
        advance.step,
        transition: advance.transition,
      );
    }
    for (final event in update.checkpointEvents) {
      _pdrDebugRecorder?.recordCheckpointEvent(event);
    }
    final measured = update.measuredProgress;
    if (measured != null) {
      _pdrDebugRecorder?.recordRouteProgress(
        measured,
        displayProgress: update.displayProgress,
        holdReason: update.holdReason,
      );
    }
    if (update.shouldReroute &&
        DateTime.now().millisecondsSinceEpoch - _lastIndoorRerouteAtMs >=
            2000) {
      unawaited(_rerouteIndoorFromCurrentPosition());
    }
    if (mounted) setState(() {});
    _syncArrivalHighlight();
  }

  /// 도착한 순간 목적지 매장 폴리곤을 강조하고, 벗어나면 되돌린다.
  ///
  /// 카드가 "여기에 도착했다"고 말할 때 지도에서 **그 여기가 어디인지**를 함께
  /// 보여 준다. 이름만 적힌 카드로는 눈앞의 여러 매장 중 어느 쪽인지 알 수 없다.
  ///
  /// 도착이 아닐 때 강조를 지우는 쪽도 함께 둔다 — 도착 판정은 걸음에 따라
  /// 들락날락할 수 있어서, 켜기만 하면 지나쳐 걸어간 뒤에도 강조가 남는다.
  /// 사용자가 매장을 눌러 직접 켜 둔 강조는 건드리지 않는다.
  void _syncArrivalHighlight() {
    if (!mounted) return;
    final destinationId = _indoorRouteDestination?.placeId;
    if (destinationId == null) return;
    final arrived = _indoorRouteGuidance?.action == RouteGuidanceAction.arrived;
    final shouldHighlight = arrived ? destinationId : null;
    if (shouldHighlight == null && _highlightedStoreId != destinationId) return;
    if (_highlightedStoreId == shouldHighlight) return;
    setState(() => _highlightedStoreId = shouldHighlight);
    unawaited(_syncHighlightLayer());
  }

  bool _indoorRerouteInFlight = false;
  int _lastIndoorRerouteAtMs = 0;

  /// 경로를 벗어난 것이 확인되면 목적지는 유지한 채 현 위치에서 다시 뽑는다.
  ///
  /// **층 선택기 층이 아니라 앵커 층을 기준으로 한다.** 선택기는 사용자가 다른
  /// 층을 둘러보는 UI 상태일 뿐이다. 그 층으로 재탐색하면 다층 안내 중간
  /// 세그먼트가 단층 경로로 바뀌어 최종 도착처럼 보인다.
  Future<void> _rerouteIndoorFromCurrentPosition() async {
    if (_indoorRerouteInFlight) return;
    final destination = _indoorRouteDestination;
    final destinationNodeId = destination?.nodeId;
    final floor = _pdrTrailState.anchor?.floorId;
    final graph = _floorGraph;
    final buildingId = _building?.id;
    final current = _guidance.trackingResult?.previewPosition;
    if (destination == null ||
        destinationNodeId == null ||
        floor == null ||
        graph == null ||
        buildingId == null ||
        current == null) {
      return;
    }
    final startNodeId = _nearestNodeId(
      graph.nodes,
      current.eastM,
      current.northM,
      excludingNodeId: destinationNodeId,
    );
    if (startNodeId == null) return;

    _indoorRerouteInFlight = true;
    try {
      // **재탐색에는 개요 연출을 붙이지 않는다.** 재탐색은 사용자가 걷고 있는
      // 도중에 일어난다. 그때 카메라가 경로 전체를 담으러 크게 물러섰다 돌아오면
      // 연출이 아니라 방해다 — 다음 걸음을 보려던 화면이 통째로 바뀐다.
      if (destination.floor == floor) {
        await _computeAndShowSingleFloorIndoorRoute(
          buildingId: buildingId,
          floor: floor,
          endNodeId: destinationNodeId,
          playOverview: false,
          startNodeId: startNodeId,
        );
      } else {
        await _computeAndShowMultiFloorIndoorRoute(
          buildingId: buildingId,
          startFloor: floor,
          endFloor: destination.floor,
          endNodeId: destinationNodeId,
          playOverview: false,
          startNodeId: startNodeId,
        );
      }
      _lastIndoorRerouteAtMs = DateTime.now().millisecondsSinceEpoch;
    } finally {
      _indoorRerouteInFlight = false;
    }
  }

  /// 지금 이 층 실내 경로의 턴바이턴 안내. 없으면 null.
  ///
  /// 실내 탭과 같은 규칙을 쓴다 — 도착 안내는 **목적지 세그먼트에서만** 낸다.
  /// 중간 층 세그먼트의 끝은 도착이 아니라 환승이라, 거기서 "도착했습니다"를
  /// 띄우면 사용자가 남은 층을 안 가고 멈춘다.
  RouteGuidanceInstruction? get _indoorRouteGuidance {
    final route = _indoorRouteSegment;
    if (route == null || route.pointsLocalM.isEmpty) return null;
    // **실내 위치가 없으면 한 줄 안내를 내지 않는다.**
    //
    // [buildRouteGuidance]는 진행률이 null이면 경로 **전체**를 기준으로 다음
    // 회전을 찾는다. 그래서 건물 밖에 서 있어도 "110미터 후 에스컬레이터 탑승"
    // 같은 문장이 떴다 — 사용자는 아직 버스에서 내려 걷는 중인데 화면은 건물 안
    // 몇 미터 앞을 말한다. 실내 오버레이만으로 가르면 안 되는 이유는, 그 오버레이가
    // 건물로 확대하기만 해도 켜지기 때문이다(indoor_entry_zoom.dart).
    //
    // 기준은 "우리가 이 사람이 실내 어디에 있는지 아는가"다. 그게 곧 진행률의
    // 출처이고, 진입을 실제로 감지해 앵커를 잡았을 때만 참이 된다.
    if (_guidance.displayProgress == null) return null;
    final multi = _indoorMultiFloorRoute;
    final segment = multi?.segmentForFloor(_activeFloor ?? '');
    final allowArrival =
        multi == null ||
        (segment != null &&
            identical(segment, multi.destinationSegment) &&
            _activeFloor == _indoorRouteDestination?.floor);
    return buildRouteGuidance(
      localPoints: route.pointsLocalM,
      wgs84Points: route.points,
      progress: _guidance.displayProgress,
      travelDirectionState: _guidance.travelDirectionState,
      transferMode: segment?.transferModeToNext,
      allowArrival: allowArrival,
    );
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

  /// 야외 POI 검색의 기준점.
  ///
  /// GPS를 먼저 쓰고, 아직 신호가 없으면 **지금 보고 있는 지도 중심**으로
  /// 떨어진다. 후자를 폴백으로 두는 이유는, 기준점이 없으면 TMAP POI 검색이
  /// 전국을 뒤져 걸어갈 수 없는 후보를 첫 줄에 올리기 때문이다. 사용자가 보고
  /// 있는 화면 중심은 "여기 근처"라는 의도로 읽어도 무리가 없다.
  ll.LatLng? get outdoorSearchCenter {
    final position = _position;
    if (position != null) {
      return ll.LatLng(position.latitude, position.longitude);
    }
    final target = _mapController?.cameraPosition?.target;
    if (target == null) return null;
    return ll.LatLng(target.latitude, target.longitude);
  }

  /// 이 좌표가 우리 실내 도면이 있는 건물의 것인가.
  ///
  /// 검색 결과를 합칠 때 "이 POI가 우리가 아는 건물의 가게인가"를 묻는 자리가
  /// 있어서 밖으로 연다([SearchPanel.isInsideIndoorBuilding]).
  ///
  /// **외곽선 안인지만 보면 안 된다.** 이유와 여유 폭의 근거는
  /// [_poiBuildingProximityMeters]에 적어 뒀다 — 실제로 "스타벅스
  /// 더현대서울(B2)R점"이 엄격 판정에서 "건물 밖"이 되어 우리 "스타벅스
  /// 리저브"와 나란히 남아 있었다.
  bool isAtIndoorBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) return false;
    return metersToPolygon(point, footprint) <= _poiBuildingProximityMeters;
  }

  /// 지도를 한 지점으로 옮긴다. 검색 결과에서 고른 야외 장소를 시트가 덮기 전에
  /// 화면에 먼저 보여 주는 용도다.
  Future<void> focusPoint(ll.LatLng point) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(point), _poiFocusZoom),
    );
  }

  /// 상위(MapShellScreen)가 매장 정보 시트가 닫힐 때 호출해 강조를 지운다.
  void clearHighlight() {
    if (_highlightedStoreId == null) return;
    setState(() => _highlightedStoreId = null);
    _syncHighlightLayer();
  }

  /// 지금 층을 **다시 고른 것과 같은 화면**으로 되돌린다.
  ///
  /// 매장을 고르면 카메라가 그 매장으로 당겨지고 시트에 가리지 않도록 위로
  /// 밀린다. 아무것도 고르지 않고 시트를 닫으면 사용자가 보려던 것은 다시 층
  /// 전체인데, 그 치우친 화면이 그대로 남아 있으면 방금 어디를 보고 있었는지
  /// 다시 찾아야 한다. 층 전환과 **같은 함수·같은 시간**으로 되돌려, 층 선택기를
  /// 누른 것과 구분되지 않는 화면을 만든다.
  ///
  /// 실내에 들어와 있지 않으면 되돌릴 기준이 없으므로 아무것도 하지 않는다.
  Future<void> realignToActiveFloor() async {
    if (!_indoorEntered) return;
    await _fitCameraToActiveFloor(duration: _floorSwitchZoomDuration);
  }

  /// 검색 후보(`StoreIndexEntry`)를 좌표까지 갖춘 [PoiSearchResult]로 바꾼다.
  /// 찾지 못하면 null — 상위가 이름으로 검색을 다시 돌린다.
  ///
  /// **후보 목록이 좌표를 들고 오지 않기 때문에 이 변환이 필요하다.**
  /// `/store-index`는 1,640건을 한 번에 내려보내는 응답이라 좌표를 싣지 않는다
  /// (근거와 실측치는 `StoreIndexResponse` 주석). 그렇다고 후보를 탭했을 때
  /// 그 이름으로 검색을 다시 돌리면 사용자는 같은 줄을 두 번 누르게 된다.
  ///
  /// 그래서 이미 가진 것에서 좌표를 찾는다 — 층 도면([_floorPlan])이 매장마다
  /// `centroid`를 들고 있고, 그 층은 어차피 열어야 한다. 추가 요청이 없다.
  ///
  /// 이름이 아니라 **id로 찾는다.** 이름은 유일 키가 아니라서(동명 시설 다수)
  /// 이름으로 맞추면 같은 층의 다른 매장을 열 수 있다.
  ///
  /// **실내에 들어와 있지 않으면 층을 옮기지 않고 포기한다.** 층 전환은 실내
  /// MVT 소스를 통째로 갈아 끼우고 끝에서 카메라를 건물로 당겨오는 작업이라,
  /// 야외에서 부르면 매장 강조는 [focusStore]가 `_indoorEntered` 검사로 막는데
  /// 카메라만 건물로 튀는 반쪽 이동이 남는다. 그 경우 null을 돌려주면 상위가
  /// 이름 재검색으로 떨어지고, 사용자는 한 번 더 누르지만 화면은 어긋나지 않는다.
  Future<PoiSearchResult?> resolveIndexEntry(StoreIndexEntry entry) async {
    if (entry.floorName.isNotEmpty && entry.floorName != _activeFloor) {
      if (!_indoorEntered) return null;
      // 검색에서 타 층 매장을 고른 경로 — 사용자가 층 전환을 가장 자주 체감하는
      // 자리다. 새 도면 페이드인은 이어지는 매장 포커스 카메라 이동과 겹친다.
      await _switchOverlayFloorCrossfaded(entry.floorName);
      if (!mounted) return null;
      // 기다리는 사이 다른 전환이 추월했으면 다른 층 도면에서 좌표를 찾게
      // 되므로 여기서 멈춘다([focusStore]와 같은 규칙).
      if (_activeFloor != entry.floorName) return null;
    }
    // 층은 맞지만 그 층 도면 로드가 아직 도는 중일 수 있다 — 층을 막 바꾼
    // 직후의 검색 탭이 대표적이다. 기다리지 않으면 [_floorPlan]이 비어 있어
    // 첫 탭이 조용히 null로 떨어지고, 상위가 이름 재검색으로 돌려 사용자는
    // 같은 매장을 **두 번** 눌러야 한다.
    await _floorGraphLoad;
    if (!mounted) return null;
    final stores = _floorPlan?.stores;
    if (stores == null) return null;

    for (final store in stores) {
      if (store.id != entry.id) continue;
      return PoiSearchResult(
        name: entry.name,
        floor: entry.floorName,
        point: store.centroid,
        placeId: entry.id,
        // 도착 노드는 색인 쪽을 쓴다. 층 도면에도 같은 값이 있지만, 후보 줄에
        // "길찾기 가능"을 판단한 근거가 색인이라 화면과 행동이 갈리지 않는다.
        nodeId: entry.entranceNodeId,
        category: entry.category,
        subcategory: entry.subcategory,
      );
    }
    return null;
  }

  /// 목록에서 고른 매장을 실내 진입 오버레이 위에서 보여 준다.
  /// [IndoorMapBodyState.focusStore]와 같은 계약이라 상위가 두 화면을 똑같이
  /// 다룰 수 있다 — 다만 **층은 옮기지 않는다**. 이 화면의 층 전환은 실내 MVT
  /// 소스를 통째로 갈아 끼우는 작업이라, 목록을 훑는 중에 자동으로 일어나면
  /// 사용자가 보고 있던 층이 소리 없이 바뀐다. 호출부가 지금 층 매장만 넘긴다.
  /// [enterBuildingIfNeeded]면 건물 밖에서 골랐어도 **건물에 들어가고 층까지
  /// 맞춘 뒤** 그 매장을 보여 준다.
  ///
  /// 검색 결과에서 매장을 고르는 것은 "이 매장을 보여 달라"는 명시적 조작인데,
  /// 예전에는 실내가 아니거나 다른 층이면 여기서 조용히 빠져나갔다. 그래서 멀리
  /// 있는 사용자가 매장을 눌러도 아무 일도 일어나지 않았다 — 시트만 올라오고
  /// 지도는 도시 축척 그대로였다.
  ///
  /// 지도 위 카테고리 목록에서 오는 호출은 이 값을 주지 않는다. 그쪽 시트는
  /// **지금 층 매장만** 올려 주므로, 층을 갈아타면 시트 머리글이 말하는 층과
  /// 지도가 어긋난다.
  Future<void> focusStore(
    PoiSearchResult store, {
    double bottomSheetFraction = 0,
    double topInsetPx = 0,
    bool keepZoom = false,
    bool enterBuildingIfNeeded = false,
  }) async {
    // 밖에서 들어온 경우 배율을 유지하면 도시 축척 그대로 매장 위에 서게 된다.
    // 그때는 keepZoom 요청을 무시하고 매장이 보이는 배율까지 확대한다.
    final fromOutside = !_indoorEntered;
    if (fromOutside && !enterBuildingIfNeeded) return;

    // **여기서 실내 모드를 직접 켜지 않는다.** 켜면 [_indoorContextActive]가
    // 함께 참이 되고, 그 값이 길찾기의 출발지 규칙을 통째로 바꾼다 — 야외
    // GPS 대신 PDR 앵커를 요구하게 되어, 멀리서 매장을 고른 사용자가 "도착"을
    // 눌렀을 때 "출발 위치를 먼저 지정해주세요"로 막힌다. 검색에서 매장을 고른
    // 것은 위치를 지정한 것이 아니다.
    //
    // 대신 카메라만 그 매장으로 확대한다. 진입 판정은 사용자가 직접 확대했을
    // 때와 **같은 경로**([_handleCameraIdle])가 맡는다 — 그 배율에 도달하면
    // 알아서 켜지고, 판정 근거(건물 근접·줌 임계값)도 한 곳에만 남는다.
    if (store.floor.isNotEmpty && store.floor != _activeFloor) {
      if (!enterBuildingIfNeeded) return;
      // 층 교체는 실내 모드와 무관하다 — 도면 소스만 갈아 끼우므로, 카메라가
      // 도착했을 때 그 매장이 있는 층이 그려져 있게 된다.
      await _switchOverlayFloorCrossfaded(store.floor);
      if (!mounted) return;
      // 층 전환이 실패했으면(그 층 그래프·도면을 못 받음) 다른 층 도면 위에
      // 엉뚱한 자리를 강조하게 되므로 여기서 멈춘다.
      if (store.floor != _activeFloor) return;
    }
    // 도면 로드가 아직 도는 중이면 기다린다 — 아래 강조([_syncHighlightLayer])가
    // [_floorPlan]에서 매장 폴리곤을 찾으므로, 로드 전에 그리면 강조 없이
    // 카메라만 움직이는 반쪽 포커스가 된다([resolveIndexEntry]와 같은 이유).
    await _floorGraphLoad;
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    setState(() => _highlightedStoreId = store.placeId);
    await _syncHighlightLayer();
    if (!mounted) return;

    // 뷰포트는 카메라 이동 전에 읽는다(실내 화면과 같은 이유 — await 뒤에
    // MediaQuery를 보면 그 사이 위젯이 트리에서 빠졌을 수 있다).
    final viewport = MediaQuery.sizeOf(context);
    final camera = controller.cameraPosition;
    final currentZoom = camera?.zoom ?? 0;
    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toGl(store.point),
          // 배율 규칙은 실내 도면과 한 함수를 공유한다(focusZoomFor).
          zoom: focusZoomFor(
            currentZoom: currentZoom,
            keepZoom: keepZoom && !fromOutside,
            storeFocusZoom: _storeFocusZoom,
          ),
          bearing: camera?.bearing ?? 0,
          tilt: camera?.tilt ?? 0,
        ),
      ),
    );
    // 위(검색창·카테고리 줄)와 아래(시트)가 가리고 남는 띠의 한가운데로. 부호와
    // 단위 근거는 `floor_plan_view.dart`의 같은 계산 주석에 있다.
    final lift = (viewport.height * bottomSheetFraction - topInsetPx) / 2;
    if (lift <= 0) return;
    await controller.moveCamera(CameraUpdate.scrollBy(0, -lift));
  }

  /// 목록에서 고른 매장을 볼 때의 최소 확대. 실내 화면과 같은 값이라야 두
  /// 화면을 오가도 같은 크기로 보인다.
  static const _storeFocusZoom = 19.0;

  /// 검색 결과에서 고른 **건물**의 바깥 모습이 보이도록 카메라를 옮긴다.
  ///
  /// 매장은 [focusStore]가 한 점으로 끌어오지만 건물은 **면**이다. 입구 좌표
  /// 하나로만 옮기면 더현대 서울처럼 큰 건물은 중심만 맞은 채 화면 밖으로
  /// 삐져나가, 정작 "무엇을 고른 것인지"가 안 보인다.
  ///
  /// **여기서 실내로 들어가지는 않는다.** 이게 이 함수의 핵심 제약이다. 한때
  /// 외곽선을 화면에 꼭 맞췄는데(`newLatLngBounds`), 그 배율이 곧 실내 진입
  /// 임계값이라([_entryZoomThreshold]는 "건물이 화면을 채우는 zoom"이다) 검색 결과를
  /// 누르자마자 도면이 열렸다. 검색은 "저 건물이 어디 있는지"를 묻는 조작이지
  /// "들어가겠다"가 아니다. 들어가는 것은 건물을 **탭**하는 별도 조작이 맡는다
  /// ([_handleMapClick] 끝의 [_triggerIndoorEntry]).
  ///
  /// 그래서 배율은 [exteriorViewZoomFor]가 정한다 — 진입 판정과 **같은 파일**에
  /// 두어 두 값이 어긋날 수 없게 묶어 둔 함수다.
  ///
  /// 옮길 자리가 없으면(외곽선도 입구도 없는 건물) 아무 일도 하지 않는다.
  Future<void> focusBuilding(Building building) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    // **목록 응답으로 온 건물은 외곽선이 없다.** `/buildings`는 id·이름·층만
    // 내려주고 `footprint_wgs84`·`entrance`는 단건(`/buildings/{id}`)에만 있다
    // (같은 이유로 [_fetchAllBuildings]가 목록으로 단건 캐시를 채우지 않는다).
    // 검색 결과의 건물 한 줄은 그 목록에서 나오므로, 여기 그대로 쓰면 옮길
    // 좌표가 하나도 없어 아무 일도 일어나지 않는다 — 화면에서는 "눌렀는데
    // 지도가 안 움직인다"로만 보인다.
    final resolved = building.id == _building?.id
        // 지금 지도에 올라온 건물이면 이미 단건으로 받아 둔 것을 쓴다.
        ? _building!
        : (await buildingRepository.getBuilding(building.id) ?? building);
    if (!mounted) return;

    final footprint = resolved.footprintWgs84;
    final center = footprint == null || footprint.length < 3
        ? null
        : _buildingCenter(footprint);
    if (footprint != null && center != null) {
      final width = polygonWidthMeters(footprint);
      // 폭이 0이면 zoom 계산이 발산한다. 그런 외곽선은 점이나 마찬가지라
      // 아래 입구 폴백으로 흘려보낸다.
      if (width > 0) {
        final zoom = exteriorViewZoomFor(
          buildingWidthMeters: width,
          viewportWidthPx: MediaQuery.sizeOf(context).width,
          latitude: center.latitude,
        );
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(_toGl(center), zoom),
        );
        // 카메라만 움직이면 "뭔가 지나갔다"로 끝난다. 건물을 탭했을 때와 같은
        // 반짝임을 줘서 어느 건물을 말하는 것인지 화면에 못 박는다.
        await _flashBuildingFill();
        return;
      }
    }

    final entrance = resolved.entrance;
    if (entrance == null) {
      // 옮길 좌표가 하나도 없다. 조용히 끝내면 "눌렀는데 아무 일도 안 일어난다"의
      // 원인을 화면 밖에서 찾을 수 없다 — 실제로 이 침묵 때문에 목록 응답에
      // 외곽선이 없다는 사실을 한참 뒤에야 찾았다.
      debugPrint(
        '[outdoor overlay] focusBuilding ${building.id}: 좌표 없음 '
        '(footprint=${footprint?.length ?? 0}pts, entrance=null)',
      );
      return;
    }
    await controller.animateCamera(CameraUpdate.newLatLng(_toGl(entrance)));
  }

  /// PDR 세션이 [floor]를 가리키게 맞춘다. 이어서 앵커를 찍어도 되면 true.
  ///
  /// **다른 층에서 이미 돌고 있는 세션을 그냥 재사용하면 안 된다.** 앵커에
  /// 찍히는 층은 세션의 층([IndoorNavigationView.currentFloorId])이고, 위치
  /// 마커·경로는 `anchor.floorId == 지금 보고 있는 층`일 때만 그려진다. 그래서
  /// 1층에서 위치를 지정한 뒤 2층에서 다시 지정하면, 새 앵커가 여전히 1층으로
  /// 기록돼 2층 지도에는 아무것도 나타나지 않았다 — 사용자 눈에는 "첫 층 말고는
  /// 위치 지정이 안 되는" 버그였다. 오류도 안 뜨니 원인을 짚을 단서도 없었다.
  ///
  /// 앵커를 새로 찍는 것은 **기준점을 새로 잡는 것**이므로, 이전 기준점 기준의
  /// 궤적·복도 보정을 함께 비운다. 이전 층에서 쌓은 걸음·궤적을 그대로 이어받으면
  /// 새 앵커 기준 위치가 처음부터 어긋난 채 시작한다.
  ///
  /// [gatePermission]이 false면 권한을 확인하지 않고 곧바로 세션을 시작한다. GPS로
  /// 건물 안임을 이미 확인한 **자동 진입** 경로만 그렇게 쓴다 — 거기서 게이트를 한
  /// 번 더 두면 자동 추적 자체가 시작되지 않는다. 자동 진입은 또 세션이 이미 같은
  /// 층에서 돌고 있으면 아무것도 건드리지 않는다. 사용자가 쌓아온 궤적을 GPS 틱이
  /// 지울 이유가 없다.
  ///
  /// [announceFailure]는 센서를 못 켠 이유를 사용자에게 알릴지다. 사용자가 직접
  /// "위치 지정"을 누른 경우에만 켠다 — 출발지 매장을 따라 찍는 경로는 조용히
  /// 포기하고 경로만 그린다.
  Future<bool> _bindPdrSessionToFloor(
    String floor, {
    bool gatePermission = true,
    bool announceFailure = false,
  }) async {
    if (indoorNavigationDriver.currentRuntimeStatus.state ==
        PdrRuntimeState.idle) {
      if (!gatePermission) {
        setState(() => _pdrTrailState.beginNewSession());
        await indoorNavigationDriver.startGuidance(floorId: floor);
        return mounted;
      }
      await _startPdrIfIdle();
      if (!mounted) return false;
      if (indoorNavigationDriver.currentRuntimeStatus.state ==
          PdrRuntimeState.idle) {
        if (announceFailure) {
          _showSnack('걸음 센서 권한이 없어 위치를 추적할 수 없습니다. 설정에서 동작·피트니스 권한을 허용해주세요.');
        }
        return false;
      }
    } else if (indoorNavigationDriver.currentFloorId != floor) {
      await indoorNavigationDriver.changeFloor(floorId: floor);
      if (!mounted) return false;
    } else if (!gatePermission) {
      // 자동 진입인데 이미 이 층 세션이 돌고 있다. 그대로 이어 쓴다.
      return true;
    }
    setState(() {
      _pdrTrailState.beginNewSession();
      // 새 PDR 세션이다. 이전 세션의 보정을 들고 가면 첫 프레임이 지난 세션
      // 좌표에서 시작한다. 층·경로 컨텍스트는 그대로 두고 보정만 비운다.
      //
      // 진행률 기준점도 함께 버린다. 앵커가 옮겨졌는데 진행거리만 이전 세션
      // 값으로 남으면, 다음 걸음에서 남은거리가 튀거나 재획득이 매 걸음 켜진다.
      _guidance
        ..resetTracking()
        ..clearProgress();
    });
    return true;
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
    // 위치를 다시 지정하는 것은 기준점을 새로 잡는 것이다. 세션을 이 층에 맞추고
    // 이전 기준점 기준의 궤적·보정을 비우는 일은 모두 여기서 처리한다.
    if (!await _bindPdrSessionToFloor(floor, announceFailure: true)) return;
    _setPlacingAnchor(true);
    _showSnack('지도에서 현재 서 있는 위치를 탭해 지정해주세요.');
  }

  /// 진단 세션은 실내 지도 탭과 같은 경계를 쓴다 — **한 번의 길안내**.
  ///
  /// 상세한 근거는 실내 화면의 `_beginRouteRecordingSession` 주석을 본다. 요지는
  /// PDR이 상시 실행이 된 뒤 "시작~종료"를 경계로 쓸 수 없고, 그대로 두면 표본
  /// 상한에 걸려 분석하려는 구간이 앞에서부터 잘려 나간다는 것이다.
  void _beginRouteRecordingSession() {
    _pdrDebugRecorder = PdrDebugSessionRecorder()
      ..recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) _pdrDebugRecorder?.recordSnapshot(snapshot);
    _pdrDebugRecorder?.recordCalibration(
      indoorNavigationDriver.currentCalibration,
    );
  }

  /// 경로가 해제되면 세션을 닫는다. [announceExport]는 세션 경계 기록에만 쓴다
  /// — 사용자가 끝낸 것(routeEnded)과 새 경로로 갈아탄 것(routeReplaced)을
  /// 사후 분석에서 구분하기 위해서다.
  ///
  /// 예전에는 여기서 "진단 JSON을 내보낼 수 있다"는 토스트를 띄웠다. 안내가
  /// 끝나는 순간은 도착 카드가 뜨는 순간이라 토스트가 그 위를 덮었고, 내보내기
  /// 진입점은 디버그 모드의 공유 버튼([PdrMapControl])이 이미 지도에 상시로
  /// 있다 — 같은 일을 하는 두 번째 입구가 화면을 가리기만 했다.
  void _endRouteRecordingSession({bool announceExport = true}) {
    final recorder = _pdrDebugRecorder;
    if (recorder == null) return;
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) recorder.recordSnapshot(snapshot);
    recorder.recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    recorder.recordSessionBoundary(
      announceExport ? 'routeEnded' : 'routeReplaced',
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

  /// [localPoint]가 지도 위 Flutter 오버레이(층 선택기·PDR 제어와 상위가 얹은
  /// 검색창·카테고리 열·하단 바) 영역이면 true. 인자는 MapLibre가
  /// 준 지도 위젯 로컬 좌표라 전역 좌표로 바꿔 비교한다.
  bool _isTapOnMapOverlay(Offset localPoint) {
    final mapBox = context.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.attached) return false;
    final globalPoint = mapBox.localToGlobal(localPoint);
    if (_mapOverlayTapGuard.consumeIfBlocked(globalPoint)) return true;

    for (final key in [
      _floorSelectorKey,
      _pdrControlKey,
      _placingHintKey,
      _buildingLoadFailedKey,
      _etaCardKey,
      ...widget.outerOverlayKeys,
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

  /// 길찾기 "지도에서 선택" 중에 매장이 아닌 곳을 눌렀을 때. 후보를 만들어
  /// 넘겼으면 true(=이 탭은 여기서 끝난다).
  ///
  /// 스냅 규칙은 [_onMapPressedForPdr]와 **같은 것**을 쓰고, 노드까지 확정해
  /// 넘기는 이유도 실내 화면의 동명 처리와 같다(다익스트라가 노드에서 시작·종료
  /// 하므로 노드 id 없는 후보는 경로를 만들지 못한다).
  ///
  /// 통로에서 너무 먼 탭은 **false를 돌려 흘려보낸다.** 실내와 다른 점이 여기다 —
  /// 야외 지도에서 그 탭은 대개 "건물 밖을 눌러 실내에서 나가겠다"는 뜻이므로,
  /// 여기서 삼키면 고르는 중에는 실내에서 빠져나올 방법이 사라진다.
  bool _handleMapPickTap(ll.LatLng point) {
    final floor = _activeFloor;
    final graph = _floorGraph;
    if (floor == null || graph == null || graph.nodes.isEmpty) return false;
    final transform = fitFloorGeoTransform(graph.nodes);
    final local = transform.invert(point.latitude, point.longitude);
    if (local == null) return false;
    final snapped = FloorMapMatcher(
      graph,
    ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
    if (snapped == null) return false;
    if (snapped.distanceToGraphM > _maxPdrAnchorSnapDistanceM) return false;

    final nodeId = _nearestGraphNodeId(
      graph.nodes,
      snapped.point.eastM,
      snapped.point.northM,
    );
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return false;
    // 노드에 실측 좌표가 있으면 그대로 쓴다. 있는 값을 두고 변환을 태우면
    // 피팅 오차만큼 어긋난 자리에 핀이 찍힌다(실내 화면과 같은 규칙).
    final latLng = node.lat != null && node.lng != null
        ? ll.LatLng(node.lat!, node.lng!)
        : () {
            final (lat, lng) = transform.apply(node.xM, node.yM);
            return ll.LatLng(lat, lng);
          }();
    widget.onMapPointPicked?.call(
      PoiSearchResult(
        name: kMapPickedPointLabel,
        floor: floor,
        point: latLng,
        nodeId: node.id,
      ),
    );
    return true;
  }

  /// [xM], [yM]에 가장 가까운 그래프 노드 id. 실내 화면의 동명 헬퍼와 같은
  /// 계산이다.
  String? _nearestGraphNodeId(List<GraphNode> nodes, double xM, double yM) {
    GraphNode? nearest;
    double? nearestDistanceSquared;
    for (final node in nodes) {
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

  /// [notifyLocationChanged]는 "사용자의 현재 위치가 새로 잡혔다"를 상위에
  /// 알릴지다. 기본은 알린다 — 지도 탭·입구 자동 배치처럼 **새 위치가 생긴**
  /// 경우이기 때문이다. 출발지 매장을 따라 찍는 경우([_anchorAtStoreOrigin])만
  /// 끈다. 그쪽은 상위가 방금 정한 출발지를 되짚어 찍는 것이라, 다시 알리면
  /// 상위가 그 출발지를 스스로 버리게 된다.
  Future<void> _confirmPdrAnchor(
    PdrLocalPoint floorPoint, {
    bool notifyLocationChanged = true,
  }) async {
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
    if (notifyLocationChanged) widget.onLocationAnchored?.call();
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
    _pdrDebugRecorder?.recordPedometerFinalize(
      indoorNavigationDriver.lastPedometerFinalizeInfo,
    );
    _pdrDebugRecorder?.recordSessionBoundary('sensorStopped');
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

  /// 마지막으로 띄운(아직 닫히지 않은) 스낵바 문구. 같은 문구의 연속 재표시를
  /// 막는 근거다.
  String? _visibleSnackMessage;

  void _showSnack(String message) => _showSnackGuarded(message, replace: false);

  /// 지금 떠 있는 안내를 걷어내고 새 안내를 띄운다.
  ///
  /// 자동 실내 진입은 '건물 감지 중...'을 먼저 띄우고 뒤이어 결과를 알린다.
  /// 그냥 showSnackBar를 부르면 두 번째 안내가 큐에 쌓여 첫 안내가 4초를 다
  /// 채운 뒤에야 뜬다 — 이미 끝난 작업의 진행 중 문구를 계속 보여주고, 하단
  /// 바를 그만큼 오래 가린다.
  void _replaceSnack(String message) =>
      _showSnackGuarded(message, replace: true);

  /// 같은 문구가 이미 떠 있으면(또는 큐에 남아 있으면) 다시 띄우지 않는다.
  ///
  /// GPS 틱·건물 감지처럼 **반복 호출되는 경로**가 같은 안내를 매번 다시 띄우면,
  /// 표시 시간이 그때마다 처음부터 다시 시작돼 "영원히 안 사라지는" 스낵바가
  /// 된다(replace 계열은 이전 것을 걷어내고 새로 띄우므로 특히 그렇다). 시각
  /// 기억 대신 "지금 그 문구가 떠 있는가"를 기준으로 거른다 — 닫힌 뒤의 정당한
  /// 재표시는 막지 않고, 테스트의 가짜 시계와도 어긋나지 않는다.
  void _showSnackGuarded(String message, {required bool replace}) {
    if (!mounted) return;
    if (_visibleSnackMessage == message) return;
    final messenger = ScaffoldMessenger.of(context);
    if (replace) messenger.hideCurrentSnackBar();
    _visibleSnackMessage = message;
    messenger
        .showSnackBar(SnackBar(content: Text(message)))
        .closed
        .whenComplete(() {
          if (_visibleSnackMessage == message) _visibleSnackMessage = null;
        });
  }

  @override
  Widget build(BuildContext context) {
    // 어느 경로로 상태가 바뀌든 여기서 한 번 보고한다. 상태를 바꾸는 자리마다
    // 호출을 흩뿌리면 반드시 한 곳을 빠뜨리고, 그러면 배너가 남거나 안 뜬다.
    // 같은 값이면 알리지 않으므로 매 프레임 불러도 부모가 다시 그리지 않는다.
    _reportFloorTransitionUi();
    return _buildBody();
  }

  Widget _buildBody() {
    final position = _position;
    final accuracy = position?.accuracy ?? 0;
    // GPS를 쓰지 않는 실내 상태에서는 신호 품질 배지도 띄우지 않는다. 위치가
    // 비어 있다는 이유로 "GPS 신호 약함"이 뜨면, 실내에서 GPS를 기다리는 중인
    // 것처럼 읽혀 실제 동작(PDR 기반)과 어긋난다.
    final lowAccuracy =
        _outdoorGpsVisible &&
        (position == null || accuracy > _lowAccuracyThresholdMeters);
    final route = _route;
    final userDestination = _userDestination;
    final indoorRouteDestination = _indoorRouteDestination;
    // 거리·시간을 한 번에 계산한다(예전엔 같은 계산을 두 번 돌았다).
    final indoorEta = _indoorEta();
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
            // (건물 fill처럼 enableInteraction이 켜진 레이어)를 탭한 순간 별도
            // feature-tap만 발화하고 onMapClick은 삼켜버린다. 그러면 사용자가
            // 실내 진입 오버레이 위에서 "위치 지정" → 건물 폴리곤을 탭했을
            // 때 _handleMapClick이 아예 호출되지 않아 PDR 앵커 배치가 조용히
            // 실패한다. 이 값을 켜서 feature-tap이 있어도 onMapClick도 함께
            // 오게 만든다(실내 지도의 FloorPlanView가 같은 이유로 이미 켜둠).
            // 실내 오버레이 레이어는 전부 인터랙션을 꺼 두었다 — 이유는
            // _ensureIndoorTilesRegistered의 레이어 등록 주석 참고.
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

        // 층 전환이 오래 걸릴 때만 지도 위 중앙에 뜨는 에스컬레이터 모티프.
        // 이전 층 도면이 그대로 보이는 위에 뜬다 — 덮개(베일)는 없다. 실기기
        // 에서 흰 베일이 캡처 플래시처럼 번쩍여 걷어냈고, 모티프는 자체 카드
        // 배경이 있어 도면 위에서도 읽힌다. 타이밍 정책은
        // core/floor_switch_progress.dart. AnimatedSwitcher가 등장·퇴장을
        // 페이드로 처리하고, 숨김이 끝나면 위젯을 트리에서 내려 벨트 애니메이션
        // ticker도 함께 멈춘다. IgnorePointer라 지도 조작을 안 막는다.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _floorSwitchMotifVisible
                  ? Center(
                      child: FloorSwitchEscalatorMotif(
                        direction: _floorSwitchMotifDirection,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),

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

        // 건물을 못 불러오면 층 선택기·위치 지정·실내 진입·실내 도면이 통째로
        // 사라진다. 그 이유를 화면에 남기고 재시도 경로를 준다 — 예전에는 이
        // 상태가 아무 표시 없이 조용히 지나갔다.
        //
        // 자리는 위치 지정 안내와 같은 [_placingHintTopPx]다. **누를 수 있어야
        // 하므로 GPS 배지 자리(top 76)를 쓰면 안 된다** — 거기는 MapShellScreen의
        // 카테고리 chip 열(top 78)에 덮여 탭이 chip으로 먹힌다. 두 오버레이는
        // 동시에 뜨지 않는다(위치 지정은 실내 진입 상태에서만 열리고, 그러려면
        // 건물이 로드돼 있어야 한다).
        if (_buildingLoadFailed)
          Positioned(
            top: _placingHintTopPx,
            left: 12,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                key: _buildingLoadFailedKey,
                onTap: () => unawaited(_retryBuildingLoad()),
                child: StatusBadge(
                  label: _retryingBuildingLoad
                      ? '건물 정보를 다시 불러오는 중…'
                      : '건물 정보를 불러오지 못했습니다 · 다시 시도',
                  color: AppColors.warning,
                  icon: Icons.wifi_off,
                ),
              ),
            ),
          ),

        // GPS 실내 진입 판정의 근거를 그 자리에서 읽기 위한 진단 칩.
        //
        // 실기기를 들고 건물을 드나드는 실험에서, 화면에 보이는 유일한 신호는
        // "건물 감지 중…" 스낵바와 도면 전환뿐이라 **안 걸렸을 때 원인을 알
        // 방법이 없었다.** 오차가 커서 건너뛴 것인지, 안쪽 문턱을 못 넘은
        // 것인지, 자동 진입이 꺼져 있는 것인지가 이 한 줄에서 갈린다.
        //
        // 자리는 건물 로드 실패 배지([_placingHintTopPx]) 한 줄 아래다. 둘은
        // 동시에 뜰 수 있고(외곽선을 못 받으면 칩은 '외곽선 없음'을 띄운다),
        // 겹치면 정작 원인을 가린다. 칩 자체는 IgnorePointer라 탭을 안 먹는다.
        if (debugEnabled)
          Positioned(
            top: _placingHintTopPx + 44,
            left: 12,
            child: SafeArea(
              bottom: false,
              child: ValueListenableBuilder<String?>(
                valueListenable: _gpsVerdictDebugText,
                builder: (_, text, _) => MapDebugChip(text: text),
              ),
            ),
          ),

        // 실내 진입 오버레이 — 야외 지도 위 좌측 하단에 세로 층 선택기를 얹어
        // 실내 화면과 동일한 위치·디자인으로 층을 훑을 수 있게 한다.
        //
        // **안내 중에는 접는다.** 안내가 도는 동안 층은 사용자가 고르는 것이
        // 아니라 경로가 정한다 — 층이 바뀌는 순간 [_enqueueFloorTransition]이
        // 도면을 갈아 끼우고, 그 판정이 틀렸을 때 되돌리는 수단은 층 선택기가
        // 아니라 전환 배너의 "아니에요"다. 안내 중에 남겨 두면 사용자가 고른 층과
        // 경로가 가리키는 층이 어긋난 화면이 생기고, 그 상태를 정리할 규칙이 없다.
        if (_indoorEntered &&
            !_guidanceActive &&
            _building != null &&
            _activeFloor != null &&
            _building!.floors.isNotEmpty)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                _floorSelectorBottomOffset +
                (indoorRouteVisible ? _bottomBarLiftPx : 0),
            child: SafeArea(
              top: false,
              child: FloorSelector(
                key: _floorSelectorKey,
                floors: _building!.floors,
                selectedFloor: _activeFloor!,
                onSelectFloor: _onFloorChipSelected,
              ),
            ),
          ),

        // 안내 중 "내 위치로" — 방금 접힌 층 선택기와 **같은 자리**에 놓는다.
        // 안내가 시작되면 그 자리가 비고, 사용자는 이미 거기에 조작이 있다는
        // 것을 알고 있다.
        //
        // 안내 중에만 띄우는 이유는 [GuidanceRecenterButton] 주석에 있다 —
        // 평상시에는 하단 바의 "위치 보정"이 그 자리를 대신하므로, 둘을 같이
        // 띄우면 비슷하게 생긴 두 조작이 화면에 남는다.
        if (_guidanceActive && _canRecenterOnCurrentPosition)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                _floorSelectorBottomOffset +
                (indoorRouteVisible ? _bottomBarLiftPx : 0),
            child: SafeArea(
              top: false,
              child: GuidanceRecenterButton(
                key: const Key('guidance-recenter'),
                onPressed: () => unawaited(_recenterOnCurrentPosition()),
              ),
            ),
          ),

        // 디버그 전용 — 강제 층 전환. "내 위치로" 버튼 바로 위, 안내 중 +
        // 디버그 모드 + 에스컬레이터 환승이 남아 있을 때만 뜬다.
        // 무엇을 태우는지는 [_debugForceFloorTransition]에 있다.
        if (debugEnabled && _guidanceActive && _debugForceableTransfer != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                _floorSelectorBottomOffset +
                (indoorRouteVisible ? _bottomBarLiftPx : 0) +
                52,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.white.withValues(alpha: 0.96),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.16),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: AppColors.indoor.withValues(alpha: 0.2),
                  ),
                ),
                child: IconButton(
                  key: const Key('debug-force-floor-transition'),
                  tooltip: '층 전환 시뮬레이션',
                  onPressed: _debugForceFloorTransition,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(Icons.escalator, size: 20),
                ),
              ),
            ),
          ),

        // PDR 제어 — 실내 지도 탭과 같은 자리(하단 홈/실내 세그먼트 왼쪽,
        // 층 선택기 옆)에 같은 위젯으로 놓는다. 두 화면에서 버튼이 옮겨 다니면
        // 실측 중에 "지금 어느 화면인지"를 먼저 확인해야 해서 테스트가 끊긴다.
        //
        // 노출 조건에 pdrActive를 함께 두는 이유: 세션이 도는 중에 사용자가
        // 지도를 축소하면 _handleCameraIdle이 실내 진입 오버레이를 끄는데,
        // 그때 버튼까지 사라지면 방금 걸은 세션을 내보낼 수단이 없어진다.
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
                  canExport: _pdrDebugRecorder?.hasSnapshot ?? false,
                  exporting: _exportingPdrDebugJson,
                  onExport: () => unawaited(_exportPdrDebugJson()),
                  shareButtonKey: _pdrShareButtonKey,
                ),
              ),
            ),
          ),

        // 디버그 설정 진입점(왼쪽 하단 벌레 아이콘)은 앱 메뉴(햄버거)로 옮겼다.
        // 실내 진입 오버레이가 켜졌을 때만 뜨는 버튼이라, 그 상태에 있는지에 따라
        // 개발 도구가 나타났다 사라지는 화면이기도 했다.
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
                // 배너를 탭하면 경로 전체 단계 목록이 올라온다. 배너 자체는
                // "다음 한 수"만 말하므로, 전체를 보고 싶은 사용자가 갈 곳이
                // 여기뿐이다. 종료 버튼은 Listener가 먼저 받아 탭과 겹치지
                // 않는다.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showIndoorRouteSteps(indoorRouteDestination),
                  child: EtaCard(
                    key: _etaCardKey,
                    distanceMeters: indoorEta.distanceM,
                    // 시간은 비용 기준 — 엘리베이터 대기·탑승 시간이 여기 들어 있다.
                    minutes:
                        (indoorEta.costM /
                                _indoorWalkingSpeedMetersPerSecond /
                                60)
                            .ceil()
                            .clamp(1, 999),
                    label: _indoorEtaLabel(indoorRouteDestination),
                    instruction: _indoorRouteGuidance,
                    // 도착 순간 배너가 "어디에 도착했는지"를 말하도록 목적지를
                    // 함께 넘긴다. [_indoorEtaLabel]은 경유 층까지 붙인 긴 줄이라
                    // 카드 제목으로는 쓸 수 없다.
                    destinationName: indoorRouteDestination.name,
                    destinationFloor: indoorRouteDestination.floor,
                    onClose: _dismissIndoorRouteFromEtaCard,
                    onClosePointerDown: (position) =>
                        _etaClosePointerDown = position,
                  ),
                ),
              ),
            ),
          )
        // 대중교통 안내는 도보 ETA 카드와 **같은 자리**를 쓰고 서로를 밀어낸다.
        // 두 카드가 함께 뜨면 한 화면에서 소요 시간이 두 개가 되어, 지도에
        // 그려진 선이 어느 쪽인지 알 수 없다.
        else if (_transitItinerary case final itinerary?)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TransitSummaryCard(
                  key: _etaCardKey,
                  itinerary: itinerary,
                  label: _transitLabel ?? '목적지까지',
                  onClose: _dismissUserDestinationFromEtaCard,
                  onClosePointerDown: (position) =>
                      _etaClosePointerDown = position,
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
                  key: _etaCardKey,
                  distanceMeters: _outdoorEta(route).distanceM,
                  minutes: _outdoorEta(route).minutes,
                  label: userDestination != null
                      ? (_userDestinationLabel ?? '목적지까지')
                      : '건물 입구까지',
                  onClose: userDestination != null
                      ? _dismissUserDestinationFromEtaCard
                      : null,
                  // 자동차 계획 상태에서만 붙는다. 누르면 카메라가 현재 위치로
                  // 내려가고 버튼은 사라진다([startFollowingCurrentLocation]).
                  onStartGuidance: _offerStartGuidance
                      ? () => unawaited(startFollowingCurrentLocation())
                      : null,
                  onClosePointerDown: userDestination != null
                      ? (position) => _etaClosePointerDown = position
                      : null,
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
    // 앱의 카드 문법(surface + hairline + 아이콘만 primary)을 따른다. 예전의
    // 파란 원색(AppColors.indoor) 배경은 절제된 화이트/뮤트 톤에서 이 배지만
    // 튀어 보였다. "지도 탭을 가져가는 상태"라는 긴장은 하단 바 버튼의 활성
    // 톤이 이미 말하고 있으므로, 여기는 안내문답게 조용히 있는다.
    return Material(
      color: AppColors.surface,
      elevation: AppElevation.chrome,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.hairline),
      ),
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
              child: Icon(Icons.touch_app, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '지도를 탭해 현재 서 있는 위치를 지정해주세요',
                  maxLines: 2,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _HintCancelButton(onPressed: onCancel, color: AppColors.muted),
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
