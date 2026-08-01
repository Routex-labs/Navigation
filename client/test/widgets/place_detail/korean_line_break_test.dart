import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/place_detail/korean_line_break.dart';

// word joiner를 다시 걷어내면 원문과 같아야 한다. 화면에 보이는 글자는 그대로 두고
// 줄 끊는 위치만 바꾸는 것이 이 함수의 계약이다.
const joiner = '⁠';

void main() {
  test('어절 안의 글자를 묶어 공백에서만 끊기게 한다', () {
    final result = keepWordsWhole('한 줄 소개');

    expect(result.replaceAll(joiner, ''), '한 줄 소개');
    expect(result.split(' ').last, '소$joiner' '개');
  });

  test('한 줄보다 길 수 있는 어절은 묶지 않는다', () {
    // 묶어 버리면 줄바꿈 대신 넘침이 되어 글자가 잘린다.
    const long = '더현대서울지하이층리저브매장에서만드는아메리카노입니다';
    expect(keepWordsWhole(long), long);
  });

  test('한 글자 어절과 빈 문자열은 그대로 둔다', () {
    expect(keepWordsWhole('B2'), 'B${joiner}2');
    expect(keepWordsWhole('가 나'), '가 나');
    expect(keepWordsWhole(''), '');
  });
}
