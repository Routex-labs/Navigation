import 'package:flutter/material.dart';

import '../../../../domain/guidance/escalator_ride.dart';
import '../../../../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../../../../theme/app_theme.dart';
import '../../../../map/icon/location_marker_icon.dart';

/// 층 도면이 교체되는 구간을 덮는 스크림. 앱 셸 root Stack의 **마지막 레이어**에
/// 둔다 — 지도 안에 두면 검색창·하단 바가 그대로 보여 전환 사실이 안 드러난다.
///
/// **도면이 갈리는 앞뒤만 덮는다**(약 4.7초). 덮인 **뒤에서** 크로스페이드와 마커
/// 활강이 그대로 돌아야 걷히는 순간 "가려 놓고 순간이동시킨" 것으로 안 보인다.
///
/// 카드의 점은 **실제 진행률을 따르지 않는다** — 실제 진행은 10초 이상에 걸쳐
/// 흐르는데 덮개는 몇 초만 보여, 얹으면 점이 멈춘 것으로 읽혔다.
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
                  // 애니메이션까지 남겨 두면 보이지도 않는 위젯이 매 프레임
                  // rebuild를 요청한다.
                  animating: opacity > 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 스크림 가운데의 층 전환 연출. 두 층 라벨을 **세로로** 세우고 점이 그 사이를
/// 탄다 — 가로로 `B1 → B2`라고 적으면 지하로 내려가는데 화면은 오른쪽으로 가는
/// 그림이라 방향 감각이 꼬인다.
///
/// 점은 자체 시계로 **한 번** 재생하고 도착 쪽에 머문다. **반복하지 않는다** —
/// 무한 반복했더니 덮개가 3초를 넘길 때 같은 장면이 두 번 재생돼 오히려 "지금
/// 어디쯤인지"를 알 수 없게 만들었다.
class _FloorTransitionCard extends StatefulWidget {
  const _FloorTransitionCard({required this.state, required this.animating});

  final FloorTransitionUiState state;

  /// 애니메이션을 돌릴지. 스크림이 걷힌 뒤에는 false로 내려온다.
  final bool animating;

  @override
  State<_FloorTransitionCard> createState() => _FloorTransitionCardState();
}

class _FloorTransitionCardState extends State<_FloorTransitionCard>
    with SingleTickerProviderStateMixin {
  /// 한 번 재생하는 스위프의 길이. 덮개가 완전히 걷히기 전에 점이 도착 쪽에
  /// 닿아 있도록 덮개 유지 시간(약 4.7초)보다 짧게 둔다.
  static const _travel = escalatorGlideDuration;

  /// 두 라벨 사이 선의 길이. 짧으면 이동이 안 읽히고, 길면 라벨이 화면
  /// 위아래로 흩어져 한 덩어리로 안 보인다.
  static const _lineHeight = 104.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _travel,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animating) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _FloorTransitionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating == oldWidget.animating) return;
    if (widget.animating) {
      _controller.forward(from: 0);
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          _build(context, _controller.value.clamp(0.0, 1.0)),
    );
  }

  Widget _build(BuildContext context, double progress) {
    final scheme = Theme.of(context).colorScheme;
    final state = widget.state;
    // 출발 층이 늘 **점이 떠나는 쪽**이다. 내려갈 때는 위, 올라갈 때는 아래.
    final topLabel = state.goingUp ? state.toFloorLabel : state.fromFloorLabel;
    final bottomLabel = state.goingUp
        ? state.fromFloorLabel
        : state.toFloorLabel;

    // 점이 도착 쪽에 가까워질수록 강조가 넘어간다. 라벨 색이 이동과 함께
    // 변해야 "지금 어디로 가는 중"이 한 그림으로 읽힌다.
    final arriving = Curves.easeInOut.transform(progress);
    final topWeight = state.goingUp ? arriving : 1 - arriving;

    // 캡션은 **가는 방향 쪽**에 붙인다. 내려가는데 글이 위에 있으면 시선이
    // 점과 반대로 끌려간다.
    final caption = Text(
      state.detail,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface.withValues(alpha: 0.6),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.goingUp) ...[caption, const SizedBox(height: 14)],
        _FloorLabel(label: topLabel, emphasis: topWeight, scheme: scheme),
        SizedBox(
          height: _lineHeight,
          width: 2 * _markerRimRadius,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // 선은 항상 같은 자리에 옅게 깔려 있다. 지나온 구간을 따로
              // 칠하지 않는 이유는, 이 점이 곧 마커라 "지나온 길"이 아니라
              // "지금 어디"만 말하면 되기 때문이다.
              Container(
                width: 1.5,
                height: _lineHeight,
                color: scheme.onSurface.withValues(alpha: 0.18),
              ),
              Positioned(
                // 위에서 아래로 내려갈 때 progress가 곧 화면 아래 방향이다.
                top:
                    (state.goingUp ? 1 - arriving : arriving) *
                    (_lineHeight - 2 * _markerRimRadius),
                child: const _MarkerDot(key: Key('floor-transition-dot')),
              ),
            ],
          ),
        ),
        _FloorLabel(
          label: bottomLabel,
          emphasis: 1 - topWeight,
          scheme: scheme,
        ),
        if (!state.goingUp) ...[const SizedBox(height: 14), caption],
      ],
    );
  }
}

/// 지도 위 현재 위치 마커와 **같은 그림**의 점.
///
/// 크기·색을 마커와 맞춰야 덮개가 마커를 가져온 것으로 읽힌다. 값의 출처는
/// [kLocationMarkerCoreRadiusPx]·[kLocationMarkerRimRadiusPx]로, 지도가 아이콘을
/// 그릴 때 쓰는 것과 같은 상수다 — 한쪽만 바꾸면 두 점의 크기가 어긋난다.
class _MarkerDot extends StatelessWidget {
  const _MarkerDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2 * _markerRimRadius,
      height: 2 * _markerRimRadius,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        // 지도 아이콘의 그림자와 **같은 무게**로 맞춘다. 아이콘은 2배 캔버스에
        // 그려 절반으로 축소되므로, 캔버스에서 blur 5 / offset 2인 그림자가
        // 화면에서는 blur 2.5 / offset 1이 된다. 여기에 원래 값을 그대로 쓰면
        // 점이 한 겹 더 두꺼워 보이고, 그게 "덮개 점이 더 크다"로 읽힌다.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 2 * kLocationMarkerCoreRadiusPx,
          height: 2 * kLocationMarkerCoreRadiusPx,
          decoration: const BoxDecoration(
            color: kLocationMarkerColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

const _markerRimRadius = kLocationMarkerRimRadiusPx;

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
