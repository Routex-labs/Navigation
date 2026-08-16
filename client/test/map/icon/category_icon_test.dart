import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:navigation_client/map/icon/category_icon.dart';
import 'package:navigation_client/domain/category/subcategory_label.dart';

/// 대분류·소분류 어휘가 바뀌었을 때 아이콘·문구가 조용히 폴백으로 떨어지지
/// 않는지 고정한다.
///
/// 이 파일이 필요한 이유: `식음료`를 음식점·카페·식품관으로 나누고 편의시설
/// 소분류의 영어 원본값을 한글로 옮기는 변경에서, 매핑을 빠뜨려도 **화면은
/// 멀쩡해 보인다** — 회색 storefront 아이콘이 뜰 뿐이라 리뷰에서 눈에 띄지
/// 않는다. 테스트로 못 박아 두지 않으면 다음 어휘 변경에서 같은 일이 난다.
void main() {
  group('대분류 아이콘·색', () {
    test('나뉜 세 대분류가 각각 다른 아이콘을 갖는다', () {
      final icons = {
        categoryIconFor('음식점'),
        categoryIconFor('카페'),
        categoryIconFor('식품관'),
      };

      expect(icons.length, 3, reason: '셋이 같은 글리프면 나눈 의미가 없다');
      expect(
        icons,
        isNot(contains(Icons.storefront)),
        reason: '폴백으로 떨어지면 안 된다',
      );
    });

    test('나뉜 세 대분류가 각각 다른 색을 갖는다', () {
      final colors = {
        categoryColorFor('음식점'),
        categoryColorFor('카페'),
        categoryColorFor('식품관'),
      };

      expect(colors.length, 3);
    });

    test('구 어휘 식음료도 아직 폴백으로 떨어지지 않는다', () {
      // 클라이언트가 먼저 배포되고 백엔드 시드가 아직 옛 어휘를 주는 구간이 있다.
      expect(categoryIconFor('식음료'), isNot(Icons.storefront));
    });

    test('모르는 대분류는 상점 아이콘으로 폴백한다', () {
      expect(categoryIconFor('없는분류'), Icons.storefront);
    });

    // 같은 분류를 두 표가 안다. 지도 폴리곤·심볼은 위의 앱 표를 읽고, 지도 위
    // 분류 칩은 Runtime Kit의 `RoutexCategoryTokens`를 읽는다. 값을 옮겨 적은
    // 것이라 **한쪽만 고치면 조용히 갈라진다** — 같은 분류가 도면에서는 살구색인데
    // 칩에서는 회색 storefront로 나오는 식이다. 화면은 멀쩡해 보인다.
    //
    // 표를 하나로 합치지 않은 이유는 지도 쪽이 MapLibre에 비트맵을 사전 등록하는
    // 경로라 단계 7까지 앱이 소유하기 때문이다. 합치기 전까지는 이 테스트가
    // 두 표를 묶어 둔다.
    test('앱 표와 Runtime Kit 표가 같은 색·글리프를 가리킨다', () {
      expect(
        RoutexCategoryTokens.categories.toSet(),
        categoryPaletteCategories.toSet(),
        reason: '한쪽에만 있는 대분류가 생기면 칩과 도면이 갈라진다',
      );
      for (final category in categoryPaletteCategories) {
        expect(
          RoutexCategoryTokens.colorFor(category),
          categoryColorFor(category),
          reason: category,
        );
        expect(
          RoutexCategoryTokens.iconFor(category),
          categoryIconFor(category),
          reason: category,
        );
      }
    });
  });

  group('시설 소분류', () {
    test('한글 소분류가 영어 원본값과 같은 아이콘을 준다', () {
      expect(
        storeIconFor(subcategory: '화장실'),
        storeIconFor(subcategory: 'restroom'),
      );
      expect(
        storeIconFor(subcategory: '엘리베이터'),
        storeIconFor(subcategory: 'elevator'),
      );
      expect(
        storeIconFor(subcategory: '에스컬레이터'),
        storeIconFor(subcategory: 'escalator'),
      );
    });

    test('생활편의 소분류가 이름 기반 판정을 덮지 않는다', () {
      // 소분류 switch가 이름 규칙보다 먼저 도므로, `생활편의`를 switch에 넣으면
      // 정수기·수유실이 전부 같은 글리프가 된다. 그래서 일부러 넣지 않았다.
      expect(
        storeIconFor(name: '정수기', subcategory: '생활편의'),
        Icons.water_drop_outlined,
      );
      expect(
        storeIconFor(name: '수유실', subcategory: '생활편의'),
        Icons.child_friendly,
      );
    });

    test('facility는 화면 문구로 생활편의가 된다', () {
      // 대분류와 같은 `편의시설`을 쓰면 "편의시설 > 편의시설"이 되어 안 읽힌다.
      expect(subcategoryLabelFor('facility'), '생활편의');
    });

    test('이미 한글인 소분류는 그대로 통과한다', () {
      expect(subcategoryLabelFor('생활편의'), '생활편의');
      expect(subcategoryLabelFor('와인·주류'), '와인·주류');
    });
  });
}
