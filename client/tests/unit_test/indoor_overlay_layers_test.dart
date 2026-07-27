import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:navigation_client/screens/outdoor_map/indoor_overlay_layers.dart';

/// 실기기에서 건물이 **불투명한 검정 덩어리**로 덮이던 회귀를 막는 테스트.
///
/// 원인은 `MapLibreMapController.setLayerProperties`가 patch가 아니라 전체
/// 교체라는 점이었다. 넘긴 객체를 `toJson(skipNulls: false)`로 직렬화하므로
/// 설정하지 않은 속성이 전부 `null`로 함께 전송되고, Android 네이티브는 그
/// null을 그대로 적용해 스펙 기본값으로 되돌린다. `fill-color`의 기본값이
/// `#000000`이라 흰색 footprint가 검정으로 바뀌었다.
///
/// 웹에서는 증상이 안 보이므로 Chrome 확인만으로는 절대 못 잡는다. 그래서
/// "레이어 속성 묶음은 항상 완전해야 한다"를 여기서 못 박는다.
void main() {
  // 진입 후 어느 zoom에서든 쓰이는 대표 페이드 표현식.
  final fadeExpr = <Object>[
    'interpolate',
    ['linear'],
    ['zoom'],
    15.6,
    0,
    16.0,
    1,
  ];

  /// setLayerProperties가 실제로 보내는 형태 그대로 검사한다.
  Map<String, dynamic> wireJson(LayerProperties props) =>
      props.toJson(skipNulls: false);

  group('fill 레이어는 색을 항상 함께 보낸다', () {
    final cases = <String, FillLayerProperties>{
      '실내 footprint': indoorFootprintProps(fadeExpr),
      '실내 매장 fill': indoorStoresFillProps(fadeExpr),
      '수직이동 구조물': indoorVerticalTransportProps(fadeExpr),
      '건물 폴리곤': buildingFillProps(0.15),
      'dim scrim': dimScrimProps(0),
    };

    cases.forEach((name, props) {
      test('$name — fill-color가 null이 아니다', () {
        final json = wireJson(props);
        expect(
          json['fill-color'],
          isNotNull,
          reason:
              '$name의 fill-color가 null로 전송되면 Android에서 스펙 기본값 #000000(검정)으로 '
              '되돌아간다. opacity만 넘기는 부분 업데이트를 되살리지 말 것.',
        );
        expect(json['fill-opacity'], isNotNull);
      });
    });

    test('실내 footprint는 흰색이다', () {
      expect(wireJson(indoorFootprintProps(fadeExpr))['fill-color'], '#FFFFFF');
    });

    test('건물 폴리곤은 검정이 아닌 테마 색이다', () {
      final color = wireJson(buildingFillProps(0.15))['fill-color'] as String;
      expect(color, isNot('#000000'));
      expect(color, matches(RegExp(r'^#[0-9A-F]{6}$')));
    });
  });

  group('symbol 레이어는 layout 속성을 항상 함께 보낸다', () {
    test('매장 라벨 — text-field/text-font/text-color가 살아 있다', () {
      final json = wireJson(indoorStoresLabelProps(fadeExpr));
      // text-field가 null로 가면 라벨이 통째로 사라진다.
      expect(json['text-field'], isNotNull);
      expect(json['text-font'], isNotNull);
      expect(json['text-color'], isNotNull);
      expect(json['text-opacity'], isNotNull);
    });

    test('POI·시설 아이콘 — icon-image/icon-size가 살아 있다', () {
      for (final props in [
        indoorPoiIconProps(fadeExpr),
        indoorFacilityIconProps(fadeExpr),
      ]) {
        final json = wireJson(props);
        // icon-image가 null로 가면 아이콘이 통째로 사라진다.
        expect(json['icon-image'], isNotNull);
        expect(json['icon-size'], isNotNull);
        expect(json['icon-opacity'], isNotNull);
      }
    });
  });

  test('페이드 표현식은 그대로 실려 나간다', () {
    // opacity를 zoom 표현식으로 주는 구조 자체는 유지되어야 한다 —
    // 이 값이 상수로 바뀌면 오버레이 페이드인이 죽는다.
    expect(wireJson(indoorFootprintProps(fadeExpr))['fill-opacity'], fadeExpr);
  });
}
