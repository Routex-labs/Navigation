import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/api_config.dart';
import '../../map/floor_switch_progress.dart';
import '../../map/geojson.dart';
import '../../map/picked_point.dart';
import '../../service_locator.dart';
import '../../core/tile_url.dart';
import '../../domain/route/building_entrances.dart';
import '../../domain/guidance/completed_route_history.dart';
import '../../domain/geo/geo_transform.dart';
import '../../domain/guidance/geo_route_progress.dart';
import '../../domain/guidance/guidance_chrome.dart';
import '../../features/debug_mode/debug_mode.dart';
import '../../domain/route/dijkstra.dart';
import '../../domain/route/route_endpoint_fill.dart';
import '../../domain/guidance/route_guidance.dart';
import '../../features/indoor_navigation/application/corridor_position_tracker.dart';
import '../../domain/guidance/escalator_ride.dart';
import '../../features/indoor_navigation/application/escalator_arrival.dart';
import '../../features/indoor_navigation/application/escalator_node_naming.dart';
import '../../features/indoor_navigation/application/escalator_transition_detector.dart';
import '../../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../../features/indoor_navigation/application/floor_map_matcher.dart';
import '../../features/indoor_navigation/application/guidance_trail_session.dart';
import '../../features/indoor_navigation/application/indoor_guidance_position.dart';
import '../../features/indoor_navigation/application/indoor_guidance_session.dart';
import '../../features/indoor_navigation/application/indoor_location_estimate.dart';
import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';
import '../../features/indoor_navigation/debug/escalator_debug_text.dart';
import '../../features/indoor_navigation/debug/pdr_debug_device_info.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_share.dart';
import '../../domain/route/multi_floor_router.dart';
import '../../domain/route/transfer_route_geometry.dart';
import '../../models/building.dart';
import '../../models/building_graph.dart';
import '../../models/directions_route.dart';
import '../../models/floor_graph.dart';
import '../../models/floor_plan.dart';
import '../../models/indoor_route.dart';
import '../../models/poi_search_result.dart';
import '../../models/transit_route.dart';
import '../../theme/app_theme.dart';
import 'widgets/store_cluster_sheet.dart';
import '../../map/store_label_anchor.dart';
import '../../widgets/eta_card.dart';
import 'widgets/transit_summary_card.dart';
import '../../models/store_index_entry.dart';
import '../../map/floor_camera_bounds.dart';
import '../../map/category_map_filter.dart';
import '../../map/category_map_icon.dart';
import '../../map/floor_facility_style.dart';
import 'widgets/floor_selector.dart';
import 'widgets/floor_switch_escalator_motif.dart';
import 'widgets/guidance_recenter_button.dart';
import 'widgets/indoor_arrival_card.dart';
import 'widgets/route_steps_sheet.dart';
import '../../map/icon_cache.dart';
import 'widgets/map_overlay_tap_guard.dart';
import 'widgets/status_badge.dart';
import 'floor_outline.dart';
import 'gps_session.dart';
import 'indoor_entry_gps.dart';
import 'building_orientation.dart';
import 'indoor_entry_proximity.dart';
import 'indoor_entry_zoom.dart';
import 'outdoor_map_tuning.dart';
import 'widgets/placing_anchor_hint.dart';
import 'route_recompute_policy.dart';
import 'indoor_overlay_layers.dart';
import 'map_camera_commands.dart';
import 'marker_map_layers.dart';
import 'shape_map_layers.dart';
import 'pdr_debug_map_layers.dart';
import 'pdr_session_lifecycle.dart';
import 'route_map_layers.dart';
import 'transit_map_layers.dart';

part 'outdoor_map_screen_escalator.dart';
part 'outdoor_map_screen_pdr.dart';
part 'outdoor_map_screen_route.dart';
part 'outdoor_map_screen_guidance.dart';
part 'outdoor_map_screen_route_layers.dart';
part 'outdoor_map_screen_indoor.dart';
part 'outdoor_map_screen_floor_switch.dart';
part 'outdoor_map_screen_store_tap.dart';
part 'outdoor_map_screen_gps.dart';
part 'outdoor_map_screen_map.dart';
part 'outdoor_map_screen_ui.dart';

// 건물 진입/이탈 판정 정책은 indoor_entry_gps.dart가 소유한다. 임계값과 그 근거,
// "왜 직전 값 대비 비율이 아닌가"는 전부 그쪽 주석에 있다.

