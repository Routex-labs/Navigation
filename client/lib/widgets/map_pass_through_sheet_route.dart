import 'package:flutter/material.dart';

/// 시트 **위쪽 빈 자리로 들어온 포인터를 지도에 넘기는** 바텀시트 라우트.
///
/// 포인터를 삼키는 겹이 셋이고 **하나라도 남으면 증상은 그대로다** — ① `ModalBarrier`
/// (투명이어도 `opaque`라 전부 흡수, 이 라우트가 비운다) ② 시트를 감싸는 전체 화면
/// `GestureDetector(opaque)`(이 라우트를 쓰는 시트는 두면 안 된다) ③ 지도 제스처
/// 잠금(웹에서만).
///
/// **바깥을 눌러 닫기를 잃는 것은 의도된 교환이다** — 원한 것이 "시트를 놔둔 채 지도를
/// 움직이는 것"이라 그 동작 자체가 요구와 충돌한다. 닫기는 X·뒤로·끌어내리기가 맡는다.
class MapPassThroughSheetRoute<T> extends ModalBottomSheetRoute<T> {
  MapPassThroughSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.backgroundColor,
    super.shape,
    super.isDismissible,
    super.sheetAnimationStyle,
    this.crossFade = false,
  });

  /// 제자리에서 나타난다 — **창이 움직이지 않고 내용만 바뀐다.**
  ///
  /// 이미 떠 있는 시트를 다른 매장으로 갈아 끼울 때 쓴다. 첫 등장에는 쓰지
  /// 않는다: 바닥에서 올라오는 동작이 "새로 떴다"를 말해 준다.
  ///
  /// **떠 있는 동안 바뀔 수 있다.** 나가기 직전에 켜면 그 시트도 내려가지 않고
  /// 사라진다(`beginPlaceDetailCrossFadeExit`). 경위는
  /// `docs/client/kakao-map-indoor-observation.md` S절.
  bool crossFade;

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!crossFade) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    // 슬라이드를 걷어내고 투명도만 남긴다. 이 자리에서 바뀌는 것은 위치가
    // 아니라 내용이다.
    return FadeTransition(opacity: animation, child: child);
  }
}
