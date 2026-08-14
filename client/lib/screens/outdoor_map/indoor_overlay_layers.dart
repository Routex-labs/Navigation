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

import 'package:flutter/painting.dart' show Color;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/map_fonts.dart';
import '../../core/map_label_style.dart';
import '../../core/map_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_map_fill.dart';
import '../../widgets/category_map_filter.dart';
import '../../widgets/category_map_icon.dart';
import '../../widgets/floor_facility_style.dart';

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
  Object? symbolSortKey,
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
  // 일반 매장은 아이콘과 이름을 **한 단위로** 배치한다. 둘 중 하나만 optional로
  // 두면 붐비는 축소 화면에서 이름은 사라지고 색 아이콘만 남아, 무엇을 뜻하는지
  // 알 수 없는 점들로 지도가 다시 복잡해진다. 둘 다 필수면 한쪽이 충돌할 때
  // 심볼 전체가 빠지고, 확대해 자리가 생기면 둘이 함께 돌아온다.
  // 공유 매장은 alwaysVisible이 충돌 판정을 끄므로 같은 값이 그대로 안전하다.
  textOptional: false,
  iconOptional: false,
  symbolSortKey: symbolSortKey,
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
