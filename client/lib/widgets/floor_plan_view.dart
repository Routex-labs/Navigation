import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/api_config.dart';
import '../core/floor_switch_timing.dart';
import '../core/tile_url.dart';
import '../core/map_fonts.dart';
import '../core/map_label_style.dart';
import '../core/map_palette.dart';
import '../core/map_route_style.dart';
import 'destination_pin.dart';
import 'floor_camera_bearing.dart';
import 'floor_camera_bounds.dart';
import '../features/debug_mode/debug_map_overlay.dart';
import '../models/floor_plan.dart';
import '../screens/outdoor_map/indoor_entry_zoom.dart';
import 'category_map_fill.dart';
import 'map_icon_cache.dart';
import 'category_map_filter.dart';
import 'category_map_icon.dart';
import 'floor_facility_style.dart';
import 'store_label_fit.dart';

/// maplibre_gl은 web/android/iOS만 지원한다(패키지 자체 pubspec에 명시된
/// 플랫폼 목록). Windows/Linux/macOS 데스크톱에서 `flutter run`으로 띄우면
/// 플러그인이 대체 구현을 찾지 못해 알아보기 힘든
/// "TargetPlatform.windows is not yet supported by the maps plugin" 텍스트를
/// 그대로 그리므로, 그 대신 원인이 분명한 안내를 보여준다.
const _mapSupportedNativePlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
};

bool get _isMapSupportedOnThisPlatform =>
    kIsWeb || _mapSupportedNativePlatforms.contains(defaultTargetPlatform);

const _tileSourceId = 'floor-tiles';

/// 층마다 다른 타일 소스 id. 층 이름을 붙이는 이유는 [_installFloorTileLayers]
/// 주석에 있다 — 같은 id를 지웠다 다시 만드는 경로를 피하려는 것이다.
String _tileSourceIdFor(String floor) => '$_tileSourceId-$floor';

/// 매장명 라벨 전용 GeoJSON 소스 id.
///
/// **왜 라벨만 타일이 아니라 GeoJSON인가.** 글자 크기를 매장 크기에 맞추려면
/// feature마다 "이 매장에서 1em은 몇 미터인가"가 실려 있어야 하는데
/// ([store_label_fit.dart]), 벡터 타일 properties에는 그 값이 없다. 폴리곤은
/// 이미 클라이언트가 [FloorPlan.stores]로 들고 있으므로 라벨 앵커 점만 여기서
/// 만들어 얹는다. 면·아이콘·POI는 그대로 타일이 그린다 — 바뀐 것은 라벨의
/// 데이터 출처뿐이다.
///
/// 타일 소스와 같은 이유로 층 이름을 붙인다.
String _storeLabelSourceIdFor(String floor) => 'floor-store-labels-$floor';

/// 한 층을 그리는 레이어 id의 원본 목록. 설치([_installFloorTileLayers])와
/// 제거([_removeFloorTileLayers])가 **같은 목록**을 봐야 한다 — 한쪽에만 있는
/// 레이어가 생기면 옛 층 도면 일부가 새 층 위에 그대로 남는다.
///
/// 대부분 타일 소스 위에 얹히지만 두 라벨 레이어
/// (`floor-stores-label`·[_facilityLabelLayerId])만 클라이언트 GeoJSON 소스를
/// 본다([_storeLabelSourceIdFor]). 제거는 소스와 무관하게 레이어 id로 하므로
/// 이 목록은 그대로 하나면 된다.
const _tileLayerBases = <String>[
  'floor-footprint-fill',
  _storesFillLayerId,
  _categoryHighlightFillLayerId,
  _verticalTransportFillLayerId,
  'floor-stores-label',
  _facilityLabelLayerId,
  'floor-pois-icon',
  'floor-pois-label',
  'floor-store-facility-icons',
];

String _tileLayerId(String base, String floor) => '$base-$floor';

/// 층 타일 위에 있는 첫 레이어. 층을 갈아 끼울 때 새 도면을 이 아래에 넣어야
/// 경로선·마커가 도면 밑으로 사라지지 않는다.
const _firstOverlayLayerId = 'floor-completed-route-line';

// 실내 MVT 소스의 zoom 범위는 indoor_entry_zoom.dart의 공용 상수를 그대로 쓴다.
// 예전에는 이 파일이 같은 값을 따로 들고 "야외 화면과 같은 값"이라고 적어 뒀지만
// 실제로는 minzoom이 16.0 vs 15.0으로 어긋나 있었다. 두 화면이 같은 백엔드
// 엔드포인트를 부르는 이상 범위가 갈리면 (1) 한쪽에서만 도면이 비고 (2) 백엔드
// 워밍업이 덮지 못하는 zoom이 생겨 그 타일만 쿼리를 새로 낸다. 값의 근거는
// indoorTilesMinZoom/indoorTilesMaxZoom 정의 위 주석에 정리되어 있다.
const _routeSourceId = 'floor-route';
const _completedRouteSourceId = 'floor-completed-route';
const _transferRouteSourceId = 'floor-transfer-route';
const _pdrTrailSourceId = 'floor-pdr-trail';
const _pdrPreviewTrailSourceId = 'floor-pdr-preview-trail';
const _pdrRawTrailSourceId = 'floor-pdr-raw-trail';
const _pdrConfirmedTrailSourceId = 'floor-pdr-confirmed-trail';
const _pdrRoninTrailSourceId = 'floor-pdr-ronin-trail';
const _debugGraphSourceId = 'floor-debug-graph';
const _markersSourceId = 'floor-markers';
const _highlightSourceId = 'floor-highlight';
const _storesFillLayerId = 'floor-stores-fill';
const _categoryHighlightFillLayerId = 'floor-category-highlight-fill';
const _verticalTransportFillLayerId = 'floor-vertical-transport-fill';

/// 편의시설의 텍스트 전용 라벨 레이어. 대분류 아이콘이 붙는 매장명 라벨
/// (`floor-stores-label`)과 정확히 반대 집합을 그린다
/// ([facilityStoreLabelFilter]).
const _facilityLabelLayerId = 'floor-store-facility-label';

/// 목적지 핀 이미지의 addImage 등록 이름.
// 디자인을 바꾸면 버전을 올린다 — 웹 addImage는 같은 이름이 이미 있으면
// 새 비트맵을 버려서, 이름을 그대로 두면 살아 있는 지도에 반영되지 않는다.
// v3: "도착" 글씨를 비트맵에 구워 넣었다(심볼 텍스트에서 이동).
const _destinationPinImageName = 'marker-destination-pin-v3';

/// 도착 핀 iconSize의 zoom 보간 구간. "도착" 글씨가 비트맵에 구워져 있으므로
/// 이 값을 바꾸면 글씨도 같은 비율로 함께 커지고 작아진다.
const _destPinIconSizeZ16 = 0.115;
const _destPinIconSizeZ20 = 0.25;

/// 현재 위치 심볼의 addImage 등록 이름. **이름 끝에 코어 반지름을 박아 둔다.**
///
/// maplibre_gl 웹 구현의 addImage는 같은 이름이 이미 등록돼 있으면 새 비트맵을
/// 버리고 조용히 건너뛴다(`if (!_map.hasImage(name))` … `else { print(...) }`,
/// maplibre_web_gl_platform.dart). 게다가 이 패키지의 플랫폼 인터페이스에는
/// removeImage가 없어서 이미 등록된 이름을 지울 방법도 없다. 그래서 이름이
/// 고정이면, 살아 있는 지도 인스턴스에 예전 크기의 비트맵이 그대로 남아
/// 디자인을 바꿔도 화면이 안 바뀐다. 반지름을 이름에 넣어 두면 디자인이 바뀔
/// 때 이름도 함께 바뀌므로 항상 새 비트맵으로 등록된다.
const _currentLocationImageName =
    'marker-current-location-r$_currentLocationCoreRadius';
const _currentLocationDotImageName =
    'marker-current-location-dot-r$_currentLocationCoreRadius';

/// 현재 위치 심볼을 그릴 때 쓰는 디자인 좌표계의 한 변 길이(px). 아래 렌더
/// 코드의 모든 반지름/오프셋은 이 좌표계 기준이다.
const _currentLocationIconDesignSize = 144.0;

/// 디자인 좌표계 대비 실제 비트맵 배율. 아이콘을 크게 키우면 MapLibre가
/// 비트맵을 화면 픽셀 수보다 적은 원본으로 늘려 그리게 되어 흰 테두리가
/// 뭉개진다(특히 devicePixelRatio 2~3인 폰). 비트맵만 이 배율로 크게 렌더하고
/// iconSize는 같은 배율로 나눠서, 화면상 크기는 그대로 두고 해상도만 올린다.
const _currentLocationIconPixelRatio = 2.0;

/// 현재 위치 심볼의 화면 크기. 디자인 좌표계 1px = 화면 1px이 되도록 고정한다
/// (비트맵은 [_currentLocationIconPixelRatio]배로 렌더하므로 그만큼 나눈다).
///
/// zoom 보간을 쓰지 않는 이유: 야외 GPS 마커는 `CircleLayer`의 상수
/// `circleRadius`로 그려져 zoom과 무관하게 같은 크기를 유지한다
/// (outdoor_map_screen.dart의 `outdoor-accuracy`/`outdoor-current-dot`).
/// 실내 마커도 같은 크기로 보여야 하므로 zoom에 따라 커지면 안 된다.
///
/// 크기의 기준은 "눈에 보이는 경계"다. GPS 마커에서 사용자가 크기로 인식하는
/// 것은 18px 도트가 아니라 정확도 원의 **불투명도 100%인 1px 테두리**(지름
/// 44px)다. 실내 마커에는 그 테두리 원이 없고 바깥 흰 링은 도면 바닥(#FFFFFF)에
/// 묻혀 안 보이므로, 지각되는 경계는 파란 코어 원뿐이다. 그래서 코어 지름이
/// 곧 이 마커의 체감 크기이며, 그 값은 [_currentLocationCoreRadius]가 정한다.
const _currentLocationIconSize = 1.0 / _currentLocationIconPixelRatio;

/// 파란 코어 원의 반지름(디자인 단위 = 화면 px). 이 마커의 체감 크기를 정하는
/// 유일한 값이므로, 크기를 조정할 때는 여기만 바꾼다 — 흰 링·그림자는 이 값에서
/// 파생되고, 비트맵 등록 이름([_currentLocationImageName])도 이 값을 포함해
/// 자동으로 새 이름이 된다.
///
/// GPS 정확도 원의 테두리 지름(44px)에 맞춰 22로 뒀다가, 실내 도면에서 너무
/// 크다고 판단해 지름 32px로 줄인 값이다. 야외 GPS 도트(18px)보다는 크고 정확도
/// 원(44px)보다는 작다.
const _currentLocationCoreRadius = 16.0;

/// 코어를 감싸는 흰 링의 반지름. 코어보다 5px 두껍게 잡아, 도면 바닥(#FFFFFF)
/// 에서는 묻히더라도 매장 fill([mapStoreFill])이나 경로선 위에서는 코어가 배경과
/// 분리돼 보이게 한다.
const _currentLocationRimRadius = _currentLocationCoreRadius + 5;

/// 현재 위치 심볼 레이어 id.
const _currentMarkerLayerId = 'floor-markers-current';

/// 목적지 핀 심볼 레이어 id. 현재 위치 레이어를 다시 등록할 때 이 레이어 아래로
/// 넣어야 원래의 위/아래 순서(목적지 핀이 위)가 유지된다.
const _destinationMarkerLayerId = 'floor-markers-destination-pin';

/// 현재 위치 심볼 레이어의 filter. 마커 소스에는 목적지도 함께 들어오므로
/// `kind`로 걸러낸다. 레이어를 다시 등록할 때 이 filter를 빠뜨리면 목적지
/// 좌표에도 파란 도트가 찍힌다.
const _currentMarkerFilter = <Object>[
  '==',
  ['get', 'kind'],
  'current',
];

/// 현재 위치 심볼 레이어의 속성 묶음. 등록([_onStyleLoaded])과 hot reload 시
/// 재적용([FloorPlanViewState.reassemble])이 같은 값을 쓰도록 한 곳에 모아 둔다.
///
/// 현재 위치와 heading을 하나의 심볼로 합친다. 미터 단위 GeoJSON 폴리곤은
/// 확대할수록 화살표만 커지므로, 고정 픽셀 PNG를 회전시켜 점과 방향 표시가
/// 언제나 같은 비율과 크기를 유지하게 한다. heading이 없을 때는 북쪽을 임의로
/// 가리키지 않고 동일 디자인의 원형 점만 사용한다.
const _currentLocationSymbolProperties = SymbolLayerProperties(
  iconImage: [
    'case',
    ['has', 'heading'],
    _currentLocationImageName,
    _currentLocationDotImageName,
  ],
  iconSize: _currentLocationIconSize,
  iconRotate: [
    'coalesce',
    ['get', 'heading'],
    0,
  ],
  iconRotationAlignment: 'map',
  iconPitchAlignment: 'viewport',
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
);

/// 지도 위에 얹을 현재 위치/목적지 점 마커. 종류에 따라 스타일이 달라진다
/// (마커 색상은 [_markersGeoJson]의 circle-color data-driven 표현식이 결정).
enum MapMarkerKind { current, destination }

/// FloorPlanView의 카메라를 외부에서 직접 조작(회전/중심 이동)하기 위한
/// controller. 상위 위젯(IndoorMapBody)이 이 controller를 생성해 FloorPlanView
/// 에 전달하면, FloorPlanView가 initState에서 자신을 attach한다.
///
/// 건물/층이 바뀔 때 FloorPlanView는 ValueKey 차이로 통째로 재생성되지만,
/// controller는 새 state가 만들어질 때 자동으로 재attach되므로 상위는 controller
/// 를 한 번만 만들어 놓고 계속 재사용할 수 있다.
class FloorPlanController {
  FloorPlanViewState? _state;

  void _attach(FloorPlanViewState state) => _state = state;

  void _detach(FloorPlanViewState state) {
    if (identical(_state, state)) _state = null;
  }

  /// FloorPlanView가 아직 준비되지 않았거나 detach된 상태면 false.
  bool get isAttached => _state != null;

  /// 카메라 중심만 [target]으로 옮긴다. bearing/줌은 유지.
  Future<void> centerOn(ll.LatLng target) async {
    await _state?.centerOn(target);
  }

  /// 내 위치 추적을 다시 켜고 즉시 중앙으로 가져온다.
  ///
  /// 사용자가 지도를 직접 끌면 추적이 풀린다([FloorPlanView.followTarget] 주석).
  /// 다시 켜는 유일한 경로가 이 메서드다 — 저절로 되살아나면, 주변을 보려고
  /// 밀어 둔 지도가 몇 초 뒤 제멋대로 돌아온다.
  Future<void> resumeFollow() async {
    await _state?.resumeFollow();
  }

  /// 지금 내 위치를 따라가는 중인지. 상위가 "내 위치" 버튼의 눌린 상태를
  /// 표시하는 데 쓴다.
  bool get isFollowing => _state?.isFollowing ?? false;

  /// 지금 카메라 상태. 아직 붙지 않았거나 스타일 로드 전이면 null.
  ///
  /// 층 전환을 가로질러 화면을 이어 붙이려면 상위가 **전환 직전** 값을 읽어
  /// 새 층 뷰에 [FloorPlanView.initialCamera]로 넘겨야 한다.
  FloorCameraSnapshot? get cameraSnapshot {
    final position = _state?._controller?.cameraPosition;
    if (position == null) return null;
    return FloorCameraSnapshot(
      target: ll.LatLng(position.target.latitude, position.target.longitude),
      zoom: position.zoom,
      bearing: position.bearing,
      tilt: position.tilt,
    );
  }
}

