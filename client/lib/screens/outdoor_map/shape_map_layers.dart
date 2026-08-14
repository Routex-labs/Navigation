/// 폴리곤으로 그려지는 레이어들 — 건물 fill, 실내 진입 dim scrim, 현재 층
/// 외곽선, 매장 강조.
///
/// 넷 다 "링 하나(또는 없음)를 소스에 쓴다"가 전부다. **어떤 링을 쓸지는 화면이
/// 정한다** — 층 도면 외곽선인지 건물 외곽선인지, 지금 강조할 매장이 무엇인지는
/// 상태와 얽힌 판단이다.
///
/// 레이어 속성(색·굵기·불투명도) 자체는 [indoor_overlay_layers.dart]가 소유한다.
/// 그쪽에 모아 둔 이유(setLayerProperties가 patch가 아니라 전체 교체라는 것)는
/// 그 파일 상단 주석에 있고, 등록과 갱신이 같은 함수를 쓰게 하는 규칙도 거기서
/// 온다. 여기는 그 속성으로 **어떤 소스·레이어를 어떤 순서로 쌓는지**만 안다.
library;

import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../map/geojson.dart';
import '../../map/palette.dart';
import 'indoor_entry_zoom.dart';
import 'indoor_overlay_layers.dart';

/// 건물 폴리곤. 탭 피드백으로 fill opacity가 오르내리므로 레이어 id를 밖에
/// 연다([buildingFillProps]와 함께 쓴다).
const kOutdoorBuildingSourceId = 'outdoor-building';
const kOutdoorBuildingFillLayerId = 'outdoor-building-fill';

/// 실내 진입 dim scrim. 진입/이탈에 따라 opacity 표현식을 갈아 끼우므로 레이어
/// id를 밖에 연다.
const kOutdoorDimScrimSourceId = 'outdoor-dim-scrim';
const kOutdoorDimScrimFillLayerId = 'outdoor-dim-scrim-fill';

/// 현재 층 외곽선.
const kOutdoorFloorOutlineSourceId = 'outdoor-floor-outline';
const _floorOutlineLayerId = 'outdoor-floor-outline-line';

/// 실내 오버레이에서 매장 폴리곤을 탭했을 때 그 매장 하나만 파란색으로 채우고
/// 테두리를 두르는 전용 소스·레이어. 색은 앱의 선택 색(mapSelectionColor)
/// 하나를 쓴다.
const kOutdoorHighlightSourceId = 'outdoor-highlight';
const _highlightFillLayerId = 'outdoor-highlight-fill';
const _highlightLineLayerId = 'outdoor-highlight-line';

/// **fill 0.16은 사실상 안 보였다.** 매장 바닥(#F1EEEA)이 밝은 회색이라 16%
/// 파랑을 얹어도 "눌렀는데 아무 일도 안 일어난 것 같다"는 인상이었다. 0.35면
/// 어느 매장을 골랐는지 한눈에 들어오고, 매장 이름은 흰 헤일로를 두르고 그 위
/// 심볼 레이어에 찍히므로 여전히 읽힌다. 더 올리면 이름이 배경에 먹히기
/// 시작하므로 여기가 상한에 가깝다.
const _highlightFillOpacity = 0.35;

