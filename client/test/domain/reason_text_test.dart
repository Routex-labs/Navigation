import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/reason_text.dart';

/// 목록에서 되풀이되는 근거 문장을 걷어내는 규칙을 고정한다.
///
/// 여기서 막으려는 실패는 둘이다.
/// 1. **다섯 행이 같은 문장을 되풀이하는 것** — 정보량이 0이면서 층이 있던 자리를 먹는다.
/// 2. **행마다 다른 근거까지 지워 버리는 것** — clarify 미리보기는 서로 다른 성격의
///    후보를 보여주는 게 목적이라(conversational-discovery 4-2절) 그 차이가 남아야 한다.
void main() {
  group('reasonSentences', () {
    test('마침표로 끊고 마침표는 되붙인다', () {
      expect(reasonSentences('신발 관련 매장이에요. 캐주얼 스타일 매장이에요.'), [
        '신발 관련 매장이에요.',
        '캐주얼 스타일 매장이에요.',
      ]);
    });

    // 없던 마침표를 만들면 화면 글자가 서버가 준 것과 어긋난다.
    test('마침표 없이 끝나면 마침표를 만들지 않는다', () {
      expect(reasonSentences('이유-가까운곳'), ['이유-가까운곳']);
      expect(reasonSentences('앞 문장이에요. 꼬리'), ['앞 문장이에요.', '꼬리']);
    });

    test('문장이 하나면 그대로 한 건이다', () {
      expect(reasonSentences('신발 관련 매장이에요.'), ['신발 관련 매장이에요.']);
    });
  });

  group('sharedReasonSentences', () {
    // "신발" 질의의 clarify 미리보기. 앞 문장은 세 행이 같고 뒤는 다르다.
    test('모든 행에 있는 문장만 공통으로 본다', () {
      final shared = sharedReasonSentences([
        '신발 관련 매장이에요. 캐주얼 스타일 매장이에요.',
        '신발 관련 매장이에요. 컨템포러리 스타일 매장이에요.',
        '신발 관련 매장이에요. 명품 스타일 매장이에요.',
      ]);

      expect(shared, {'신발 관련 매장이에요.'});
    });

    // "스포츠"를 고른 뒤의 목록. 모든 행이 완전히 같은 문장이다.
    test('전부 같으면 문장 전체가 공통이다', () {
      final shared = sharedReasonSentences([
        '신발 관련 매장이에요. 스포츠 스타일 매장이에요.',
        '신발 관련 매장이에요. 스포츠 스타일 매장이에요.',
      ]);

      expect(shared, {'신발 관련 매장이에요.', '스포츠 스타일 매장이에요.'});
    });

    // 태그가 아직 없는 매장은 근거가 빈다. 그 행 때문에 공통 집합이 비면 겹치는
    // 문장을 그대로 되풀이하게 되므로 계산에서 뺀다.
    test('근거가 없는 행은 공통 계산에서 뺀다', () {
      final shared = sharedReasonSentences([
        '신발 관련 매장이에요. 캐주얼 스타일 매장이에요.',
        null,
        '신발 관련 매장이에요. 명품 스타일 매장이에요.',
      ]);

      expect(shared, {'신발 관련 매장이에요.'});
    });

    // 비교할 상대가 없으면 되풀이도 없다. 이걸 빼먹으면 결과가 한 건일 때 그 한 건의
    // 근거가 통째로 사라진다.
    test('행이 하나뿐이면 공통이 없다', () {
      expect(sharedReasonSentences(['신발 관련 매장이에요. 스포츠 스타일 매장이에요.']), isEmpty);
    });

    test('근거가 하나도 없으면 공통도 없다', () {
      expect(sharedReasonSentences([null, null]), isEmpty);
      expect(sharedReasonSentences(const <String?>[]), isEmpty);
    });
  });

  group('distinctiveReason', () {
    test('공통 문장을 빼고 그 매장만의 근거를 남긴다', () {
      final reason = distinctiveReason('신발 관련 매장이에요. 캐주얼 스타일 매장이에요.', {
        '신발 관련 매장이에요.',
      });

      expect(reason, '캐주얼 스타일 매장이에요.');
    });

    // 남는 게 없으면 호출부가 그 자리에 층을 넣는다.
    test('전부 공통이면 null이다', () {
      final reason = distinctiveReason('신발 관련 매장이에요. 스포츠 스타일 매장이에요.', {
        '신발 관련 매장이에요.',
        '스포츠 스타일 매장이에요.',
      });

      expect(reason, isNull);
    });

    test('근거가 없으면 null이다', () {
      expect(distinctiveReason(null, {'신발 관련 매장이에요.'}), isNull);
      expect(distinctiveReason('   ', const {}), isNull);
    });

    test('공통이 없으면 원문 그대로다', () {
      expect(distinctiveReason('캐주얼 스타일 매장이에요.', const {}), '캐주얼 스타일 매장이에요.');
    });
  });
}
