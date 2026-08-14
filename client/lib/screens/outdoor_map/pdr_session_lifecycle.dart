/// PDR 센서 세션의 **수명**을 소유한다 — 언제 켜고 끄고, 아직 끝나지 않은 정지를
/// 누가 기다리는가. 앵커·궤적·층 결속은 화면 상태와 얽혀 있어 여기 없다.
///
/// 화면 상태는 소유하지 않고 **호출 시점에 읽는다**(기다리는 사이에 바뀐다).
///
/// 한 곳에 모은 이유는 **정지가 즉시 끝나지 않기** 때문이다 — `stopping`을 "돌고
/// 있다"로 읽는 코드가 하나라도 있으면 세션 없이 앵커만 찍힌다(실기기에서 "나갔다
/// 들어오면 위치가 굳는다").
library;

import 'dart:async';

import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';

class PdrSessionLifecycle {
  PdrSessionLifecycle({
    required this.driver,
    required this.isPermissionGranted,
  });

  final IndoorNavigationController driver;

  /// 걸음 센서 권한 게이트. 전역 seam을 **호출 시점에** 읽도록 클로저로 받는다 —
  /// 테스트가 setUp에서 갈아끼우고 tearDown에서 되돌리기 때문이다.
  final Future<bool> Function() isPermissionGranted;

  /// 진행 중인 PDR 세션 정지. 다음 시작이 이걸 기다린다([awaitStop]).
  Future<void>? _stopInFlight;

  bool get isIdle => driver.currentRuntimeStatus.state == PdrRuntimeState.idle;

  /// 세션 정지를 발사하고 **기다리지 않는다.**
  ///
  /// 사용자가 건물을 나갔다고 판정했을 때 부른다. 화면 상태는 지금 즉시 맞아야
  /// 하므로 여기서 붙잡지 않고, 대신 그 Future를 남겨 다음 시작이 기다리게 한다
  /// ([awaitStop]).
  void stopWithoutWaiting() {
    final stopping = driver.stopGuidance();
    _stopInFlight = stopping;
    unawaited(stopping);
  }

  /// 아직 끝나지 않은 [IndoorNavigationIntents.stopGuidance]가 있으면 기다린다.
  ///
  /// 기다리지 않으면 시작 쪽이 `stopping`을 "이미 세션이 돌고 있구나"로 잘못
  /// 읽는다. 그러면 세션 없이 앵커만 찍힌다 — 화면에는 실내 위치가 **뜨는데**
  /// (그 마커는 PDR이 아니라 실내 위치 추정값이 그린다) 걸음이 쌓이는 세션이
  /// 없어 **한 발짝도 움직이지 않는다.**
  Future<void> awaitStop() async {
    final stopping = _stopInFlight;
    if (stopping == null) return;
    try {
      await stopping;
    } on Object {
      // 정지에 실패해도 시작은 시도해야 한다. 여기서 멈추면 센서가 한 번
      // 어긋난 뒤로 실내 위치가 영영 안 잡힌다.
    }
    if (identical(_stopInFlight, stopping)) _stopInFlight = null;
  }

  /// 세션이 꺼져 있으면 켠다. 층을 **두 번** 읽는다 — 정지와 권한 조회를 기다리는
  /// 사이에 사용자가 층을 바꾸거나 화면을 떠날 수 있다.
  ///
  /// 두 클로저의 조건이 다른 것은 의도다. [readStartableFloor]는 그래프까지 보고,
  /// [readActiveFloor]는 **보지 않는다** — 재확인이 그래프까지 보면 같은 층을 다시
  /// 로드하는 찰나에 시작이 취소된다.
  Future<void> startIfIdle({
    required String? Function() readStartableFloor,
    required String? Function() readActiveFloor,
  }) async {
    // 아래 idle 판정이 정지 중인 세션을 "돌고 있다"로 읽지 않게 한다.
    await awaitStop();
    final floor = readStartableFloor();
    if (floor == null) return;
    if (!isIdle) return;
    if (!await isPermissionGranted()) return;
    if (readActiveFloor() != floor) return;
    if (!isIdle) return;
    await driver.startGuidance(floorId: floor);
  }
}
