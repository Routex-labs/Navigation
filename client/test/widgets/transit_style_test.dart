/// 대중교통 표현 규칙 — 색·아이콘·시간·거리·요금 표기.
///
/// 같은 노선이 **세 군데에 동시에 보인다**(시트의 칩, 하단 요약 카드, 지도 위
/// 선). 셋이 어긋나면 사용자는 그것이 같은 구간인지 알 수 없다. 그래서 값이
/// 아니라 **규칙**을 못 박는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/transit_route.dart';
import 'package:navigation_client/widgets/transit_style.dart';

TransitLeg _leg(TransitMode mode, {String? colorHex, int seconds = 600}) =>
    TransitLeg(
      mode: mode,
      sectionTimeSeconds: seconds,
      distanceMeters: 1000,
      points: const [LatLng(37.5, 127.0)],
      routeColorHex: colorHex,
    );

void main() {
  group('수단 구분 — 문서가 말하는 목적', () {
    test('모든 수단이 서로 다른 색이다', () {
      // "어떤 노선인지 모를 때도 탈것과 도보가 한눈에 갈리는 게 목적"이다.
      // 두 수단이 같은 색이면 그 목적이 깨진다.
      final colors = TransitMode.values.map(transitModeColor).toList();
      expect(colors.toSet().length, TransitMode.values.length);
    });

    test('모든 수단이 서로 다른 아이콘이다', () {
      final icons = TransitMode.values.map(transitModeIcon).toList();
      expect(icons.toSet().length, TransitMode.values.length);
    });
  });

  group('구간 색', () {
    test('노선 고유색이 있으면 그것을 쓴다', () {
      // 사용자가 역 안내판에서 보는 색과 같아야 "그 파란 버스"가 맞는지 안다.
      final leg = _leg(TransitMode.bus, colorHex: '#FF6600');
      expect(transitLegColor(leg).toARGB32(), 0xFFFF6600);
      expect(transitLegColorHex(leg), '#FF6600');
    });

    test('노선 고유색이 없으면 수단 기본색으로 떨어진다', () {
      final leg = _leg(TransitMode.subway);
      expect(transitLegColor(leg), transitModeColor(TransitMode.subway));
    });

    test('색 문자열이 깨져 있어도 터지지 않고 기본색으로 떨어진다', () {
      // 백엔드가 주는 값이라 형식을 보장할 수 없다. 여기서 던지면 경로 목록이
      // 통째로 안 뜬다.
      final broken = _leg(TransitMode.bus, colorHex: '#XYZXYZ');
      expect(transitLegColor(broken), transitModeColor(TransitMode.bus));
    });

    test('hex 문자열과 Color가 같은 색을 가리킨다', () {
      // 지도는 문자열을, 시트는 Color를 쓴다. 둘이 갈라지면 같은 구간이
      // 화면마다 다른 색이 된다.
      for (final mode in TransitMode.values) {
        final leg = _leg(mode);
        final fromHex = int.parse(
          transitLegColorHex(leg).substring(1),
          radix: 16,
        );
        expect(
          transitLegColor(leg).toARGB32() & 0xFFFFFF,
          fromHex,
          reason: '$mode에서 두 표현이 어긋난다',
        );
      }
    });
  });

  group('소요 시간', () {
    test('0초라도 1분으로 올린다', () {
      // "0분"은 "안 걸린다"가 아니라 "계산이 안 됐다"로 읽힌다.
      expect(formatTransitDuration(0), '1분');
      expect(formatTransitDuration(1), '1분');
    });

    test('올림이다 — 61초는 2분이다', () {
      expect(formatTransitDuration(60), '1분');
      expect(formatTransitDuration(61), '2분');
      expect(formatTransitDuration(1440), '24분');
    });

    test('한 시간을 넘으면 시간과 분으로 나눈다', () {
      expect(formatTransitDuration(3600), '1시간');
      expect(formatTransitDuration(3660), '1시간 1분');
      expect(formatTransitDuration(4320), '1시간 12분');
    });

    test('하루를 넘겨도 하루에서 멈춘다', () {
      // 상한이 없으면 파싱 오류로 온 거대한 값이 그대로 화면에 찍힌다.
      expect(formatTransitDuration(60 * 60 * 24), '24시간');
      expect(formatTransitDuration(60 * 60 * 999), '24시간');
    });
  });

  group('거리', () {
    test('1km 미만은 미터로 반올림한다', () {
      expect(formatTransitDistance(0), '0m');
      expect(formatTransitDistance(480.4), '480m');
      expect(formatTransitDistance(999.4), '999m');
    });

    test('1km부터는 소수 한 자리 km다', () {
      expect(formatTransitDistance(1000), '1.0km');
      expect(formatTransitDistance(12400), '12.4km');
    });
  });

  group('요금', () {
    test('천 단위마다 쉼표를 넣는다', () {
      expect(formatTransitFare(0), '0원');
      expect(formatTransitFare(500), '500원');
      expect(formatTransitFare(1500), '1,500원');
      expect(formatTransitFare(12345), '12,345원');
      expect(formatTransitFare(1234567), '1,234,567원');
    });

    test('세 자리 경계에서 쉼표가 앞에 붙지 않는다', () {
      // 1000이 ",1,000"이 되는 실수가 흔한 자리다.
      expect(formatTransitFare(1000), '1,000원');
      expect(formatTransitFare(100), '100원');
    });
  });
}