/// 층을 가로질러 물려줄 카메라 상태.
///
/// maplibre의 `CameraPosition`을 그대로 쓰지 않는 이유는 이 값을 들고 다니는
/// 쪽이 지도 화면(`IndoorMapBody`)이기 때문이다. 그 화면은 지금 지도 SDK 타입을
/// 하나도 모르고, 그 경계를 카메라 인계 하나 때문에 무너뜨릴 이유가 없다.
class FloorCameraSnapshot {
  const FloorCameraSnapshot({
    required this.target,
    required this.zoom,
    required this.bearing,
    required this.tilt,
  });

  final ll.LatLng target;
  final double zoom;
  final double bearing;
  final double tilt;
}

/// 매장 폴리곤을 탭할 수 있는 실내 평면도 뷰.
///
/// 건물/층의 벡터 타일(MVT, `GET /buildings/{id}/floors/{floor}/tiles/{z}/{x}/{y}.mvt`)을
/// MapLibre GL 벡터 소스로 얹어서 외곽선·매장·POI를 그린다.
///
/// **매장 이름 라벨만 타일이 아니다.** 글자 크기를 매장 폴리곤 크기에 맞추려면
/// feature마다 크기가 실려 있어야 하는데 타일 properties에는 그 값이 없어서,
/// 앵커 점만 클라이언트가 GeoJSON으로 만들어 얹는다. 계산과 그 한계는
/// [store_label_fit.dart], 소스는 [_storeLabelSourceIdFor]에 적어 두었다.
/// 배치(줄바꿈·충돌·앵커 뒤집기)는 그대로 MapLibre 심볼 레이어가 맡는다.
///
/// 경로선과 현재 위치/목적지 마커는 벡터 타일과 별개로 GeoJSON 소스에
/// 얹는다 — 다익스트라 결과가 바뀔 때마다 소스 데이터만 교체한다.
class FloorPlanView extends StatefulWidget {
  const FloorPlanView({
    super.key,
    required this.buildingId,
    required this.floorName,
    required this.floorPlan,
    this.onStoreSelected,
    this.onMapPressed,
    this.onEmptyMapPressed,
    this.currentLocation,
    this.currentHeadingDegrees,
    this.destination,
    this.routePoints = const [],
    this.completedRoutePoints = const [],
    this.walkedRouteSegments = const [],
    this.transferRoutePoints = const [],
    this.pdrPathPoints = const [],
    this.pdrPreviewPathPoints = const [],
    this.pdrRawPathPoints = const [],
    this.pdrConfirmedPathPoints = const [],
    this.pdrRoninPathPoints = const [],
    this.debugMapOverlay = const DebugMapOverlay(),
    this.interactive = true,
    this.highlightedStoreId,
    this.categorySelection,
    this.focusTarget,
    this.focusTick = 0,
    this.focusBottomSheetFraction = 0,
    this.focusTopInsetPx = 0,
    this.tileRevision,
    this.visibleInsets = EdgeInsets.zero,
    this.overlayHitTest,
    this.onCameraBearingChanged,
    this.onFollowingChanged,
    this.controller,
    this.initialCamera,
  });

  /// 스타일 로드 직후 건물 fit 대신 그대로 적용할 카메라.
  ///
  /// 층이 바뀌면 이 위젯은 ValueKey 차이로 통째로 재생성되고, 새 지도는
  /// 건물 전체에 맞춰 카메라를 다시 잡는다. 사용자가 층 선택기로 다른 층을
  /// 훑어볼 때는 그게 맞다 — 낯선 층이니 전체를 보여 줘야 한다.
  ///
  /// 반대로 **에스컬레이터 자동 전환**은 사용자가 같은 자리에 서 있는데 층만
  /// 바뀌는 사건이다. 이때 카메라가 건물 fit으로 튀면 방금 보고 있던 확대
  /// 수준과 위치를 잃는다. 그 경우에만 상위가 전환 직전 카메라를 여기로
  /// 넘겨 화면을 이어 붙인다.
  ///
  /// 상위가 controller로 직접 밀지 않고 값으로 내려 주는 이유는
  /// [focusTarget]과 같다 — 준비가 끝난 쪽이 스스로 적용해야 경합이 없다.
  final FloorCameraSnapshot? initialCamera;

  /// 추적이 켜지고 꺼질 때 알린다. 상위가 "내 위치" 버튼 상태를 맞추는 데 쓴다.
  final ValueChanged<bool>? onFollowingChanged;

  /// 카메라를 외부에서 조작(회전/중심 이동)하기 위한 controller. 상위 위젯이
  /// 재보정 버튼처럼 지도 밖에서 오는 명령을 이 controller로 전달한다.
  final FloorPlanController? controller;

  final String buildingId;
  final String floorName;
  final FloorPlan floorPlan;
  final ValueChanged<StorePolygon>? onStoreSelected;

  /// PDR anchor를 놓는 중인 경우 지도 빈 곳 탭을 상위에 전달한다. true를
  /// 반환하면 해당 탭은 매장 선택으로 이어지지 않는다.
  final bool Function(ll.LatLng point)? onMapPressed;

  /// 매장 폴리곤을 **맞히지 못한** 탭을 상위에 전달한다. 즉 복도·빈 공간을 누른
  /// 경우다.
  ///
  /// [onMapPressed]로 대신할 수 없어서 따로 둔다. 그쪽은 매장 hit-test보다
  /// **먼저** 불리고 true를 돌려주면 탭을 통째로 삼키는 계약이라, "매장이면 매장,
  /// 아니면 복도"처럼 매장을 우선하고 싶은 흐름을 표현할 수 없다 — 길찾기의
  /// "지도에서 선택"이 정확히 그 흐름이다(매장을 눌렀으면 그 매장이 목적지고,
  /// 복도를 눌렀으면 그 지점이 목적지다). 반대로 위치 지정은 매장 위를 눌러도
  /// 그 자리에 앵커를 찍어야 하므로 계속 [onMapPressed]를 쓴다.
  ///
  /// 반환값은 지금 쓰이지 않지만(이 시점 이후에 할 일이 없다) 두 콜백의 모양을
  /// 맞춰 두면 나중에 뒤이은 처리를 붙일 때 계약을 바꾸지 않아도 된다.
  final bool Function(ll.LatLng point)? onEmptyMapPressed;

  /// 선택된(또는 포커스된) 매장의 [StorePolygon.id]. null이면 강조 표시가 없다.
  final String? highlightedStoreId;

  /// 지도 위 카테고리 필터 pill에서 고른 카테고리. null이면 강조하지 않는다.
  /// 층이 바뀌어도 상위(MapShellScreen)가 같은 값을 계속 내려주므로 선택은
  /// 층 전환을 넘어 유지된다.
  final CategorySelection? categorySelection;

  /// 목록에서 고른 매장 위치. 값이 있으면 스타일 로드 직후(=층 전환으로 지도가
  /// 새로 만들어진 경우) 또는 [focusTick]이 바뀔 때 카메라를 그리로 옮긴다.
  ///
  /// **상위가 직접 카메라를 조작하지 않고 이 값을 내려 주는 이유는 타이밍이다.**
  /// 층을 바꾸면 FloorPlanView가 ValueKey 차이로 통째로 재생성되고 MapLibre
  /// 스타일이 다시 로드된다. 상위가 층 전환 직후에 controller로 카메라를 밀면
  /// 아직 준비되지 않은(또는 방금 detach된) state에 명령이 가서 조용히 무시된다.
  /// 값으로 내려 주면 준비가 끝난 쪽이 스스로 적용하므로 그 경합이 사라진다.
  final ll.LatLng? focusTarget;

  /// 같은 매장을 다시 골랐을 때도 카메라를 다시 옮기기 위한 카운터.
  /// [focusTarget]만 보면 값이 그대로라 didUpdateWidget이 변화를 못 본다.
  final int focusTick;

  /// 벡터 타일 URL에 붙일 버전 토큰(`Building.tileRevision`). 근거는
  /// `core/tile_url.dart` 주석.
  final String? tileRevision;

  /// [focusTarget]으로 이동한 뒤 화면 아래쪽을 덮을 시트의 높이(화면 비율).
  /// 이만큼을 감안해 매장을 위로 밀어 올린다 — 0이면 정중앙에 놓는다.
  ///
  /// 지도 위젯이 시트의 존재를 직접 알면 안 되므로 상위가 값으로 넘긴다.
  final double focusBottomSheetFraction;

  /// [focusTarget]으로 이동할 때 화면 **위쪽**을 덮고 있는 오버레이(검색창·
  /// 카테고리 chip 줄)의 두께(논리 픽셀). 아래(시트)만 감안하면 매장이 이번엔
  /// 그 줄 뒤로 올라가므로, 위아래 둘 다 빼고 남는 띠의 한가운데에 놓는다.
  ///
  /// [focusBottomSheetFraction]과 달리 비율이 아니라 픽셀인 이유는, 이 줄이
  /// 화면 높이에 비례하지 않기 때문이다 — 상위가 실제로 재서 넘긴다.
  final double focusTopInsetPx;

  /// 지도 위에 얹은 Flutter 오버레이(층 selector 같은)가 자기 영역을 알려주는
  /// 콜백. 인자는 화면 전역 좌표. true 반환 시 그 좌표의 탭은 매장 선택으로
  /// 이어지지 않는다.
  ///
  /// MapLibre는 PlatformView라 위에 얹힌 Flutter 위젯 위의 탭이 gesture arena
  /// 를 우회해 네이티브 지도까지 흘러들어와 매장까지 함께 선택되는 문제가 있다.
  /// 이 콜백으로 오버레이 소유자가 명시적으로 그 영역의 탭을 무시하게 한다.
  final bool Function(Offset globalPoint)? overlayHitTest;

  /// 화면 위/오른쪽처럼 뷰포트 기준 방향을 실제 지도 방향으로 바꿀 수 있도록
  /// 현재 카메라 bearing(0°=북쪽)을 상위에 알린다.
  final ValueChanged<double>? onCameraBearingChanged;

  /// 현재 위치 마커. null이면 표시하지 않는다.
  final ll.LatLng? currentLocation;

  /// 현재 위치 화살표가 가리킬 방향(북쪽 기준 시계방향 각도). null이면
  /// 아직 방향을 몰라 북쪽(0도)을 기본값으로 그린다 — 실내는 PDR 방향
  /// 추정이 이 값으로 연동되기 전까지는 항상 null이다.
  final double? currentHeadingDegrees;

  /// 목적지 마커. null이면 표시하지 않는다.
  final ll.LatLng? destination;

  /// 시작점→목적지 경로선. 2개 미만이면 그리지 않는다.
  final List<ll.LatLng> routePoints;

  /// 현재 위치 이전의 안내 경로. 남은 파란선보다 뒤에 회색으로 그린다.
  final List<ll.LatLng> completedRoutePoints;

  /// 길안내 시작 이후 실제로 누적한 보정 보행 궤적. 재탐색으로 파란 경로가
  /// 교체돼도 유지하며, 층 전환·재보정 점프는 서로 다른 선으로 전달한다.
  final List<List<ll.LatLng>> walkedRouteSegments;

  /// 현재 층의 에스컬레이터 탑승점과 다음 층 도착점을 잇는 수직 이동 안내선.
  /// 일반 경로와 달리 파선으로 그려 "이 구간에서 층을 바꾼다"는 뜻을 준다.
  final List<ll.LatLng> transferRoutePoints;

  /// navigation graph에 부착한 PDR 경로. 보라색 실선으로 렌더한다.
  /// 기존 호출부 호환을 위해 필드 이름은 유지한다.
  final List<ll.LatLng> pdrPathPoints;

  /// 주황 걸음으로 간선 위에 임시 적분한 보라색 preview 꼬리.
  /// 확정 경로와 구분되도록 반투명 점선으로 렌더한다.
  final List<ll.LatLng> pdrPreviewPathPoints;

  /// 아직 확정되지 않은 accel preview 경로. 주황색 점선으로 렌더한다.
  final List<ll.LatLng> pdrRawPathPoints;

  /// 센서 파이프라인이 자체 확정한 PDR 경로. 초록색 실선으로 렌더한다.
  final List<ll.LatLng> pdrConfirmedPathPoints;

  /// Android RoNIN 속도에서 구한 자동보폭 비교 경로. 분홍 파선으로 렌더한다.
  final List<ll.LatLng> pdrRoninPathPoints;

  /// 디버그 모드에서만 채워지는 navigation graph 노드·간선 데이터.
  final DebugMapOverlay debugMapOverlay;

  /// false면 스크롤/줌/회전 제스처를 전부 끈다. 웹에서는 MapLibre 지도가
  /// 실제 DOM 캔버스라 그 위에 떠 있는 바텀시트를 스크롤해도 마우스 휠
  /// 이벤트가 새어나가 지도가 같이 움직일 수 있다 — 시트가 열려 있는
  /// 동안은 상위(MapShellScreen)가 이 값을 false로 내려 막는다.
  final bool interactive;

  /// 지도 위에 얹혀 있어 실제 지도 영역을 가리는 UI(상단 검색바/하단 홈-실내
  /// 버튼바/ETA 카드 등)의 두께. 지도 자체는 화면 끝까지 그려지지만 축소 하한을
  /// 계산할 때는 이만큼 좁은 영역에 건물이 들어오도록 잡아야, 하한에 도달했을 때
  /// 건물의 위/아래가 오버레이 뒤로 밀려 안 보이는 일이 없다. 상위가 자기가
  /// 얹은 UI 크기를 알고 있으므로 여기에 그대로 전달한다.
  final EdgeInsets visibleInsets;

  @override
  State<FloorPlanView> createState() => FloorPlanViewState();
}

class FloorPlanViewState extends State<FloorPlanView> {
  MapLibreMapController? _controller;
  bool _styleReady = false;

  /// 화면 배율. `icon-size`가 **물리 픽셀**에 곱해지는 값이라 논리 px로 잡은
  /// 아이콘 크기를 여기로 환산한다([storeCategoryIconSizeIndoor]).
  ///
  /// `MediaQuery.devicePixelRatioOf(context)`를 레이어 등록 시점에 바로 읽지
  /// 않는 이유는 그 코드가 여러 번의 `await` 뒤라서다 — 그 사이 위젯이
  /// 사라지면 context 접근이 터진다. 의존성이 잡히는 시점에 한 번 받아 둔다.
  double _devicePixelRatio = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  /// 지금 지도에 설치돼 있는 층의 타일. 층이 바뀌면 이 값이 가리키는 레이어를
  /// 새 층 것으로 갈아 끼운다(위젯을 다시 만들지 않는다).
  String? _activeTileFloor;

  /// 타일 교체가 도는 중인지. 사용자가 층 선택기를 빠르게 여러 번 누르면
  /// 교체가 겹쳐 같은 층을 두 번 설치하거나, 아직 안 얹힌 층을 지우려 든다.
  bool _swappingFloorTiles = false;
  Size? _lastViewport;
  double? _minZoom;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  /// hot reload 때 현재 위치 심볼을 다시 등록·적용한다(debug 빌드에서만 호출됨).
  ///
  /// MapLibre 지도는 PlatformView/캔버스라 hot reload로도 살아남고, 스타일이
  /// 이미 로드된 상태에서는 `onStyleLoadedCallback`이 다시 불리지 않는다. 마커
  /// 비트맵 등록과 `iconSize` 적용이 전부 [_onStyleLoaded] 안에 있으므로, 이
  /// 훅이 없으면 마커 디자인을 고쳐도 hot reload에서는 화면이 그대로다 —
  /// "크기를 바꿨는데 안 바뀐다"의 실제 원인이 이것이었다.
  @override
  void reassemble() {
    super.reassemble();
    unawaited(_refreshMarkerSymbols());
  }

