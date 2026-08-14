/// 야외 지도 위 실내 오버레이 레이어의 **완성된** 속성 묶음.
///
/// 화면 코드에서 분리해 둔 이유는 [indoor_entry_zoom.dart]와 같다 — 규칙을
/// 함수로 고정하고 테스트로 지키기 위해서다. 여기서 지켜야 하는 규칙은 하나다.
///
/// ## setLayerProperties는 patch가 아니라 **전체 교체**다
///
/// `MapLibreMapController.setLayerProperties`는 넘긴 객체를
/// `toJson(skipNulls: false)`로 직렬화한다. 즉 **설정하지 않은 속성도 전부
/// `null`로 함께 전송된다.** Android 네이티브(`LayerPropertyConverter`)는 그
/// null을 "값 없음"으로 무시하지 않고 `PropertyFactory.fillColor(null)`처럼
/// 그대로 적용하고, MapLibre 코어는 그 속성을 **스펙 기본값**으로 되돌린다.
///
/// `fill-color`의 스펙 기본값은 **`#000000`(검정)** 이다. 그래서
/// `FillLayerProperties(fillOpacity: ...)`처럼 opacity만 넘기면 실내 오버레이의
/// 흰색 footprint(`#FFFFFF`)가 **불투명한 검정 덩어리**로 바뀌어 건물 전체를
/// 덮는다 — 실기기에서 지도가 검게 뜨던 원인이다. 심볼 레이어도 마찬가지로
/// `text-field`·`icon-image` 같은 layout 속성까지 null이 되어 라벨과 아이콘이
/// 통째로 사라진다.
///
/// **웹(maplibre_gl_web)은 이 경로가 달라 증상이 안 보인다.** Chrome에서만
/// 확인하면 절대 못 잡으므로, 규칙을 테스트로 못 박아 둔다.
///
/// 따라서 최초 등록(`addFillLayer`/`addSymbolLayer`)과 갱신
/// (`setLayerProperties`)이 **같은 함수**를 쓴다. 한쪽만 고쳐 어긋나는 일을
/// 구조적으로 막는 게 이 파일의 목적이다.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show Color;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/map_fonts.dart';
import '../../core/map_label_style.dart';
import '../../core/map_palette.dart';
import '../../theme/app_theme.dart';
import '../../core/map/category_map_fill.dart';
import '../../core/map/category_map_filter.dart';
import '../../core/map/category_map_icon.dart';
import '../../core/map/floor_facility_style.dart';
import 'indoor_entry_zoom.dart' show indoorTilesMaxZoom, indoorTilesMinZoom;
import 'route_map_layers.dart' show kOutdoorRouteCasingLayerId;

/// `Color`를 MapLibre가 받는 `#RRGGBB` 문자열로. 알파는 별도 opacity 속성으로
/// 주므로 여기서는 RGB만 쓴다.
extension MapColorHex on Color {
  String toHexString() {
    final rgb =
        (r * 255).round() << 16 | (g * 255).round() << 8 | (b * 255).round();
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// 야외 건물 폴리곤 fill. 탭 피드백으로 opacity만 오르내리지만, 그때도 색을
/// 반드시 함께 넘겨야 한다(파일 상단 규칙).
FillLayerProperties buildingFillProps(double opacity) => FillLayerProperties(
  fillColor: AppColors.primary.toHexString(),
  fillOpacity: opacity,
);

/// 실내 진입 상태에서만 그리는 현재 층 외곽선.
///
/// 실내 도면 **위에** 얹히는 선이라 얇게(1px) 긋는다. 굵게 그으면 도면 가장자리
/// 매장을 덮고, 지하처럼 외곽이 들쭉날쭉한 층에서는 선 자체가 도면처럼 읽힌다.
///
/// 어느 링을 따라갈지는 [floor_outline.dart]가 정한다. 그 링은 바로 아래
/// [indoorFootprintProps]가 칠하는 타일 `footprint`와 **같은 층 footprint**에서
/// 나온다 — 선과 바닥이 다른 데이터에서 나오면 층마다 경계가 미세하게 어긋난다
/// (그렇게 어긋났던 경위는 [floor_outline.dart] 상단 주석 참고).
LineLayerProperties floorOutlineProps(List<Object> fadeExpr) =>
    LineLayerProperties(
      lineColor: AppColors.primary.toHexString(),
      lineWidth: 1,
      lineOpacity: fadeExpr,
      lineJoin: 'round',
    );

/// 실내 진입 dim scrim. 세계를 덮는 outer ring + 건물 hole 폴리곤을 칠한다.
FillLayerProperties dimScrimProps(Object fillOpacity) =>
    FillLayerProperties(fillColor: '#000000', fillOpacity: fillOpacity);

FillLayerProperties indoorFootprintProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: mapFootprintFill,
      fillOutlineColor: mapFootprintOutline,
      fillOpacity: fadeExpr,
    );

/// 실내 오버레이의 매장 fill. 실내 화면(`FloorPlanView`)과 **같은 기본 색**이다.
/// 두 화면이 같은 MVT `stores` 레이어를 보는데 색이 다르면 같은 매장이 야외
/// 오버레이와 실내 화면에서 다르게 읽힌다.
FillLayerProperties indoorStoresFillProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: mapStoreFill,
      fillOutlineColor: mapStoreOutline,
      fillOpacity: fadeExpr,
    );

