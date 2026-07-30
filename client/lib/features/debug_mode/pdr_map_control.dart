import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 진단 JSON 공유 버튼. 디버그 모드에서만 지도 위에 뜬다.
///
/// 예전에는 여기에 "PDR 시작/종료" 버튼이 함께 있었다. PDR이 실내 지도를 보는
/// 동안 상시 실행으로 바뀐 뒤에는 켜고 끌 대상이 없고, 사용자가 시작을 눌러야
/// 위치 추적이 시작되던 흐름도 "위치 지정" 하나로 합쳐졌다. 남은 역할은 마지막
/// 길안내 세션을 파일로 꺼내는 것 하나뿐이라 아이콘 버튼만 남긴다.
///
/// 실내 지도와 야외 지도의 실내 진입 오버레이가 같은 위젯을 쓴다 — 두 화면의
/// 진단 진입점이 모양·위치까지 같아야 사용자가 "지금 어느 화면인지"와 무관하게
/// 같은 버튼으로 파일을 꺼낼 수 있다.
class PdrMapControl extends StatelessWidget {
  const PdrMapControl({
    super.key,
    required this.canExport,
    required this.exporting,
    required this.onExport,
    required this.shareButtonKey,
  });

  /// 내보낼 수 있는(스냅샷이 쌓인) 진단 세션이 있는지. false면 아무것도 그리지
  /// 않아, 꺼낼 게 없을 때 눌리지 않는 버튼이 지도를 가리지 않는다.
  final bool canExport;
  final bool exporting;
  final VoidCallback onExport;

  /// iOS 공유 시트의 popover 기준 사각형을 계산하기 위한 key.
  final GlobalKey shareButtonKey;

  @override
  Widget build(BuildContext context) {
    if (!canExport) return const SizedBox.shrink();
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      shape: StadiumBorder(
        side: BorderSide(color: AppColors.indoor.withValues(alpha: 0.2)),
      ),
      child: IconButton(
        key: shareButtonKey,
        tooltip: 'PDR 진단 JSON 공유',
        onPressed: exporting ? null : onExport,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        icon: exporting
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share_rounded, size: 20),
      ),
    );
  }
}