  /// 마커 심볼 레이어들을 지우고 다시 등록한다(hot reload 전용).
  ///
  /// **목적지 핀이 여기 빠져 있었다.** 현재 위치 마커만 갱신했기 때문에, 핀의
  /// 생김새나 레이어 속성을 고쳐도 hot reload 화면은 그대로였다 — 코드는 맞는데
  /// 화면만 안 바뀌니 "고쳤는데 반영이 안 된다"로 보인다. 위젯 코드(예: 하단 바
  /// 아이콘)는 hot reload가 바로 반영하므로, 같은 세션에서 한쪽만 바뀌는 모습이
  /// 특히 헷갈린다.
  ///
  /// 순서가 중요하다. 목적지 핀을 먼저 다시 올려야(맨 위) 그다음 현재 위치를
  /// 그 아래로 끼워 넣을 수 있다 — 원래의 위/아래 관계가 유지된다.
  Future<void> _refreshMarkerSymbols() async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;
    try {
      await controller.removeLayer(_destinationMarkerLayerId);
      await _addDestinationPinSymbolLayer(controller);
      await _refreshCurrentLocationSymbol();
    } catch (error, stackTrace) {
      // hot reload 편의 기능이므로 실패해도 앱을 죽이지 않는다.
      debugPrint('marker symbol refresh failed: $error\n$stackTrace');
    }
  }

  /// 목적지 핀 심볼 레이어를 얹는다.
  ///
  /// 도형과 글씨를 나눠 그리는 이유, 치수와 textOffset 유도, `text-font`를 반드시
  /// 명시해야 하는 이유는 전부 [destination_pin.dart]에 있다.
  ///
  /// 현재 위치는 같은 소스에 함께 들어와 있어도 filter가 걸러낸다.
  Future<void> _addDestinationPinSymbolLayer(
    MapLibreMapController controller,
  ) async {
    await controller.addSymbolLayer(
      _markersSourceId,
      _destinationMarkerLayerId,
      destinationPinSymbolProps(
        imageName: _destinationPinImageName,
        iconSizeZ16: _destPinIconSizeZ16,
        iconSizeZ20: _destPinIconSizeZ20,
      ),
      filter: [
        '==',
        ['get', 'kind'],
        'destination',
      ],
      enableInteraction: false,
    );
  }

  /// 현재 위치 비트맵을 등록하고 심볼 레이어를 얹는다.
  ///
  /// 비트맵 이름에 코어 반지름이 들어 있으므로([_currentLocationImageName]),
  /// 크기를 바꿨다면 새 이름이라 웹 addImage의 "이미 있으면 건너뛰기"에 걸리지
  /// 않는다. 크기를 안 바꿨다면 같은 이름이라 건너뛰고 로그만 남는다.
  Future<void> _addCurrentLocationSymbolLayer(
    MapLibreMapController controller, {
    String? belowLayerId,
  }) async {
    await controller.addImage(
      _currentLocationImageName,
      await cachedIconPng(
        _currentLocationImageName,
        () => _renderCurrentLocationIcon(showHeading: true),
      ),
    );
    await controller.addImage(
      _currentLocationDotImageName,
      await cachedIconPng(
        _currentLocationDotImageName,
        () => _renderCurrentLocationIcon(showHeading: false),
      ),
    );
    await controller.addSymbolLayer(
      _markersSourceId,
      _currentMarkerLayerId,
      _currentLocationSymbolProperties,
      filter: _currentMarkerFilter,
      belowLayerId: belowLayerId,
      enableInteraction: false,
    );
  }

  /// 현재 위치 심볼을 지우고 다시 등록한다.
  ///
  /// `setLayerProperties`로 속성만 갈아끼우지 않는 이유가 두 가지다.
  /// 1. 웹 구현은 키마다 `setPaintProperty`를 먼저 시도하고 **예외가 났을 때만**
  ///    `setLayoutProperty`로 폴백한다(maplibre_web_gl_platform.dart). 그런데
  ///    `icon-image`/`icon-size`는 layout 속성이고, MapLibre GL JS가 알 수 없는
  ///    paint 속성에 대해 예외를 던지는지 아니면 error 이벤트만 쏘고 조용히
  ///    반환하는지가 버전에 따라 다르다. 후자면 폴백이 안 타서 아무것도 적용되지
  ///    않는다 — 바로 이번에 문제였던 "조용히 안 바뀜"을 다시 만드는 셈이다.
  /// 2. `iconImage`가 이미지 **이름**을 담은 표현식이라, 코어 크기를 바꿔 이름이
  ///    바뀌면 레이어 자체를 다시 등록해야 새 이름을 가리킨다.
  ///
  /// 다시 등록하면 레이어가 스택 맨 위로 가므로 목적지 핀 아래로 넣어 원래
  /// 순서를 유지한다.
  Future<void> _refreshCurrentLocationSymbol() async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;
    try {
      await controller.removeLayer(_currentMarkerLayerId);
      await _addCurrentLocationSymbolLayer(
        controller,
        belowLayerId: _destinationMarkerLayerId,
      );
    } catch (error, stackTrace) {
      // hot reload 편의 기능이므로 실패해도 앱을 죽이지 않는다. 레이어가 이미
      // 사라진 뒤(층 전환 직후 등)에 호출되면 native가 예외를 던질 수 있다.
      debugPrint('current location symbol refresh failed: $error\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMapSupportedOnThisPlatform) {
      return const _UnsupportedPlatformNotice();
    }
    // 건물 전체가 화면에 다 들어오는 줌보다 더 축소되지 않도록 최솟값으로
    // 고정한다. _fitBearingAndZoom은 건물 정렬 각도를 가정하고 화면을 꽉
    // 채우는 줌을 구하는데, 그 값을 그대로 하한으로 쓰면 사용자가 지도를
    // 회전했을 때(회전하면 외곽선이 화면에 더 넓게 걸쳐짐) 그 줌으로는
    // 건물 일부가 화면 밖으로 밀려나는데도 더 축소를 못 하는 문제가 있었다
    // — 그래서 회전 각도와 무관하게 항상 전체가 들어오도록 회전-불변
    // 반지름(중심~가장 먼 꼭짓점) 기준으로 따로 계산한다.
    //
    // 뷰포트 크기는 MediaQuery.sizeOf 대신 LayoutBuilder로 얻은 지도 위젯의
    // 실제 크기를 쓴다. 상단 정보바/하단 ETA 카드처럼 지도 밖 UI가 자리를
    // 차지하고 있을 때 화면 전체 크기로 계산하면 실제 지도 영역보다 큰
    // 뷰포트를 가정해 하한이 필요 이상으로 낮게(=더 많이 축소 가능) 나온다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return _buildMap(viewport);
      },
    );
  }

  Widget _buildMap(Size viewport) {
    _lastViewport = viewport;
    // 축소 하한은 "건물이 실제로 얼마나 큰가"만 알면 되고, 그 위치가 지도 어디에
    // 놓여 있는지는 필요 없다(줌 레벨은 화면 픽셀당 지도 미터 비율만 결정하므로).
    // 백엔드가 항상 채워 내려주는 footprint_local_m(미터 좌표)에서 반지름을
    // 뽑아 쓴다 — 실좌표 앵커가 없어 footprint_wgs84가 비어 오는 건물이라도
    // 여기서는 상관없이 정확한 건물 크기를 얻는다. local_m이 어쩌다 비어
    // 있다면 매장/POI 좌표(wgs84)로 폴백한다.
    final minZoom = _computeMinZoom(
      widget.floorPlan,
      viewport,
      widget.visibleInsets,
    );
    _minZoom = minZoom;
    // Listener는 gesture arena에 참여하지 않으므로 MapLibre PlatformView가
    // 제스처를 가져가도 포인터 이벤트는 그대로 받는다. 지도 조작을 막지 않고
    // "사용자가 끌었다"만 관찰하는 데는 이 방식이어야 한다.
    return Listener(
      onPointerDown: _onMapPointerDown,
      onPointerMove: _onMapPointerMove,
      child: _buildMapLibre(viewport, minZoom),
    );
  }

  Widget _buildMapLibre(Size viewport, double? minZoom) {
    return MapLibreMap(
      styleString: _initialStyle,
      initialCameraPosition: CameraPosition(
        target: _initialCenter(widget.floorPlan),
        zoom: 18,
        bearing: _straighteningBearing(widget.floorPlan.footprint),
      ),
      minMaxZoomPreference: MinMaxZoomPreference(minZoom, null),
      // _enforceMinZoom이 controller.cameraPosition으로 현재 줌을 읽는데,
      // 이 값은 trackCameraPosition이 켜져 있을 때만 갱신된다. 꺼두면
      // initialCameraPosition의 줌(18)에 영원히 멈춰 있어서, 사용자가 확대해도
      // onCameraIdle마다 "하한보다 낮다"고 오판하고 줌을 되돌려버린다.
      trackCameraPosition: true,
      onMapCreated: (controller) {
        _controller = controller;
        _notifyCameraBearing();
      },
      onStyleLoadedCallback: _onStyleLoaded,
      // 타일까지 다 그려 지도가 멈춘 시점 — 사용자가 "떴다"고 느끼는 순간이다.
      // 계측이 꺼져 있으면 [FloorSwitchTiming.mark]가 즉시 반환한다.
      onMapIdle: () => FloorSwitchTiming.mark('idle'),
      onMapClick: _handleMapClick,
      onCameraMove: (position) =>
          widget.onCameraBearingChanged?.call(position.bearing),
      // maplibre_gl 웹 구현이 minMaxZoomPreference를 놓치는 경우에 대비한
      // 이중 안전장치. 제스처가 끝난 시점에 하한 아래로 내려가 있으면
      // 하한으로 다시 올려서, "축소하면 건물이 사라진다"는 문제를 뿌리째 막는다.
      onCameraIdle: _handleCameraIdle,
      // 웹에서는 기본값(false)이면 매장 폴리곤처럼 상호작용 가능한 레이어를
      // 탭했을 때 onMapClick이 아예 안 불려서(대신 별도 feature-tap 이벤트만
      // 발생) 매장을 눌러도 아무 반응이 없었다. onMapClick 하나로 매장 탭
      // 여부까지 직접 판별하는 _handleMapClick 구조를 그대로 쓰려면 이 값을
      // true로 켜서 매장을 눌렀을 때도 onMapClick이 항상 같이 불리게 해야 한다.
      featureTapsTriggersMapClick: true,
      compassEnabled: false,
      myLocationEnabled: false,
      logoEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: widget.interactive,
      tiltGesturesEnabled: widget.interactive,
      dragEnabled: widget.interactive,
    );
  }

  @override
  void didUpdateWidget(covariant FloorPlanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    // 내 위치가 갱신되면 카메라도 따라간다. 이게 없으면 걷는 동안 마커만
    // 움직여 화면 밖으로 나가고, 사용자가 "위치 보정"을 누를 때까지 돌아오지
    // 않는다 — 실내에서 걸으면 늘 그 상태가 된다.
    //
    // 바라보는 방향이 바뀌었을 때도 같이 부른다. 위치는 그대로인데 몸만 돌린
    // 경우(코너에서 방향을 트는 순간)가 실제로 방향 정렬이 가장 필요한 때다.
    if (_following &&
        widget.currentLocation != null &&
        (widget.currentLocation != oldWidget.currentLocation ||
            widget.currentHeadingDegrees != oldWidget.currentHeadingDegrees)) {
      unawaited(_followCamera());
    }
    if (!_styleReady) return;
    if (oldWidget.buildingId != widget.buildingId) {
      // 건물이 바뀌면 위젯을 통째로 다시 만든다(다른 key로 재생성됨).
      return;
    }
    if (oldWidget.floorName != widget.floorName) {
      // **층은 위젯을 다시 만들지 않는다.** 예전에는 층까지 key에 넣어 지도를
      // 통째로 새로 만들었는데, 실기기 계측에서 그 재생성(네이티브 뷰 + 스타일
      // 로드 + 아이콘·레이어 등록 + 첫 렌더)이 층 전환의 대부분(약 0.9~1.2초)을
      // 차지했다. 타일 소스만 갈아 끼우면 그 값을 통째로 안 낸다.
      unawaited(_swapFloorTiles(oldWidget.floorName, widget.floorName));
      // 아래 갱신들은 층이 바뀐 경우에도 그대로 필요하다(경로·마커는 새 층
      // 기준으로 다시 그려야 한다). 그래서 return하지 않고 계속 내려간다.
    } else if (oldWidget.floorPlan != widget.floorPlan) {
      // 같은 층인데 도면 객체만 바뀐 경우다(재조회 등). 층이 바뀐 경우는 위
      // _swapFloorTiles가 새 소스를 통째로 만들므로 여기서 또 건드리면 안 된다 —
      // 그 시점의 _activeTileFloor는 아직 옛 층이라 엉뚱한 소스를 덮어쓴다.
      unawaited(_updateStoreLabelSource());
    }
    if (oldWidget.routePoints != widget.routePoints) {
      _updateRouteSource();
      // 경로가 새로 생기면(이전엔 없다가 이번에 생김) 사용자의 현재 위치인
      // 경로 출발점으로 카메라를 옮겨, 지금 어디서 어느 방향으로 가야 하는지가
      // 바로 보이게 한다. 이미 경로가 있는 상태에서 갱신될 때는(예: PDR
      // 위치가 계속 바뀌는 경우) 다시 맞추지 않는다 — 사용자가 지도를 보는
      // 중에 카메라가 계속 튀면 방해가 된다.
      if (widget.routePoints.isNotEmpty && oldWidget.routePoints.isEmpty) {
        _fitToRouteBounds(widget.routePoints);
      }
    }
    if (oldWidget.completedRoutePoints != widget.completedRoutePoints) {
      _updateCompletedRouteSource();
    }
    if (oldWidget.walkedRouteSegments != widget.walkedRouteSegments) {
      _updateCompletedRouteSource();
    }
    if (oldWidget.transferRoutePoints != widget.transferRoutePoints) {
      _updateTransferRouteSource();
    }
    if (oldWidget.pdrPathPoints != widget.pdrPathPoints) {
      _updatePdrTrailSource();
    }
    if (oldWidget.pdrPreviewPathPoints != widget.pdrPreviewPathPoints) {
      _updatePdrPreviewTrailSource();
    }
    if (oldWidget.pdrRawPathPoints != widget.pdrRawPathPoints) {
      _updatePdrRawTrailSource();
    }
    if (oldWidget.pdrConfirmedPathPoints != widget.pdrConfirmedPathPoints) {
      _updatePdrConfirmedTrailSource();
    }
    if (oldWidget.pdrRoninPathPoints != widget.pdrRoninPathPoints) {
      _updatePdrRoninTrailSource();
    }
    if (oldWidget.debugMapOverlay != widget.debugMapOverlay) {
      _updateDebugGraphSource();
    }
    if (oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.currentHeadingDegrees != widget.currentHeadingDegrees ||
        oldWidget.destination != widget.destination) {
      _updateMarkersSource();
    }
    if (oldWidget.highlightedStoreId != widget.highlightedStoreId) {
      _updateHighlightSource();
    }
    if (oldWidget.categorySelection != widget.categorySelection) {
      _applyCategoryFilter();
    }
    if (oldWidget.focusTick != widget.focusTick) {
      _applyFocusTarget();
    }
  }


  /// 지도에 쓰는 비트맵 전부. **층과 무관**하므로 스타일 로드 때 한 번만 부른다.
  /// 층을 바꿀 때 다시 부르지 않는 것이 [_installFloorTileLayers]와 나눈 이유다 —
  /// 예전에는 층마다 지도를 새로 만들면서 이 26장을 매번 다시 구웠다.
  Future<void> _registerMapImages(MapLibreMapController controller) async {
    // 대분류 아이콘 비트맵. 매장명 라벨 레이어가 참조하므로 **레이어보다 먼저**
    // 등록한다. 없는 이름을 참조하면 아이콘 없이 텍스트만 그려지고 로그도
    // 조용해서, 순서가 어긋나면 원인을 찾기 어렵다.
    for (final category in storeCategoryIconKeys) {
      final imageName = storeCategoryIconImageName(category);
      await controller.addImage(
        imageName,
        // 층을 오갈 때마다 같은 그림을 다시 굽지 않는다([map_icon_cache.dart]).
        await cachedIconPng(imageName, () => renderStoreCategoryIconPng(category)),
      );
    }
    // 엘리베이터/에스컬레이터/화장실 같은 POI는 단순 점 대신 종류별 아이콘으로
    // 그린다. MapLibre 심볼 레이어는 사전 등록된 비트맵만 참조할 수 있어서,
    // 필요한 아이콘들을 먼저 오프스크린 렌더링해 addImage로 등록한 다음
    // type 속성에 따라 골라 쓰는 match 표현식을 iconImage에 건다.
    for (final icon in {...kPoiIconByType.values, kDefaultPoiIcon}) {
      final imageName = poiIconImageName(icon);
      await controller.addImage(
        imageName,
        await cachedIconPng(imageName, () => renderPoiIconPng(icon)),
      );
    }
    // 편의시설 아이콘은 이름별로 배경색/구성이 달라 각각 별도로 렌더링한다.
    for (final entry in kStoreFacilityStyleByName.entries) {
      final imageName = facilityIconImageName(entry.key);
      await controller.addImage(
        imageName,
        await cachedIconPng(imageName, () => renderFacilityIconPng(entry.value)),
      );
    }
    await controller.addImage(
      _destinationPinImageName,
      await cachedIconPng(_destinationPinImageName, renderDestinationPinIcon),
    );
    await controller.addImage(
      _currentLocationImageName,
      await cachedIconPng(
        _currentLocationImageName,
        () => _renderCurrentLocationIcon(showHeading: true),
      ),
    );
    await controller.addImage(
      _currentLocationDotImageName,
      await cachedIconPng(
        _currentLocationDotImageName,
        () => _renderCurrentLocationIcon(showHeading: false),
      ),
    );
  }

  /// 한 층의 타일 소스와 그 위 레이어 9개를 설치한다.
  ///
  /// **소스·레이어 id에 층 이름을 박는다.** 층을 바꿀 때 같은 id를 지웠다 다시
  /// 만들면, 네이티브가 이전 레이어 정리를 스케줄만 한 채 리턴해 다음 추가가
  /// 조용히 실패하는 경로를 밟는다(`kCategoryHighlightNoneFilter`·
  /// `outdoor_map_screen.dart`의 addSource 주석과 같은 함정). id가 층마다 다르면
  /// **새 층을 먼저 얹고 옛 층을 나중에 지울 수 있어** 그 경로를 아예 피한다.
  ///
  /// [belowLayerId]는 새로 얹는 레이어가 경로선·마커 아래로 들어가게 한다.
  /// 최초 설치(스타일 로드 직후)에는 그 위에 아무것도 없으므로 null이다.
  Future<void> _installFloorTileLayers(
    MapLibreMapController controller,
    String floor, {
    String? belowLayerId,
  }) async {
    final sourceId = _tileSourceIdFor(floor);
    final tileUrl = indoorTileUrl(
      buildingId: widget.buildingId,
      floorName: floor,
      tileRevision: widget.tileRevision,
    );
    // `?v=` 유무가 서버 캐시를 1년 immutable과 60초로 가른다. 계측 빌드에서만
    // 실제 URL을 남겨, 버전이 붙는지 코드가 아니라 실기기에서 확인한다.
    FloorSwitchTiming.note('tileUrl=$tileUrl');

    await controller.addSource(
      sourceId,
      VectorSourceProperties(
        tiles: [tileUrl],
        // 낮은 zoom에서 저정밀 양자화된 타일이 캐시되는 것을 막는다. 근거는
        // indoorTilesMinZoom 정의 위 주석 참고.
        minzoom: indoorTilesMinZoom,
        // 극한 확대에서 quantize precision 오차로 도면이 미세하게 뒤틀리는 것을
        // 막는다. 근거는 indoorTilesMaxZoom 정의 위 주석 참고.
        maxzoom: indoorTilesMaxZoom,
      ),
    );

    // 매장명 라벨 앵커. 타일이 아니라 클라이언트가 만든다(이유는
    // [_storeLabelSourceIdFor] 주석).
    //
    // **`addGeoJsonSource`가 아니라 `addSource`인 이유는 `maxzoom` 때문이다.**
    // GeoJSON 소스의 기본 maxzoom은 18인데 실내 지도는 z22까지 쓴다
    // ([kStoreLabelSourceMaxZoom]). 그 위에서는 z18 타일을 확대해 재활용하는데,
    // 그 상태에서 심볼의 **아이콘만** 통째로 빠지는 것을 실기기에서 확인했다 —
    // 같은 화면에서 zoom을 한 단계씩 올리며 배지 픽셀을 세면 있음 → 없음 →
    // 없음이었고, 글자와 (타일 소스를 쓰는) POI 아이콘은 멀쩡했다. 소스가 실제
    // 줌까지 타일을 만들게 하면 그 경계가 사라진다.
    //
    // buffer도 함께 올린다. 라벨 앵커는 점이지만 그려지는 심볼(배지 + 이름)은
    // 폭이 있어서, 기본 buffer(128/512)로는 타일 경계 근처 매장의 심볼이
    // 잘려 나갈 수 있다.
    final labelSourceId = _storeLabelSourceIdFor(floor);
    final labelLatitude = _storeLabelLatitude();
    await controller.addSource(
      labelSourceId,
      GeojsonSourceProperties(
        data: _storeLabelFeatureCollection(),
        maxzoom: kStoreLabelSourceMaxZoom.toDouble(),
        buffer: 256,
      ),
    );

    // 도면 폴리곤 색은 [map_palette.dart]가 갖는다 — 야외 오버레이가 같은 도면을
    // 그려서 두 곳이 어긋나면 층을 오갈 때 색이 바뀌어 보인다. 원본 SVG
    // (hyundai_floor_map_corrected_v6.svg)에서 옮겨온 값이었으나 통로와 대비가
    // 없어 지금은 의도적으로 다르다(사유는 map_palette.dart).
    await controller.addFillLayer(
      sourceId,
      _tileLayerId('floor-footprint-fill', floor),
      const FillLayerProperties(
        fillColor: mapFootprintFill,
        fillOutlineColor: mapFootprintOutline,
      ),
      sourceLayer: 'footprint',
      belowLayerId: belowLayerId,
      enableInteraction: false,
    );
    // 매장 면·경계선은 도면 기본 색이다. 대분류 색은 카테고리를 눌렀을 때만
    // 아래 강조 레이어가 칠한다(사유는 [category_map_fill.dart] 상단).
    await controller.addFillLayer(
      sourceId,
      _tileLayerId(_storesFillLayerId, floor),
      const FillLayerProperties(
        fillColor: mapStoreFill,
        fillOutlineColor: mapStoreOutline,
      ),
      sourceLayer: 'stores',
      belowLayerId: belowLayerId,
    );
    // 카테고리 필터 강조. 일반 매장 fill 바로 위에 얹어 선택한 카테고리의
    // 매장만 그 대분류 색으로 칠한다 — chip에서 누른 색이 그대로 도면에 나온다.
    //
    // **비매칭 매장을 숨기는 대신 매칭 매장을 강조하는 이유**는 도면 맥락이다.
    // 매장을 걸러내면 층 도면이 텅 비어 사용자가 지금 어디를 보고 있는지 알 수
    // 없고, 그 층에 해당 카테고리가 없으면 화면이 통째로 비어 앱이 깨진 것처럼
    // 읽힌다. 강조 방식은 기본 레이어를 건드리지 않으므로 라벨만 남는 유령
    // 매장도 생기지 않고, 필터를 끄면 원래 화면으로 정확히 돌아온다.
    //
    // 선택이 없을 때는 레이어를 지우지 않고 아무것도 맞지 않는 필터를 걸어 둔다
    // (근거는 kCategoryHighlightNoneFilter 주석).
    await controller.addFillLayer(
      sourceId,
      _tileLayerId(_categoryHighlightFillLayerId, floor),
      FillLayerProperties(
        fillColor: storeCategoryHighlightFillColorExpression(),
        fillOutlineColor: storeCategoryHighlightOutlineExpression(),
      ),
      sourceLayer: 'stores',
      belowLayerId: belowLayerId,
      filter: _categoryFilterExpression(),
      // 탭은 아래 일반 매장 fill이 받는다. 이 레이어까지 탭을 받으면 같은
      // 폴리곤에 두 번 반응한다.
      enableInteraction: false,
    );
    // 수직이동 구조물(에스컬레이터/엘리베이터) 전용 오버레이. 일반 매장 fill
    // 바로 위, 라벨/POI 아이콘보다 아래에 깔아서 초록 아이콘과 한 덩어리로
    // 읽히게 한다. 필터가 어긋나면(백엔드 name 변경 등) 이 레이어만 비고
    // 아래 일반 매장 스타일로 자연스럽게 폴백된다.
    //
    // 필터는 이 파일의 다른 레이어(_debugGraphSourceId 등)와 같은 ['any',
    // ['==', ...], ...] 형태를 쓴다 — ['match', [get, name], <배열>, ...]도
    // 스펙상은 유효하지만 MapLibre GL Native(Android/iOS)에서 label 위치의
    // 배열이 항상 안정적으로 파싱되지 않아 조용히 필터 매치가 0건이 되던
    // 케이스가 있었다. ==는 이 파일 전반에서 검증된 경로라 그 쪽으로 통일한다.
    await controller.addFillLayer(
      sourceId,
      _tileLayerId(_verticalTransportFillLayerId, floor),
      const FillLayerProperties(
        fillColor: '#DCEBD4',
        fillOutlineColor: '#6FA167',
      ),
      sourceLayer: 'stores',
      belowLayerId: belowLayerId,
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
    // 매장명 라벨: 크기와 줄바꿈 폭을 **매장 폴리곤에 맞춰** 미리 계산해
    // feature에 실어 둔다([store_label_fit.dart]). 예전에는 zoom 보간만으로
    // 9~14px을 줬는데, 도면은 zoom 1레벨마다 2배가 되는 월드 좌표라 확대할수록
    // 글자가 상대적으로 작아지고 축소할수록 매장 밖으로 넘쳤다.
    //
    // 이름 옆에 대분류 아이콘을 **같은 심볼로** 얹는다. 아이콘을 별도 레이어로
    // 두면 충돌 판정이 따로 돌아 아이콘만 남거나 이름만 남는 짝이 안 맞는 라벨이
    // 생긴다. 한 심볼이면 둘이 함께 놓이고 함께 밀린다.
    //
    // 이름이 아이콘 앞/뒤 중 어디에 붙을지는 `text-variable-anchor`가 정한다
    // (규칙과 한계는 [category_map_icon.dart] 주석).
    await controller.addSymbolLayer(
      labelSourceId,
      _tileLayerId('floor-stores-label', floor),
      SymbolLayerProperties(
        textField: ['get', 'name'],
        textFont: _mapFontStack,
        textSize: storeLabelTextSizeExpression(latitude: labelLatitude),
        // 크기를 잴 때 가정한 줄바꿈 폭 그대로 걸어야 계산이 맞는다
        // ([kStoreLabelMaxWidthProperty] 주석).
        textMaxWidth: ['get', kStoreLabelMaxWidthProperty],
        iconImage: storeCategoryIconExpression(),
        // 크기는 화면 배율을 곱해 정한다 — `icon-size`는 물리 픽셀이고
        // `text-size`는 논리 픽셀이라, 안 곱하면 고밀도 화면에서 아이콘만
        // 배율만큼 작아진다([storeCategoryIconSizeIndoor] 실측표).
        iconSize: storeCategoryIconSize(_devicePixelRatio),
        textVariableAnchor: kStoreLabelVariableAnchor,
        textRadialOffset: kStoreLabelRadialOffset,
        // variable-anchor가 고른 방향에 맞춰 좌/우 정렬을 따라가게 한다.
        // 기본값(center)으로 두면 두 줄로 접힌 이름이 아이콘 쪽으로 쏠린다.
        textJustify: 'auto',
        // 색·헤일로는 [map_label_style.dart]가 단일 출처다(야외 오버레이와 같은 값).
        textColor: mapLabelStoreColor,
        textHaloColor: mapLabelHaloColor,
        textHaloWidth: mapLabelHaloWidth,
        // variable-anchor는 충돌 판정 위에서만 동작한다. true로 바꾸면 앵커가
        // 항상 첫 번째 값으로 굳어 뒤집기가 조용히 죽는다.
        textAllowOverlap: false,
        // 자리가 없으면 **이름만** 포기한다. 아이콘은 항상 그린다.
        //
        // ⚠️ **예전 규칙을 뒤집었다.** 원래는 `iconOptional: true`로 두고
        // "붐빌 때는 아이콘을 포기해 이름을 살린다"였는데, 실기기에서 재 보니
        // 그 대가가 예상보다 훨씬 컸다 — 같은 1F에서 zoom을 한 단계씩 올리며
        // 배지 픽셀을 세면 **0 → 5,956 → 0**이었다. 확대해서 자리가 남아도는
        // 화면에서도 배지가 통째로 사라졌다. 사용자에게는 "아이콘이 커지거나
        // 줄어드는 게 아니라 없어진다"로 보인다.
        //
        // 아이콘은 이름보다 조금 크기만 하고(11~16 논리 px) 색만으로도 업종을
        // 말하므로, 밀릴 때 버릴 것은 이쪽이 아니다.
        //
        // **`iconIgnorePlacement`는 켰다가 껐다.** 켜 두면 배지가 충돌 판정에서
        // 아예 빠져 "다른 라벨을 밀어내지 않는" 대신 **다른 매장 이름 위에 그대로
        // 올라앉는다** — 실기기에서 「탬버린즈」·「오휘/후」가 옆 매장 배지에
        // 덮였다. 배지를 장애물로 되돌려 이름들이 그 자리를 피해 가게 한다.
        // 배지 자체는 `iconAllowOverlap`·`iconOptional: false` 덕에 그래도
        // 사라지지 않는다.
        textOptional: true,
        iconOptional: false,
        iconAllowOverlap: true,
      ),
      belowLayerId: belowLayerId,
      // 라벨 소스는 타일이 아니라 클라이언트 GeoJSON이라 타일 소스의 zoom 범위를
      // 물려받지 않는다. 그대로 두면 도면 타일이 아직 안 나오는 축소 구간에서
      // **이름만 허공에 뜬다.** 소스 minzoom과 같은 값을 레이어에 직접 건다.
      minzoom: indoorTilesMinZoom,
      filter: storeLabelWithCategoryIconFilter(),
      enableInteraction: false,
    );

    // 편의시설(화장실·정수기 등) 이름 — 아이콘은 아래 전용 레이어가 그리므로
    // 여기서는 텍스트만 얹는다. 위 레이어에 섞으면 같은 폴리곤에 시설 아이콘과
    // 대분류 아이콘이 둘 다 떠서 무엇을 봐야 할지 알 수 없게 된다.
    //
    // **매장명과 달리 크기가 고정이다.** 폴리곤 맞춤 계산은 글자가 폴리곤 안에
    // 들어가는 경우의 계산인데 이 이름은 아이콘을 피해 폴리곤 밖으로 내려 그린다
    // ([mapLabelFacilityTextSize] 주석에 근거를 적었다).
    await controller.addSymbolLayer(
      labelSourceId,
      _tileLayerId(_facilityLabelLayerId, floor),
      const SymbolLayerProperties(
        textField: ['get', 'name'],
        textFont: _mapFontStack,
        textSize: mapLabelFacilityTextSize,
        textMaxWidth: mapLabelFacilityMaxWidth,
        // 아이콘이 centroid를 차지하므로 이름은 그 아래로 내린다. POI 라벨
        // (`floor-pois-label`)·야외 오버레이와 같은 오프셋이라 세 곳의 라벨
        // 높이가 맞는다.
        textOffset: mapLabelBelowIconOffset,
        textColor: mapLabelFacilityColor,
        textHaloColor: mapLabelHaloColor,
        textHaloWidth: mapLabelHaloWidth,
        textAllowOverlap: false,
      ),
      belowLayerId: belowLayerId,
      // 위 매장명 라벨과 같은 이유.
      minzoom: indoorTilesMinZoom,
      filter: facilityStoreLabelFilter(),
      enableInteraction: false,
    );

    await controller.addSymbolLayer(
      sourceId,
      _tileLayerId('floor-pois-icon', floor),
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
        iconSize: indoorMarkerIconSize(_devicePixelRatio),
        iconOpacity: 0.92,
        iconAllowOverlap: true,
      ),
      sourceLayer: 'pois',
      belowLayerId: belowLayerId,
      enableInteraction: false,
    );
    // POI 이름. **수직이동(에스컬레이터·엘리베이터)은 이름을 그리지 않는다** —
    // 그 이름이 `ES3-UP(TO2F)` 같은 Studio 내부 코드라서다([poiLabelFilter]에
    // 실데이터 개수와 예시를 적어 두었다). 아이콘은 위 레이어가 계속 그린다.
    await controller.addSymbolLayer(
      sourceId,
      _tileLayerId('floor-pois-label', floor),
      const SymbolLayerProperties(
        textField: ['get', 'name'],
        textFont: _mapFontStack,
        // 같은 "아이콘 + 아래 이름" 꼴인 편의시설 라벨과 같은 값을 쓴다.
        textSize: mapLabelFacilityTextSize,
        textMaxWidth: mapLabelFacilityMaxWidth,
        textOffset: mapLabelBelowIconOffset,
        textColor: mapLabelFacilityColor,
        textHaloColor: mapLabelHaloColor,
        textHaloWidth: mapLabelHaloWidth,
      ),
      sourceLayer: 'pois',
      belowLayerId: belowLayerId,
      filter: poiLabelFilter(),
      enableInteraction: false,
    );

    // 편의시설 아이콘: `stores` 소스에 있는 화장실·정수기 같은 시설물은 POI
    // 레이어를 타지 않으므로 아이콘이 안 붙는다. 매장 이름을 기준으로
    // 심볼을 하나 더 얹어 라벨 바로 위에 아이콘이 뜨게 한다.
    // 필터에서 걸러진 매장은 아예 이 레이어에 등장하지 않고, iconImage의
    // match 표현식은 안전을 위해 알 수 없는 name이 왔을 때 default를 준다.
    await controller.addSymbolLayer(
      sourceId,
      _tileLayerId('floor-store-facility-icons', floor),
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
        iconSize: indoorMarkerIconSize(_devicePixelRatio),
        iconOpacity: 0.92,
        iconAllowOverlap: true,
        // iconOffset을 주지 않아 아이콘이 폴리곤 중심(centroid)에 그려진다.
        // 벡터 타일 심볼의 기준점이 폴리곤 centroid이므로, 오프셋이 없으면
        // 시설 블록 정중앙에 아이콘이 놓인다. 이름은 [_facilityLabelLayerId]가
        // 아이콘 아래로 내려 그리므로 둘이 겹치지 않는다.
      ),
      sourceLayer: 'stores',
      belowLayerId: belowLayerId,
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
  }

  /// 한 층의 레이어와 소스를 걷어낸다. **새 층을 설치한 뒤에만** 부른다.
  ///
  /// 레이어를 모두 지운 뒤에 소스를 지운다 — 참조가 남은 소스를 먼저 지우면
  /// 네이티브가 거부하거나 조용히 무시한다.
  Future<void> _removeFloorTileLayers(
    MapLibreMapController controller,
    String floor,
  ) async {
    for (final base in _tileLayerBases.reversed) {
      try {
        await controller.removeLayer(_tileLayerId(base, floor));
      } on Object {
        // 이미 없는 레이어는 무시한다. 여기서 예외가 새면 남은 레이어가
        // 그대로 살아 옛 층 도면이 새 층 위에 겹쳐 보인다.
      }
    }
    try {
      await controller.removeSource(_tileSourceIdFor(floor));
    } on Object {
      // 위와 같은 이유.
    }
    try {
      await controller.removeSource(_storeLabelSourceIdFor(floor));
    } on Object {
      // 위와 같은 이유. 이 소스가 남으면 다음 번 같은 층 설치에서 addSource가
      // 중복 id로 실패해 라벨만 통째로 빠진다.
    }
  }

  /// 라벨 크기 계산에 쓰는 기준 위도. 픽셀당 미터가 위도에 따라 달라져서
  /// 필요하다 — 건물 하나 안에서는 상수로 봐도 되므로 도면 중심 하나를 쓴다.
  double _storeLabelLatitude() {
    final points = _extentWgs84Points(widget.floorPlan);
    if (points.isEmpty) return 37.5;
    return _bboxCenter(points).latitude;
  }

  /// 매장명 라벨 앵커 FeatureCollection.
  ///
  /// 점 하나에 이름·카테고리(필터·아이콘용)와 [store_label_fit.dart]가 계산한
  /// 크기 두 값을 싣는다. 좌표는 백엔드가 준 매장 중심점을 그대로 쓴다 —
  /// 오목한 폴리곤에서도 데이터가 의도한 라벨 자리다.
  ///
  /// 폴리곤이 비어 온 매장(실좌표 앵커가 없는 건물)은 박스를 잴 수 없어
  /// 크기가 0으로 나가고, 표현식의 하한이 받아 [kStoreLabelMinPx]로 그린다 —
  /// 즉 이 경우의 동작은 예전과 같다.
  Map<String, dynamic> _storeLabelFeatureCollection() {
    // 라벨 박스는 화면 가로/세로로 재야 한다. 초기 카메라가 건물 축에 맞춰
    // 돌아가 있으므로([_buildMapLibre]) 그 각도를 기준으로 쓴다.
    final bearing = _straighteningBearing(widget.floorPlan.footprint);
    final features = <Map<String, dynamic>>[];
    for (final store in widget.floorPlan.stores) {
      if (store.name.trim().isEmpty) continue;
      final box = storeLabelBoxMeters(
        polygon: store.polygon,
        bearingDeg: bearing,
      );
      final fit = fitStoreLabel(
        name: store.name,
        boxWidthM: box.widthM,
        boxHeightM: box.heightM,
      );
      features.add(<String, dynamic>{
        'type': 'Feature',
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[
            store.centroid.longitude,
            store.centroid.latitude,
          ],
        },
        'properties': <String, dynamic>{
          'id': store.id,
          'name': store.name,
          // null은 키째 뺀다. 실으면 `['has', 'category']`가 참이 되면서 값
          // 비교는 어긋나, "카테고리가 없다"를 표현할 방법이 사라진다
          // (백엔드 `_store_properties`가 같은 이유로 같은 규칙을 쓴다).
          if (store.category != null) 'category': store.category,
          if (store.subcategory != null) 'subcategory': store.subcategory,
          kStoreLabelEmMetersProperty: fit.emMeters,
          kStoreLabelMaxWidthProperty: fit.maxWidthEm,
        },
      });
    }
    return <String, dynamic>{
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  /// 같은 층에서 도면 데이터만 새로 받아온 경우(재조회·건물 갱신) 라벨을
  /// 다시 만든다. 층이 바뀌는 경우는 [_swapFloorTiles]가 소스째 갈아 끼운다.
  Future<void> _updateStoreLabelSource() async {
    final controller = _controller;
    final floor = _activeTileFloor;
    if (controller == null || !_styleReady || floor == null) return;
    await controller.setGeoJsonSource(
      _storeLabelSourceIdFor(floor),
      _storeLabelFeatureCollection(),
    );
  }

  /// 층이 바뀌었을 때 지도를 새로 만들지 않고 타일만 갈아 끼운다.
  ///
  /// 순서가 핵심이다: **새 층을 먼저 얹고**, 다 얹힌 뒤에 옛 층을 지운다.
  /// 반대로 하면 그 사이 도면이 통째로 사라져 흰 화면이 보이고, 위에서 말한
  /// 네이티브 함정도 그대로 밟는다.
  Future<void> _swapFloorTiles(String fromFloor, String toFloor) async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;
    if (_swappingFloorTiles) return;
    _swappingFloorTiles = true;
    try {
      await _installFloorTileLayers(
        controller,
        toFloor,
        // 경로선·마커는 이미 이 위에 있다. 앵커를 안 주면 새 도면이 그것들을
        // 덮어 경로가 도면 밑으로 사라진다.
        belowLayerId: _firstOverlayLayerId,
      );
      if (!mounted) return;
      _activeTileFloor = toFloor;
      FloorSwitchTiming.mark('tilesSwapped');
      await _removeFloorTileLayers(controller, fromFloor);
    } finally {
      _swappingFloorTiles = false;
    }
  }

  /// 목록에서 고른 매장이 화면에 크게 보이도록 카메라를 옮긴다.
  ///
  /// 두 단계로 나눈다. 먼저 매장을 화면 정중앙에 놓고, 그 다음 아래쪽 시트가
  /// 가리는 만큼 위로 밀어 올린다. 한 번에 계산하지 않는 이유는 실내 지도가
  /// 건물에 맞춰 회전(bearing)돼 있어서다 — 위경도로 미리 빼면 회전 각도만큼
  /// 엉뚱한 방향으로 밀린다. `scrollBy`는 화면 좌표라 회전을 알아서 반영한다.
  Future<void> _applyFocusTarget() async {
    final controller = _controller;
    final target = widget.focusTarget;
    if (controller == null || target == null || !_styleReady) return;

    // 목록에서 고른 매장은 층 반대편일 수 있다. 그대로 두면 이 이동이 끝나자마자
    // onCameraIdle이 카메라를 내 위치 근방으로 도로 끌어당겨 포커스가 통째로
    // 깨진다. "딴 데를 보러 갔다"는 명시적 의사 표시이므로 위치 제한만 끈다
    // (도면 제한은 그대로다). 내 위치로 돌아오는 [resumeFollow]에서 다시 켜진다.
    //
    // `widget.focusTarget != null`을 대신 볼 수는 없다 — 상위가 이 값을 한 번
    // 정하면 null로 되돌리지 않아서, 매장을 한 번이라도 누르면 위치 제한이
    // 영원히 꺼진다.
    _userBoundsSuspended = true;
    // **도면 제한도 함께 끈다.** 이게 없으면 건물 가장자리 매장을 고를 때
    // 포커스가 통째로 무효가 된다 — [clampToFootprint]는 뷰포트가 bbox 안에
    // 머물도록 허용 영역을 화면 절반만큼 깎으므로, 가장자리 매장은 애초에
    // 중앙에 놓을 수 없고 아래 lift까지 되돌려진다.
    //
    // 그 규칙의 근거는 "가장자리는 화면 **끝**에 보이면 된다"였는데, 시트가
    // 화면의 60%를 덮는 순간 그 '끝'이 곧 시트 뒤다. 실기기에서 6F
    // 「이탈리 마켓」(건물 동쪽 끝)을 고르면 매장이 우하단으로 밀려 시트에
    // 완전히 가렸다.
    //
    // 꺼도 카메라가 멀리 도망가지는 않는다 — 목표가 건물 안 매장이라 최대
    // 화면 절반만큼 바깥이고, 그동안 도면은 화면에 남는다. 다시 켜지는 곳은
    // 위치 제한과 같다(사용자가 지도를 끌거나 [resumeFollow]).
    _footprintBoundsSuspended = true;

    // 뷰포트는 await 전에 읽는다. 카메라 이동을 기다린 뒤 MediaQuery를 보면
    // 그 사이 위젯이 트리에서 빠졌을 수 있다.
    final viewport = _lastViewport ?? MediaQuery.sizeOf(context);

    final current = controller.cameraPosition;
    final currentZoom = current?.zoom ?? 0;
    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toMapLibreLatLng(target),
          // 이미 더 가까이 들어가 있으면 그 배율을 유지한다. 목록에서 골랐다고
          // 사용자가 맞춰 둔 확대를 되돌리면 방금 보던 맥락을 잃는다.
          zoom: currentZoom > _storeFocusZoom ? currentZoom : _storeFocusZoom,
          bearing: current?.bearing ?? 0,
          tilt: current?.tilt ?? 0,
        ),
      ),
    );

    // 정중앙에 놓으면 방금 고른 매장이 시트 뒤에 숨는다. 위(검색창·카테고리 줄)
    // 와 아래(시트)가 가리고 남는 띠의 한가운데로 오도록 밀어 올린다.
    //
    // 계산: 시트가 f를 덮고 위쪽이 t 픽셀을 덮으면 남는 띠는 [t, H(1-f)]이고
    // 그 중앙은 (t + H(1-f))/2다. 정중앙(H/2)에서 그만큼 올리면
    // H/2 - (t + H(1-f))/2 = (H·f - t)/2.
    //
    // 실기기로 확인한 `scrollBy`의 성질 두 가지를 여기 남긴다. 문서만 보고
    // 고치면 두 번 다 틀린다.
    //  1. 단위는 **논리 픽셀**이다. dpr(3배)을 곱해 보정하면 매장이 건물 밖으로
    //     날아간다.
    //  2. 부호는 **음수가 위로**다. 문서는 "양수 dy면 카메라 타깃이 남쪽으로
    //     간다"고 적혀 있어 매장이 위로 올라갈 것처럼 읽히지만, 실제로는 매장이
    //     그만큼 아래로 내려가 시트 뒤에 숨었다.
    final lift =
        (viewport.height * widget.focusBottomSheetFraction -
            widget.focusTopInsetPx) /
        2;
    if (lift <= 0) return;
    await controller.moveCamera(CameraUpdate.scrollBy(0, -lift));
  }

  /// 목록에서 고른 매장을 볼 때 최소한 이만큼은 확대한다. 매장 이름 라벨이
  /// 읽히는 배율이다.
  static const _storeFocusZoom = 19.0;

  /// 지금 선택에 해당하는 MapLibre 필터 표현식. 선택이 없으면 아무것도 맞지
  /// 않는 필터를 돌려준다 — 레이어 추가 시점과 갱신 시점이 같은 함수를 쓰게
  /// 해서, 한쪽만 고쳐 어긋나는 일을 막는다(indoor_overlay_layers.dart의
  /// "등록과 갱신이 같은 함수를 쓴다" 규칙과 같은 이유).
  List<Object> _categoryFilterExpression() {
    final selection = widget.categorySelection;
    if (selection == null) return kCategoryHighlightNoneFilter;
    return categoryHighlightFilter(selection);
  }

  /// 강조 레이어의 필터만 갈아 끼운다.
  ///
  /// `setLayerProperties`가 아니라 `setFilter`를 쓴다 — 전자는 넘기지 않은
  /// 속성까지 null로 함께 보내 스펙 기본값(fill-color는 검정)으로 되돌리므로,
  /// 실기기에서 지도가 검게 덮인다(indoor_overlay_layers.dart 상단 주석).
  Future<void> _applyCategoryFilter() async {
    final controller = _controller;
    final floor = _activeTileFloor;
    if (controller == null || !_styleReady || floor == null) return;
    // 지금 설치돼 있는 층의 강조 레이어를 고른다. 층마다 id가 다르므로
    // ([_installFloorTileLayers]) 고정 id로 부르면 층을 한 번 바꾼 뒤부터
    // 필터가 조용히 아무 데도 안 걸린다.
    await controller.setFilter(
      _tileLayerId(_categoryHighlightFillLayerId, floor),
      _categoryFilterExpression(),
    );
  }

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;
    // 네이티브 지도 생성 + 스타일 로드가 끝난 시점. 여기까지가 "지도 위젯을
    // 새로 만드는 값"이고, 여기부터 [_styleReady]까지가 아이콘·레이어 등록이다.
    FloorSwitchTiming.mark('style');

    // 비트맵은 층과 무관하다 — 스타일 로드 때 한 번만 등록한다.
    await _registerMapImages(controller);
    await _installFloorTileLayers(controller, widget.floorName);
    _activeTileFloor = widget.floorName;

    await controller.addGeoJsonSource(
      _completedRouteSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _completedRouteSourceId,
      'floor-completed-route-line',
      const LineLayerProperties(
        lineColor: kRouteCompletedColor,
        lineWidth: kRouteLineWidthExpr,
        lineOpacity: 0.72,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addGeoJsonSource(_routeSourceId, _emptyFeatureCollection);
    // casing → 본선 → 화살표 순으로 얹는다. 값과 근거는 [map_route_style.dart].
    await controller.addLineLayer(
      _routeSourceId,
      'floor-route-casing',
      const LineLayerProperties(
        lineColor: kRouteCasingColor,
        lineWidth: kRouteCasingWidthExpr,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _routeSourceId,
      'floor-route-line',
      const LineLayerProperties(
        lineColor: kRouteLineColor,
        lineWidth: kRouteLineWidthExpr,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addImage(
      kRouteArrowImageName,
      await cachedIconPng(kRouteArrowImageName, renderRouteArrowIcon),
    );
    await controller.addSymbolLayer(
      _routeSourceId,
      'floor-route-arrow',
      routeArrowProps(),
      enableInteraction: false,
    );
    await controller.addGeoJsonSource(
      _transferRouteSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _transferRouteSourceId,
      'floor-transfer-route-line',
      const LineLayerProperties(
        lineColor: kRouteLineColor,
        lineWidth: kRouteTransferWidthExpr,
        lineOpacity: 0.82,
        lineDasharray: [1.2, 1.1],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _debugGraphSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _debugGraphSourceId,
      'floor-debug-graph-edges',
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
    await controller.addLineLayer(
      _debugGraphSourceId,
      'floor-debug-graph-active-edges',
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
      'floor-debug-graph-nodes',
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
      'floor-debug-graph-active-nodes',
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
    await controller.addGeoJsonSource(
      _pdrRawTrailSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _pdrRawTrailSourceId,
      'floor-pdr-raw-trail-line',
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

    await controller.addGeoJsonSource(
      _pdrConfirmedTrailSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _pdrConfirmedTrailSourceId,
      'floor-pdr-confirmed-trail-casing',
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
      'floor-pdr-confirmed-trail-line',
      const LineLayerProperties(
        lineColor: '#2E7D32',
        lineWidth: 3.25,
        lineOpacity: 0.96,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _pdrRoninTrailSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _pdrRoninTrailSourceId,
      'floor-pdr-ronin-trail-casing',
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
      _pdrRoninTrailSourceId,
      'floor-pdr-ronin-trail-line',
      const LineLayerProperties(
        lineColor: '#D81B60',
        lineWidth: 3.5,
        lineOpacity: 0.96,
        lineDasharray: [3.0, 1.5],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _pdrTrailSourceId,
      _emptyFeatureCollection,
    );
    // 그래프에 부착한 경로는 raw(주황)·confirmed(초록)와 겹쳐도 구별되도록
    // 보라색으로 그린다. 세 소스가 독립적이라 디버그 설정에서 각각 끌 수 있다.
    await controller.addLineLayer(
      _pdrTrailSourceId,
      'floor-pdr-trail-casing',
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
      _pdrTrailSourceId,
      'floor-pdr-trail-line',
      const LineLayerProperties(
        lineColor: '#7E57C2',
        lineWidth: 3.25,
        lineOpacity: 0.96,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addGeoJsonSource(
      _pdrPreviewTrailSourceId,
      _emptyFeatureCollection,
    );
    await controller.addLineLayer(
      _pdrPreviewTrailSourceId,
      'floor-pdr-preview-trail-line',
      const LineLayerProperties(
        lineColor: '#7E57C2',
        lineWidth: 3.25,
        lineOpacity: 0.68,
        lineDasharray: [1.5, 1.5],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    await controller.addGeoJsonSource(
      _markersSourceId,
      _emptyFeatureCollection,
    );

    // 목적지 핀 레이어보다 먼저 등록해, 겹칠 때 목적지 핀이 위에 오게 한다.
    await _addCurrentLocationSymbolLayer(controller);

    await _addDestinationPinSymbolLayer(controller);

    await controller.addGeoJsonSource(
      _highlightSourceId,
      _emptyFeatureCollection,
    );
    // 선택된 매장을 옅게 채우고 테두리 선 색을 진하게 바꿔서 "포커스"가
    // 어디 있는지 보여준다. 매장 탭/검색으로 고른 매장이 바뀔 때마다
    // _updateHighlightSource가 이 소스의 폴리곤만 바꿔치기한다.
    await controller.addFillLayer(
      _highlightSourceId,
      'floor-highlight-fill',
      const FillLayerProperties(fillColor: '#1A73E8', fillOpacity: 0.16),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      _highlightSourceId,
      'floor-highlight-line',
      const LineLayerProperties(
        lineColor: '#1A73E8',
        // 두꺼운 파란 테두리는 옆 매장까지 덮어 지도 가독성을 해쳤다. 채움
        // 색으로도 포커스를 충분히 표현하므로, 테두리는 매장 경계선을 아주
        // 살짝 진하게 하는 정도로만 남긴다.
        lineWidth: 1.2,
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

    _styleReady = true;
    // 아이콘 비트맵·레이어 등록이 모두 끝난 시점.
    FloorSwitchTiming.mark('layers');
    await _updateCompletedRouteSource();
    await _updateRouteSource();
    await _updateTransferRouteSource();
    await _updateDebugGraphSource();
    await _updatePdrRawTrailSource();
    await _updatePdrConfirmedTrailSource();
    await _updatePdrRoninTrailSource();
    await _updatePdrTrailSource();
    await _updatePdrPreviewTrailSource();
    await _updateMarkersSource();
    await _updateHighlightSource();
    final handover = widget.initialCamera;
    if (handover != null) {
      // 이어받은 카메라가 있으면 fit을 아예 하지 않는다. fit을 한 뒤 되돌리면
      // 그 사이 한 프레임이 건물 전체로 그려져 화면이 한 번 튄다.
      // 축소 하한은 build의 `_computeMinZoom`이 층마다 따로 잡으므로 여기서
      // 건너뛰어도 이어받은 줌이 하한 아래로 내려가 있으면 곧 교정된다.
      await _controller?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _toMapLibreLatLng(handover.target),
            zoom: handover.zoom,
            bearing: handover.bearing,
            tilt: handover.tilt,
          ),
        ),
      );
    } else if (widget.routePoints.isNotEmpty) {
      await _fitToRouteBounds(widget.routePoints);
    } else {
      await _fitToFootprint();
    }
    // 층을 바꿔 들어온 경우 여기가 카메라를 잡는 마지막 지점이다. 건물 전체에
    // 맞춘 뒤에 적용해야 그 fit이 포커스를 덮어쓰지 않는다.
    await _applyFocusTarget();
  }

  void _enforceMinZoom() {
    final controller = _controller;
    final minZoom = _minZoom;
    if (controller == null || minZoom == null) return;
    final position = controller.cameraPosition;
    if (position == null) return;
    // 부동소수 오차로 하한과 사실상 같은 값에서 반복적으로 카메라를 옮기지
    // 않도록 아주 작은 여유(0.01)를 둔다.
    if (position.zoom < minZoom - 0.01) {
      controller.moveCamera(CameraUpdate.zoomTo(minZoom));
    }
  }

  void _handleCameraIdle() {
    _enforceMinZoom();
    _pullBackIntoFootprint();
    _notifyCameraBearing();
  }

  /// 카메라 중심이 도면 밖으로 나갔으면 가장자리로 되돌린다.
  ///
  /// **왜 MapLibre의 `cameraTargetBounds`를 안 쓰나** — 써 봤는데 이 조합
  /// (maplibre_gl 0.26.2 + Android)에서는 지도가 아예 렌더되지 않았다. 도면이
  /// 통째로 안 그려져서 실기 확인 때 바로 드러났다. 여기서는 이미 축소 하한
  /// 강제([_enforceMinZoom])가 쓰고 있는, 동작이 검증된 훅으로 같은 목적을
  /// 이룬다.
  ///
  /// 제스처가 **끝난 뒤에** 되돌린다. 미는 동안 붙잡으면 손가락과 지도가 계속
  /// 싸우게 된다 — 놓으면 돌아오는 편이 예측 가능하다.
  ///
  /// wgs84 footprint가 없는 건물에서는 아무것도 하지 않는다. 기준이 없는데
  /// 되돌리면 엉뚱한 데로 끌고 간다.
  Future<void> _pullBackIntoFootprint() async {
    final controller = _controller;
    final center = controller?.cameraPosition?.target;
    if (controller == null || center == null) return;

    // 매장 포커스 중에는 되돌리지 않는다(위 [_applyFocusTarget] 주석).
    if (_footprintBoundsSuspended) return;

    final halfSpan = await _visibleHalfSpan(controller);
    if (!mounted) return;

    final clamped = clampToFootprint(
      ll.LatLng(center.latitude, center.longitude),
      widget.floorPlan.footprint,
      halfSpanLat: halfSpan?.lat ?? 0,
      halfSpanLng: halfSpan?.lng ?? 0,
      userLocation: _userBoundsSuspended ? null : widget.currentLocation,
    );
    if (clamped == null) return;

    // 되돌림도 미끄러지게 한다. 기본 애니메이션은 짧아서 경계에서 지도가
    // 튕겨 나오는 것처럼 보였다 — 같은 거리를 같은 방향으로 옮기더라도
    // "벽에 부딪혔다"와 "벽에 닿아 멈췄다"는 다르게 읽힌다.
    await controller.animateCamera(
      CameraUpdate.newLatLng(_toMapLibreLatLng(clamped)),
      duration: _pullBackAnimationDuration,
    );
  }

  /// 도면 밖으로 나간 카메라를 되돌리는 데 쓰는 시간. [_followAnimationDuration]
  /// 보다 조금 길게 둔다 — 이쪽은 사용자가 방금 민 것을 되돌리는 동작이라,
  /// 빠를수록 "튕겼다"로 읽힌다.
  static const _pullBackAnimationDuration = Duration(milliseconds: 450);

  /// 지금 화면이 덮는 위경도 범위의 **절반**. 못 구하면 null이다.
  ///
  /// 직접 삼각함수로 계산하지 않고 `getVisibleRegion()`을 쓴다. 실내 지도는
  /// 건물에 맞춰 회전(bearing)돼 있어서 뷰포트의 위경도 범위가 화면 가로·세로와
  /// 그대로 대응하지 않는데, 이 값은 회전을 반영한 뒤의 축정렬 bbox라 그 문제를
  /// 알아서 넘긴다. 대신 45° 근처에서는 실제 뷰포트보다 넉넉하게 잡혀 필요보다
  /// 조금 더 깎인다 — 건물 모서리를 화면 끝까지 못 미는 정도이고, 빈 공간이
  /// 생기는 쪽보다 낫다고 보고 감수한다.
  ///
  /// **실패하면 null을 돌려주고 호출부는 깎기 없이(=예전 동작으로) 되돌린다.**
  /// 화면 크기를 모른다고 되돌림 자체를 포기하면 무한히 밀리던 원래 문제로
  /// 돌아가므로, 덜 좋은 쪽으로 폴백하되 기능은 남긴다.
  Future<({double lat, double lng})?> _visibleHalfSpan(
    MapLibreMapController controller,
  ) async {
    try {
      final region = await controller.getVisibleRegion();
      final lat = (region.northeast.latitude - region.southwest.latitude) / 2;
      final lng = (region.northeast.longitude - region.southwest.longitude) / 2;
      if (!lat.isFinite || !lng.isFinite || lat <= 0 || lng <= 0) return null;
      return (lat: lat, lng: lng);
    } catch (error, stackTrace) {
      debugPrint('visible region query failed: $error\n$stackTrace');
      return null;
    }
  }

  void _notifyCameraBearing() {
    final bearing = _controller?.cameraPosition?.bearing;
    if (bearing != null && bearing.isFinite) {
      widget.onCameraBearingChanged?.call(bearing);
    }
  }

  /// 선택된 매장(있으면)의 폴리곤을 강조 표시용 GeoJSON 소스에 채운다.
  /// 선택이 없으면 빈 FeatureCollection으로 비워서 강조를 지운다.
  Future<void> _updateHighlightSource() async {
    final controller = _controller;
    if (controller == null) return;

    final storeId = widget.highlightedStoreId;
    final store = storeId == null
        ? null
        : widget.floorPlan.stores.where((s) => s.id == storeId).firstOrNull;
    if (store == null || store.polygon.length < 3) {
      await controller.setGeoJsonSource(
        _highlightSourceId,
        _emptyFeatureCollection,
      );
      return;
    }

    final ring = [
      for (final point in store.polygon) [point.longitude, point.latitude],
    ];
    // GeoJSON Polygon 링은 닫혀 있어야 한다(첫 점 == 마지막 점).
    if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
      ring.add(ring.first);
    }

    await controller.setGeoJsonSource(_highlightSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [ring],
          },
        },
      ],
    });
  }

  /// 새 경로가 그려질 때 카메라를 경로의 **출발점**으로 옮긴다. 예전엔 경로
  /// 전체 bounding box에 맞춰 줌아웃했지만, 그러면 사용자가 지금 서 있는
  /// 위치와 바로 가야 할 방향이 화면 안에서 너무 작게 보인다. 특히 층 간
  /// 경로(1F→6F)에서는 이 층에 그려진 세그먼트가 사용자 시점에서 크게 보여야
  /// "여기서 저기 엘리베이터로 가면 되는구나"가 즉시 이해된다.
  ///
  /// 줌은 [_routeStartZoom]으로 고정한다(사용자가 방향을 놓치지 않을 정도로
  /// 가깝게). 현재 bearing은 유지하며, 사용자가 이후 줌/이동을 하면 그 조작을
  /// 덮지 않는다 — 이 함수는 "경로가 새로 생긴 순간"에만 호출된다.
  Future<void> _fitToRouteBounds(List<ll.LatLng> points) async {
    final controller = _controller;
    if (controller == null || points.isEmpty) return;
    final current = controller.cameraPosition;
    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toMapLibreLatLng(points.first),
          zoom: _routeStartZoom,
          bearing: current?.bearing ?? 0,
          tilt: current?.tilt ?? 0,
        ),
      ),
    );
  }

  /// 경로 시작 시 사용할 카메라 줌 레벨. 사용자가 지금 위치와 바로 앞 방향을
  /// 명확히 볼 수 있을 정도의 값.
  static const _routeStartZoom = 19.0;

  /// 화면(뷰포트) 크기에 맞춰 건물이 최대한 크게(=매장 라벨이 최대한 많이
  /// 안 겹치고 보이게) 나오도록 카메라 bearing과 zoom을 같이 계산해서 적용한다.
  ///
  /// `newLatLngBounds`는 항상 지도를 정북 방향으로 맞춘 뒤 그 상태 기준으로
  /// zoom을 정하기 때문에, 그 다음에 건물을 반듯하게 돌리는(bearing) 회전을
  /// 더하면 회전된 모양이 뷰포트에 다시 안 맞아 여백이 생긴다(예: 가로로
  /// 긴 건물을 세로로 긴 화면에 정북 기준으로 맞추면 좌우 폭에 걸려 축소된
  /// 채로, 돌려도 그 축소율 그대로 남는다). 그래서 bearing 후보 두 개(건물
  /// 외곽선에 맞춘 각도, 그리고 그걸 90도 돌린 각도) 각각에 대해 "그 각도로
  /// 봤을 때 건물이 뷰포트에 얼마나 크게 들어가는지"를 직접 계산해서 더 크게
  /// 보이는 쪽을 고른다.

  /// 추적 중일 때 카메라를 내 위치와 바라보는 방향에 맞춘다.
  ///
  /// **중심 이동과 회전을 한 번의 `moveCamera`로 묶는다.** 나눠 부르면 걸음마다
  /// 화면이 두 번 튄다(먼저 밀리고 그 다음 돈다).
  ///
  /// 회전할지 말지는 [bearingToFollow]가 정한다 — heading이 데드밴드 안에서
  /// 흔들리는 동안에는 null을 돌려주고, 그때는 지금 각도를 그대로 쓴다.
  /// [force]는 "위치 보정"처럼 사용자가 명시적으로 정렬을 요청한 경우다.
  Future<void> _followCamera({bool force = false}) async {
    final controller = _controller;
    final target = widget.currentLocation;
    if (controller == null || target == null) return;
    final current = controller.cameraPosition;
    final bearing = bearingToFollow(
      heading: widget.currentHeadingDegrees,
      cameraBearing: current?.bearing,
      force: force,
    );

    // 위치에도 데드밴드를 둔다. 예전에는 위치가 갱신될 때마다 무조건 중앙에
    // 맞췄는데, PDR이 한 걸음마다 값을 내놓으므로 걷는 내내 지도가 끌려다녔다
    // ([kFollowDeadbandRatio]).
    final cameraCenter = current?.target;
    var recenter = force || cameraCenter == null;
    if (!recenter) {
      final halfSpan = await _visibleHalfSpan(controller);
      if (!mounted) return;
      recenter = shouldRecenterFollow(
        camera: ll.LatLng(cameraCenter.latitude, cameraCenter.longitude),
        user: target,
        halfSpanLat: halfSpan?.lat ?? 0,
        halfSpanLng: halfSpan?.lng ?? 0,
      );
    }
    // 위치도 방향도 손댈 게 없으면 카메라를 아예 건드리지 않는다. 같은 자리로
    // animateCamera를 부르면 그 자체가 onCameraIdle을 다시 불러 되돌림 판정이
    // 헛돈다([floor_camera_bounds.dart]의 `_epsilonDeg` 주석과 같은 함정).
    if (!recenter && bearing == null) return;

    // **중심 이동과 회전을 한 번의 호출로 묶는다.** 나눠 부르면 걸음마다 화면이
    // 두 번 튄다(먼저 밀리고 그 다음 돈다).
    //
    // `moveCamera`가 아니라 `animateCamera`인 이유는 데드밴드와 짝이다 — 데드밴드
    // 를 두면 한 번에 옮기는 거리가 그만큼 커지는데, 순간이동으로 처리하면
    // 조용해진 대신 가끔 크게 튀는 화면이 되어 오히려 더 거슬린다.
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: recenter
              ? _toMapLibreLatLng(target)
              : LatLng(cameraCenter!.latitude, cameraCenter.longitude),
          zoom: current?.zoom ?? 18,
          bearing: bearing ?? current?.bearing ?? 0,
          tilt: current?.tilt ?? 0,
        ),
      ),
      duration: _followAnimationDuration,
    );
  }

  /// 추적 카메라가 새 위치로 미끄러지는 시간. 걸음 간격(약 0.5~0.8초)보다 짧게
  /// 둬야 다음 갱신이 오기 전에 끝난다 — 길게 잡으면 애니메이션이 밀려 쌓인다.
  static const _followAnimationDuration = Duration(milliseconds: 350);

  /// 카메라 중심만 [target]으로 옮긴다. 현재 bearing/줌은 유지 — 사용자 위치를
  /// 화면 정중앙에 오게 하는 데 쓴다.
  Future<void> centerOn(ll.LatLng target) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.moveCamera(
      CameraUpdate.newLatLng(_toMapLibreLatLng(target)),
    );
  }

  /// 내 위치를 따라갈지. 켜져 있으면 [FloorPlanView.currentLocation]이 바뀔
  /// 때마다 카메라가 그 자리로 옮겨간다.
  ///
  /// **기본이 켜짐이다.** 실내에서 사용자가 하려는 일은 대부분 "내가 지금 어디
  /// 있나"이고, 걷는 동안 마커가 화면 밖으로 나가면 그걸 알 방법이 없어진다.
  ///
  /// 사용자가 지도를 **끌면** 꺼진다. 주변을 보려고 밀어 둔 지도가 다음 걸음에
  /// 제자리로 돌아오면 지도를 볼 수가 없다. 탭만으로는 꺼지지 않는다 —
  /// 매장 하나 눌러 보는 것으로 따라가기가 멈추면 그것대로 당황스럽다.
  bool _following = true;
  bool get isFollowing => _following;

  /// 내 위치 근방 제한([clampToFootprint]의 `userLocation`)을 꺼 둔 상태인지.
  ///
  /// 매장 포커스처럼 사용자가 **명시적으로 딴 데를 보러 간** 경우에만 켠다.
  /// 자세한 이유는 [_applyFocusTarget] 주석에 있다.
  bool _userBoundsSuspended = false;

  /// 도면 밖 되돌림([_pullBackIntoFootprint])을 꺼 둔 상태인지.
  ///
  /// 매장 포커스 중에만 켠다. 건물 가장자리 매장은 되돌림 때문에 화면 중앙에
  /// 놓을 수 없고, 시트를 피해 올려 둔 것까지 되돌려지기 때문이다
  /// ([_applyFocusTarget] 주석에 실기기 사례를 적어 두었다).
  bool _footprintBoundsSuspended = false;

  /// 이번 제스처에서 손가락이 움직인 누적 거리(논리 픽셀). 이 값이 임계를
  /// 넘어야 "끌었다"로 본다.
  double _gesturePanPx = 0;

  /// 탭과 드래그를 가르는 값. Flutter 기본 터치 슬롭(18)보다 조금 작게 둬서,
  /// 지도가 실제로 움직이기 시작하는 순간과 추적 해제 시점이 어긋나지 않게 한다.
  static const _followBreakSlopPx = 12.0;

  void _onMapPointerDown(PointerDownEvent event) => _gesturePanPx = 0;

  void _onMapPointerMove(PointerMoveEvent event) {
    if (!_following) return;
    _gesturePanPx += event.delta.distance;
    if (_gesturePanPx < _followBreakSlopPx) return;
    setState(() => _following = false);
    // **내 위치 근방 제한도 함께 푼다.** 이게 없으면 추적만 꺼지고 카메라는
    // 여전히 "내 위치에서 화면 절반 이내"에 묶여 있어서, 옆 구역을 보려고 밀어
    // 둔 지도가 손을 떼는 순간 [_pullBackIntoFootprint]에 도로 끌려온다 —
    // 사용자 입장에서는 추적을 끈 것이 아무 소용이 없다.
    //
    // 도면 제한은 그대로 남는다. 밀어서 볼 수 있는 범위가 **이 건물 이 층**으로
    // 제한되는 것은 맞고, 그게 없으면 도면이 화면에서 사라진다
    // ([clampToFootprint] 주석).
    //
    // 다시 켜는 곳은 [resumeFollow] 하나다("위치 보정").
    _userBoundsSuspended = true;
    // 반대로 도면 제한은 **여기서 되살린다.** 포커스 때문에 꺼 뒀던 것인데,
    // 사용자가 직접 밀기 시작하면 "도면 밖으로 무한히 밀리지 않는다"가 다시
    // 필요하다([clampToFootprint] 주석).
    _footprintBoundsSuspended = false;
    widget.onFollowingChanged?.call(false);
  }

  Future<void> resumeFollow() async {
    if (!_following) {
      setState(() => _following = true);
      widget.onFollowingChanged?.call(true);
    }
    // 내 위치로 돌아왔으니 매장 포커스 때문에 꺼 뒀던 제한들을 다시 켠다.
    _userBoundsSuspended = false;
    _footprintBoundsSuspended = false;
    // 중심만 맞추고 끝내지 않는다. 추적이 풀린 사이 사용자가 지도를 돌려 놨을
    // 수 있고, 그러면 "내 위치로 돌아왔는데 방향은 딴 데를 보는" 화면이 된다.
    // 명시적 요청이므로 데드밴드를 건너뛴다.
    await _followCamera(force: true);
  }


  Future<void> _fitToFootprint() async {
    final controller = _controller;
    final footprint = widget.floorPlan.footprint;
    if (controller == null || footprint.isEmpty) return;

    final viewport = _lastViewport ?? MediaQuery.sizeOf(context);
    final fit = _fitBearingAndZoom(footprint, viewport);

    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toMapLibreLatLng(_centroid(footprint)),
          zoom: fit.zoom,
          bearing: fit.bearing,
        ),
      ),
    );
  }

  static ll.LatLng _centroid(List<ll.LatLng> footprint) {
    final lat =
        footprint.map((p) => p.latitude).reduce((a, b) => a + b) /
        footprint.length;
    final lng =
        footprint.map((p) => p.longitude).reduce((a, b) => a + b) /
        footprint.length;
    return ll.LatLng(lat, lng);
  }

  /// 목적지 마커의 빨간 물방울 핀 이미지를 오프스크린 렌더링해 PNG 바이트로
  /// 돌려준다. 위쪽 원 + 아래쪽 삼각 꼬리를 같은 빨간색으로 합쳐 물방울
  /// 모양을 만들고, 그 안에 흰 원을 얹는다. 삼각 꼬리의 두 밑변은 원의
  /// 접선에 정확히 맞물리도록 tangentAngle(중심-끝점 축과 접점 사이의 각도,
  /// acos(r/d))로 계산해서 원과 이음매가 매끄럽게 이어진다.
  ///

  /// 상용 지도 앱처럼 흰 테두리의 파란 현재 위치 점 뒤로 반투명 heading cone이
  /// 퍼지는 하나의 심볼을 렌더링한다. MapLibre가 이 비트맵 전체를 회전하므로
  /// 확대/축소해도 점과 방향 범위의 비율·간격이 흐트러지지 않는다.
  ///
  /// 아래 좌표는 모두 [_currentLocationIconDesignSize] 기준의 디자인 단위이고,
  /// 실제 비트맵은 [_currentLocationIconPixelRatio]배로 렌더링한다 — 화면상
  /// 크기는 iconSize가 정하고(=[_currentLocationIconSize]) 이 배율은 해상도만
  /// 올린다. iconSize가 디자인 1px = 화면 1px로 고정이므로, 아래 반지름은 그대로
  /// 화면 픽셀로 읽으면 된다(코어 반지름 16 = 화면 지름 32px).
  static Future<Uint8List> _renderCurrentLocationIcon({
    required bool showHeading,
  }) async {
    const canvasSize = _currentLocationIconDesignSize;
    const center = Offset(canvasSize / 2, canvasSize / 2);
    const pixelSize = canvasSize * _currentLocationIconPixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, pixelSize, pixelSize),
    );
    canvas.scale(_currentLocationIconPixelRatio);

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
      _currentLocationRimRadius + 3,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      center,
      _currentLocationRimRadius,
      Paint()..color = Colors.white,
    );

    const blue = Color(0xFF1976D2);
    canvas.drawCircle(
      center,
      _currentLocationCoreRadius,
      Paint()..color = blue,
    );
    // 코어 왼쪽 위의 광택 점. 코어 크기를 바꿔도 비율이 유지되도록 코어 반지름에서
    // 파생시킨다(원본 디자인의 코어 18 / offset 5 / 반지름 4.5 비율).
    const glossOffset = _currentLocationCoreRadius * 0.28;
    canvas.drawCircle(
      center - const Offset(glossOffset, glossOffset),
      _currentLocationCoreRadius * 0.25,
      Paint()..color = const Color(0x66FFFFFF),
    );

    final image = await recorder.endRecording().toImage(
      pixelSize.toInt(),
      pixelSize.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static const _metersPerDegreeLat = 111320.0;
  static const _fitPaddingPx = 24.0;
  // 표준 Web Mercator 상수: 적도에서 zoom 0일 때 픽셀당 미터.
  static const _metersPerPixelAtZoom0Equator = 156543.03392804097;

  static ({double bearing, double zoom}) _fitBearingAndZoom(
    List<ll.LatLng> footprint,
    Size viewport,
  ) {
    final center = _centroid(footprint);
    final cosLat = cos(center.latitude * pi / 180);

    // 외곽선을 중심 기준 등방(=1 단위가 어느 축이든 같은 실제 거리) 평면
    // 좌표(미터)로 바꾼다 — 회전/거리 계산을 위/경도 그대로 하면 위도에 따라
    // 경도 1도의 실제 거리가 달라 왜곡되기 때문이다.
    final localPoints = footprint.map((p) {
      final dx =
          (p.longitude - center.longitude) * cosLat * _metersPerDegreeLat;
      final dy = (p.latitude - center.latitude) * _metersPerDegreeLat;
      return Offset(dx, dy);
    }).toList();

    final axisBearing = _straighteningBearing(footprint);
    final availableWidth = max(1.0, viewport.width - _fitPaddingPx * 2);
    final availableHeight = max(1.0, viewport.height - _fitPaddingPx * 2);

    var bestBearing = 0.0;
    var bestZoom = double.negativeInfinity;
    for (final candidate in [axisBearing, axisBearing + 90]) {
      final rad = candidate * pi / 180;
      final cosB = cos(rad);
      final sinB = sin(rad);

      var minX = double.infinity, maxX = double.negativeInfinity;
      var minY = double.infinity, maxY = double.negativeInfinity;
      for (final p in localPoints) {
        // 카메라 bearing이 candidate일 때 화면에 어떻게 투영되는지: 화면
        // "위"는 나침반 방향 candidate, "오른쪽"은 candidate+90을 가리킨다.
        final rx = p.dx * cosB - p.dy * sinB;
        final ry = p.dx * sinB + p.dy * cosB;
        minX = min(minX, rx);
        maxX = max(maxX, rx);
        minY = min(minY, ry);
        maxY = max(maxY, ry);
      }
      final widthM = maxX - minX;
      final heightM = maxY - minY;
      if (widthM <= 0 || heightM <= 0) continue;

      final metersPerPixelAtLat = _metersPerPixelAtZoom0Equator * cosLat;
      final metersPerPixelNeeded = max(
        widthM / availableWidth,
        heightM / availableHeight,
      );
      final zoom = log(metersPerPixelAtLat / metersPerPixelNeeded) / log(2);

      if (zoom > bestZoom) {
        bestZoom = zoom;
        bestBearing = candidate;
      }
    }

    if (bestZoom.isFinite) return (bearing: bestBearing, zoom: bestZoom);
    return (bearing: axisBearing, zoom: 18.0);
  }

  /// 건물 전체가 뷰포트 안에 들어오는 축소 하한을 뽑는다.
  ///
  /// [_initialCenter]가 카메라를 bbox 중심에 놓으므로, 하한은 그 중심에서 잰
  /// 회전-불변 반지름의 지름(2 × maxRadius)이 뷰포트 짧은 변의 실제 보이는
  /// 영역([visibleInsets] 뺀 크기)에 딱 들어가는 줌으로 잡는다. 임의 여유
  /// 계수를 곱하지 않는다 — 곱하는 순간 하한에서 건물이 너무 작게 보이거나
  /// 반대로 너무 타이트해서 건물이 잘리는 문제가 매번 반복된다.
  static double? _computeMinZoom(
    FloorPlan floorPlan,
    Size viewport,
    EdgeInsets visibleInsets,
  ) {
    // 지도는 화면 끝까지 그려지지만 상단 검색바·하단 버튼바가 위쪽/아래쪽을
    // 가리고 있어, "건물이 실제로 보이는" 세로/가로 영역은 오버레이만큼 좁다.
    // 그 실제 영역을 짧은 변으로 잡아야 하한에 도달했을 때 건물이 오버레이에
    // 가려지지 않는다.
    final visibleWidth = viewport.width - visibleInsets.horizontal;
    final visibleHeight = viewport.height - visibleInsets.vertical;
    final shortSide = min(visibleWidth, visibleHeight);
    if (!shortSide.isFinite || shortSide <= 0) return null;
    final availableShortSide = max(1.0, shortSide - _fitPaddingPx * 2);

    final points = _extentWgs84Points(floorPlan);
    if (points.isEmpty) return null;
    final center = _bboxCenter(points);
    final radiusMeters = _maxRadiusMeters(points, center);
    if (radiusMeters <= 0) return null;

    final cosLat = cos(center.latitude * pi / 180);
    final metersPerPixelAtLat = _metersPerPixelAtZoom0Equator * cosLat;
    final metersPerPixelNeeded = (radiusMeters * 2) / availableShortSide;
    final zoom = log(metersPerPixelAtLat / metersPerPixelNeeded) / log(2);
    return zoom.isFinite ? zoom : null;
  }

  /// 축소 하한/초기 카메라 위치 계산에 쓰는 "화면에 반드시 보여야 할" wgs84
  /// 좌표 집합. 실좌표 앵커가 없는 건물은 footprint 자체가 비어 있으므로
  /// 매장 폴리곤/중심점과 POI 위치까지 함께 넣는다. footprint_local_m은 크기
  /// 정보만 담을 뿐 wgs84 위치가 없어 여기서는 쓰지 않는다.
  static List<ll.LatLng> _extentWgs84Points(FloorPlan floorPlan) {
    return <ll.LatLng>[
      ...floorPlan.footprint,
      for (final store in floorPlan.stores) ...[
        store.centroid,
        ...store.polygon,
      ],
      for (final poi in floorPlan.pois) poi.point,
    ];
  }

  static ll.LatLng _bboxCenter(List<ll.LatLng> points) {
    var minLat = double.infinity, maxLat = double.negativeInfinity;
    var minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    return ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  static double _maxRadiusMeters(List<ll.LatLng> points, ll.LatLng center) {
    final cosLat = cos(center.latitude * pi / 180);
    var maxRadius = 0.0;
    for (final p in points) {
      final dx =
          (p.longitude - center.longitude) * cosLat * _metersPerDegreeLat;
      final dy = (p.latitude - center.latitude) * _metersPerDegreeLat;
      maxRadius = max(maxRadius, sqrt(dx * dx + dy * dy));
    }
    return maxRadius;
  }

  Future<void> _updateRouteSource() async {
    final controller = _controller;
    if (controller == null) return;
    final points = widget.routePoints;
    if (points.length < 2) {
      await controller.setGeoJsonSource(
        _routeSourceId,
        _emptyFeatureCollection,
      );
      return;
    }
    await controller.setGeoJsonSource(_routeSourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final point in points) [point.longitude, point.latitude],
            ],
          },
        },
      ],
    });
  }

  Future<void> _updateTransferRouteSource() async {
    await _updateLineSource(_transferRouteSourceId, widget.transferRoutePoints);
  }

  Future<void> _updateCompletedRouteSource() async {
    final segments = widget.walkedRouteSegments.isNotEmpty
        ? widget.walkedRouteSegments
        : [widget.completedRoutePoints];
    final drawable = segments
        .where((segment) => segment.length >= 2)
        .toList(growable: false);
    final controller = _controller;
    if (controller == null) return;
    if (drawable.isEmpty) {
      await controller.setGeoJsonSource(
        _completedRouteSourceId,
        _emptyFeatureCollection,
      );
      return;
    }
    await controller.setGeoJsonSource(_completedRouteSourceId, {
      'type': 'FeatureCollection',
      'features': [
        for (final segment in drawable)
          {
            'type': 'Feature',
            'properties': const <String, dynamic>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final point in segment) [point.longitude, point.latitude],
              ],
            },
          },
      ],
    });
  }

  Future<void> _updatePdrTrailSource() async {
    await _updateLineSource(_pdrTrailSourceId, widget.pdrPathPoints);
  }

  Future<void> _updatePdrPreviewTrailSource() async {
    await _updateLineSource(
      _pdrPreviewTrailSourceId,
      widget.pdrPreviewPathPoints,
    );
  }

  Future<void> _updatePdrRawTrailSource() async {
    await _updateLineSource(_pdrRawTrailSourceId, widget.pdrRawPathPoints);
  }

  Future<void> _updatePdrConfirmedTrailSource() async {
    await _updateLineSource(
      _pdrConfirmedTrailSourceId,
      widget.pdrConfirmedPathPoints,
    );
  }

  Future<void> _updatePdrRoninTrailSource() async {
    await _updateLineSource(_pdrRoninTrailSourceId, widget.pdrRoninPathPoints);
  }

  Future<void> _updateLineSource(
    String sourceId,
    List<ll.LatLng> points,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    if (points.length < 2) {
      await controller.setGeoJsonSource(sourceId, _emptyFeatureCollection);
      return;
    }
    await controller.setGeoJsonSource(sourceId, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final point in points) [point.longitude, point.latitude],
            ],
          },
        },
      ],
    });
  }

  Future<void> _updateDebugGraphSource() async {
    final controller = _controller;
    if (controller == null) return;
    final overlay = widget.debugMapOverlay;
    if (overlay.isEmpty) {
      await controller.setGeoJsonSource(
        _debugGraphSourceId,
        _emptyFeatureCollection,
      );
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final edge in overlay.edges) {
      if (overlay.showEdges) {
        features.add({
          'type': 'Feature',
          'properties': {'kind': 'edge', 'active': edge.active},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final point in edge.points)
                [point.longitude, point.latitude],
            ],
          },
        });
      }
    }
    for (final node in overlay.nodes) {
      if (overlay.showNodes) {
        features.add({
          'type': 'Feature',
          'properties': {'kind': 'node', 'active': node.active},
          'geometry': {
            'type': 'Point',
            'coordinates': [node.position.longitude, node.position.latitude],
          },
        });
      }
    }
    await controller.setGeoJsonSource(_debugGraphSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  Future<void> _updateMarkersSource() async {
    final controller = _controller;
    if (controller == null) return;
    final features = <Map<String, dynamic>>[];
    final current = widget.currentLocation;
    final destination = widget.destination;
    if (current != null) {
      features.add(
        _markerFeature(
          current,
          MapMarkerKind.current,
          headingDegrees: widget.currentHeadingDegrees,
        ),
      );
    }
    if (destination != null) {
      features.add(_markerFeature(destination, MapMarkerKind.destination));
    }
    await controller.setGeoJsonSource(_markersSourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  Map<String, dynamic> _markerFeature(
    ll.LatLng point,
    MapMarkerKind kind, {
    double? headingDegrees,
  }) {
    return {
      'type': 'Feature',
      'properties': {
        'kind': kind.name,
        if (headingDegrees != null && headingDegrees.isFinite)
          'heading': headingDegrees,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [point.longitude, point.latitude],
      },
    };
  }

  Future<void> _handleMapClick(Point<double> point, LatLng coordinates) async {
    // 매장 정보/길찾기 시트가 열려 있는 동안(widget.interactive == false)은
    // 무시한다. 웹에서는 시트 안 버튼(예: "도착지로 설정")을 누른 클릭이
    // 그 아래 실제 DOM 캔버스(MapLibre)까지 새어나가, 마침 그 자리에 다른
    // 매장 폴리곤이 있으면 그 매장 정보 시트가 겹쳐 열리는 문제가 있었다.
    if (!widget.interactive) return;

    // 검색창에 포커스가 있어 소프트키보드가 떠 있는 상태로 지도를 탭하면
    // "키보드 바깥을 눌렀다"는 사용자 의도로 보고 포커스를 내려 키보드를
    // 닫는다. MapLibre가 PlatformView라 Flutter의 outer GestureDetector로는
    // 지도 위 탭을 잡지 못하므로 이 콜백에서 직접 처리한다.
    //
    // 이 한 번의 탭은 "키보드 닫기"에만 사용하고, 매장 선택·onMapPressed 등
    // 다른 지도 상호작용은 실행하지 않고 그대로 return한다 — 그렇지 않으면
    // 키보드를 내리려고 지도를 눌렀는데 뒤에 있던 매장 정보 시트가 함께
    // 뜨는 문제가 생긴다.
    //
    // "키보드가 떠 있는지"는 `FocusManager.primaryFocus`로 판단하면 안 된다 —
    // IconButton/InkWell 등 흔한 위젯이 내부에 Focus 노드를 만들어, 사용자가
    // 상단 검색 아이콘/하단 모드 버튼을 한 번이라도 탭한 뒤에는 primary focus
    // 가 계속 그 버튼에 남아 매장 탭을 포함한 모든 지도 클릭이 삼켜졌다. 실제
    // 판정은 뷰포트 하단이 소프트키보드에 잘려있는지로 한다 — 웹/데스크톱에서
    // 이 값은 항상 0이라 자연스럽게 지도 탭이 통과된다.
    final keyboardHeight = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
    if (keyboardHeight > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }

    // 층 selector 같은 지도 위 오버레이 영역의 탭은 무시한다. MapLibre가
    // PlatformView라 Flutter gesture arena를 우회해 네이티브 지도가 독립적으로
    // 탭을 받아버려, 오버레이 InkWell이 소비하더라도 뒤의 매장이 함께
    // 선택되는 문제가 남아 있었다. onMapClick의 point는 지도 위젯 로컬 좌표
    // 이므로 지도 자체의 RenderBox로 전역 좌표로 변환한 뒤 오버레이 소유자에
    // 게 물어본다.
    final overlayHitTest = widget.overlayHitTest;
    if (overlayHitTest != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        final globalTap = box.localToGlobal(Offset(point.x, point.y));
        if (overlayHitTest(globalTap)) return;
      }
    }

    final mapPressed = widget.onMapPressed;
    if (mapPressed?.call(
          ll.LatLng(coordinates.latitude, coordinates.longitude),
        ) ==
        true) {
      return;
    }

    // 여기서부터는 "매장을 눌렀는가"를 판정한다. 어느 갈래로 빠지든 매장을
    // 맞히지 못했으면 [onEmptyMapPressed]로 넘긴다 — 중간에 그냥 return하면
    // 복도를 누른 탭이 조용히 사라져, 길찾기의 "지도에서 선택"에서 복도를 눌러도
    // 아무 일도 안 일어나는 상태가 된다.
    final tapped = ll.LatLng(coordinates.latitude, coordinates.longitude);
    final store = await _storeAt(point);
    if (store == null) {
      widget.onEmptyMapPressed?.call(tapped);
      return;
    }
    widget.onStoreSelected?.call(store);
  }

  /// 화면 픽셀 [point]에 그려져 있는 매장 폴리곤. 없으면 null.
  Future<StorePolygon?> _storeAt(Point<double> point) async {
    final controller = _controller;
    if (controller == null) return null;
    final activeFloor = _activeTileFloor;
    if (activeFloor == null) return null;
    final features = await controller.queryRenderedFeatures(point, [
      _tileLayerId(_storesFillLayerId, activeFloor),
    ], null);
    if (features.isEmpty) return null;

    final properties = (features.first as Map)['properties'] as Map?;
    final id = properties?['id'] as String?;
    if (id == null) return null;

    return widget.floorPlan.stores.where((s) => s.id == id).firstOrNull;
  }

  LatLng _initialCenter(FloorPlan floorPlan) {
    // 축소 하한 계산이 이 중심점 기준으로 반지름을 재기 때문에, 같은 함수로
    // 뽑은 bbox 중심을 그대로 쓴다 — 첫 매장이나 첫 POI 좌표를 그대로 쓰면
    // 카메라가 건물 한쪽 구석에 놓여, 하한에 도달해도 반대편 끝이 시야
    // 밖으로 밀려나 전체가 안 보이는 문제가 있었다.
    final points = _extentWgs84Points(floorPlan);
    if (points.isNotEmpty) return _toMapLibreLatLng(_bboxCenter(points));
    return const LatLng(37.5665, 126.9780); // fallback: 서울시청
  }

  static LatLng _toMapLibreLatLng(ll.LatLng point) {
    return LatLng(point.latitude, point.longitude);
  }

  /// 건물 외곽선의 실제 방위각(진북 기준)과 화면(북쪽=위) 사이의 어긋남만큼
  /// 카메라를 회전시켜서, 실좌표(WGS84) 데이터는 그대로 두고 화면에는 건물이
  /// 반듯하게(축에 맞춰) 보이도록 하는 bearing을 계산한다.
  ///
  /// 외곽선에서 가장 긴 변의 진북 기준 방위각을 구해 90으로 나눈 나머지를
  /// 쓴다 — 그 나머지만큼 카메라를 돌리면 그 변이 화면에서 수평/수직에 맞춰진다.
  static double _straighteningBearing(List<ll.LatLng> footprint) {
    if (footprint.length < 2) return 0.0;

    final meanLatRad =
        footprint.map((p) => p.latitude).reduce((a, b) => a + b) /
        footprint.length *
        (pi / 180);
    final cosLat = cos(meanLatRad);

    var longestLength = -1.0;
    var longestBearingDeg = 0.0;
    for (var i = 0; i < footprint.length; i++) {
      final p1 = footprint[i];
      final p2 = footprint[(i + 1) % footprint.length];
      final dx = (p2.longitude - p1.longitude) * cosLat;
      final dy = p2.latitude - p1.latitude;
      final length = sqrt(dx * dx + dy * dy);
      if (length > longestLength) {
        longestLength = length;
        longestBearingDeg = atan2(dx, dy) * 180 / pi;
      }
    }

    return longestBearingDeg % 90;
  }
}

class _UnsupportedPlatformNotice extends StatelessWidget {
  const _UnsupportedPlatformNotice();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF3F1EF),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 40, color: Colors.black45),
              SizedBox(height: 12),
              Text(
                '실내 지도는 웹 브라우저 또는 모바일 앱에서만 볼 수 있어요.\n'
                'Windows 데스크톱 앱에서는 아직 지원하지 않아요.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _emptyFeatureCollection = {
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[],
};

