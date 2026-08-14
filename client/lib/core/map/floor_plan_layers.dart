/// 층 도면(`FloorPlanView`)이 스타일 로드 때 붙이는 **소스와 레이어**.
///
/// 예전에는 `_onStyleLoaded` 한 함수가 371줄이었다. 그 안에 비트맵 등록,
/// 타일 레이어, 소스·레이어 등록 스무 장, 초기 데이터 밀어넣기, 카메라 맞추기가
/// 다 들어 있었다 — `await` 51번, 지도 쓰기 31번. 무엇이 실패했는지 한 줄도
/// 짚어 주지 못하는 크기다.
///
/// 여기는 그중 **등록만** 가져온다. 등록은 화면 상태를 하나도 읽지 않는다
/// (옮기기 전에도 `widget.` 참조가 0건이었다). 그래서 컨트롤러만 있으면
/// 화면 없이 부를 수 있다.
///
/// **등록 순서가 곧 쌓임 순서다.** 아래에서 위로 완료선 → 본선 → 화살표 →
/// 전이 → 디버그 그래프 → PDR 궤적 → 마커 → 강조. 순서를 바꾸면 위치 마커가
/// 경로선 밑으로 깔린다.
library;

import 'dart:async';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../map_palette.dart';
import '../map_route_style.dart';
import './destination_pin.dart';
import './location_marker_icon.dart';
import './map_icon_cache.dart';

// 실내 MVT 소스의 zoom 범위는 indoor_entry_zoom.dart의 공용 상수를 그대로 쓴다.
// 예전에는 이 파일이 같은 값을 따로 들고 "야외 화면과 같은 값"이라고 적어 뒀지만
// 실제로는 minzoom이 16.0 vs 15.0으로 어긋나 있었다. 두 화면이 같은 백엔드
// 엔드포인트를 부르는 이상 범위가 갈리면 (1) 한쪽에서만 도면이 비고 (2) 백엔드
// 워밍업이 덮지 못하는 zoom이 생겨 그 타일만 쿼리를 새로 낸다. 값의 근거는
// indoorTilesMinZoom/indoorTilesMaxZoom 정의 위 주석에 정리되어 있다.
const kFloorPlanRouteSourceId = 'floor-route';

const kFloorPlanCompletedRouteSourceId = 'floor-completed-route';

const kFloorPlanTransferRouteSourceId = 'floor-transfer-route';

const kFloorPlanPdrTrailSourceId = 'floor-pdr-trail';

const kFloorPlanPdrPreviewTrailSourceId = 'floor-pdr-preview-trail';

const kFloorPlanPdrRawTrailSourceId = 'floor-pdr-raw-trail';

const kFloorPlanPdrConfirmedTrailSourceId = 'floor-pdr-confirmed-trail';

const kFloorPlanPdrRoninTrailSourceId = 'floor-pdr-ronin-trail';

const kFloorPlanDebugGraphSourceId = 'floor-debug-graph';

const kFloorPlanMarkersSourceId = 'floor-markers';

const kFloorPlanHighlightSourceId = 'floor-highlight';

/// 목적지 핀 이미지의 addImage 등록 이름.
// 디자인을 바꾸면 버전을 올린다 — 웹 addImage는 같은 이름이 이미 있으면
// 새 비트맵을 버려서, 이름을 그대로 두면 살아 있는 지도에 반영되지 않는다.
// v3: "도착" 글씨를 비트맵에 구워 넣었다(심볼 텍스트에서 이동).
const kFloorPlanDestinationPinImageName = 'marker-destination-pin-v3';

/// 도착 핀 iconSize의 zoom 보간 구간. "도착" 글씨가 비트맵에 구워져 있으므로
/// 이 값을 바꾸면 글씨도 같은 비율로 함께 커지고 작아진다.
const kFloorPlanDestPinIconSizeZ16 = 0.115;

const kFloorPlanDestPinIconSizeZ20 = 0.25;

