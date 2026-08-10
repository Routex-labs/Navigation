import 'package:flutter/material.dart';

import '../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../theme/app_theme.dart';

/// 층 도면이 교체되는 구간을 덮는 스크림.
///
/// 앱 셸 root Stack의 **마지막 레이어**에 둔다. 지도 안에 두면 검색창·카테고리
/// 줄·하단 바는 그대로 보인 채 지도만 페이드돼, 전환이 일어난 사실이 화면에
/// 드러나지 않는다.
///
/// 두 층으로 그린다.
///
/// - **배경**: [opacity]만큼 흐려지는 surface 색.
/// - **카드**: 배경이 조금이라도 덮인 동안 **또렷하게** 뜬다. 같이 흐려지면
///   정작 읽어야 할 문구가 제일 안 보인다.
///
/// **탑승 구간 전체를 덮지 않는다.** 한때 하차까지 반투명으로 덮어 뒀는데,
/// 그 구간은 길게는 수십 초라 "전환 중"이 아니라 "화면이 계속 덮여 있다"로
/// 읽혔다. 덮개는 도면이 바뀌는 **사건**을 알리는 것이고, 탑승 중이라는
/// **상태**는 배너가 말한다. 대신 페이드를 느리게 둬서(진입 0.5초 / 해제 0.7초)
/// 전환이 일어났다는 사실이 눈에 남게 한다.
class FloorTransitionScrim extends StatelessWidget {
  const FloorTransitionScrim({
    super.key,
    required this.opacity,
    required this.fadeIn,
    required this.fadeOut,
    this.state,
  });

  /// 배경을 덮는 정도. 0이면 아무것도 그리지 않고 입력도 그대로 통과한다.
  final double opacity;
  final Duration fadeIn;
  final Duration fadeOut;

  /// 가운데 카드에 표시할 `B1 → 1F`. 없으면 배경만 덮는다.
  final FloorTransitionUiState? state;

  /// 이 이상 덮였으면 뒤쪽 입력을 막는다.
  ///
  /// 거의 다 가려진 동안에는 막아야 한다 — 보이지도 않는 지도 위의 탭은
  /// 사용자가 의도한 대상이 아니다. 반대로 페이드가 걷히는 동안에는 통과시킨다.
  /// 해제가 0.7초로 느려서, 그동안 막아 두면 전환이 끝난 화면이 잠깐 먹통으로
  /// 느껴진다.
  static const _inputBlockingOpacity = 0.9;

  @override
  Widget build(BuildContext context) {
    final transition = state;
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: opacity < _inputBlockingOpacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: opacity.clamp(0.0, 1.0),
            duration: opacity > 0 ? fadeIn : fadeOut,
            curve: Curves.easeOut,
            child: ColoredBox(color: scheme.surface),
          ),
          if (transition != null)
            AnimatedOpacity(
              opacity: opacity > 0 ? 1 : 0,
              duration: opacity > 0 ? fadeIn : fadeOut,
              curve: Curves.easeOut,
              child: Center(
                child: _FloorTransitionCard(
                  state: transition,
                  // 걷힌 뒤에도 카드는 트리에 남는다(페이드 아웃 때문에).
                  // 반복 애니메이션까지 남겨 두면 보이지도 않는 위젯이 매
                  // 프레임 rebuild를 요청한다.
                  animating: opacity > 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 스크림 가운데의 `B1 → 1F` 카드.
///
/// 정지한 화살표 하나로는 **어느 쪽으로 가는 중인지**가 한눈에 안 읽힌다.
/// 위/아래로 흐르는 chevron 세 개가 방향을 계속 말해 주고, 그 움직임 자체가
/// "지금 진행 중"이라는 신호가 된다(멈춘 화면과 구분된다).
class _FloorTransitionCard extends StatefulWidget {
  const _FloorTransitionCard({required this.state, required this.animating});

  final FloorTransitionUiState state;

  /// 반복 애니메이션을 돌릴지. 스크림이 걷힌 뒤에는 false로 내려온다.
  final bool animating;

  @override
  State<_FloorTransitionCard> createState() => _FloorTransitionCardState();
}

class _FloorTransitionCardState extends State<_FloorTransitionCard>
    with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF1A73E8);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animating) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _FloorTransitionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating == oldWidget.animating) return;
    if (widget.animating) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = widget.state;
    return Material(
      color: scheme.surface,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  state.fromFloorLabel,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _FlowingChevrons(
                    progress: _controller,
                    goingUp: state.goingUp,
                  ),
                ),
                Text(
                  state.toFloorLabel,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              state.scrimCaption,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 진행 방향으로 순차 점등하며 흐르는 chevron 세 개.
class _FlowingChevrons extends StatelessWidget {
  const _FlowingChevrons({required this.progress, required this.goingUp});

  final Animation<double> progress;
  final bool goingUp;

  static const _count = 3;
  static const _accent = Color(0xFF1A73E8);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < _count; index++)
              _chevron(
                // 위로 갈 때는 아래쪽 chevron부터 밝아져야 시선이 위로 흐른다.
                // 아래로 갈 때는 그 반대다.
                phase: goingUp ? _count - 1 - index : index,
              ),
          ],
        );
      },
    );
  }

  Widget _chevron({required int phase}) {
    // 각 chevron은 한 주기 안에서 자기 차례에만 밝아진다. 차례를 3등분해 두면
    // 세 개가 겹치지 않고 한 줄기로 흐르는 것처럼 보인다.
    final offset = (progress.value - phase / _count) % 1.0;
    final glow = (1 - offset * 1.6).clamp(0.0, 1.0);
    // chevron끼리 겹쳐 쌓아야 한 줄기로 흐르는 것처럼 보인다. 아이콘 자체는
    // 22px지만 줄 높이는 12px만 차지하게 두고, 넘치는 부분은 OverflowBox로
    // 허용한다(높이를 억지로 조이면 아이콘이 잘린다).
    return SizedBox(
      // 너비도 함께 준다. OverflowBox는 가로 제약이 무한이면 크기를 못 정한다
      // (Row 안이라 그대로 두면 무한 폭이 내려온다).
      width: 22,
      height: 12,
      child: OverflowBox(
        minHeight: 22,
        maxHeight: 22,
        child: Icon(
          goingUp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 22,
          color: Color.lerp(_accent.withValues(alpha: 0.18), _accent, glow),
        ),
      ),
    );
  }
}

/// 층 전환 진행 배너.
///
/// 문구는 [FloorTransitionUiState.message]가 정한다. 이 위젯은 임계값도
/// 단계 판정도 모른다 — 상태를 받아 그리기만 한다.
class FloorTransitionBanner extends StatelessWidget {
  const FloorTransitionBanner({super.key, required this.state, this.onUndo});

  final FloorTransitionUiState state;

  /// 되돌리기 콜백. [FloorTransitionUiState.canUndo]가 true일 때만 쓰인다.
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final undo = state.canUndo ? onUndo : null;
    return Material(
      color: const Color(0xFF1A73E8),
      // 몇 초짜리 임시 레이어다 — 지금 층이 바뀌고 있다는 사실이 화면에서 가장
      // 앞에 있어야 한다(AppElevation.overlay). 색이 진해 경계선은 필요 없다.
      elevation: AppElevation.overlay,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 9, undo == null ? 14 : 6, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.goingUp ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                state.message,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (undo != null)
              TextButton(
                onPressed: undo,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  '아니에요',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