// 실내 지도와 같은 이유. maplibre_gl은 web/android/iOS만 지원하므로
// 데스크톱에서는 사전에 안내를 보여주고 지도 자체는 그리지 않는다.
const _mapSupportedNativePlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
};
bool get _isMapSupportedOnThisPlatform =>
    kIsWeb || _mapSupportedNativePlatforms.contains(defaultTargetPlatform);

// MapLibre 소스·레이어 ID. 층 지도의 명명 규칙(_로 시작하지 않는 kebab-case) 준수.
// 건물 fill·dim scrim·층 외곽선·매장 강조의 소스/레이어 id, 등록, 폴리곤 쓰기는
// shape_map_layers.dart가 소유한다.
// 실내 오버레이 소스·레이어 id는 indoor_overlay_layers.dart의 [IndoorOverlayIds]가
// 소유한다. 층 전환마다 세대를 올려 실제 id를 새로 만드는 이유도 거기 적혀 있다.
// 경로선 소스·레이어 id와 등록은 route_map_layers.dart가 소유한다. 화면은
// 공개 소스 id(kOutdoorRoute*)로 데이터만 밀어 넣는다.
// 대중교통 경로 오버레이(소스·레이어 id, 등록, 데이터 쓰기)는
// transit_map_layers.dart가 소유한다.
// 현재 위치·야외 목적지·실내 도착 핀의 소스/레이어 id, 등록, 점 하나 쓰기는
// marker_map_layers.dart가 소유한다. 화면은 공개 소스 id(kOutdoorCurrent/Dest/
// IndoorDest)로 좌표만 넘긴다.
// PDR 위치 마커의 소스/레이어 id, 비트맵·레이어 등록, 데이터 조립은
// marker_map_layers.dart가 소유한다.

// 디버그 모드 전용 PDR 진단 레이어(소스·레이어 id, 등록, 데이터 쓰기)는
// pdr_debug_map_layers.dart가 소유한다. 여기서는 무엇을 보여줄지(토글·층·앵커
// 판단)만 정해 완성된 데이터를 넘긴다.

// 사람 조작 층 전환 크로스페이드의 근거·타이밍 정책(즉시 교체 임계, 페이드
// 길이, 에스컬레이터 모티프 임계)은 core/floor_switch_progress.dart가 단일
// 출처다.

// 도면을 화면에 맞출 때 채우는 비율은 map_camera_commands.dart가 소유한다.

// 실내 진입/이탈 임계값·오버레이 페이드 구간은 서로 얽혀 있어 한 곳에서만
// 정의한다 — indoor_entry_zoom.dart 참고. 값 하나만 옮겨도 "도면이 다 보이기
// 전에 실내에서 튕겨 나가는" 증상이나 "이탈 순간 도면이 툭 끊기는" 증상이
// 조용히 되살아나므로, 관계를 함수로 고정하고 테스트로 지킨다.

// latlong2 <-> MapLibre 타입 브릿지.
LatLng _toGl(ll.LatLng p) => LatLng(p.latitude, p.longitude);

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

/// 활강 중 마커를 다시 그리는 주기. 위젯 트리를 rebuild하지 않고 지도 소스만
/// 갱신하므로(=[_syncPdrCurrentLayer]) 이 정도 빈도를 감당할 수 있다.
/// 덮개 카드의 점은 이 값을 보간해 프레임 단위로 부드럽게 그린다.
const _escalatorGlideFrame = escalatorGlideSampleInterval;

/// 도면을 갈아 끼운 뒤 덮개를 그대로 두는 시간.
///
/// 페이드(진입 520ms · 해제 700ms)까지 더하면 화면이 가려지는 시간은 약 4.7초다.
/// 예전 400ms(총 1.6초)에서 두 번 늘렸다 — 처음엔 덮개가 크로스페이드·마커
/// 활강보다 먼저 걷혀 교체 과정이 그대로 보였고, 2026-08-13 실측에서는 도면
/// 교체가 반 층 시점으로 옮겨지며 "전환 연출을 좀 더 길게 봐도 된다"는
/// 피드백을 받았다(남은 탑승 ~10초 중 절반은 여전히 새 도면을 본다).
/// 하차까지 덮지는 않는다 — 내리기 전에 새 층 도면과 다음 경로를 봐 둬야 한다.
const _indoorFloorSwapVeilHold = Duration(milliseconds: 3500);

/// 층 이동 확정 뒤 도착 배너를 띄워 두는 시간.
const _indoorArrivalBannerHold = Duration(seconds: 6);

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
const _buildingRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

/// 목록에서 고른 매장을 볼 때의 최소 확대. 실내 화면과 같은 값이라야 두
/// 화면을 오가도 같은 크기로 보인다.
const _storeFocusZoom = 19.0;

