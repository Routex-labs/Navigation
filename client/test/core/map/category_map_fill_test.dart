import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/map_palette.dart';
import 'package:navigation_client/core/map/category_icon.dart';
import 'package:navigation_client/core/map/category_map_fill.dart';

/// 카테고리를 눌렀을 때 강조 매장을 대분류 색으로 칠하는 규칙의 회귀 테스트.
///
/// 화면으로만 확인하면 놓치는 것들을 여기서 잡는다. 지도 색은 "예뻐 보이는가"가
/// 아니라 **읽히는가**가 기준이고, 실패는 대개 조용하다 — 표현식 형태가 어긋나면
/// 예외 없이 매치 0건이 되고, 색이 짙어지면 그 위 매장명이 안 보일 뿐 아무것도
/// 깨지지 않는다.
void main() {
  /// `#RRGGBB`를 상대 휘도(0~1)로. WCAG 정의를 그대로 쓴다.
  double luminance(String hex) {
    final rgb = int.parse(hex.substring(1), radix: 16);
    return Color.fromARGB(
      255,
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
    ).computeLuminance();
  }

  test('아이콘 표와 색 표의 대분류가 일치한다', () {
    // 한쪽에만 있으면 지도에서 아이콘은 붙는데 면은 회색인(또는 그 반대)
    // 대분류가 생긴다.
    expect(categoryPaletteCategories.toSet(), categoryIconCategories.toSet());
  });

  test('면 색은 매장명이 읽힐 만큼 밝다', () {
    // 라벨은 #444846(휘도 약 0.06)이다. 아홉 대분류 전부 뮤트 중간톤이지만
    // 그중 어두운 쪽(서비스·식품관, 휘도 약 0.38)까지 포함해 면이 충분히
    // 밝아야 이름이 먼저 읽힌다. 이 임계값을 낮추려면 실기기에서 그 매장들의
    // 이름 가독성부터 확인해야 한다.
    for (final category in categoryPaletteCategories) {
      final tint = categoryFillTintHex(category);
      expect(
        luminance(tint),
        greaterThan(0.7),
        reason: '$category 면($tint)이 너무 어두워 매장명이 묻힌다',
      );
    }
  });

  test('경계선은 면보다 확실히 진하다', () {
    // 면만 옅게 칠하고 테두리가 같이 옅어지면 매장 사이 구분이 사라진다.
    for (final category in categoryPaletteCategories) {
      final fill = luminance(categoryFillTintHex(category));
      final outline = luminance(categoryOutlineHex(category));
      expect(
        fill - outline,
        greaterThan(0.3),
        reason: '$category 면과 경계선의 명도 차가 부족하다',
      );
    }
  });

  test('리빙은 틸 계열 한 가지로 면·선이 함께 간다', () {
    // 사용자가 지목한 대분류다. 시트·chip에서 쓰는 색(#87BEB8)이 그대로
    // 지도 경계선이 되어야 "시트에서 본 틸 = 지도의 틸"이 성립한다.
    expect(categoryOutlineHex('리빙'), '#87BEB8');
    expect(categoryFillTintHex('리빙'), '#E9F3F2');
  });

  group('표현식', () {
    test('match + 문자열 label 형태다', () {
      final expr = storeCategoryHighlightFillColorExpression();
      // 배열을 label로 쓰는 형태는 GL Native에서 조용히 매치 0건이 된다.
      expect(expr[0], 'match');
      expect(expr[1], ['get', 'category']);
      for (var i = 2; i < expr.length - 1; i += 2) {
        expect(expr[i], isA<String>(), reason: 'label 자리에 배열이 들어갔다');
        expect(expr[i + 1], isA<String>());
      }
    });

    test('모든 대분류가 면·선 표현식에 들어 있다', () {
      final fill = storeCategoryHighlightFillColorExpression();
      final outline = storeCategoryHighlightOutlineExpression();
      for (final category in categoryPaletteCategories) {
        expect(fill, contains(category));
        expect(fill, contains(categoryFillTintHex(category)));
        expect(outline, contains(categoryOutlineHex(category)));
      }
    });

    test('모르는 대분류·category 없는 매장은 기본 매장 색으로 떨어진다', () {
      // 표현식의 마지막 원소가 default다. 여기가 바뀌면 대분류가 안 붙은
      // 매장들이 강조될 때 통째로 다른 색(최악은 검정)이 된다.
      expect(storeCategoryHighlightFillColorExpression().last, mapStoreFill);
      expect(storeCategoryHighlightOutlineExpression().last, mapStoreOutline);
    });
  });
}
