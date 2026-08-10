import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/floor_camera_bearing.dart';

void main() {
  group('bearingToFollow', () {
    // 실내 heading은 가만히 서 있어도 몇 도씩 흔들린다. 그대로 따라 돌리면
    // 화면이 쉬지 않고 떨린다.
    test('데드밴드 안의 흔들림은 무시한다', () {
      expect(bearingToFollow(heading: 95, cameraBearing: 90), isNull);
    });

    test('데드밴드를 넘게 돌면 그 방향으로 맞춘다', () {
      expect(
        bearingToFollow(heading: 110, cameraBearing: 90),
        closeTo(110, 1e-9),
      );
    });

    // 359°와 1°는 2° 차이지 358° 차이가 아니다.
    test('북쪽을 지나는 흔들림도 최단 회전각으로 잰다', () {
      expect(bearingToFollow(heading: 1, cameraBearing: 359), isNull);
      expect(bearingToFollow(heading: 355, cameraBearing: 5), isNull);
    });

    test('북쪽을 지나 크게 돌면 맞춘다', () {
      expect(
        bearingToFollow(heading: 20, cameraBearing: 355),
        closeTo(20, 1e-9),
      );
    });

    // 모르는 방향으로 지도를 돌리는 것보다 안 돌리는 게 낫다.
    test('heading을 모르면 돌리지 않는다', () {
      expect(bearingToFollow(heading: null, cameraBearing: 90), isNull);
      expect(bearingToFollow(heading: double.nan, cameraBearing: 90), isNull);
    });

    test('카메라 각도를 모르면 첫 정렬로 보고 그대로 적용한다', () {
      expect(
        bearingToFollow(heading: 42, cameraBearing: null),
        closeTo(42, 1e-9),
      );
    });

    test('0~360 밖의 heading은 정규화해서 돌려준다', () {
      expect(
        bearingToFollow(heading: -90, cameraBearing: 0),
        closeTo(270, 1e-9),
      );
      expect(
        bearingToFollow(heading: 450, cameraBearing: 0),
        closeTo(90, 1e-9),
      );
    });

    // "위치 보정"을 눌렀는데 3° 어긋난 채로 두면 누른 보람이 없다.
    test('force면 데드밴드를 건너뛴다', () {
      expect(
        bearingToFollow(heading: 93, cameraBearing: 90, force: true),
        closeTo(93, 1e-9),
      );
    });

    test('force여도 heading을 모르면 돌리지 않는다', () {
      expect(
        bearingToFollow(heading: null, cameraBearing: 90, force: true),
        isNull,
      );
    });
  });
}