/// 카테고리 필터로 강조된 매장 fill.
///
/// 색은 실내 화면과 **같은 표현식**([category_map_fill.dart])을 써서 선택한
/// 대분류의 색으로 칠한다. 두 화면이 같은 MVT `stores` 레이어를 보는데 강조색이
/// 다르면, 같은 매장이 야외 오버레이에서와 실내 화면에서 다른 색으로 보인다.
///
/// 다른 점은 **opacity를 fadeExpr로 묶는다**는 것뿐이다. 야외 오버레이는 줌에
/// 따라 통째로 페이드인/아웃되므로, 강조만 불투명하게 두면 도면이 아직 안 보이는
/// 줌에서 강조 폴리곤만 공중에 뜬다.
FillLayerProperties indoorCategoryHighlightProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: storeCategoryHighlightFillColorExpression(),
      fillOutlineColor: storeCategoryHighlightOutlineExpression(),
      fillOpacity: fadeExpr,
    );

FillLayerProperties indoorVerticalTransportProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: '#DCEBD4',
      fillOutlineColor: '#6FA167',
      fillOpacity: fadeExpr,
    );

/// 매장명 라벨 + 대분류 아이콘.
///
/// 아이콘을 별도 레이어로 두지 않고 같은 심볼에 얹는 이유, 이름이 아이콘 앞/뒤로
/// 뒤집히는 방식과 그 한계는 [category_map_icon.dart]에 적어 두었다. 실내 화면
/// (`FloorPlanView`)과 **같은 표현식·같은 앵커 규칙**을 써야 두 화면 사이에서
/// 같은 매장이 다른 아이콘을 달지 않는다.
///
/// [selection]은 지금 고른 카테고리다. 실내 화면과 마찬가지로 선택이 있으면 그
/// 매장만 이름을 달고 나머지는 아이콘만 남는다([categoryLabelTextField]).
/// **호출하는 쪽이 모두 지금 선택을 넘겨야 한다** — 이 함수는 페이드 갱신
/// (`_syncIndoorOverlayFade`)에서도 불리는데, 거기서 선택을 빼먹으면 줌만
/// 움직여도 가려 뒀던 이름이 되살아난다(파일 상단의 "전체 교체" 규칙이 layout
/// 속성에도 그대로 적용되는 경우다).
///
/// [devicePixelRatio]는 아이콘 크기를 논리 px으로 환산하는 데 쓴다 —
/// [indoorMarkerIconSize] 주석 참고. 호출하는 쪽이 화면에서 읽어 넘긴다.
/// [alwaysVisible]은 **한 폴리곤을 여러 매장이 나눠 쓰는 자리**(타일 라벨의
/// `shared` 속성) 전용이다. 백엔드가 라벨 점을 흩어 놓아도 간격이 글자 폭보다
/// 좁을 수 있어, 충돌 판정에 맡기면 결국 하나가 지워진다 — 그러면 화면에는
/// 이름 하나만 보이는데 그 자리에는 매장이 둘이라, 보이는 이름과 열리는 매장이
/// 어긋난다. 같은 자리에 둘이 있다는 사실 자체가 정보이므로 이 라벨들은 조금
/// 겹치더라도 전부 그린다(전체 1,640곳 중 91곳뿐이라 겹침이 번지지 않는다).
SymbolLayerProperties indoorStoresLabelProps(
  List<Object> fadeExpr,
  CategorySelection? selection,
  double devicePixelRatio, {
  bool alwaysVisible = false,
}) => SymbolLayerProperties(
  textField: categoryLabelTextField(selection),
  textFont: const [mapFontStackRegular],
  // 색·헤일로·크기 전부 [map_label_style.dart]가 단일 출처다. 크기가 고정인
  // 이유는 이 오버레이가 도면 전체를 훑는 축소 화면이라, 폴리곤 맞춤 크기를
  // 쓰면 작은 매장 이름이 읽을 수 없게 작아지기 때문이다.
  textSize: mapLabelFixedTextSize,
  textColor: mapLabelStoreColor,
  textHaloColor: mapLabelHaloColor,
  textHaloWidth: mapLabelHaloWidth,
  textMaxWidth: mapLabelFixedMaxWidth,
  textOpacity: fadeExpr,
  iconImage: storeCategoryIconExpression(),
  // 화장실·정수기 같은 시설 아이콘과 **같은 크기 하나**를 쓴다
  // ([kIndoorMarkerLogicalPx]). 실내 화면이 같은 피드백("대분류 아이콘을
  // 화장실만큼")으로 이미 내린 결론인데 이 오버레이만 따라오지 않았다.
  iconSize: indoorMarkerIconSize(devicePixelRatio),
  iconOpacity: fadeExpr,
  // 이름은 항상 아이콘 아래다 — 실내 도면·편의시설 라벨과 같은 규칙.
  textAnchor: 'top',
  textOffset: mapLabelBelowIconOffset,
  textJustify: 'center',
  textAllowOverlap: alwaysVisible,
  iconAllowOverlap: alwaysVisible,
  // 자리가 없으면 아이콘·이름 중 하나만이라도 남긴다. iconOptional이 없으면
  // 심볼이 넓어진 만큼 이름이 밀려난다(실내 화면 주석의 실측 참고).
  // alwaysVisible에서는 반대로 **아무것도 포기하지 않는다** — 포기가 곧
  // "매장이 지도에서 사라짐"인 자리다.
  textOptional: !alwaysVisible,
  iconOptional: !alwaysVisible,
);

