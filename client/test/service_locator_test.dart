import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/features/indoor_navigation/platform/android_pdr_motion_source.dart';
import 'package:navigation_client/features/indoor_navigation/platform/ios_pdr_motion_source.dart';
import 'package:navigation_client/features/indoor_navigation/platform/pdr_motion_source.dart';
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

  test('모바일 테스트에서 권한 플러그인만 없으면 자동 시작을 막지 않는다', () async {
    // Flutter 단위 테스트의 기본 Android 환경에서는 플러그인이 없더라도 센서
    // 시작 실패를 driver의 degraded 상태로 처리한다.
    expect(await defaultIsPedometerPermissionGranted(), isTrue);
  });

  test('PDR 센서 소스는 모바일 네이티브 플랫폼에서만 생성한다', () {
    expect(
      createDefaultPdrMotionSource(platform: TargetPlatform.iOS, isWeb: false),
      isA<IosPdrMotionSource>(),
    );
    expect(
      createDefaultPdrMotionSource(
        platform: TargetPlatform.android,
        isWeb: false,
      ),
      isA<AndroidPdrMotionSource>(),
    );
    expect(
      createDefaultPdrMotionSource(
        platform: TargetPlatform.linux,
        isWeb: false,
      ),
      isA<UnsupportedPdrMotionSource>(),
    );
    expect(
      createDefaultPdrMotionSource(platform: TargetPlatform.iOS, isWeb: true),
      isA<UnsupportedPdrMotionSource>(),
    );
  });

  test('Linux에서는 네이티브 채널을 열지 않도록 PDR 자동 시작을 막는다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      expect(await defaultIsPedometerPermissionGranted(), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
