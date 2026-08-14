/// "위치 지정" 모드에서 지도 위에 뜨는 안내 카드.
///
/// 화면 파일 끝에 붙어 있던 사설 위젯이다. 이 디렉터리가 이미 야외 지도의
/// 위젯 자리라 여기로 옮겼다 — 화면 파일에는 상태와 생명주기만 남긴다.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// PDR 앵커 배치 대기 중임을 상단에 짧게 알려주는 배지. 하단 바 버튼의 활성
/// 톤과 함께 사용자에게 "지금 지도 탭이 다음 액션을 소비한다"는 상태를 전한다.
///
/// 배치 대기는 지도 탭을 통째로 가져가는 상태라(건물 진입·매장 선택이 모두
/// 막힌다) **빠져나올 길이 안내 안에 있어야 한다.** 예전에는 축소해 실내
/// 오버레이를 접거나 세그먼트를 옮기는 우회로밖에 없었다.
class PlacingAnchorHint extends StatelessWidget {
  const PlacingAnchorHint({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // 앱의 카드 문법(surface + hairline + 아이콘만 primary)을 따른다. 예전의
    // 파란 원색(AppColors.indoor) 배경은 절제된 화이트/뮤트 톤에서 이 배지만
    // 튀어 보였다. "지도 탭을 가져가는 상태"라는 긴장은 하단 바 버튼의 활성
    // 톤이 이미 말하고 있으므로, 여기는 안내문답게 조용히 있는다.
    return Material(
      color: AppColors.surface,
      elevation: AppElevation.chrome,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          // X는 문구 오른쪽 **상단**에 고정한다. 좁은 화면에서 문구가 두 줄로
          // 접혀도 취소 버튼이 세로 중앙으로 밀려나지 않아, 눌러야 할 자리가
          // 문구 길이에 따라 흔들리지 않는다.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Icon(Icons.touch_app, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '지도를 탭해 현재 서 있는 위치를 지정해주세요',
                  maxLines: 2,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _HintCancelButton(onPressed: onCancel, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// 안내 배너 오른쪽 상단의 취소(X).
///
/// Material `IconButton`을 쓰지 않는 이유: 기본 최소 탭 영역이 48x48이라
/// 한 줄짜리 안내 pill 높이를 두 배 이상으로 늘려 카테고리 chip 열까지
/// 밀어 올린다. 여기서는 26x26으로 줄이되 아이콘보다 넓은 탭 영역은 남긴다.
class _HintCancelButton extends StatelessWidget {
  const _HintCancelButton({required this.onPressed, required this.color});

  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '위치 지정 취소',
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Center(
            child: Icon(Icons.close_rounded, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