/// 편의시설의 텍스트 전용 라벨. 아이콘은 [indoorFacilityIconProps]가 그린다.
///
/// [selection]은 매장명 라벨과 같은 규칙으로 쓴다 — 아이콘이 다른 레이어에 있을
/// 뿐 화면에서는 이름 달린 폴리곤 하나라, 여기만 예외로 두면 고른 카테고리
/// 이외의 시설 이름이 그대로 남는다. 호출하는 쪽이 모두 지금 선택을 넘겨야
/// 하는 이유도 [indoorStoresLabelProps]와 같다.
SymbolLayerProperties indoorFacilityLabelProps(
  List<Object> fadeExpr,
  CategorySelection? selection,
) => SymbolLayerProperties(
  textField: categoryLabelTextField(selection),
  textFont: const [mapFontStackRegular],
  textSize: mapLabelFixedTextSize,
  textColor: mapLabelFacilityColor,
  textHaloColor: mapLabelHaloColor,
  textHaloWidth: mapLabelHaloWidth,
  textMaxWidth: mapLabelFixedMaxWidth,
  textOpacity: fadeExpr,
  // 아이콘이 centroid를 차지하므로 이름은 아래로 내린다.
  textOffset: mapLabelBelowIconOffset,
  textAllowOverlap: false,
);

SymbolLayerProperties indoorPoiIconProps(
  List<Object> fadeExpr,
  double devicePixelRatio,
) => SymbolLayerProperties(
  iconImage: [
    'match',
    ['get', 'type'],
    for (final entry in kPoiIconByType.entries) ...[
      entry.key,
      poiIconImageName(entry.value),
    ],
    poiIconImageName(kDefaultPoiIcon),
  ],
  iconSize: indoorMarkerIconSize(devicePixelRatio),
  iconOpacity: fadeExpr,
  iconAllowOverlap: true,
);

