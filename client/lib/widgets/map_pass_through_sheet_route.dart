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
  });

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();
}
