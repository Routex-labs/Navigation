import 'package:flutter/material.dart';

/// 시트 **위쪽 빈 자리로 들어온 포인터를 지도에 그대로 넘기는** 바텀시트 라우트.
///
/// ## 왜 필요한가 — 지도가 보이는데 만질 수 없었다
///
/// 지도 위에 뜨는 시트(매장 상세·카테고리 목록)는 화면 아래 절반만 덮는다.
/// 위쪽에는 방금 고른 매장이 지도에 그대로 보이는데, 그 위에서 **끌기·확대·회전이
/// 전부 먹지 않았다.** 사용자에게는 "터치가 안 먹는" 화면이다.
///
/// 세 겹이 겹쳐 있었고, 하나라도 남으면 증상은 그대로다.
///
///  1. `showModalBottomSheet`의 **`ModalBarrier`** — `barrierColor`를 투명으로
///     주면 색만 사라진다. barrier는 `HitTestBehavior.opaque`라 **투명해도
///     포인터는 전부 흡수한다.** 이 라우트가 [buildModalBarrier]를 비워 없앤다.
///  2. 시트 본문을 감싸던 **전체 화면 `GestureDetector(opaque)`** — 이 라우트를
///     쓰는 시트는 그 래퍼를 두면 안 된다. `isScrollControlled: true`라 라우트의
///     child가 화면 전체 높이를 차지하므로, 시트가 아래 절반만 그려져도 위쪽
///     투명 영역이 `opaque` 탓에 히트 테스트에 걸린다. `DraggableScrollableSheet`
///     를 `expand: false`로 두면 실제로 그려지는 영역만 잡히고 그 위는 지도로
///     흘러간다. 시트 본문은 builder 안쪽의 `GestureDetector(onTap: () {})`가
///     계속 막는다.
///  3. `MapShellScreen._withMapsLocked`의 **지도 제스처 잠금** — 그쪽 주석 참고
///     (웹에서만 건다).
///
/// ## 잃는 것 — 바깥을 눌러 닫기
///
/// barrier가 사라지면 "시트 밖을 눌러 닫기"도 함께 사라진다. 그 자리를 지도가
/// 가져간다 — 다른 매장을 누르면 시트가 그 매장으로 바뀌고, 닫기는 X 버튼과
/// 뒤로 가기, 아래로 끌어내리기가 맡는다. **이건 의도된 교환이다.** 사용자가
/// 원한 것은 "시트를 놔둔 채로 지도를 움직이는 것"이라, 지도 위 포인터를 닫기
/// 신호로 쓰는 동작 자체가 그 요구와 충돌한다.
///
/// [ModalBottomSheetRoute]를 그대로 상속하는 이유는 애니메이션·드래그·safe area
/// 같은 나머지 동작을 한 줄도 다시 구현하지 않기 위해서다. 바꾸는 것은 barrier
/// 하나뿐이다.
class MapPassThroughSheetRoute<T> extends ModalBottomSheetRoute<T> {
  MapPassThroughSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.backgroundColor,
    super.shape,
    super.isDismissible,
    super.sheetAnimationStyle,
  });

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();
}