SymbolLayerProperties indoorFacilityIconProps(
  List<Object> fadeExpr,
  double devicePixelRatio,
) => SymbolLayerProperties(
  iconImage: [
    'match',
    ['get', 'name'],
    for (final entry in kStoreFacilityStyleByName.entries) ...[
      entry.key,
      facilityIconImageName(entry.key),
    ],
    poiIconImageName(kDefaultPoiIcon),
  ],
  iconSize: indoorMarkerIconSize(devicePixelRatio),
  iconOpacity: fadeExpr,
  iconAllowOverlap: true,
  // iconOffset 없음 = 폴리곤 중심(centroid)에 그린다. 실내 화면
  // (`FloorPlanView`)의 편의시설 아이콘과 같은 기준이라 두 화면 사이에서
  // 아이콘 위치가 어긋나지 않는다.
);

/// 실내 오버레이 소스·레이어의 **한 세대**분 실제 ID 묶음.
///
/// 층을 바꿀 때마다 세대(generation) 카운터를 베이스 이름 뒤에 붙여 매번 다른
/// 실제 ID를 만든다 — 같은 ID로 removeSource → addSource를 반복하면 maplibre_gl
/// native(Android/iOS)가 이전 소스 정리를 스케줄만 한 채 리턴해 곧이은 addSource가
/// "source already exists"로 조용히 실패하는 사례가 있었다(특정 층으로 전환 시
/// 아무것도 안 그려지는 증상). 세대 카운터로 실제 ID를 유일하게 만들면 native
/// cleanup 경쟁이 사라진다.
///
/// 화면이 필드 11개로 들고 있던 것을 값 하나로 묶었다. 세대가 바뀔 때 하나라도
/// 빠뜨리면 그 레이어만 이전 세대 ID로 남아 remove 대상에서 새는데, 묶어 두면
/// [next]가 전부를 한 번에 넘긴다.
class IndoorOverlayIds {
  const IndoorOverlayIds([this.generation = 0]);

  final int generation;

  /// 다음 세대. 반드시 이전 세대의 remove **이후**, 다음 세대의 add **전에**
  /// 갈아 끼운다.
  IndoorOverlayIds next() => IndoorOverlayIds(generation + 1);

  String _idFor(String base) => '$base-g$generation';

  String get source => _idFor('outdoor-indoor-tiles');
  String get footprint => _idFor('outdoor-indoor-footprint');
  String get storesFill => _idFor('outdoor-indoor-stores-fill');

  /// 카테고리 필터로 고른 매장만 파란톤으로 덧칠하는 fill. 일반 매장 fill 위,
  /// 수직이동 오버레이 아래에 넣어 실내 화면과 레이어 순서를 맞춘다 — 순서가
  /// 어긋나면 같은 선택인데 두 화면에서 강조가 다른 것에 가려진다.
  String get categoryHighlightFill =>
      _idFor('outdoor-indoor-category-highlight-fill');

  /// 수직이동(에스컬레이터/엘리베이터) 구조물 폴리곤을 초록톤으로 덧칠하는 fill.
  /// [storesFill] 위, 라벨/아이콘보다 아래에 삽입해 초록 배경 + 라벨/아이콘이 한
  /// 덩어리로 읽히게 한다.
  String get verticalTransportFill =>
      _idFor('outdoor-indoor-vertical-transport-fill');

  String get storesLabel => _idFor('outdoor-indoor-stores-label');

  /// 한 폴리곤을 여러 매장이 나눠 쓰는 자리의 라벨 전용 레이어. 타일 라벨의
  /// `shared` 속성으로 갈라내고, 충돌 판정을 꺼서 이름이 지워지지 않게 한다
  /// ([indoorStoresLabelProps]의 alwaysVisible).
  String get sharedStoresLabel => _idFor('outdoor-indoor-stores-label-shared');

