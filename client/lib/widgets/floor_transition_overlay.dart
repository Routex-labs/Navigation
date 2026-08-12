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

/// 스크림 가운데의 층 전환 연출.
///
/// 두 층 라벨을 **세로로** 세우고 그 사이를 선으로 잇는다. 점이 그 선을 타고
/// 출발 층에서 도착 층으로 내려가면(올라가면), 라벨의 강조도 함께 넘어간다.
///
/// 가로로 `B1 → B2`라고 적지 않는 이유는 **층 이동이 수직 사건**이기 때문이다.
/// 화살표 방향을 글로 읽어서 아는 것과, 점이 실제로 아래로 내려가는 것을 보는
/// 것은 다르다 — 지하로 내려가는데 화면에서는 오른쪽으로 가는 그림을 보면 방향
/// 감각이 한 번 꼬인다.
///
/// 애니메이션은 **반복한다.** 이 연출이 떠 있는 시간은 에스컬레이터 탑승 시간에
/// 달려 있어 미리 알 수 없다. 한 번만 재생하면 남은 시간 동안 정지 화면이 되어
/// "멈췄나" 싶어진다.
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
  // 강조는 앱 포인트 색 하나로 통일한다. 예전의 구글 파랑(#1A73E8)은 앱의
  // 절제된 화이트/뮤트 톤에서 혼자 다른 팔레트로 떠 보였다.
  static const _accent = AppColors.primary;

  /// 점이 한쪽 끝에서 반대쪽 끝까지 가는 데 걸리는 시간.
  static const _travel = Duration(milliseconds: 1600);

  /// 두 라벨 사이 선의 길이. 짧으면 이동이 안 읽히고, 길면 라벨이 화면
  /// 위아래로 흩어져 한 덩어리로 안 보인다.
  static const _lineHeight = 104.0;
  static const _dotRadius = 5.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _travel,
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
    // 출발 층이 늘 **점이 떠나는 쪽**이다. 내려갈 때는 위, 올라갈 때는 아래.
    final topLabel = state.goingUp ? state.toFloorLabel : state.fromFloorLabel;
    final bottomLabel = state.goingUp
        ? state.fromFloorLabel
        : state.toFloorLabel;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 진행도 0 = 출발 층, 1 = 도착 층.
        final progress = _controller.value;
        // 점이 도착 쪽에 가까워질수록 강조가 넘어간다. 라벨 색이 이동과 함께
        // 변해야 "지금 어디로 가는 중"이 한 그림으로 읽힌다.
        final arriving = Curves.easeInOut.transform(progress);
        final topWeight = state.goingUp ? arriving : 1 - arriving;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FloorLabel(label: topLabel, emphasis: topWeight, scheme: scheme),
            SizedBox(
              height: _lineHeight,
              width: 2 * _dotRadius + 6,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // 선은 항상 같은 자리에 옅게 깔려 있다. 점이 지나간 자리를
                  // 따로 칠하지 않는 이유는, 반복 재생이라 매 주기 지워야 해서
                  // 오히려 깜빡임으로 읽히기 때문이다.
                  Container(
                    width: 1.5,
                    height: _lineHeight,
                    color: scheme.onSurface.withValues(alpha: 0.18),
                  ),
                  Positioned(
                    // 위에서 아래로 내려갈 때 progress가 곧 화면 아래 방향이다.
                    top:
                        (state.goingUp ? 1 - arriving : arriving) *
                        (_lineHeight - 2 * _dotRadius),
                    child: Container(
                      width: 2 * _dotRadius,
                      height: 2 * _dotRadius,
                      decoration: const BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _FloorLabel(
              label: bottomLabel,
              emphasis: 1 - topWeight,
              scheme: scheme,
            ),
            const SizedBox(height: 14),
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
        );
      },
    );
  }
}

/// 층 라벨 한 개. [emphasis] 1이면 도착 층(포인트 파랑·큼), 0이면 지나온 층
/// (옅은 회색·작음)이다. 그 사이를 연속으로 오간다.
class _FloorLabel extends StatelessWidget {
  const _FloorLabel({
    required this.label,
    required this.emphasis,
    required this.scheme,
  });

  final String label;
  final double emphasis;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final t = emphasis.clamp(0.0, 1.0);
    return Text(
      label,
      style: TextStyle(
        fontSize: 20 + 10 * t,
        fontWeight: FontWeight.w800,
        color: Color.lerp(
          scheme.onSurface.withValues(alpha: 0.35),
          AppColors.primary,
          t,
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
    // 앱의 카드 문법(surface + hairline + 포인트만 primary)을 그대로 쓴다.
    // 예전에는 구글 파랑(#1A73E8) 원색 알약이었는데, 절제된 화이트/뮤트 톤의
    // 화면에서 이 배너만 다른 앱처럼 보였다. "임시 레이어라 가장 앞"이라는
    // 위계는 색이 아니라 그림자(AppElevation.overlay)가 말한다. 흰 배경이라
    // 경계선(hairline)이 윤곽을 맡는다.
    return Material(
      color: AppColors.surface,
      elevation: AppElevation.overlay,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: const StadiumBorder(side: BorderSide(color: AppColors.hairline)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 9, undo == null ? 14 : 6, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.goingUp ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                state.message,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
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
                  // 배너의 유일한 조작이므로 여기만 포인트 색이다.
                  foregroundColor: AppColors.primary,
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
