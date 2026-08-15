import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/clipboard_confirmation.dart';

/// "복사했습니다"가 두 번 뜨던 문제의 판정을 잠근다.
///
/// 실기기(Android 13+)에서 시스템 확인 UI 위에 앱 토스트가 겹쳐 두 번 보였다.
/// 그렇다고 전부 끄면 minSdk 24라 구형 기기에서 아무 피드백도 없어진다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => setClipboardAnnouncementForTest(null));

  test('Android가 아니면 앱이 알린다 — 시스템 확인 UI가 없다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(await shouldAnnounceClipboardCopy(), isTrue);
  });

  test('한 번 정해지면 다시 조회하지 않는다 — 기기 버전은 안 바뀐다', () async {
    setClipboardAnnouncementForTest(false);
    expect(await shouldAnnounceClipboardCopy(), isFalse);
    // 플랫폼을 바꿔도 캐시가 이긴다(플랫폼 채널을 다시 타지 않는다는 뜻).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await shouldAnnounceClipboardCopy(), isFalse);
  });

  test('조회에 실패하면 알리는 쪽으로 기운다', () async {
    // 플랫폼 채널이 없는 테스트 환경 = 조회 실패와 같은 상황이다.
    // 중복은 거슬릴 뿐이지만 침묵은 복사 여부를 알 수 없게 만든다.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(await shouldAnnounceClipboardCopy(), isTrue);
  });

  test('경계값은 33이다 — Android 13부터 시스템이 띄운다', () {
    expect(kSystemClipboardToastSdk, 33);
  });
}
