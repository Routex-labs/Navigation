import 'package:flutter/foundation.dart';

import 'place_link.dart';

/// 링크로 받은 장소를 지도 셸이 가져갈 때까지 들고 있는 자리.
///
/// **한 개만 들고 있다.** 링크는 앱이 아직 화면을 세우기 전에도 도착한다(cold
/// start). 그때 곧바로 시트를 열려고 하면 열 `BuildContext`가 없어 아무 일도
/// 일어나지 않고, 사용자는 링크를 눌렀는데 지도만 보게 된다. 그래서 도착한 것을
/// 여기 두고, 화면이 준비된 뒤 가져가게 한다.
///
/// **같은 링크를 두 번 처리하지 않는다.** 하나의 URI가 최초 URI와 stream 양쪽으로
/// 연달아 오는 경우가 있고, 그대로 두면 시트가 두 번 열린다.
class PlaceLinkInbox extends ValueNotifier<PlaceLink?> {
  PlaceLinkInbox({this.origin = placeLinkOrigin}) : super(null);

  /// 우리 링크로 인정할 주소. 기본은 빌드에 박힌 값이고, 테스트만 바꿔 넣는다.
  final String origin;

  Uri? _lastSeen;

  /// 받은 URI를 해석해 보관한다. 우리 링크가 아니거나 방금 본 것이면 무시한다.
  ///
  /// **처리한 뒤에도 [_lastSeen]은 지우지 않는다.** 지우면 stream이 같은 URI를 한 번
  /// 더 흘렸을 때 같은 시트가 다시 열린다. 사용자가 링크를 다시 누르면 OS가 새
  /// 이벤트를 주므로 같은 주소라도 그때는 열려야 하지만, 그건 화면이 이미 그 장소를
  /// 보고 있는 상태라 다시 여는 것이 손해가 아니다 — 여기서는 **연달아 온 중복만**
  /// 막는다.
  void offer(Uri uri) {
    if (uri == _lastSeen) return;
    _lastSeen = uri;
    final link = parsePlaceLink(uri, origin: origin);
    if (link == null) return;
    value = link;
  }

  /// 화면이 가져갔다. 다음 링크를 받을 준비를 한다.
  void take() => value = null;
}
