import 'package:flutter/material.dart';

import '../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../theme/app_theme.dart';

/// 층 도면이 실제로 교체되는 짧은 구간을 덮는 베일.
///
/// 앱 셸 root Stack의 **마지막 레이어**에 둔다. 지도 안에 두면 검색창·카테고리
/// 줄·하단 바는 그대로 보인 채 지도만 페이드돼, 전환이 일어난 사실이 화면에
/// 드러나지 않는다.
///
/// 탑승 전체를 덮지 않는다 — 사용자가 지도를 볼 수 없는 시간이 길어지면
/// "앱이 멈췄다"로 읽힌다. 도면 swap 프레임만 짧게 가린다.
class FloorSwapVeil extends StatelessWidget {
  const FloorSwapVeil({
    super.key,
    required this.opacity,
    required this.fadeIn,
    required this.fadeOut,
    this.state,
  });

  final double opacity;
  final Duration fadeIn;
  final Duration fadeOut;

  /// 가운데에 표시할 `B1 → 1F`. 없으면 빈 화면만 덮는다.
  final FloorTransitionUiState? state;

  @override
  Widget build(BuildContext context) {
    final transition = state;
    // 페이드 중에는 뒤쪽 입력을 막는다. 지도가 절반쯤 가려진 상태에서 눌린
    // 검색·층 선택·하단 버튼은 사용자가 의도한 대상이 아니다. 반대로 베일이
    // 걷힌 뒤에는 반드시 통과시켜야 한다 — 투명해도 opaque한 자식이 그대로
    // 남아 있으면 전환이 끝난 화면 전체가 먹통이 된다.
    return IgnorePointer(
      ignoring: opacity <= 0,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: opacity > 0 ? fadeIn : fadeOut,
        curve: Curves.easeOut,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: transition == null
              ? const SizedBox.expand()
              : Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        transition.fromFloorLabel,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          transition.goingUp
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 20,
                        ),
                      ),
                      Text(
                        transition.toFloorLabel,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
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
