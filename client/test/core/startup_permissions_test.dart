import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/service_locator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('걸음 센서 권한은 플랫폼에 맞는 것을 고른다', () {
    // iOS는 Motion & Fitness, 그 외(Android)는 ActivityRecognition이다. 가속도·
    // 자력계 원시값은 권한이 필요 없어 목록에 넣지 않는다.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(pedometerPermission, Permission.sensors);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(pedometerPermission, Permission.activityRecognition);
    debugDefaultTargetPlatformOverride = null;
  });

  test('권한 플러그인을 쓸 수 없으면 자동 시작을 막지 않는다', () async {
    // 웹 개발 실행·테스트 환경에서 false를 돌려주면 플러그인이 없다는 이유만으로
    // PDR이 아예 시작하지 못한다. 센서 시작 실패는 driver가 degraded로 알린다.
    expect(await defaultIsPedometerPermissionGranted(), isTrue);
  });
}
