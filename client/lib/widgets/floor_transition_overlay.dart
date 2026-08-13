import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/escalator_ride.dart';
import '../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../theme/app_theme.dart';
import 'location_marker.dart';

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
/// **도면이 갈리는 앞뒤만 덮는다**(약 3.2초). 하차까지 덮어 본 적이 있는데,
/// 그러면 내리기 전에 새 층 도면과 다음 경로를 볼 시간이 없다.
///
/// 덮인 **뒤에서** 도면 크로스페이드와 마커 활강이 그대로 돈다. 걷히는 순간
/// 새 층 도면과 하차 지점에 선 마커가 이미 자리를 잡고 있어야, 이 덮개가
/// "가려 놓고 순간이동시킨" 것으로 보이지 않는다. 가운데 카드의 점은 그 활강과
/// **같은 진행률**로 움직인다 — 덮개는 마커를 가리는 것이 아니라 데려간다.
///
/// 페이드는 느리다(진입 0.5초 / 해제 0.7초) — 빠르면 전환이 아니라 깜빡임으로
/// 읽힌다.
class FloorTransitionScrim extends StatelessWidget {
  const FloorTransitionScrim({
    super.key,
    required this.opacity,
    required this.fadeIn,
    required this.fadeOut,
    this.state,
    this.progress,
  });

  /// 배경을 덮는 정도. 0이면 아무것도 그리지 않고 입력도 그대로 통과한다.
  final double opacity;
  final Duration fadeIn;
  final Duration fadeOut;

  /// 가운데 카드에 표시할 `B1 → 1F`. 없으면 배경만 덮는다.
  final FloorTransitionUiState? state;

  /// 탑승 활강의 진행률. 카드의 점이 이 값으로 움직인다 — 지도 위 마커와 같은
  /// 값이라 덮개를 사이에 두고도 하나의 움직임으로 이어진다.
  final ValueListenable<double>? progress;

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
                  progress: progress,
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
/// **점은 지도 마커 그 자체다.** 생김새(흰 테 + 파란 코어)를 지도 위 현재 위치
/// 마커와 맞추고, 위치도 마커와 **같은 진행률**로 움직인다([progress] — 실제
/// 탑승 활강이 내는 값이다). 덮개가 마커를 가져와서 층 사이를 데려간 뒤 새 층에
/// 내려놓는 그림이라, 사용자가 보는 것은 처음부터 끝까지 같은 점 하나다.
///
/// 그래서 **반복하지 않는다.** 예전에는 1.6초짜리 왕복을 무한 반복했는데, 덮개가
/// 3초를 넘기자 같은 내려가는 장면이 두 번 재생돼 "지금 어디쯤인지"를 오히려
/// 알 수 없게 만들었다. 진행률이 실제 값이면 남은 시간도 사용자가 읽을 수 있다.
///
/// [progress]가 없을 때(양 끝을 몰라 활강을 못 건 경우)만 자체 시계로 한 번
/// 재생하고 도착 쪽에 머문다. 그때도 반복은 하지 않는다.
class _FloorTransitionCard extends StatefulWidget {
  const _FloorTransitionCard({
    required this.state,
    required this.animating,
    this.progress,
  });

  final FloorTransitionUiState state;

  /// 애니메이션을 돌릴지. 스크림이 걷힌 뒤에는 false로 내려온다.
  final bool animating;

  /// 탑승 활강의 진행률(0 = 출발 층, 1 = 도착 층). 지도 위 마커가 쓰는 값과
  /// **같은 객체**라, 덮개 뒤에서 움직이는 마커와 이 점이 어긋날 수 없다.
  final ValueListenable<double>? progress;

  @override
  State<_FloorTransitionCard> createState() => _FloorTransitionCardState();
}

class _FloorTransitionCardState extends State<_FloorTransitionCard>
    with SingleTickerProviderStateMixin {
  /// 진행률을 못 받았을 때 자체로 한 번 재생하는 시간. 활강과 같은 길이라
  /// 어느 경로로 그리든 리듬이 같다.
  static const _travel = escalatorGlideDuration;

  /// 두 라벨 사이 선의 길이. 짧으면 이동이 안 읽히고, 길면 라벨이 화면
  /// 위아래로 흩어져 한 덩어리로 안 보인다.
  static const _lineHeight = 104.0;

  /// 진행률을 받은 경우에는 **만들지 않는다.** 쓰지 않는 티커를 들고 있으면
  /// dispose에서 뒤늦게 생성되며 트리가 이미 죽은 뒤 ancestor를 찾는다.
  AnimationController? _controller;

  AnimationController _ensureController() =>
      _controller ??= AnimationController(vsync: this, duration: _travel);

  @override
  void initState() {
    super.initState();
    if (widget.animating && widget.progress == null) {
      _ensureController().forward();
    }
  }

  @override
  void didUpdateWidget(covariant _FloorTransitionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != null) {
      _controller?.stop();
      return;
    }
    if (widget.animating == oldWidget.animating) return;
    if (widget.animating) {
      _ensureController().forward(from: 0);
    } else {
      _controller?.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    if (progress == null) {
      final driver = _ensureController();
      return AnimatedBuilder(
        animation: driver,
        builder: (context, _) => _build(context, driver.value.clamp(0.0, 1.0)),
      );
    }
    // 활강 진행률은 [escalatorGlideSampleInterval]마다 한 번 갱신된다(지도 소스
    // 를 플랫폼 채널로 밀어야 해서 프레임마다 보낼 수 없다). 그 값을 그대로
    // 그리면 점이 초당 16번 툭툭 끊기므로, 샘플 사이를 프레임 단위로 잇는다.
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: progress.value.clamp(0.0, 1.0)),
        duration: escalatorGlideSampleInterval,
        curve: Curves.linear,
        builder: (context, value, _) => _build(context, value),
      ),
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
      state.scrimCaption,
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

/// 층 전환 진행 배너.
///
/// 문구는 [FloorTransitionUiState.message]가 정한다. 이 위젯은 임계값도
/// 단계 판정도 모른다 — 상태를 받아 그리기만 한다.
class FloorTransitionBanner extends StatelessWidget {
  const FloorTransitionBanner({super.key, required this.state});

  final FloorTransitionUiState state;

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
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
          ],
        ),
      ),
    );
  }
}
