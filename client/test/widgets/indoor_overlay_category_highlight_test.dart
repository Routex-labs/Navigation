import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/layers/indoor_overlay_layers.dart';
import 'package:navigation_client/map/style/category_map_fill.dart';
import 'package:navigation_client/map/style/category_map_filter.dart';

/// 야외 오버레이의 카테고리 강조 fill 규칙을 못 박는다.
///
/// 이 레이어는 `setLayerProperties`로 갱신되는데, 그 호출은 patch가 아니라
/// **전체 교체**다(indoor_overlay_layers.dart 상단 주석). 넘기지 않은 속성은
/// null로 함께 전송돼 스펙 기본값으로 되돌아가고, `fill-color`의 기본값은
/// 검정이라 실기기에서 도면이 검게 덮인다. 웹에서는 이 경로가 달라 증상이
/// 안 보이므로 Chrome 확인만으로는 절대 못 잡는다.
void main() {
  group('indoorCategoryHighlightProps', () {
    test('opacity만이 아니라 색까지 항상 함께 넘긴다', () {
      final json = indoorCategoryHighlightProps(const ['literal', 1]).toJson();

      expect(json['fill-color'], storeCategoryHighlightFillColorExpression());
      expect(
        json['fill-outline-color'],
        storeCategoryHighlightOutlineExpression(),
      );
    });

    test('강조색은 실내 화면과 같은 대분류 색 표현식을 쓴다', () {
      // 두 화면이 같은 MVT `stores` 레이어를 본다. 색이 갈라지면 같은 매장이
      // 야외 오버레이와 실내 화면에서 다른 색으로 보인다.
      final fill = indoorCategoryHighlightProps(const [
        'literal',
        1,
      ]).toJson()['fill-color'];

      expect(fill, contains('리빙'));
      expect(fill, contains(categoryFillTintHex('리빙')));
    });

    test('페이드 표현식을 그대로 opacity에 싣는다', () {
      // 야외 오버레이는 줌에 따라 통째로 페이드인/아웃된다. 강조만 불투명하게
      // 두면 도면이 아직 안 보이는 줌에서 강조 폴리곤만 공중에 뜬다.
      const fade = ['interpolate', 'linear', 'zoom', 16, 0, 18, 1];
      final json = indoorCategoryHighlightProps(fade).toJson();

      expect(json['fill-opacity'], fade);
    });
  });

  group('categoryHighlightFilter', () {
    test('소분류가 없으면 대분류만 비교한다', () {
      final filter = categoryHighlightFilter(
        const CategorySelection(category: '리빙'),
      );

      expect(filter, [
        'all',
        [
          '==',
          ['get', 'category'],
          '리빙',
        ],
      ]);
    });

    test('소분류가 있으면 == 비교를 하나 더 붙인다', () {
      // `match`나 `in` 형태는 MapLibre GL Native에서 예외도 로그도 없이 매치
      // 0건이 되는 경우가 있어 `==` 비교만 쓴다(category_map_filter.dart 주석).
      final filter = categoryHighlightFilter(
        const CategorySelection(category: '식음료', subcategory: '카페·베이커리'),
      );

      expect(filter, [
        'all',
        [
          '==',
          ['get', 'category'],
          '식음료',
        ],
        [
          '==',
          ['get', 'subcategory'],
          '카페·베이커리',
        ],
      ]);
    });
  });
}