// 원본 SVG(hyundai_floor_map_corrected_v6.svg)의 배경색을 그대로 옮겼다.
// 나머지 레이어(외곽선/매장/POI/경로)는 스타일 로드 후 벡터·GeoJSON
// 소스로 추가한다.
/// 심볼 레이어(매장명/POI 라벨)가 쓰는 폰트. API가 app/data/fonts 아래 같은
/// 이름의 디렉터리로 글리프를 서빙한다(GET /fonts/{fontstack}/{range}.pbf).
/// 매장명이 한글이라 한글 글리프가 있는 폰트여야 한다 — MapLibre 기본값인
/// Open Sans에는 한글이 없어서 라벨이 깨진다.
const _mapFontStack = [mapFontStackRegular];

/// [_initialStyle]의 glyphs 템플릿. `{fontstack}`/`{range}`는 MapLibre가
/// 치환하는 자리표시자라 Dart 보간과 섞이지 않게 따로 조립한다.
String get _glyphsUrl => '$apiBaseUrl/fonts/{fontstack}/{range}.pbf';

/// glyphs가 비어 있으면 심볼 레이어가 폰트를 못 받아 레이아웃을 끝내지 못하고,
/// 그 여파로 같은 벡터 타일의 fill 레이어까지 전부 안 그려진다. 배경색만 남고
/// 지도가 빈 화면이 되므로 glyphs는 반드시 채워야 한다.
String get _initialStyle =>
    '''
{
  "version": 8,
  "glyphs": "$_glyphsUrl",
  "sources": {},
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "#EDF4E7"}}
  ]
}
''';
