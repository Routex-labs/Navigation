import 'dart:async';

import 'package:flutter/material.dart';

/// 지도 위 시트를 **한 번에 한 장**으로 유지한다 — 두 장째가 뜨면 앞의 것을 걷는다.
///
/// 세는 대상은 `ModalBottomSheetRoute`뿐이라, 의도적으로 겹치는 것(대중교통
/// 상세·사진 뷰어·PDR 입력)은 route 타입이 달라 **표시 없이 예외**가 된다.
///
/// 왜 입구마다 막지 않고 여기서 막는지, 왜 `pop`이 아니라 `removeRoute`인지는
/// `docs/client/sheet-exclusivity.md`.
class SheetStackGuard extends NavigatorObserver {
  final _open = <ModalBottomSheetRoute<dynamic>>[];

  /// 지금 살아 있는 시트 라우트 수. 불변식대로면 늘 0 또는 1이다.
  int get openCount => _open.length;

  /// **겹친 것을 실제로 걷어낸 횟수.** 테스트가 "정말 일했나"를 재는 데 쓴다 —
  /// 0이면 겹친 적이 없었다는 뜻이지, 막았다는 뜻이 아니다.
  int get caughtStackings => _caught;
  int _caught = 0;

  /// 테스트가 앱을 새로 띄울 때 부른다 — 앞 테스트가 두고 간 라우트는 이미
  /// 버려진 Navigator의 것이라 세면 안 된다.
  @visibleForTesting
  void resetForTest() {
    _open.clear();
    _caught = 0;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! ModalBottomSheetRoute) return;
    final stale = _open.toList();
    _open
      ..clear()
      ..add(route);
    if (stale.isEmpty) return;
    _caught += stale.length;
    // 지금은 push 처리 한복판이다. 그 자리에서 Navigator의 목록을 건드리지 않고
    // 마이크로태스크로 미룬다 — 프레임을 그리기 전에 실행되므로 두 장이 함께
    // 보이는 프레임은 생기지 않는다.
    scheduleMicrotask(() {
      for (final other in stale) {
        other.navigator?.removeRoute(other);
      }
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _open.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _open.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _open.remove(oldRoute);
    if (newRoute is ModalBottomSheetRoute) _open.add(newRoute);
  }
}

/// 앱에 하나뿐인 관찰자. `MaterialApp`의 `navigatorObservers`에 넣는다.
///
/// 전역인 이유는 Navigator가 하나뿐이어서다 — 이 앱에는 push할 다른 화면이 없고
/// (`app.dart`), 시트·오버레이가 전부 그 하나 위에 얹힌다.
final sheetStackGuard = SheetStackGuard();
