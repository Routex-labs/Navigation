import 'package:flutter/material.dart';

/// 시트 **위쪽 빈 자리로 들어온 포인터를 지도에 그대로 넘기는** 바텀시트 라우트.
///
/// 시트 위쪽에 지도가 보이는데 **끌기·확대·회전이 전부 먹지 않던** 문제를 푼다.
/// 포인터를 삼키는 겹이 셋이고, **하나라도 남으면 증상은 그대로다.**
///
///  1. `ModalBarrier` — `barrierColor`를 투명으로 줘도 `HitTestBehavior.opaque`라
///     **포인터는 전부 흡수한다.** 이 라우트가 [buildModalBarrier]를 비워 없앤다.
///  2. 시트를 감싸는 **전체 화면 `GestureDetector(opaque)`** — 이 라우트를 쓰는 시트는
///     그 래퍼를 두면 안 된다. `DraggableScrollableSheet`를 `expand: false`로 두면
///     실제로 그려지는 영역만 히트 테스트에 잡힌다.
///  3. `MapShellScreen._withMapsLocked`의 지도 제스처 잠금(웹에서만 건다).
///
/// **바깥을 눌러 닫기를 잃는 것은 의도된 교환이다.** 사용자가 원한 것이 "시트를 놔둔
/// 채 지도를 움직이는 것"이라, 지도 위 포인터를 닫기 신호로 쓰는 동작 자체가 그 요구와
/// 충돌한다. 닫기는 X 버튼·뒤로 가기·끌어내리기가 맡는다.
///
/// [ModalBottomSheetRoute]를 그대로 상속해 **barrier 하나만** 바꾼다.
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
