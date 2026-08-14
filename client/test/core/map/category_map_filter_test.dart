import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/map/category_map_filter.dart';

/// 지도 카테고리 필터 표현식의 **형태**를 고정한다.
///
/// 이 테스트가 지키려는 것은 값이 아니라 형태다. MapLibre GL Native는
/// `['match', ...]`나 `['in', ..., ['literal', [...]]]`처럼 인자 자리에 배열이
/// 오는 형태를 조용히 매치 0건으로 처리하는 경우가 있어(floor_plan_view.dart의
/// 수직이동 레이어 주석 참고), `==` 비교만 쓰는 형태로 고정해야 한다.
/// 웹에서는 잘못된 형태도 동작하므로 실기기 없이 잡을 방법이 이 테스트뿐이다.
void main() {
  group('categoryHighlightFilter', () {
    test('대분류만 고르면 category 하나만 비교한다', () {
      final filter = categoryHighlightFilter(
        const CategorySelection(category: '식음료'),
      );

      expect(filter, [
        'all',
        [
          '==',
          ['get', 'category'],
          '식음료',
        ],
      ]);
    });

    test('소분류까지 고르면 두 조건을 all로 묶는다', () {
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

    test('영어 원본값 소분류도 그대로 필터에 들어간다', () {
      // 화면에는 '화장실'로 보이지만 타일 property는 영어 원본값이다.
      // 여기서 label이 새어들어오면 필터가 조용히 0건이 된다.
      final filter = categoryHighlightFilter(
        const CategorySelection(category: '편의시설', subcategory: 'restroom'),
      );

      expect(filter.last, [
        '==',
        ['get', 'subcategory'],
        'restroom',
      ]);
    });

    test('match·in 같은 배열 인자 형태를 쓰지 않는다', () {
      final filter = categoryHighlightFilter(
        const CategorySelection(category: '패션', subcategory: '명품'),
      );

      final flattened = filter.toString();
      expect(flattened.contains('match'), isFalse);
      expect(flattened.contains('literal'), isFalse);
      // 모든 비교는 == 하나로 이뤄진다.
      for (final condition in filter.skip(1)) {
        expect((condition as List).first, '==');
      }
    });
  });

  group('categoryLabelTextField', () {
    test('선택이 없으면 모든 매장이 이름을 단다', () {
      // 카테고리를 고르기 전 화면은 예전과 한 글자도 달라지면 안 된다.
      expect(categoryLabelTextField(null), ['get', 'name']);
    });

    test('선택이 있으면 그 매장만 이름을 달고 나머지는 빈 문자열이다', () {
      final field = categoryLabelTextField(
        const CategorySelection(category: '식음료'),
      );

      expect(field.first, 'case');
      // 조건은 강조 fill과 **같은 함수**에서 나온다. 갈라지면 파랗게 칠해진
      // 매장과 이름이 남는 매장이 어긋난다.
      expect(
        field[1],
        categoryHighlightFilter(const CategorySelection(category: '식음료')),
      );
      expect(field[2], ['get', 'name']);
      // 이름을 지우는 값은 빈 문자열이다. null이면 text-field가 통째로 빠져
      // 스펙 기본값으로 돌아간다.
      expect(field[3], '');
      expect(field, hasLength(4));
    });

    test('소분류까지 고른 선택도 조건에 그대로 실린다', () {
      const selection = CategorySelection(
        category: '식음료',
        subcategory: '카페·베이커리',
      );

      expect(
        categoryLabelTextField(selection)[1],
        categoryHighlightFilter(selection),
      );
    });

    test('match·in 같은 배열 인자 형태를 쓰지 않는다', () {
      // 이 파일의 필터와 같은 이유다. `case`의 인자는 데이터 배열이 아니라
      // 불리언 표현식이라 그 함정에 걸리지 않는다.
      final flattened = categoryLabelTextField(
        const CategorySelection(category: '패션', subcategory: '명품'),
      ).toString();

      expect(flattened.contains('match'), isFalse);
      expect(flattened.contains('literal'), isFalse);
    });
  });

  group('kCategoryHighlightNoneFilter', () {
    test('선택이 없을 때 쓰는 필터는 실제 데이터와 맞지 않는다', () {
      // 'kind'는 타일의 모든 매장 feature가 'store'로 갖고 있는 값이라,
      // 이 상수와 같아지는 feature는 존재할 수 없다.
      expect(kCategoryHighlightNoneFilter, [
        '==',
        ['get', 'kind'],
        '__카테고리_선택_없음__',
      ]);
      expect(kCategoryHighlightNoneFilter.last, isNot('store'));
    });
  });

  group('CategorySelection', () {
    test('값 동등성으로 비교한다', () {
      // didUpdateWidget이 이 비교로 필터 재적용 여부를 정하므로, 참조 동등성이면
      // 매 rebuild마다 네이티브 setFilter가 불린다.
      expect(
        const CategorySelection(category: '식음료'),
        const CategorySelection(category: '식음료'),
      );
      expect(
        const CategorySelection(category: '식음료'),
        isNot(const CategorySelection(category: '식음료', subcategory: '레스토랑')),
      );
    });
  });
}
