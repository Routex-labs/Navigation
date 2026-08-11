import 'dart:async';

import 'package:flutter/material.dart';

/// 지도 내용을 최대한 가리지 않는 compact floating toast.
///
/// ScaffoldMessenger를 사용하므로 화면 전환·접근성 동작은 SnackBar와 같지만,
/// 하단 컨트롤 위에 작은 카드 형태로 떠 일반 배너보다 지도 가림이 적다.
void showDebugToast(
  BuildContext context, {
  required String message,
  double bottomOffset = 112,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final withAction = actionLabel != null && onAction != null;
  final accessibleNavigation =
      MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(28, 0, 28, bottomOffset),
      duration: withAction
          ? const Duration(seconds: 5)
          : const Duration(milliseconds: 2400),
      elevation: 6,
      backgroundColor: const Color(0xF0212124),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      content: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
      action: withAction
          ? SnackBarAction(
              label: actionLabel,
              textColor: const Color(0xFFAECBFA),
              onPressed: onAction,
            )
          : null,
    ),
  );
  if (withAction && accessibleNavigation) {
    // 접근성 내비게이션(TalkBack 등)이 켜져 있으면 Flutter는 **액션 달린**
    // SnackBar의 자동 해제 타이머를 무시한다 — 액션을 누를 시간을 보장하려는
    // 동작이지만, 이 토스트의 액션은 보조 손잡이일 뿐이라 영원히 남는 쪽이
    // 더 해롭다. 상한 시간이 지나도 안 닫혀 있으면 강제로 닫는다.
    // (`controller.close`는 이 SnackBar가 아직 떠 있을 때만 부른다 — 이미
    // 닫혔다면 `closed`가 먼저 완료돼 onTimeout 자체가 실행되지 않는다.)
    //
    // 그 상황에만 타이머를 건다. 일반 내비게이션에서는 프레임워크의 5초
    // 타이머가 정상 동작하므로 이 타이머는 할 일 없이 8초를 살아만 있고,
    // 테스트에서는 그 잔여 타이머가 "Timer still pending"으로 걸린다.
    unawaited(
      controller.closed.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          controller.close();
          return SnackBarClosedReason.timeout;
        },
      ),
    );
  }
}