  /// 편의시설(화장실·정수기 등)의 텍스트 전용 라벨. 매장명 라벨에는 대분류
  /// 아이콘이 붙는데, 시설은 이미 전용 아이콘 레이어가 있어 두 아이콘이 겹친다.
  /// 그래서 이름만 따로 그린다.
  String get facilityLabel => _idFor('outdoor-indoor-store-facility-label');

  /// POI(엘리베이터·에스컬레이터·화장실 등 `pois` 소스 레이어) 위 아이콘 심볼.
  String get poiIcon => _idFor('outdoor-indoor-pois-icon');

  /// `stores` 소스 레이어에 이름으로 매칭되는 편의시설 위 아이콘 심볼.
  String get storeFacilityIcon =>
      _idFor('outdoor-indoor-store-facility-icons');

  /// 현재 세대의 레이어 ID 목록(위→아래 순). removeLayer 순서로 그대로 쓸 수
  /// 있다 — 레이어는 반드시 소스보다 먼저 제거해야 한다.
  List<String> get layersTopFirst => [
    storeFacilityIcon,
    poiIcon,
    facilityLabel,
    sharedStoresLabel,
    storesLabel,
    verticalTransportFill,
    categoryHighlightFill,
    storesFill,
    footprint,
  ];
}

/// 실내 오버레이 소스와 레이어 9장을 한 번에 등록한다. 성공하면 true.
///
/// 등록 **순서가 곧 쌓임 순서**다. 아래에서 위로 footprint → 매장 fill →
/// 카테고리 강조 → 수직이동 → 라벨 → 아이콘이고, 전부 route casing 바로
/// 아래에 넣는다. 순서를 바꾸면 경로선·GPS 마커가 매장 fill 밑으로 깔려
/// 화면에서 사라진다(아래 주석 참고).
///
/// [ensureIconImages]는 아이콘 비트맵 등록이다. 호출자가 "스타일당 한 번"
/// 게이팅을 들고 있어 콜백으로 받는다 — 여기서 매번 부르면 층을 바꿀 때마다
/// 비트맵을 다시 렌더한다.
///
/// 실패하면 부분 등록된 것을 스스로 정리하고 false를 돌려준다. 소스/레이어 등록은
/// native 쪽에서 조용히 예외를 던지고 pending 상태로 남을 때가 있어(스타일 미준비·
/// 잘못된 expression 등), 정리하지 않으면 다음 호출이 addSource를 다시 시도하며
/// "source already exists"로 폭발한다.
Future<bool> registerIndoorOverlayLayers(
  MapLibreMapController controller, {
  required IndoorOverlayIds ids,
  required String tileUrl,
  required List<Object> fadeExpr,
  required List<Object> categoryFilter,
  required CategorySelection? categorySelection,
  required double devicePixelRatio,
  required Future<void> Function(MapLibreMapController) ensureIconImages,
}) async {
    try {
      await controller.addSource(
        ids.source,
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
      await ensureIconImages(controller);
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
        ids.source,
        ids.footprint,
        indoorFootprintProps(fadeExpr),
        sourceLayer: 'footprint',
        belowLayerId: kOutdoorRouteCasingLayerId,
        enableInteraction: false,
      );
      await controller.addFillLayer(
        ids.source,
        ids.storesFill,
        indoorStoresFillProps(fadeExpr),
        sourceLayer: 'stores',
        belowLayerId: kOutdoorRouteCasingLayerId,
        enableInteraction: false,
      );
      // 카테고리 강조. 일반 매장 fill 바로 위에 얹어 선택한 매장만 파랗게
      // 덮는다. 선택이 없을 때도 레이어는 남겨 두고 아무것도 맞지 않는 필터를
      // 걸어 둔다 — 이유는 kCategoryHighlightNoneFilter 주석.
      await controller.addFillLayer(
        ids.source,
        ids.categoryHighlightFill,
        indoorCategoryHighlightProps(fadeExpr),
        sourceLayer: 'stores',
        belowLayerId: kOutdoorRouteCasingLayerId,
        filter: categoryFilter,
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
        ids.source,
        ids.verticalTransportFill,
        indoorVerticalTransportProps(fadeExpr),
        sourceLayer: 'stores',
        belowLayerId: kOutdoorRouteCasingLayerId,
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
        ids.source,
        ids.storesLabel,
        indoorStoresLabelProps(
          fadeExpr,
          categorySelection,
          devicePixelRatio,
        ),
        // **폴리곤이 아니라 라벨 전용 점 레이어를 본다.** MapLibre는 폴리곤
        // 심볼을 면적 무게중심에 찍는데, ㄱ자·길쭉한 매장에서 그 점이 눈에
        // 보이는 가운데가 아니다(백엔드 `label_point.py` 주석에 실측을 적었다).
        // 백엔드가 폴리곤마다 "라벨 놓을 자리"를 계산해 이 레이어로 내려준다.
        sourceLayer: 'store_labels',
        // 한 폴리곤을 나눠 쓰는 자리(`shared`)는 아래 전용 레이어가 그린다.
        // 두 레이어가 같은 feature를 그리면 이름이 두 번 찍힌다.
        filter: [
          'all',
          storeLabelWithCategoryIconFilter(),
          [
            '!',
            ['has', 'shared'],
          ],
        ],
        belowLayerId: kOutdoorRouteCasingLayerId,
        enableInteraction: false,
      );
      // 한 폴리곤을 여러 매장이 나눠 쓰는 자리 전용. 백엔드가 라벨 점을 흩어
      // 놓았지만(`tiling._shared_label_points`) 간격이 글자 폭보다 좁을 수
      // 있어, 충돌 판정에 맡기면 결국 하나가 지워진다 — 오설록만 보이는데
      // 일상다완이 열리던 증상. 충돌 판정을 끄고 전부 그린다.
      await controller.addSymbolLayer(
        ids.source,
        ids.sharedStoresLabel,
        indoorStoresLabelProps(
          fadeExpr,
          categorySelection,
          devicePixelRatio,
          alwaysVisible: true,
        ),
        sourceLayer: 'store_labels',
        filter: [
          'all',
          storeLabelWithCategoryIconFilter(),
          ['has', 'shared'],
        ],
        belowLayerId: kOutdoorRouteCasingLayerId,
        enableInteraction: false,
      );
      // 편의시설은 이름만 — 아이콘은 아래 ids.storeFacilityIcon가
      // 그린다. 위 레이어에 섞으면 아이콘이 두 개 뜬다.
      await controller.addSymbolLayer(
        ids.source,
        ids.facilityLabel,
        indoorFacilityLabelProps(fadeExpr, categorySelection),
        // 매장명 라벨과 같은 이유로 라벨 점 레이어를 본다.
        sourceLayer: 'store_labels',
        filter: facilityStoreLabelFilter(),
        belowLayerId: kOutdoorRouteCasingLayerId,
        enableInteraction: false,
      );
      // POI(엘리베이터·에스컬레이터·화장실 등) 심볼 레이어. `pois` 소스 레이어에
      // 있는 feature의 type 속성으로 아이콘을 골라 얹는다. iconOpacity를 fadeExpr
      // 로 묶어 오버레이와 같은 줌 구간에서 함께 페이드인된다.
      await controller.addSymbolLayer(
        ids.source,
        ids.poiIcon,
        indoorPoiIconProps(fadeExpr, devicePixelRatio),
        sourceLayer: 'pois',
        belowLayerId: kOutdoorRouteCasingLayerId,
        enableInteraction: false,
      );
      // 편의시설 아이콘: 화장실·정수기 같은 시설물은 백엔드에서 `pois`가 아니라
      // 매장으로 들어오므로 POI 아이콘 레이어를 타지 않는다. 이름을 기준으로
      // 심볼을 하나 더 얹어 아이콘이 붙게 한다. 이름은 위 편의시설 라벨
      // 레이어가 같은 점에 아래로 그린다.
      await controller.addSymbolLayer(
        ids.source,
        ids.storeFacilityIcon,
        indoorFacilityIconProps(fadeExpr, devicePixelRatio),
        // 이름과 아이콘이 **같은 점**에 놓여야 한다. 하나만 라벨 점 레이어로
        // 옮기면 아이콘과 이름이 매장 안 서로 다른 자리에 뜬다.
        sourceLayer: 'store_labels',
        belowLayerId: kOutdoorRouteCasingLayerId,
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
      return true;
    } catch (error, stack) {
      debugPrint('[outdoor overlay] MVT register FAILED: $error\n$stack');
      // 부분 추가된 소스/레이어를 정리해 다음 호출이 깨끗한 상태에서 다시
      // 시도할 수 있게 한다. 각 remove가 실패해도(안 붙어있어서) 조용히 넘긴다.
      for (final id in ids.layersTopFirst) {
        try {
          await controller.removeLayer(id);
        } catch (_) {}
      }
      try {
        await controller.removeSource(ids.source);
      } catch (_) {}
      return false;
    }
}

/// [syncIndoorOverlayProps]가 어떤 레이어까지 다시 밀지.
enum IndoorOverlaySyncScope {
  /// 등록된 오버레이 레이어 전부.
  all,

  /// 매장명·공유 매장명·편의시설 라벨 세 장.
  labels,

  /// footprint·매장·카테고리 강조·수직이동 fill 네 장.
  fills,
}

/// 이미 등록된 오버레이 레이어의 속성을 지금 상태로 갈아 끼운다.
///
/// **각 레이어의 전체 속성을 매번 다시 넘긴다.** opacity만 넘기면 안 된다 —
/// 이유는 이 파일 상단 주석 참고(설정하지 않은 속성이 스펙 기본값으로 되돌아가
/// 도면이 검게 뜬다).
///
/// [scope]로 갱신 범위를 좁힌다. 전부 다시 밀 필요가 없는 경우가 둘 있다.
///  - [IndoorOverlaySyncScope.labels] — 카테고리 선택만 바뀐 경우. fill·아이콘은
///    선택과 무관하다.
///  - [IndoorOverlaySyncScope.fills] — 층 전환 크로스페이드 단계. 계수는 fill에만
///    보이면 되고, 라벨·아이콘까지 매 프레임 밀면 native 왕복이 두 배가 된다.
///
/// 이미 제거된 레이어에 대한 setLayerProperties가 native에서 예외를 던지는
/// 구현이 있어(층 전환과 겹치는 순간) 각각 감싼다.
Future<void> syncIndoorOverlayProps(
  MapLibreMapController controller, {
  required IndoorOverlayIds ids,
  required List<Object> fadeExpr,
  required CategorySelection? categorySelection,
  required double devicePixelRatio,
  IndoorOverlaySyncScope scope = IndoorOverlaySyncScope.all,
}) async {
  // 선택을 반드시 함께 넘긴다. 빼면 줌을 움직일 때마다 가려 뒀던 매장 이름이
  // 되살아난다([indoorStoresLabelProps] 주석).
  final labels = <(String, LayerProperties)>[
    (
      ids.storesLabel,
      indoorStoresLabelProps(fadeExpr, categorySelection, devicePixelRatio),
    ),
    (
      ids.sharedStoresLabel,
      indoorStoresLabelProps(
        fadeExpr,
        categorySelection,
        devicePixelRatio,
        alwaysVisible: true,
      ),
    ),
    (ids.facilityLabel, indoorFacilityLabelProps(fadeExpr, categorySelection)),
  ];
  final fills = <(String, LayerProperties)>[
    (ids.footprint, indoorFootprintProps(fadeExpr)),
    (ids.storesFill, indoorStoresFillProps(fadeExpr)),
    (ids.categoryHighlightFill, indoorCategoryHighlightProps(fadeExpr)),
    (ids.verticalTransportFill, indoorVerticalTransportProps(fadeExpr)),
  ];
  final targets = switch (scope) {
    IndoorOverlaySyncScope.labels => labels,
    IndoorOverlaySyncScope.fills => fills,
    IndoorOverlaySyncScope.all => <(String, LayerProperties)>[
      ...fills,
      ...labels,
      (ids.poiIcon, indoorPoiIconProps(fadeExpr, devicePixelRatio)),
      (
        ids.storeFacilityIcon,
        indoorFacilityIconProps(fadeExpr, devicePixelRatio),
      ),
    ],
  };
  for (final (id, props) in targets) {
    try {
      await controller.setLayerProperties(id, props);
    } catch (_) {}
  }
}