/// 현재 위치 심볼의 addImage 등록 이름. **이름 끝에 코어 반지름을 박아 둔다.**
///
/// maplibre_gl 웹 구현의 addImage는 같은 이름이 이미 등록돼 있으면 새 비트맵을
/// 버리고 조용히 건너뛴다(`if (!_map.hasImage(name))` … `else { print(...) }`,
/// maplibre_web_gl_platform.dart). 게다가 이 패키지의 플랫폼 인터페이스에는
/// removeImage가 없어서 이미 등록된 이름을 지울 방법도 없다. 그래서 이름이
/// 고정이면, 살아 있는 지도 인스턴스에 예전 크기의 비트맵이 그대로 남아
/// 디자인을 바꿔도 화면이 안 바뀐다. 반지름을 이름에 넣어 두면 디자인이 바뀔
/// 때 이름도 함께 바뀌므로 항상 새 비트맵으로 등록된다.
const kFloorPlanCurrentLocationImageName =
    'marker-current-location-r$kLocationMarkerIconCoreRadius';

const kFloorPlanCurrentLocationDotImageName =
    'marker-current-location-dot-r$kLocationMarkerIconCoreRadius';

/// 현재 위치 심볼 레이어 id.
const kFloorPlanCurrentMarkerLayerId = 'floor-markers-current';

/// 목적지 핀 심볼 레이어 id. 현재 위치 레이어를 다시 등록할 때 이 레이어 아래로
/// 넣어야 원래의 위/아래 순서(목적지 핀이 위)가 유지된다.
const kFloorPlanDestinationMarkerLayerId = 'floor-markers-destination-pin';

