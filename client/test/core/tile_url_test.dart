import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/tile_url.dart';

/// 타일 URL 규칙을 고정한다.
///
/// 실내 화면과 야외 오버레이가 **같은 함수**를 쓰게 만든 뒤에도, 버전을 붙이는
/// 조건이 흔들리면 같은 타일이 두 주소로 캐시돼 디스크에 두 벌이 쌓이고 한쪽만
/// 재검증 왕복을 계속 문다.
void main() {
  group('indoorTileUrl', () {
    test('MapLibre가 채울 z/x/y 자리표시자를 그대로 남긴다', () {
      final url = indoorTileUrl(buildingId: 'b1', floorName: 'B2');

      // 여기서 치환해 버리면 MapLibre가 타일 좌표를 넣을 자리가 없어진다.
      expect(url, contains('/tiles/{z}/{x}/{y}.mvt'));
      expect(url, contains('/buildings/b1/floors/B2/'));
    });

    test('revision이 있으면 v 파라미터로 붙는다', () {
      final url = indoorTileUrl(
        buildingId: 'b1',
        floorName: 'B2',
        tileRevision: 'abc123',
      );

      expect(url, endsWith('.mvt?v=abc123'));
    });

    test('revision이 없거나 비면 붙이지 않는다', () {
      // 구버전 백엔드는 tile_revision을 안 준다. 그때 `?v=`가 빈 값으로 붙으면
      // 서버가 버전이 있는 줄 알고 immutable을 줘서 낡은 타일이 1년간 눌러앉는다.
      expect(
        indoorTileUrl(buildingId: 'b1', floorName: 'B2'),
        isNot(contains('?v=')),
      );
      expect(
        indoorTileUrl(buildingId: 'b1', floorName: 'B2', tileRevision: ''),
        isNot(contains('?v=')),
      );
    });

    test('revision에 특수문자가 들어와도 URL이 깨지지 않는다', () {
      final url = indoorTileUrl(
        buildingId: 'b1',
        floorName: 'B2',
        tileRevision: 'a b&c',
      );

      expect(url, isNot(contains(' ')));
      expect(url, isNot(contains('&c')));
    });
  });
}
