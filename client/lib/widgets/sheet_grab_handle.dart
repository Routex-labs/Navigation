import 'package:flutter/material.dart';

/// 모달 바텀 시트 맨 위에 놓는 회색 손잡이 바 — 끌어서 크기를 바꿀 수 있다는 표시다.
///
/// **끌 수 있는 시트에만 둔다.** 고정 높이 시트에 두면 없는 조작을 약속하게 된다.
/// 어느 시트가 어느 쪽인지는 `client/test/widgets/sheet_grab_handle_test.dart`가
/// 시트마다 열어 확인한다.
///
/// **스크롤 뷰 안에 넣어야 실제로 끌린다.** [DraggableScrollableSheet]는 자기
/// scrollController가 받은 드래그로만 크기가 바뀌어, 바깥에 고정하면 끌리지 않는
/// 장식이 된다. 그래서 호출부는 스크롤 콘텐츠의 첫 항목으로 둔다.
///
/// Material 3의 `showDragHandle`을 쓰지 않는 이유는 이 앱의 시트가 투명 배경 +
/// 전체 프레임 조합이라 기본 손잡이가 **화면 중간 허공**에 그려져서다.
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
