import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 좌측 하단에 놓이는 세로 층 선택기. 흰 stadium(약통) 형태 안에 층 라벨을
/// 세로로 나열하고, 한 번에 최대 5개까지만 노출한다. 층이 그 이상이면 세로
/// 스크롤로 나머지를 볼 수 있고, 현재 층은 파란 캡슐로 강조된다.
///
/// **기본 상태는 접힘**이다. 접힌 동안에는 현재 층 캡슐 하나 + 펼치기 화살표만
/// 남는다. 층 목록은 늘 지도 좌측을 세로로 길게 가리는데, 사용자가 실제로 층을
/// 바꾸는 순간은 드물다 — 평소에는 "지금 몇 층인지"만 알면 되므로 그 한 줄만
/// 남기고, 바꿀 때만 펼친다. 층을 고르면 다시 접혀 지도를 돌려준다.
///
/// 층이 하나뿐이면 펼칠 것이 없으므로 토글 없이 단일 셀만 표시한다.
///
/// 실내 지도 화면과 야외 지도의 실내 진입 오버레이가 같은 UI를 공유하도록
/// 야외/실내 양쪽에서 이 위젯을 재사용한다.
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
  // 펼치기/접기 화살표 줄. 셀보다 눈에 덜 띄어야 현재 층 캡슐이 주인공으로
  // 남으므로 셀 높이의 절반가량만 준다.
  static const double _toggleHeight = 20;

  final ScrollController _scrollController = ScrollController();

  /// 층 목록을 펼쳐 두었는지. 접힘이 기본값이다(클래스 주석 참고).
  bool _expanded = false;

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

  /// 펼침/접힘을 바꾼다. 펼치는 쪽은 리스트가 이제 막 붙는 참이라
  /// `_scrollToSelected`가 아직 clients를 못 잡는다 — 프레임 뒤로 미뤄
  /// 현재 층이 뷰포트 가운데에 오도록 한 번 맞춰 준다.
  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() => _expanded = value);
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSelected(animate: false),
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

    // 층이 하나면 접었다 펴 봐야 같은 화면이라 토글 자체를 달지 않는다.
    final collapsible = floors.length > 1;
    final expanded = collapsible && _expanded;
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
        paddingV: _pillPaddingV,
        // 화면 아래쪽 모서리를 붙박이로 두고 위로만 자라게 한다. 상위가
        // `bottom:`으로 앉히는 위젯이라 아래가 흔들리면 하단 바와 어긋난다.
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (expanded)
                SizedBox(
                  height: listHeight,
                  child: ListView.builder(
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
                        // 고르고 나면 접는다 — 층을 바꾼 직후가 바로 지도를
                        // 다시 봐야 하는 순간이다.
                        onTap: () {
                          if (!selected) widget.onSelectFloor(floor);
                          _setExpanded(false);
                        },
                      );
                    },
                  ),
                )
              else
                _FloorCell(
                  label: widget.selectedFloor,
                  selected: true,
                  height: _cellHeight,
                  // 접힌 캡슐 자체도 펼치기 버튼이다. 화살표(20px)만 노리게
                  // 하면 지도 위에서 누르기 너무 작다.
                  onTap: collapsible ? () => _setExpanded(true) : () {},
                ),
              if (collapsible)
                _ExpandToggle(
                  expanded: expanded,
                  height: _toggleHeight,
                  onTap: () => _setExpanded(!expanded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 펼치기/접기 화살표. 목록이 위로 자라므로 접힌 상태에서는 위쪽(▲),
/// 펼친 상태에서는 접히는 방향(▼)을 가리킨다.
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({
    required this.expanded,
    required this.height,
    required this.onTap,
  });

  final bool expanded;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? '층 목록 접기' : '층 목록 펼치기',
      child: SizedBox(
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('floor-selector-toggle'),
            onTap: onTap,
            child: Center(
              child: Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: AppColors.text.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// stadium(약통) 컨테이너. 내부 리스트/단일 셀을 감싸는 껍데기 역할.
/// 높이는 자식이 정한다 — 접힘·펼침에 따라 내용 높이가 달라지기 때문이다.
class _FloorPill extends StatelessWidget {
  const _FloorPill({
    required this.width,
    required this.paddingV,
    required this.child,
  });

  final double width;
  final double paddingV;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width / 2);
    return Container(
      width: width,
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
