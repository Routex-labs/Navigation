import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/routing/place_link.dart';

/// 공유 링크가 **다른 장소를 열지 않는다**는 것을 고정한다.
///
/// 링크는 앱 밖에서 오는 유일한 입력이다. 너그럽게 읽으면 여분 segment 하나로
/// 엉뚱한 매장이 열리고, 엄격하기만 하면 한글 id가 든 정상 링크가 조용히 무시된다.
/// 두 방향을 함께 못박는다.
const _origin = 'https://example.test';

void main() {
  group('만들고 다시 읽기', () {
    test('만든 링크를 그대로 되읽는다', () {
      final link = buildPlaceLink(
        buildingId: 'thehyundai-seoul',
        placeId: 'PO-HU40njvml1512',
        origin: _origin,
      );

      expect(
        link.toString(),
        '$_origin/place/thehyundai-seoul/PO-HU40njvml1512',
      );
      expect(
        parsePlaceLink(link!, origin: _origin),
        const PlaceLink(
          buildingId: 'thehyundai-seoul',
          placeId: 'PO-HU40njvml1512',
        ),
      );
    });

    test('한글과 공백이 든 id도 왕복한다', () {
      // id는 서버가 정하는 값이라 언제든 이런 것이 들어올 수 있다. 인코딩이 빠지면
      // 링크가 공백에서 끊겨 메신저가 절반만 링크로 잡는다.
      const building = '더현대 서울';
      const place = '스타벅스 리저브';
      final link = buildPlaceLink(
        buildingId: building,
        placeId: place,
        origin: _origin,
      );

      expect(link.toString(), contains('%20'));
      expect(
        parsePlaceLink(link!, origin: _origin),
        const PlaceLink(buildingId: building, placeId: place),
      );
    });
  });

  group('만들지 않는 경우', () {
    test('origin이 없으면 링크를 만들지 않는다', () {
      // 링크를 만들 수는 있어도 그 주소가 증명 파일을 내지 못하면, 받은 사람에게는
      // 브라우저로 새는 링크일 뿐이다.
      expect(placeLinkEnabled(''), isFalse);
      expect(buildPlaceLink(buildingId: 'b', placeId: 'p', origin: ''), isNull);
    });

    test('https가 아니면 만들지 않는다', () {
      // 두 OS 모두 https로만 링크 소유를 검증한다.
      expect(placeLinkEnabled('http://example.test'), isFalse);
      expect(
        buildPlaceLink(
          buildingId: 'b',
          placeId: 'p',
          origin: 'http://example.test',
        ),
        isNull,
      );
    });

    test('빈 id로는 만들지 않는다', () {
      // `/place//p`는 잘못된 링크가 아니라 **다른 장소**를 가리키는 링크가 된다.
      expect(
        buildPlaceLink(buildingId: '  ', placeId: 'p', origin: _origin),
        isNull,
      );
      expect(
        buildPlaceLink(buildingId: 'b', placeId: '', origin: _origin),
        isNull,
      );
    });
  });

  group('읽지 않는 경우', () {
    PlaceLink? parse(String url) =>
        parsePlaceLink(Uri.parse(url), origin: _origin);

    test('다른 host는 읽지 않는다', () {
      expect(parse('https://evil.test/place/b/p'), isNull);
    });

    test('scheme이 다르면 읽지 않는다', () {
      expect(parse('http://example.test/place/b/p'), isNull);
    });

    test('segment가 모자라거나 남으면 읽지 않는다', () {
      expect(parse('$_origin/place/b'), isNull);
      expect(parse('$_origin/place/b/p/extra'), isNull);
      expect(parse('$_origin/b/p'), isNull, reason: 'place 접두가 없다');
    });

    test('공백만 있는 id는 읽지 않는다', () {
      expect(parse('$_origin/place/%20/p'), isNull);
      expect(parse('$_origin/place/b/%20'), isNull);
    });

    test('origin이 없으면 아무 링크도 읽지 않는다', () {
      expect(
        parsePlaceLink(Uri.parse('$_origin/place/b/p'), origin: ''),
        isNull,
      );
    });
  });
}
