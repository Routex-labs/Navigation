import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/hangul.dart';

void main() {
  group('decomposeJamo', () {
    test('음절을 초·중·종성으로 편다', () {
      expect(decomposeJamo('샤넬'), 'ㅅㅑㄴㅔㄹ');
      expect(decomposeJamo('나이키'), 'ㄴㅏㅇㅣㅋㅣ');
    });

    test('받침이 없으면 두 자다', () {
      expect(decomposeJamo('나'), 'ㄴㅏ');
      expect(decomposeJamo('가'), 'ㄱㅏ');
    });

    // 쪼개도 편집거리가 실질적으로 같아서 표를 늘리지 않기로 한 선택이다.
    test('겹자모는 더 쪼개지 않는다', () {
      expect(decomposeJamo('과'), 'ㄱㅘ');
      expect(decomposeJamo('닭'), 'ㄷㅏㄺ');
    });

    // 라틴 문자는 자모 분해 대상이 아니다 — 그대로 통과시켜 일반 편집거리로
    // 처리한다.
    test('한글이 아닌 문자는 그대로 통과한다', () {
      expect(decomposeJamo('A.P.C.'), 'A.P.C.');
      expect(decomposeJamo('MLB'), 'MLB');
      expect(decomposeJamo('29CM HOME'), '29CM HOME');
      expect(decomposeJamo(''), '');
    });

    // IME 조합 중에 들어오는 낱자. 이미 자모라 더 손대지 않는다.
    test('호환 자모 낱자는 그대로 둔다', () {
      expect(decomposeJamo('ㄴㅇㅋ'), 'ㄴㅇㅋ');
      expect(decomposeJamo('ㅅ'), 'ㅅ');
    });

    test('한글과 라틴이 섞여도 자리 순서가 유지된다', () {
      expect(decomposeJamo('코닥x디오디'), 'ㅋㅗㄷㅏㄱxㄷㅣㅇㅗㄷㅣ');
    });
  });

  group('initialConsonants', () {
    test('초성만 뽑는다', () {
      expect(initialConsonants('나이키'), 'ㄴㅇㅋ');
      expect(initialConsonants('엘리베이터'), 'ㅇㄹㅂㅇㅌ');
      // 받침이 있어도 초성은 하나다.
      expect(initialConsonants('설화수'), 'ㅅㅎㅅ');
    });

    // 라틴 글자를 버리면 초성열의 자리수가 원래 이름과 어긋난다.
    test('한글이 아닌 문자는 자리를 지킨 채 남는다', () {
      expect(initialConsonants('mlb'), 'mlb');
      expect(initialConsonants('코닥x디오디'), 'ㅋㄷxㄷㅇㄷ');
    });

    test('빈 문자열은 빈 문자열이다', () {
      expect(initialConsonants(''), '');
    });
  });

  group('jamoEditDistance', () {
    // 음절 단위로 재면 `낼`과 `넬`은 완전히 다른 글자라 거리 1이 안 나온다.
    test('모음 하나 차이가 거리 1이다', () {
      expect(jamoEditDistance('샤낼', '샤넬'), 1);
      expect(jamoEditDistance('룰루래몬', '룰루레몬'), 1);
    });

    test('받침 하나 차이가 거리 1이다', () {
      expect(jamoEditDistance('파리크라산', '파리크라상'), 1);
      // 받침이 없다가 생기는 것도 삽입 하나다.
      expect(jamoEditDistance('나이', '나인'), 1);
    });

    test('같으면 0이다', () {
      expect(jamoEditDistance('크록스', '크록스'), 0);
      expect(jamoEditDistance('', ''), 0);
    });

    test('라틴 문자는 글자 하나가 곧 거리 1이다', () {
      expect(jamoEditDistance('MLB', 'MLC'), 1);
      expect(jamoEditDistance('aapa', 'AAPE'), 4); // 대소문자는 여기서 안 맞춘다
    });

    // 이 함수로는 `샤낼`이 `샤넬 뷰티`를 못 찾는다. 그래서 후보 산출은
    // jamoPrefixEditDistance를 쓴다.
    test('상호가 길기만 해도 거리가 커진다', () {
      expect(jamoEditDistance('샤낼', '샤넬 뷰티'), 6);
    });

    test('한쪽이 비면 다른 쪽의 자모 길이다', () {
      expect(jamoEditDistance('', '나이'), 4);
      expect(jamoEditDistance('나이', ''), 4);
    });
  });

  group('jamoPrefixEditDistance', () {
    // 뒤에 남은 글자를 버리는 비용은 받지 않는다.
    test('상호 앞부분과만 비교한다', () {
      expect(jamoPrefixEditDistance('샤낼', '샤넬 뷰티'), 1);
      expect(jamoPrefixEditDistance('아크내', '아크네 스튜디오'), 1);
    });

    test('앞부분이 그대로 일치하면 0이다', () {
      expect(jamoPrefixEditDistance('나이', '나이키 라이즈'), 0);
      expect(jamoPrefixEditDistance('크록스', '크록스'), 0);
    });

    // 시작 지점까지 공짜로 두지 않는다 — 그러면 3글자 질의가 긴 상호 아무
    // 데나 붙는다.
    test('질의가 상호 가운데에 있으면 거리가 크다', () {
      expect(jamoPrefixEditDistance('라이즈', '나이키 라이즈'), greaterThan(1));
    });

    // 질의가 상호보다 길면 남는 자모만큼은 반드시 비용이다.
    test('상호가 질의보다 짧으면 그 차이가 하한이다', () {
      expect(jamoPrefixEditDistance('나이키', '나'), 4);
    });

    test('질의가 비면 0이다', () {
      expect(jamoPrefixEditDistance('', '나이키'), 0);
    });
  });

  group('낱자 판정', () {
    test('isHangulSyllable은 완성형만 참이다', () {
      expect(isHangulSyllable('가'.codeUnitAt(0)), isTrue);
      expect(isHangulSyllable('힣'.codeUnitAt(0)), isTrue);
      expect(isHangulSyllable('ㄱ'.codeUnitAt(0)), isFalse);
      expect(isHangulSyllable('A'.codeUnitAt(0)), isFalse);
    });

    test('isConsonantJamo는 자음 낱자만 참이다', () {
      expect(isConsonantJamo('ㄱ'.codeUnitAt(0)), isTrue);
      expect(isConsonantJamo('ㅎ'.codeUnitAt(0)), isTrue);
      // 모음 낱자는 초성 질의가 아니다.
      expect(isConsonantJamo('ㅏ'.codeUnitAt(0)), isFalse);
      expect(isConsonantJamo('가'.codeUnitAt(0)), isFalse);
    });

    test('isCompatibilityJamo는 자음·모음 낱자를 모두 받는다', () {
      expect(isCompatibilityJamo('ㄱ'.codeUnitAt(0)), isTrue);
      expect(isCompatibilityJamo('ㅏ'.codeUnitAt(0)), isTrue);
      expect(isCompatibilityJamo('가'.codeUnitAt(0)), isFalse);
    });
  });
}
