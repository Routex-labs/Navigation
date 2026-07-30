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

import '../../theme/app_theme.dart';
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
/// 화면 시야가 훨씬 넓어 그대로 두면 라벨을 가릴 만큼 크게 보인다. 화장실·정수기
/// 같은 시설이 잘 안 보인다는 피드백에 맞춰 실내 배율과 같은 1.5배로 올렸고,
/// 최대값은 실내 화면(0.42)보다 크게 잡아 확대해 들어갈수록 실내와 비슷하게
/// 읽히도록 둔다.
const indoorIconSizeExpr = [
  'interpolate',
  ['linear'],
  ['zoom'],
  indoorOverlayFadeInEndZoom,
  0.33,
  20,
  0.6,
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
/// 어느 링을 따라갈지는 [floor_outline.dart]가 정한다.
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
      fillColor: '#FFFFFF',
      fillOutlineColor: '#00000088',
      fillOpacity: fadeExpr,
    );

FillLayerProperties indoorStoresFillProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: '#F3F1EF',
      fillOutlineColor: '#D8D4D1',
      fillOpacity: fadeExpr,
    );

FillLayerProperties indoorVerticalTransportProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: '#DCEBD4',
      fillOutlineColor: '#6FA167',
      fillOpacity: fadeExpr,
    );

SymbolLayerProperties indoorStoresLabelProps(List<Object> fadeExpr) =>
    SymbolLayerProperties(
      textField: ['get', 'name'],
      textFont: const ['Noto Sans KR Regular'],
      textSize: 11,
      textColor: '#333333',
      textHaloColor: '#FFFFFF',
      textHaloWidth: 1,
      textMaxWidth: 6,
      textOpacity: fadeExpr,
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