/// 건물 fill과 dim scrim을 등록한다.
///
/// **가장 먼저 불러야 한다.** 건물 fill은 다른 레이어(경로선·위치 점)가 위에
/// 오도록 맨 아래고, scrim은 그 바로 위여서 이후 등록되는 route/실내 MVT
/// 오버레이보다 아래에 온다 — 실내 도면은 스크림 위에 그려져 밝게 남고 야외
/// base만 어두워진다.
///
/// 외곽선은 여기 붙이지 않는다 — 실내 진입 상태에서만, 층에 따라 다른 링을
/// 그리므로 전용 소스로 뺐다([registerFloorOutlineLayer]).
Future<void> registerBuildingAndScrimLayers(
  MapLibreMapController controller, {
  required double buildingFillOpacity,
}) async {
  await controller.addSource(
    kOutdoorBuildingSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addFillLayer(
    kOutdoorBuildingSourceId,
    kOutdoorBuildingFillLayerId,
    buildingFillProps(buildingFillOpacity),
  );

  // 초기 opacity=0. geometry는 footprint가 로드된 뒤 세계 outer + 건물 hole
  // 폴리곤으로 채워진다([syncDimScrimSource]).
  await controller.addSource(
    kOutdoorDimScrimSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addFillLayer(
    kOutdoorDimScrimSourceId,
    kOutdoorDimScrimFillLayerId,
    dimScrimProps(0),
    enableInteraction: false,
  );
}

/// 현재 층 외곽선을 등록한다.
///
/// **경로선 다음에** 불러야 한다 — 실내 MVT 오버레이는 나중에
/// `belowLayerId: kOutdoorRouteCasingLayerId`로 삽입되므로, 경로선 앞(=건물
/// fill·dim scrim 옆)에 두면 불투명한 흰색 footprint fill 밑으로 깔려 선이
/// 반쯤 먹힌다. 도면 위에 얹혀야 경계가 그대로 보인다.
///
/// 페이드 표현식은 **진입 상태 램프로 고정**한다. 이 레이어는 진입했을 때만
/// 지오메트리를 갖고(그 외에는 빈 소스), 진입 상태에서만 보이므로 진입 전
/// 램프가 쓰일 일이 없다. 덕분에 상태가 바뀔 때 setLayerProperties를 다시
/// 부를 필요가 없다(전체 교체 규칙에 걸릴 여지도 사라진다).
Future<void> registerFloorOutlineLayer(
  MapLibreMapController controller,
) async {
  await controller.addSource(
    kOutdoorFloorOutlineSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    kOutdoorFloorOutlineSourceId,
    _floorOutlineLayerId,
    floorOutlineProps(indoorOverlayFadeExpr(entered: true, maxOpacity: 0.9)),
    enableInteraction: false,
  );
}

/// 매장 강조 소스·레이어를 등록한다.
///
/// PDR 마커보다 아래·경로선보다 위에 두고, 실내 오버레이 매장 fill이 나중에
/// `belowLayerId`로 이 아래에 삽입되어 강조가 매장 fill 위에 확실히 덮이도록
/// 순서를 잡는다.
Future<void> registerHighlightLayers(MapLibreMapController controller) async {
  await controller.addSource(
    kOutdoorHighlightSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addFillLayer(
    kOutdoorHighlightSourceId,
    _highlightFillLayerId,
    const FillLayerProperties(
      fillColor: mapSelectionColor,
      fillOpacity: _highlightFillOpacity,
    ),
    enableInteraction: false,
  );
  await controller.addLineLayer(
    kOutdoorHighlightSourceId,
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
}

/// 링 하나짜리 폴리곤 소스를 갱신한다. [ring]이 null이거나 점이 3개 미만이면
/// 비운다(폴리곤이 성립하지 않는다).
Future<void> syncPolygonSource(
  MapLibreMapController controller,
  String sourceId,
  List<ll.LatLng>? ring,
) async {
  if (ring == null || ring.length < 3) {
    await controller.setGeoJsonSource(sourceId, emptyGeoJsonCollection());
    return;
  }
  await controller.setGeoJsonSource(
    sourceId,
    geoJsonCollection([_polygonFeature([closedRing(ring)])]),
  );
}

/// 세계를 덮고 [hole] 만큼을 뚫은 스크림 폴리곤을 쓴다. [hole]이 없으면 비운다.
Future<void> syncDimScrimSource(
  MapLibreMapController controller,
  List<ll.LatLng>? hole,
) async {
  if (hole == null || hole.length < 3) {
    await controller.setGeoJsonSource(
      kOutdoorDimScrimSourceId,
      emptyGeoJsonCollection(),
    );
    return;
  }
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
  await controller.setGeoJsonSource(
    kOutdoorDimScrimSourceId,
    geoJsonCollection([
      _polygonFeature([worldRing, closedRing(hole.reversed.toList())]),
    ]),
  );
}

Map<String, dynamic> _polygonFeature(List<List<List<double>>> rings) => {
  'type': 'Feature',
  'properties': const <String, dynamic>{},
  'geometry': {'type': 'Polygon', 'coordinates': rings},
};

/// GeoJSON Polygon linear ring은 첫 점과 마지막 점이 같아야 한다. 백엔드가
/// 이미 닫아 보내주면 중복 추가하지 않는다.
List<List<double>> closedRing(List<ll.LatLng> points) {
  final ring = <List<double>>[
    for (final p in points) [p.longitude, p.latitude],
  ];
  if (ring.length > 1) {
    final first = ring.first;
    final last = ring.last;
    if (first[0] != last[0] || first[1] != last[1]) ring.add(first);
  }
  return ring;
}
