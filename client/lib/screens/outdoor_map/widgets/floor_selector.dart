import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 좌측 하단에 놓이는 세로 층 선택기.
///
/// 생김새·노출 수·스크롤은 [RoutexFloorSelector]가 갖는다. 여기 남은 것은 **탭을
/// 흡수하는 껍데기 하나**다 — MapLibre가 PlatformView라, 지도 위 Flutter 오버레이를
/// 탭해도 그 아래 네이티브 지도의 `onMapClick`이 함께 발화해 뒤에 있는 매장이 같이
/// 눌린다. Kit 컴포넌트는 셀 안쪽만 흡수하므로 구분선·모서리 픽셀이 지도로 샌다.
///
/// 실내 지도 화면과 야외 지도의 실내 진입 오버레이가 같은 UI를 공유하도록 양쪽에서
/// 이 위젯을 재사용한다. 하단 바 baseline과 맞추는 값은 `floorSelectorBottomOffset`이
/// 별도로 갖는다.
class FloorSelector extends StatelessWidget {
  const FloorSelector({
    super.key,
    required this.floors,
    required this.selectedFloor,
    required this.onSelectFloor,
  });

  final List<String> floors;
  final String selectedFloor;
  final ValueChanged<String> onSelectFloor;

  @override
  Widget build(BuildContext context) {
    if (floors.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: RoutexFloorSelector(
        options: [
          for (final floor in floors)
            RoutexFloorOption(id: floor, label: floor),
        ],
        selectedId: selectedFloor,
        // 이미 보고 있는 층을 다시 눌러도 다시 그리지 않는다 — 진행률 기준점만
        // 흔들린다.
        onSelected: (floor) {
          if (floor != selectedFloor) onSelectFloor(floor);
        },
      ),
    );
  }
}
