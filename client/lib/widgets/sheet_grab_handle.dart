import 'package:flutter/material.dart';

/// 아래에서 올라오는 모달 바텀 시트 맨 위에 놓는 회색 손잡이 바.
///
/// 시트를 위아래로 끌어 크기를 바꿀 수 있다는 것을 알리는 표시다. 이 표시가
/// 없으면 시트가 고정 높이 카드처럼 보여서, 목록이 잘려 있어도 사용자가 위로
/// 끌어 올릴 수 있다는 걸 모른 채 스크롤만 하게 된다.
///
/// **스크롤 뷰 안에 넣어야 실제로 끌린다.** [DraggableScrollableSheet]는
/// 자기 scrollController가 받은 드래그로만 크기가 바뀌므로, 손잡이를 스크롤
/// 뷰 바깥에 고정으로 두면 보기만 하고 끌리지 않는 장식이 된다. 그래서
/// 호출부는 이 위젯을 스크롤 콘텐츠의 첫 항목으로 둔다
/// ([SliverToBoxAdapter] 포함). 스크롤이 아예 없는 고정 높이 시트에서는
/// `showModalBottomSheet`의 기본 드래그(끌어서 닫기)가 시트 전체에 걸려 있어
/// 어디에 두든 동작한다.
///
/// Material 3의 `showModalBottomSheet(showDragHandle: true)`를 쓰지 않는 이유는
/// 이 앱의 시트들이 `backgroundColor: Colors.transparent` + 프레임 전체를
/// 차지하는 [DraggableScrollableSheet] 조합이라, 기본 손잡이가 실제로 보이는
/// 시트 상단이 아니라 **투명한 프레임 맨 위**(화면 중간 허공)에 그려지기 때문이다.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  /// 시안(네이버 지도 등 국내 지도 앱) 기준 치수. 너무 얇으면 표시가 안 보이고
  /// 너무 두꺼우면 제목보다 눈에 띈다.
  static const double _width = 40;
  static const double _height = 4;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '시트 크기 조절 손잡이',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Container(
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(_height / 2),
            ),
          ),
        ),
      ),
    );
  }
}