/// 현재 위치 심볼 레이어의 filter. 마커 소스에는 목적지도 함께 들어오므로
/// `kind`로 걸러낸다. 레이어를 다시 등록할 때 이 filter를 빠뜨리면 목적지
/// 좌표에도 파란 도트가 찍힌다.
const kFloorPlanCurrentMarkerFilter = <Object>[
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
const kFloorPlanCurrentLocationSymbolProps = SymbolLayerProperties(
  iconImage: [
    'case',
    ['has', 'heading'],
    kFloorPlanCurrentLocationImageName,
    kFloorPlanCurrentLocationDotImageName,
  ],
  iconSize: kLocationMarkerIconSize,
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

const kFloorPlanEmptyGeoJson = {
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[],
};

/// 층 도면의 소스와 레이어를 전부 등록한다. 스타일 로드마다 한 번.
Future<void> registerFloorPlanLayers(MapLibreMapController controller) async {
    await controller.addGeoJsonSource(
      kFloorPlanCompletedRouteSourceId,
      kFloorPlanEmptyGeoJson,
    );
    await controller.addLineLayer(
      kFloorPlanCompletedRouteSourceId,
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
    await controller.addGeoJsonSource(kFloorPlanRouteSourceId, kFloorPlanEmptyGeoJson);
    // casing → 본선 → 화살표 순으로 얹는다. 값과 근거는 [map_route_style.dart].
    await controller.addLineLayer(
      kFloorPlanRouteSourceId,
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
      kFloorPlanRouteSourceId,
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
      kFloorPlanRouteSourceId,
      'floor-route-arrow',
      routeArrowProps(),
      enableInteraction: false,
    );
    await controller.addGeoJsonSource(
      kFloorPlanTransferRouteSourceId,
      kFloorPlanEmptyGeoJson,
    );
    await controller.addLineLayer(
      kFloorPlanTransferRouteSourceId,
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
      kFloorPlanDebugGraphSourceId,
      kFloorPlanEmptyGeoJson,
    );
    await controller.addLineLayer(
      kFloorPlanDebugGraphSourceId,
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
      kFloorPlanDebugGraphSourceId,
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
      kFloorPlanDebugGraphSourceId,
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
      kFloorPlanDebugGraphSourceId,
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
      kFloorPlanPdrRawTrailSourceId,
      kFloorPlanEmptyGeoJson,
    );
    await controller.addLineLayer(
      kFloorPlanPdrRawTrailSourceId,
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
      kFloorPlanPdrConfirmedTrailSourceId,
      kFloorPlanEmptyGeoJson,
    );
    await controller.addLineLayer(
      kFloorPlanPdrConfirmedTrailSourceId,
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
      kFloorPlanPdrConfirmedTrailSourceId,
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
      kFloorPlanPdrRoninTrailSourceId,
      kFloorPlanEmptyGeoJson,
    );
    await controller.addLineLayer(
      kFloorPlanPdrRoninTrailSourceId,
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
      kFloorPlanPdrRoninTrailSourceId,
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
      kFloorPlanPdrTrailSourceId,
      kFloorPlanEmptyGeoJson,
    );
    // 그래프에 부착한 경로는 raw(주황)·confirmed(초록)와 겹쳐도 구별되도록
    // 보라색으로 그린다. 세 소스가 독립적이라 디버그 설정에서 각각 끌 수 있다.
    await controller.addLineLayer(
      kFloorPlanPdrTrailSourceId,
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
      kFloorPlanPdrTrailSourceId,
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
      kFloorPlanPdrPreviewTrailSourceId,
      kFloorPlanEmptyGeoJson,
    );
    await controller.addLineLayer(
      kFloorPlanPdrPreviewTrailSourceId,
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
      kFloorPlanMarkersSourceId,
      kFloorPlanEmptyGeoJson,
    );

    // 목적지 핀 레이어보다 먼저 등록해, 겹칠 때 목적지 핀이 위에 오게 한다.
    await addFloorPlanCurrentLocationLayer(controller);

    await addFloorPlanDestinationPinLayer(controller);

    await controller.addGeoJsonSource(
      kFloorPlanHighlightSourceId,
      kFloorPlanEmptyGeoJson,
    );
    // 선택된 매장을 옅게 채우고 테두리 선 색을 진하게 바꿔서 "포커스"가
    // 어디 있는지 보여준다. 매장 탭/검색으로 고른 매장이 바뀔 때마다
    // _updateHighlightSource가 이 소스의 폴리곤만 바꿔치기한다.
    await controller.addFillLayer(
      kFloorPlanHighlightSourceId,
      'floor-highlight-fill',
      const FillLayerProperties(
        fillColor: mapSelectionColor,
        fillOpacity: 0.16,
      ),
      enableInteraction: false,
    );
    await controller.addLineLayer(
      kFloorPlanHighlightSourceId,
      'floor-highlight-line',
      const LineLayerProperties(
        lineColor: mapSelectionColor,
        // 두꺼운 파란 테두리는 옆 매장까지 덮어 지도 가독성을 해쳤다. 채움
        // 색으로도 포커스를 충분히 표현하므로, 테두리는 매장 경계선을 아주
        // 살짝 진하게 하는 정도로만 남긴다.
        lineWidth: 1.2,
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );

}

/// 현재 위치 비트맵을 등록하고 심볼 레이어를 얹는다.
///
/// 비트맵 이름에 코어 반지름이 들어 있으므로([kFloorPlanCurrentLocationImageName]),
/// 크기를 바꿨다면 새 이름이라 웹 addImage의 "이미 있으면 건너뛰기"에 걸리지
/// 않는다. 크기를 안 바꿨다면 같은 이름이라 건너뛰고 로그만 남는다.
Future<void> addFloorPlanCurrentLocationLayer(
  MapLibreMapController controller, {
  String? belowLayerId,
}) async {
  await controller.addImage(
    kFloorPlanCurrentLocationImageName,
    await cachedIconPng(
      kFloorPlanCurrentLocationImageName,
      () => renderLocationMarkerIcon(showHeading: true),
    ),
  );
  await controller.addImage(
    kFloorPlanCurrentLocationDotImageName,
    await cachedIconPng(
      kFloorPlanCurrentLocationDotImageName,
      () => renderLocationMarkerIcon(showHeading: false),
    ),
  );
  await controller.addSymbolLayer(
    kFloorPlanMarkersSourceId,
    kFloorPlanCurrentMarkerLayerId,
    kFloorPlanCurrentLocationSymbolProps,
    filter: kFloorPlanCurrentMarkerFilter,
    belowLayerId: belowLayerId,
    enableInteraction: false,
  );
}

/// 목적지 핀 심볼 레이어를 얹는다.
///
/// 도형과 글씨를 나눠 그리는 이유, 치수와 textOffset 유도, `text-font`를 반드시
/// 명시해야 하는 이유는 전부 [destination_pin.dart]에 있다.
///
/// 현재 위치는 같은 소스에 함께 들어와 있어도 filter가 걸러낸다.
Future<void> addFloorPlanDestinationPinLayer(
  MapLibreMapController controller,
) async {
  await controller.addSymbolLayer(
    kFloorPlanMarkersSourceId,
    kFloorPlanDestinationMarkerLayerId,
    destinationPinSymbolProps(
      imageName: kFloorPlanDestinationPinImageName,
      iconSizeZ16: kFloorPlanDestPinIconSizeZ16,
      iconSizeZ20: kFloorPlanDestPinIconSizeZ20,
    ),
    filter: [
      '==',
      ['get', 'kind'],
      'destination',
    ],
    enableInteraction: false,
  );
}