LatLng _toMapLatLng(ll.LatLng point) => LatLng(point.latitude, point.longitude);

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

  final CompletedRouteHistory _completedRouteHistory = CompletedRouteHistory();

  GeoRouteProgress? _outdoorDisplayProgress;

  int _routeGeneration = 0;

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

  /// 실내→야외 안내에서, 건물을 나간 뒤 이어 그릴 야외 목적지
  /// ([showIndoorToOutdoorRouteTo]). 위 두 값의 거울상이다.
  ll.LatLng? _pendingOutdoorDestination;

  String? _pendingOutdoorLabel;

  /// PDR 센서 세션을 언제 켜고 끌지. 정지가 끝나기를 기다리는 일도 여기가 한다.
  late final PdrSessionLifecycle _pdrLifecycle = PdrSessionLifecycle(
    driver: indoorNavigationDriver,
    // 전역 seam을 호출 시점에 읽는다 — 테스트가 setUp에서 갈아끼운다.
    isPermissionGranted: () => isPedometerPermissionGranted(),
  );

  /// 지상 출입구가 있는 층. [_groundEntrances]와 짝이라 함께 채운다 — 출구를
  /// 실내 경로의 도착 노드로 쓰려면 좌표·노드만이 아니라 **층**도 있어야 한다.
  String? _groundEntranceFloor;

  /// 지금 그려진 경로가 자동차 경로인지. 선 모양이 이 값으로 갈린다 —
  /// 자동차는 실선, 걷기는 점선이다([geoJsonLineFeature]).
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

  bool _interactive = true;

  ll.LatLng? _userDestination;

  String? _userDestinationLabel;

  MapLibreMapController? _mapController;

  bool _styleReady = false;

  /// PDR 마커 source 갱신은 센서·보정·층 전환에서 동시에 들어올 수 있다.
  ///
  /// MapLibre의 Future는 플랫폼 쪽 반영이 끝난 뒤 완료되므로 호출을 각각
  /// fire-and-forget하면 오래된 위치 쓰기가 최신 위치 뒤에 완료될 수 있다.
  /// revision으로 대기 중인 낡은 쓰기를 건너뛰고, 이미 시작된 native 쓰기는
  /// 직렬 queue 뒤의 최신 쓰기가 반드시 덮어쓰게 한다.
  int _pdrMarkerRevision = 0;

  Future<void> _pdrMarkerWriteQueue = Future<void>.value();

  /// 회색/파란 경로 source도 센서 틱·GPS 틱·재탐색 확정에서 동시에 갱신된다.
  /// native MapLibre 쓰기가 호출 순서와 다른 순서로 완료될 수 있으므로 한 줄의
  /// queue에서 순서대로 반영한다. 이 큐가 없으면 최신 진행률로 만든 회색선이
  /// 오래된 전체 경로 쓰기에 다시 덮일 수 있다.
  Future<void> _routeLayerWriteQueue = Future<void>.value();

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

  /// 지금 세대의 실내 오버레이 소스·레이어 ID. 층 전환마다 [IndoorOverlayIds.next]
  /// 로 갈아 끼운다(세대를 쓰는 이유는 그 클래스 주석).
  IndoorOverlayIds _indoorIds = const IndoorOverlayIds();

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

  final GuidanceTrailSession _guidanceTrailSession = GuidanceTrailSession();

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

  IndoorRoute? _preTransferRoute;

  MultiFloorRoute? _preTransferMultiRoute;

  PoiSearchResult? _preTransferDestination;

  String? _pendingTransferCompletedScope;

  List<ll.LatLng>? _pendingTransferCompleted;

  GraphNode? _pendingArrivalNode;

  /// 화면을 덮는 정도. 0이 아니면 셸이 스크림을 그린다.
  ///
  /// **도면이 갈리는 앞뒤만 덮는다.** 걸음이 멈추는 순간부터 하차까지 덮어 본
  /// 적이 있는데, 그 구간은 길게는 수십 초라 화면이 계속 막힌 것으로 읽혔다.
  /// 무엇보다 사용자는 **내리기 전에** 새 층 도면과 다음 경로를 봐 둬야 한다 —
  /// 내려서야 처음 보면 그 자리에서 한 번 멈춰 서게 된다.
  ///
  /// 대신 예전(총 1.6초)보다는 길게 잡는다([_indoorFloorSwapVeilHold]). 덮개
  /// 뒤에서 크로스페이드와 마커 활강이 도는데, 그보다 먼저 걷히면 교체 장면이
  /// 그대로 보인다.
  double _floorSwapVeil = 0;

  /// 덮개를 내리기로 예약해 둔 타이머. 탑승이 먼저 끝나면 취소한다.
  Timer? _floorSwapVeilTimer;

  /// 탑승 중 마커가 흐르는 구간(탑승 노드 → 하차 노드, WGS84).
  ///
  /// 이 값이 있으면 마커 위치의 출처가 여기다. 탑승부터 하차 확정까지는 걸음이
  /// 멈춰 있고 앵커도 아직 이전 층에 있어서, 이것이 없으면 마커가 **사라진 채**
  /// 도면만 바뀐다. 근거와 한계는 [EscalatorGlide] 주석에 적었다.
  EscalatorGlide? _escalatorGlide;

  Timer? _escalatorGlideTimer;

  /// 활강 진행률(0 = 탑승 노드, 1 = 하차 노드). 층 전환 덮개의 점이 이 값을
  /// 듣는다 — 지도 위 마커와 같은 값이라 덮개를 사이에 두고도 하나의 움직임이다.
  /// 객체 정체성이 유지돼야 셸이 매 프레임 다시 그리지 않는다.
  final ValueNotifier<double> _escalatorGlideProgress = ValueNotifier(0);

  /// 기압이 정하는 활강 진행률 목표. 표시값([_escalatorGlideProgress])은 매
  /// 틱 이 값을 지수 평활로 따라간다. 노이즈로 뒤로 가지 않게 단조 증가만
  /// 허용한다 — 하차 확정이 1.0을 채운다.
  double _escalatorRideTargetProgress = 0;

  /// 도면을 교체한 순간의 이동 방향 누적 Δ(m). 진행률 정규화의 0점이다.
  double _escalatorRideSwapDeltaM = 0;

  /// 이번 활강이 가정하는 층고(m). 같은 그룹의 직전 확정 Δ가 있으면 그 값,
  /// 없으면 [escalatorDefaultFloorHeightM]이다.
  double _escalatorRideExpectedM = escalatorDefaultFloorHeightM;

  /// 에스컬레이터 그룹별 실측 층고(|확정 Δ|). 세션 동안만 산다 — 같은 건물을
  /// 도는 동안 두 번째 탑승부터 진행률이 실측 높이로 정규화된다.
  final Map<String, double> _escalatorGroupHeightM = {};

  // 사람 조작 층 전환이 오래 걸릴 때 뜨는 에스컬레이터 모티프. 아무것도 덮지
  // 않는다 — 이전 층 도면이 그대로 보이는 위에 카드 하나만 뜬다. 언제
  // 띄우고 걷을지(모티프 임계·최소 표시)는 컨트롤러가 정한다.
  bool _floorSwitchMotifVisible = false;

  /// 모티프가 마지막으로 흘렀던 방향. 숨김 전환(AnimatedSwitcher 페이드아웃)
  /// 중에도 위젯이 잠깐 더 그려지므로, 방향 없는 프레임이 생기지 않게 마지막
  /// 값을 들고 있는다.
  FloorSwitchDirection _floorSwitchMotifDirection = FloorSwitchDirection.up;

  late final FloorSwitchProgressController _floorSwitchProgress =
      FloorSwitchProgressController(onChanged: _onFloorSwitchMotifChanged);

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

  /// 도착 카드가 가리키는 목적지. 사용자가 확인을 누를 때까지 남는다.
  PoiSearchResult? _arrivedDestination;

  /// 도착 안내를 읽을 시간을 준 뒤 경로를 지우는 타이머. 살아 있다는 것 자체가
  /// "이미 카운트다운 중"이라는 상태다([decideArrivalAutoClear]).
  Timer? _arrivalRouteClearTimer;

  final GlobalKey _arrivalCardKey = GlobalKey();

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

  /// 화면 배율. `icon-size`가 **물리 픽셀**에 곱해지는 값이라 논리 px으로 잡은
  /// 마커 크기를 여기로 환산한다([indoorMarkerIconSize]).
  ///
  /// 레이어를 등록하는 코드가 여러 번의 `await` 뒤라 그 자리에서
  /// `MediaQuery.devicePixelRatioOf(context)`를 읽으면 위젯이 그 사이 사라졌을 때
  /// 터진다. 그래서 의존성이 잡히는 시점에 한 번 받아 둔다.
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
      // 사용자 회색선은 실제 PDR 궤적이 아니라 현재 계획 경로의 완료 구간이다.
      // 진행률이 바뀐 같은 틱에 경로 source도 갱신해야 파란 잔여선과 회색 완료선이
      // 같은 투영점을 공유한다. GuidanceTrailSession은 별도 진단 궤적으로만 남긴다.
      unawaited(_syncRouteLayer());
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
      unawaited(_syncRouteLayer());
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

  /// 그래프 노드 하나의 WGS84 좌표. 노드를 못 찾으면 null.
  ll.LatLng? _nodeWgs84(FloorGraph? graph, String? nodeId) {
    if (graph == null || nodeId == null || graph.nodes.isEmpty) return null;
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return null;
    final wgs84 = fitFloorGeoTransform(graph.nodes).apply(node.xM, node.yM);
    return ll.LatLng(wgs84.$1, wgs84.$2);
  }

  /// 건물 로드가 실패한 상태인지. 배지를 띄우는 유일한 근거이며, 재시도가
  /// 성공하면 [_loadBuildingEntrance]가 다시 false로 되돌린다.
  bool _buildingLoadFailed = false;

  /// 재시도 요청이 아직 도는 중인지. 연타로 요청이 겹치는 것을 막고, 배지
  /// 문구를 "다시 불러오는 중"으로 바꿔 사용자가 눌린 걸 알 수 있게 한다.
  bool _retryingBuildingLoad = false;

  int _buildingRetryAttempt = 0;

  Timer? _buildingRetryTimer;

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
  /// 나온다 — 코드를 의심하게 만드는 함정이라 훅으로 막아 둔다.
  @override
  void reassemble() {
    super.reassemble();
    unawaited(_refreshIndoorDestinationPin());
  }

  @override
  void dispose() {
    _buildingRetryTimer?.cancel();
    _gps.dispose();
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    _pdrAltitudeSub?.cancel();
    _pdrRawMotionSub?.cancel();
    _escalatorArrivalTimer?.cancel();
    _escalatorGlideTimer?.cancel();
    _arrivalRouteClearTimer?.cancel();
    _floorSwapVeilTimer?.cancel();
    _escalatorGlideProgress.dispose();
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
    _escalatorDebugText.dispose();
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
    if (!_debugModeController.enabled) {
      _gpsVerdictDebugText.value = null;
      _escalatorDebugText.value = null;
    }
    if (mounted) setState(() {});
  }

  /// 진행 중인 층 그래프 로드. 자동 실내 진입은 GPS 이벤트를 따라 발화하므로
  /// 건물이 막 도착한 직후, 즉 층 그래프 요청이 아직 도는 중에 걸릴 수 있다.
  /// 그 순간 [_floorGraph]만 보면 "그래프 없음"으로 오판해 자동 앵커를 포기하게
  /// 되므로, [_startTrackingFromEntrance]가 이 future를 먼저 기다린다.
  Future<void>? _floorGraphLoad;

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

  /// 층 전환 판정의 근거를 띄우는 칩 문구. GPS 칩과 같은 이유로 [ValueNotifier]다
  /// — 기압은 초당 여러 건 들어오므로 화면 전체를 다시 그리면 안 된다.
  final ValueNotifier<String?> _escalatorDebugText = ValueNotifier<String?>(
    null,
  );

  /// 마지막으로 나온 층 전환 진단 이벤트.
  ///
  /// 이벤트는 무슨 일이 일어난 순간에만 나온다. 들고 있지 않으면 거부 사유가
  /// 한 프레임 떴다 사라져, 정작 읽어야 할 사람이 못 읽는다.
  EscalatorDetectionEvent? _lastEscalatorEvent;

  /// 이번 실내 상태가 **자동 진입**으로 켜졌는지.
  ///
  /// 자동 이탈은 자동 진입을 되돌리기 위한 것이다. 사용자가 건물을 직접 탭해서
  /// 도면을 연 경우까지 자동으로 닫으면, 입구 앞에 서서 층 도면을 보려던 사람의
  /// 화면이 신호가 잡히는 순간 제멋대로 닫힌다.
  bool _indoorEnteredByGps = false;

  /// GPS 구독을 [_gpsTrackingWanted] 상태에 맞춘다. 구독 시작/해제의 유일한
  /// 진입점이라 중복 구독이나 해제 누락이 생기지 않는다.
  /// 위치 스트림의 수명(구독·재연결·벙어리 감시·일회성 조회)은 여기가 소유한다.
  /// 화면은 좌표를 받아 쓰기만 한다.
  late final GpsSession _gps = GpsSession(
    onFix: (position, {bool fromStream = false}) =>
        _handlePosition(position, fromStream: fromStream),
    isActive: () => mounted && _gpsTrackingWanted,
    onStreamError: _handlePositionError,
  );

  ({String scopeId, List<ll.LatLng> points})?
  _currentIndoorCompletionSnapshot() {
    final route = _indoorRouteSegment;
    final floor = _activeFloor;
    if (route == null || floor == null) return null;
    final completed = _indoorRouteVisuals(route).completed;
    if (completed.length < 2) return null;
    return (scopeId: floor, points: completed);
  }

  /// 야외 계획 경로를 현재 투영점에서 완료/잔여 구간으로 나눈다.
  ({List<ll.LatLng> completed, List<ll.LatLng> remaining}) _outdoorRouteVisuals(
    DirectionsRoute? route,
  ) {
    if (route == null || route.points.length < 2) {
      return (completed: const [], remaining: route?.points ?? const []);
    }
    final progress = _outdoorDisplayProgress;
    if (progress == null) {
      return (completed: const [], remaining: route.points);
    }
    final segment = progress.segmentIndex.clamp(0, route.points.length - 2);
    return (
      completed: [...route.points.take(segment + 1), progress.projectedPoint],
      remaining: [progress.projectedPoint, ...route.points.skip(segment + 1)],
    );
  }

  /// 현재 실내 계획 경로를 displayProgress 기준으로 나눈다.
  ///
  /// 진행률이 없거나 현재 층 그래프가 아직 준비되지 않은 동안은 파란 경로
  /// 전체를 유지한다. 회색선을 만들기 위해 위치를 임의로 경로 위에 붙이지
  /// 않는 것이 중요하다.
  ({List<ll.LatLng> completed, List<ll.LatLng> remaining}) _indoorRouteVisuals(
    IndoorRoute route,
  ) {
    if (route.points.length < 2 ||
        route.pointsLocalM.length != route.points.length) {
      return (completed: const [], remaining: route.points);
    }
    final split = splitRouteAtProgress(
      route.pointsLocalM,
      _guidance.displayProgress,
    );
    final graph = _floorGraph;
    if (split == null || graph == null || graph.nodes.isEmpty) {
      return (completed: const [], remaining: route.points);
    }
    return (
      completed: _localRoutePointsToWgs84(split.completed, graph),
      remaining: _localRoutePointsToWgs84(split.remaining, graph),
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
        locationSettings: oneShotFixSettings(),
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
    bool keepCompletedHistory = false,
  }) async {
    // 새 야외 목적지를 시작하는 진입점이다. 같은 목적지의 재탐색은
    // _updateRoute/_applyRoute로만 들어오므로, 여기서만 이전 여정을 끊는다.
    // 예외는 실내→야외 예약을 소비하는 호출뿐이다([_activatePendingOutdoorRoute]) —
    // 그건 새 여정이 아니라 **같은 여정의 다음 구간**이라, 방금 걸어온 실내
    // 층의 회색선까지 지우면 안 된다. 야외 쪽 진행률은 이 경로가 확정될 때
    // [_applyRoute]가 어차피 새로 잡는다.
    if (!keepCompletedHistory) _clearCompletedRouteHistory();
    // 문 경유 안내가 스스로를 부를 때만 pending을 지키고, 그 밖의 새 안내는
    // 이전 여정을 걷어낸다. 남겨 두면 사용자가 다른 곳으로 안내를 바꾼 뒤에
    // 건물에 들어갔을 때 지웠어야 할 실내 경로가 혼자 되살아난다.
    if (!keepPendingIndoorRoute) _clearPendingIndoorRoute();
    // 실내→야외 예약은 조건 없이 접는다. 이 호출 자체가 "새 야외 목적지"라,
    // 남겨 두면 나중에 건물을 나가는 순간 방금 지운 목적지가 되살아난다.
    // (예약을 소비하는 [_activatePendingOutdoorRoute]는 부르기 전에 이미 비운다.)
    _clearPendingOutdoorRoute();
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

  /// 건물 **안**에서 바깥 목적지까지 한 번에 안내한다. [showOutdoorToIndoorRouteTo]의
  /// 거울상이다.
  ///
  /// 실내 구간(현재 위치 → 출구)만 먼저 그리고, 야외 구간은 예약해 두었다가
  /// 사용자가 실제로 건물을 나간 순간 [_activatePendingOutdoorRoute]가 이어 붙인다.
  /// 나갔다는 판정은 GPS가 한다([_applyBuildingVerdict]의 outside 갈래) — 야외에서
  /// 들어올 때와 정확히 대칭이라, 두 방향이 같은 규칙 위에 선다.
  ///
  /// ## 출구는 목적지 기준으로 고른다
  ///
  /// 현재 위치에서 가까운 문이 아니라 **목적지에서 가까운 문**이다. 전체 이동
  /// 거리를 줄이는 쪽이 그쪽이기 때문이다 — 건물 반대편으로 나가면 실내에서 아낀
  /// 30 m를 바깥에서 200 m로 갚는다. 야외→실내가 출발지 기준으로 고르는 것과
  /// 방향만 뒤집힌 같은 원리다.
  ///
  /// ## 어디서 깨지는가
  ///
  /// - **출구 데이터가 없는 건물** → 문을 경유할 수 없다. 야외 경로만 그린다.
  ///   경로가 건물을 관통하겠지만, 안내가 아예 없는 것보다는 낫다.
  /// - **실내 위치가 없다** → 실내 구간의 출발점을 만들 수 없다.
  ///   [showIndoorRouteTo]가 "출발 위치를 먼저 지정해주세요"로 안내한다.
  /// - **실내 경로가 안 풀린다** → 예약을 걸어 두면 안 된다. 문까지 못 가는데
  ///   야외 구간만 기다리고 있으면, 나가지도 못한 채 아무 일도 안 일어난다.
  ///   그래서 예약은 실내 구간이 실제로 그려진 것을 **확인한 뒤에** 건다.
  Future<void> showIndoorToOutdoorRouteTo(
    ll.LatLng destination, {
    required String label,
  }) async {
    final exitFloor = _groundEntranceFloor;
    final exit = exitFloor == null
        ? null
        : nearestEntrance(_groundEntrances, destination);
    if (exitFloor == null || exit == null) {
      await showRouteTo(destination, label: label);
      return;
    }

    final exitLabel = entranceDirectionLabel(
      exit,
      _buildingCenter(_buildingFootprint ?? const []),
    );
    // 실내 구간은 기존 실내 라우팅을 그대로 쓴다. 출구도 노드를 가진 지점이라
    // 매장과 다를 게 없다 — 따로 만들면 층 전환·재탐색·진행률이 전부 갈라진다.
    await showIndoorRouteTo(
      PoiSearchResult(
        name: exitLabel,
        floor: exitFloor,
        point: exit.point,
        nodeId: exit.nodeId,
      ),
    );
    if (!mounted) return;
    // 실내 구간이 실제로 그려졌을 때만 야외 구간을 예약한다. 위 호출은 실패해도
    // 스낵바만 띄우고 조용히 돌아오므로, 성공 여부는 결과 상태로 확인한다.
    if (_indoorRouteDestination == null) return;
    setState(() {
      _pendingOutdoorDestination = destination;
      _pendingOutdoorLabel = label;
    });
    _showSnack('$exitLabel로 안내합니다. 건물을 나가면 바깥 경로가 이어집니다.');
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
    // 새 실내 목적지를 고른 것이므로 실내→야외 예약도 접는다. 남겨 두면 다른
    // 매장으로 안내를 바꾼 사용자가 건물을 나가는 순간 옛 야외 목적지가 뜬다.
    // ([showIndoorToOutdoorRouteTo]는 이 호출이 끝난 **뒤에** 예약을 건다.)
    _clearPendingOutdoorRoute();
    // 새 목적지를 고른 순간에는 이전 여정의 완료 이력도 함께 끝낸다. 이후
    // 실내 재탐색은 이 함수가 아니라 _computeAndShow*에서 이력을 이어 붙인다.
    _clearCompletedRouteHistory();
    // 이전 걷기 경로가 남아 있으면 함께 지워, 실내 경로만 화면에 뜨도록 한다.
    setState(() {
      _route = null;
      _userDestination = null;
      _userDestinationLabel = null;
      _indoorRouteDestination = destination;
      _arrivedDestination = null;
      // 목적지가 바뀌면 새로운 길안내다. 기존 궤적을 남기면 새 파란 경로와
      // 이전 목적지로 걸어간 회색선이 한 여정처럼 섞인다.
      _guidanceTrailSession.clear();
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
    // 아래 [_rerouteIndoorFromCurrentPosition]에서 끄고, 층 전환은 하차 지점
    // 기준으로 따로 맞춘다([_swapIndoorFloorForRide]).
    if (startFloor == endFloor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: building.id,
        floor: endFloor,
        endNodeId: endNodeId,
        playOverview: true,
        // 목적지를 새로 고른 순간 — 여기서만 진단 세션이 새로 열린다.
        beginNewRecordingSession: true,
        startNodeId: explicitStartNodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: building.id,
        startFloor: startFloor,
        endFloor: endFloor,
        endNodeId: endNodeId,
        playOverview: true,
        beginNewRecordingSession: true,
        startNodeId: explicitStartNodeId,
      );
    }
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
        leg.totalCostMeters / indoorWalkingSpeedMetersPerSecond;
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

  /// 현재 진입 상태에 맞는 오버레이 페이드 표현식.
  /// 구간이 진입 전후로 왜 다른지는 [indoorOverlayFadeExpr] 쪽 주석 참고.
  List<Object> _fadeExpr({double maxOpacity = 1}) =>
      indoorOverlayFadeExpr(entered: _indoorEntered, maxOpacity: maxOpacity);

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

  // 실내 MVT 소스·레이어는 스타일 로드와 활성 건물 로드 둘 다 되면 한 번만 등록.
  bool _indoorTilesRegistered = false;

  /// 상위(MapShellScreen)의 하단 바 리프트/ETA 카드 표시와 안내 chrome 접기가
  /// 어긋나지 않도록, 경로·목적지를 건드린 뒤 이 헬퍼로 상태 변화만 통보한다.
  /// 걷기 경로 쪽 [_applyRoute]와 같은 규칙(변화가 있을 때만 콜백)을 쓴다.
  ///
  /// 두 신호를 한 함수에서 같이 본다. 호출 지점을 나누면 목적지만 바뀌고 경로는
  /// 그대로인 순간(예: [showRouteTo] 진입 직후)에 한쪽만 통보되기 쉽다.
  bool _lastRouteVisibleNotified = false;

  bool _lastGuidanceActiveNotified = false;

  bool _indoorRerouteInFlight = false;

  int _lastIndoorRerouteAtMs = 0;

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
  /// [poiBuildingProximityMeters]에 적어 뒀다 — 실제로 "스타벅스
  /// 더현대서울(B2)R점"이 엄격 판정에서 "건물 밖"이 되어 우리 "스타벅스
  /// 리저브"와 나란히 남아 있었다.
  bool isAtIndoorBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) return false;
    return metersToPolygon(point, footprint) <= poiBuildingProximityMeters;
  }

  /// 지도를 한 지점으로 옮긴다. 검색 결과에서 고른 야외 장소를 시트가 덮기 전에
  /// 화면에 먼저 보여 주는 용도다.
  Future<void> focusPoint(ll.LatLng point) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(point), poiFocusZoom),
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
    await _fitCameraToActiveFloor(duration: floorSwitchZoomDuration);
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
    // 위(검색창·카테고리 줄)와 아래(시트)가 가리고 남는 띠의 한가운데로.
    //
    // 계산: 시트가 f를 덮고 위쪽이 t 픽셀을 덮으면 남는 띠는 [t, H(1-f)]이고
    // 그 중앙은 (t + H(1-f))/2다. 정중앙(H/2)에서 그만큼 올리면 (H·f - t)/2.
    //
    // 실기기로 확인한 `scrollBy`의 성질 두 가지를 여기 남긴다. 문서만 보고
    // 고치면 두 번 다 틀린다.
    //  1. 단위는 **논리 픽셀**이다. dpr(3배)을 곱해 보정하면 대상이 건물 밖으로
    //     날아간다.
    //  2. 부호는 **음수가 위로**다. 문서는 "양수 dy면 카메라 타깃이 남쪽으로
    //     간다"고 적혀 있어 대상이 위로 올라갈 것처럼 읽히지만, 실제로는 그만큼
    //     아래로 내려가 시트 뒤에 숨었다.
    final lift = (viewport.height * bottomSheetFraction - topInsetPx) / 2;
    if (lift <= 0) return;
    await controller.moveCamera(CameraUpdate.scrollBy(0, -lift));
  }

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

  /// 마지막으로 띄운(아직 닫히지 않은) 스낵바 문구. 같은 문구의 연속 재표시를
  /// 막는 근거다.
  String? _visibleSnackMessage;

  @override
  Widget build(BuildContext context) {
    // 어느 경로로 상태가 바뀌든 여기서 한 번 보고한다. 상태를 바꾸는 자리마다
    // 호출을 흩뿌리면 반드시 한 곳을 빠뜨리고, 그러면 배너가 남거나 안 뜬다.
    // 같은 값이면 알리지 않으므로 매 프레임 불러도 부모가 다시 그리지 않는다.
    _reportFloorTransitionUi();
    return _buildBody();
  }
}
