import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/geo/distance_format.dart';

/// `formatDistance`의 검증 기준 표. 주석에 표를 베끼지 않고 여기를 가리킨다.
void main() {
  group('1 km 미만은 정수 m', () {
    test('0과 한 자리', () {
      expect(formatDistance(0), '0m');
      expect(formatDistance(3.4), '3m');
    });

    test('소수는 m으로 반올림한다', () {
      expect(formatDistance(123.4), '123m');
      expect(formatDistance(123.6), '124m');
    });

    test('경계 바로 아래', () {
      expect(formatDistance(999), '999m');
    });
  });

  group('경계 — m으로 반올림한 뒤에 가른다', () {
    test('999.6 m는 1000m이 아니라 1.0km다', () {
      // 먼저 비교하고 나중에 반올림하면 여기서 `1000m`이 나온다.
      expect(formatDistance(999.6), '1.0km');
    });

    test('정확히 1000 m', () {
      expect(formatDistance(1000), '1.0km');
    });
  });

  group('1 km 이상은 소수 한 자리 km, 버림', () {
    test('1049 m는 1.0km (반올림하면 1.0, 버려도 1.0)', () {
      expect(formatDistance(1049), '1.0km');
    });

    test('1099 m는 1.1km이 아니라 1.0km다', () {
      // toStringAsFixed(1)이면 1.1km가 된다. 거리를 부풀리면 사용자가 이미
      // 지나친 지점을 아직 남았다고 읽는다.
      expect(formatDistance(1099), '1.0km');
    });

    test('1100 m부터 1.1km', () {
      expect(formatDistance(1100), '1.1km');
    });

    test('10 km 이상도 소수 한 자리', () {
      expect(formatDistance(12400), '12.4km');
      expect(formatDistance(12000), '12.0km');
    });
  });

  group('망가진 입력은 빈 문자열', () {
    test('음수·NaN·무한대', () {
      expect(formatDistance(-1), '');
      expect(formatDistance(double.nan), '');
      expect(formatDistance(double.infinity), '');
    });
  });
}
