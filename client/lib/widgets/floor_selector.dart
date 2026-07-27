import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 좌측 하단 검색창 옆에 놓이는 세로 층 선택기. 어두운 stadium(약통) 형태
/// 안에 층 라벨을 세로로 나열하고, 한 번에 최대 5개까지만 노출한다. 층이 그
/// 이상이면 세로 스크롤로 나머지를 볼 수 있고, 현재 층은 파란 캡슐로 강조된다.
///
/// 층이 하나뿐이면 스크롤이 의미 없으므로 단일 셀만 표시한다.
///
/// 실내 지도 화면과 야외 지도의 실내 진입 오버레이가 같은 UI를 공유하도록
/// 야외/실내 양쪽에서 이 위젯을 재사용한다. MapShellScreen의 하단 바 baseline
/// 과 시각적으로 정렬되도록 [floorSelectorBottomOffset]도 함께 노출한다.
class FloorSelector extends StatefulWidget {
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
  State<FloorSelector> createState() => _FloorSelectorState();
}

class _FloorSelectorState extends State<FloorSelector> {
  // 한 셀 높이·표시할 셀 수·내부 여백은 시안(어두운 pill, 5개 노출)에 맞춘 값.
  // 셀 높이를 바꾸면 pill 총 높이와 스크롤 위치 계산이 함께 달라진다.
  // 하단 바의 "위치 지정 / 위치 보정" 버튼(44px 원형)과 같은 baseline 옆에 놓이므로
  // 너무 크면 지도 좌측을 크게 가린다 — 셀·폰트·폭을 모두 축소해서 얹는다.
  static const double _cellHeight = 36;
  static const int _maxVisibleCells = 5;
  static const double _pillPaddingV = 4;
  static const double _pillWidth = 44;
  static const double _labelFontSize = 14;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 첫 프레임 후 현재 층이 뷰포트 중앙 근처에 오도록 스크롤. controller에
    // 아직 clients가 붙기 전이라 postFrame에서 실행한다.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelected(animate: false),
    );
  }

  @override
  void didUpdateWidget(covariant FloorSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFloor != widget.selectedFloor ||
        oldWidget.floors != widget.floors) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSelected(animate: true),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected({required bool animate}) {
    if (!_scrollController.hasClients) return;
    final index = widget.floors.indexOf(widget.selectedFloor);
    if (index < 0) return;
    final viewport = _maxVisibleCells * _cellHeight;
    final rawTarget = index * _cellHeight - viewport / 2 + _cellHeight / 2;
    final position = _scrollController.position;
    final target = rawTarget.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final floors = widget.floors;
    if (floors.isEmpty) return const SizedBox.shrink();

    final visibleCount = math.min(floors.length, _maxVisibleCells);
    final listHeight = visibleCount * _cellHeight;

    // MapLibre가 PlatformView라, 지도 위 Flutter 오버레이를 탭해도 그 아래
    // 네이티브 지도의 onMapClick이 그대로 함께 발화해 뒤에 있는 매장이
    // 같이 눌리는 문제가 있다. 이 GestureDetector로 selector 영역의 모든
    // 탭을 opaque로 흡수해서 새어나가지 않게 한다. 내부 셀 InkWell은
    // nested라 자기 tap을 그대로 받는다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: _FloorPill(
        width: _pillWidth,
        listHeight: listHeight,
        paddingV: _pillPaddingV,
        child: floors.length == 1
            ? _FloorCell(
                label: floors.first,
                selected: true,
                height: _cellHeight,
                onTap: () {},
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: floors.length,
                itemExtent: _cellHeight,
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final floor = floors[index];
                  final selected = floor == widget.selectedFloor;
                  return _FloorCell(
                    label: floor,
                    selected: selected,
                    height: _cellHeight,
                    onTap: () {
                      if (!selected) widget.onSelectFloor(floor);
                    },
                  );
                },
              ),
      ),
    );
  }
}

/// 어두운 stadium(약통) 컨테이너. 내부 리스트/단일 셀을 감싸는 껍데기 역할.
class _FloorPill extends StatelessWidget {
  const _FloorPill({
    required this.width,
    required this.listHeight,
    required this.paddingV,
    required this.child,
  });

  final double width;
  final double listHeight;
  final double paddingV;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width / 2);
    return Container(
      width: width,
      height: listHeight + paddingV * 2,
      padding: EdgeInsets.symmetric(vertical: paddingV),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // 리스트 아이템이 pill 상·하 안쪽 반경을 넘어 그려지지 않도록 클립.
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

class _FloorCell extends StatelessWidget {
  const _FloorCell({
    required this.label,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: selected ? AppColors.indoor : Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: _FloorSelectorState._labelFontSize,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : AppColors.text.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
