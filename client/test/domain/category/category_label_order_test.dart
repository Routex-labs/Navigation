import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/category/category_label_order.dart';

void main() {
  test('Dart 문자열 비교는 실제 한글 카테고리를 가나다 순으로 정렬한다', () {
    final labels = ['패션', '가구', '편의시설', '레스토랑'];

    labels.sort(categoryLabelCompare);

    expect(labels, ['가구', '레스토랑', '패션', '편의시설']);
  });

  test('전체는 앞에 고정하고 같은 표시 label은 하나만 남긴다', () {
    final labels = sortedCategoryLabels([
      '패션',
      '가구',
      '전체',
      '레스토랑',
      '가구',
      '편의시설',
    ]);

    expect(labels, ['전체', '가구', '레스토랑', '패션', '편의시설']);
  });

  test('영문 보조 정렬은 앞뒤 공백과 대소문자를 무시한다', () {
    final labels = sortedCategoryLabels(['fashion', ' Bakery ', 'apparel']);

    expect(labels, ['apparel', ' Bakery ', 'fashion']);
  });
}
