import 'package:flutter/material.dart';

import '../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../theme/app_theme.dart';

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
