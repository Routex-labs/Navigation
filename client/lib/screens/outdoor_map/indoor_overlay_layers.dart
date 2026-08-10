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
import 'indoor_entry_zoom.dart';

/// `Color`를 MapLibre가 받는 `#RRGGBB` 문자열로. 알파는 별도 opacity 속성으로
/// 주므로 여기서는 RGB만 쓴다.
extension MapColorHex on Color {
  String toHexString() {
    final rgb =
        (r * 255).round() << 16 | (g * 255).round() << 8 | (b * 255).round();
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// POI/시설 아이콘 크기. 오버레이가 페이드인되는 구간에서는 살짝 작게, 사용자가
/// 실내로 더 확대해 들어갈수록 실내 화면과 비슷한 크기로 커진다. 아이콘 캔버스
/// 96px 기준으로 실내 화면은 [kIndoorPoiIconSize] 고정이지만, 야외 오버레이는
/// 화면 시야가 훨씬 넓어 그대로 두면 라벨을 가릴 만큼 크게 보인다.
///
/// **두 방향의 피드백이 이 식의 양 끝을 각각 잡고 있다.** 아래쪽(축소)은
/// "화장실·정수기 같은 시설이 잘 안 보인다"는 피드백에 맞춰 올린 값이라 그대로
/// 두고, 위쪽(확대)은 "너무 크다"는 피드백에 맞춰 0.6에서 내렸다. 실내 화면
/// ([kIndoorPoiIconSize] = 0.42)보다 아주 조금 큰 선이다.
///
/// 한쪽만 보고 고치면 반대쪽이 회귀한다 — 값을 바꿀 때는 z16 축소와 z20 확대를
/// 반드시 함께 확인한다.
const indoorIconSizeExpr = [
  'interpolate',
  ['linear'],
  ['zoom'],
  indoorOverlayFadeInEndZoom,
  0.33,
  20,
  0.45,
];

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

/// 야외 오버레이의 대분류 아이콘 배율.
///
/// 실내 화면([kStoreCategoryIconSizeIndoor])과 달리 글자 크기가 11로 고정이라
/// 아이콘만 줌에 따라 조금 커진다. 시설 아이콘([indoorIconSizeExpr], 0.33~0.45)
/// 보다 작게 두는 이유는 실내 화면과 같다 — 라벨 옆에 붙는 아이콘이 이름보다
/// 커지면 도면이 아이콘 밭이 된다.
///
/// **z16 축소와 z20 확대를 반드시 함께 확인한다**([indoorIconSizeExpr] 주석의
/// 함정이 여기에도 그대로 적용된다).
///
/// ## 여기는 키우지 않았다 (2026-08-09)
///
/// "동그란 아이콘이 너무 작다"는 피드백으로 실내는 확대 쪽을 0.20 → 0.24로
/// 키웠지만([kStoreCategoryIconSizeIndoor]) 야외는 그대로 둔다. **실내는 글자
/// 상한을 18 → 14px로 내려 심볼 예산이 남았는데, 야외는 글자가 11px 고정이라
/// 내려간 것이 없다.** 여기서 아이콘만 키우면 늘어난 폭이 그대로 이름을 밀어낸다.
const indoorCategoryIconSizeExpr = [
  'interpolate',
  ['linear'],
  ['zoom'],
  indoorOverlayFadeInEndZoom,
  0.16,
  20,
  0.21,
];

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
SymbolLayerProperties indoorStoresLabelProps(
  List<Object> fadeExpr,
  CategorySelection? selection,
) => SymbolLayerProperties(
  textField: categoryLabelTextField(selection),
  textFont: const [mapFontStackRegular],
  textSize: 11,
  // 색·헤일로는 [map_label_style.dart]가 단일 출처다(실내 화면과 같은 값).
  // 크기만 여기서 고정인데, 야외는 도면 전체를 훑는 축소 화면이라 폴리곤
  // 맞춤 크기를 쓰면 작은 매장 이름이 읽을 수 없게 작아진다.
  textColor: mapLabelStoreColor,
  textHaloColor: mapLabelHaloColor,
  textHaloWidth: mapLabelHaloWidth,
  textMaxWidth: 6,
  textOpacity: fadeExpr,
  iconImage: storeCategoryIconExpression(),
  iconSize: indoorCategoryIconSizeExpr,
  iconOpacity: fadeExpr,
  // 이름은 항상 아이콘 아래다 — 실내 도면·편의시설 라벨과 같은 규칙.
  textAnchor: 'top',
  textOffset: mapLabelBelowIconOffset,
  textJustify: 'center',
  textAllowOverlap: false,
  // 자리가 없으면 아이콘·이름 중 하나만이라도 남긴다. iconOptional이 없으면
  // 심볼이 넓어진 만큼 이름이 밀려난다(실내 화면 주석의 실측 참고).
  textOptional: true,
  iconOptional: true,
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
  textSize: mapLabelFacilityTextSize,
  textColor: mapLabelFacilityColor,
  textHaloColor: mapLabelHaloColor,
  textHaloWidth: mapLabelHaloWidth,
  textMaxWidth: mapLabelFacilityMaxWidth,
  textOpacity: fadeExpr,
  // 아이콘이 centroid를 차지하므로 이름은 아래로 내린다.
  textOffset: mapLabelBelowIconOffset,
  textAllowOverlap: false,
);

SymbolLayerProperties indoorPoiIconProps(List<Object> fadeExpr) =>
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
      iconSize: indoorIconSizeExpr,
      iconOpacity: fadeExpr,
      iconAllowOverlap: true,
    );

SymbolLayerProperties indoorFacilityIconProps(List<Object> fadeExpr) =>
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
      iconSize: indoorIconSizeExpr,
      iconOpacity: fadeExpr,
      iconAllowOverlap: true,
      // iconOffset 없음 = 폴리곤 중심(centroid)에 그린다. 실내 화면
      // (`FloorPlanView`)의 편의시설 아이콘과 같은 기준이라 두 화면 사이에서
      // 아이콘 위치가 어긋나지 않는다.
    );
