/// 복사했다는 알림을 **우리가 띄워야 하는지** 판정한다.
///
/// Android 13(API 33)부터 시스템이 클립보드 복사 확인 UI를 스스로 띄운다. 그
/// 위에 앱 토스트를 하나 더 얹으면 "복사했습니다"가 두 번 뜬다(실기기 확인).
/// Android 공식 지침도 앱 확인을 띄우지 말라고 적는다.
///
/// 그렇다고 무조건 끄면 안 된다 — 이 앱의 minSdk는 24라 시스템 UI가 없는
/// Android 12 이하에서는 아무 피드백도 없어진다.
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// 시스템이 복사 확인을 대신 띄우기 시작한 Android SDK.
const int kSystemClipboardToastSdk = 33;

bool? _cached;

/// 복사 성공을 **앱이 알려야 하면** true.
///
/// 첫 호출만 플랫폼 채널을 타고 이후에는 캐시한다 — 기기 버전은 앱이 사는
/// 동안 바뀌지 않는다. 조회가 실패하면 **알리는 쪽으로 기운다**: 중복은 거슬릴
/// 뿐이지만 침묵은 복사가 됐는지 알 수 없게 만든다.
///
/// 실패(`복사하지 못했습니다`)는 이 판정과 무관하게 항상 알린다. 시스템은
/// 성공했을 때만 확인 UI를 띄운다.
Future<bool> shouldAnnounceClipboardCopy() async {
  if (_cached != null) return _cached!;
  if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
    return _cached = true;
  }
  try {
    final android = await DeviceInfoPlugin().androidInfo;
    return _cached = android.version.sdkInt < kSystemClipboardToastSdk;
  } catch (_) {
    return _cached = true;
  }
}

/// 테스트에서 판정을 고정한다. null이면 다음 호출이 다시 조회한다.
@visibleForTesting
void setClipboardAnnouncementForTest(bool? value) => _cached = value;
