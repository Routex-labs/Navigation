import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 지도 톤을 해치지 않는 compact PDR 시작/종료 제어. 강한 파란 큰 버튼 대신
/// 실제 지도 앱처럼 흰 surface 위에 상태 색만 얹어, 지도와 현재 위치가
/// 시각적으로 우선되게 한다.
///
/// 실내 지도와 야외 지도의 실내 진입 오버레이가 같은 위젯을 쓴다 — 두 화면의
/// PDR 진입점이 모양·위치·문구까지 같아야 사용자가 "지금 어느 화면인지"와
/// 무관하게 같은 버튼으로 측정을 시작/종료할 수 있다.
class PdrMapControl extends StatelessWidget {
  const PdrMapControl({
    super.key,
    required this.active,
    required this.onPressed,
    required this.canExport,
    required this.exporting,
    required this.onExport,
    required this.shareButtonKey,
  });

  /// PDR 세션이 진행 중인지. true면 버튼이 "종료" 톤(빨강)으로 바뀐다.
  final bool active;
  final VoidCallback onPressed;

  /// 내보낼 수 있는(스냅샷이 쌓인) 종료된 세션이 있는지. true일 때만 공유
  /// 아이콘이 붙는다.
  final bool canExport;
  final bool exporting;
  final VoidCallback onExport;

  /// iOS 공유 시트의 popover 기준 사각형을 계산하기 위한 key.
  final GlobalKey shareButtonKey;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFD93025) : AppColors.indoor;
    return Tooltip(
      message: active ? 'PDR 종료' : 'PDR 시작',
      child: Material(
        color: Colors.white.withValues(alpha: 0.96),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: active ? 0.36 : 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onPressed,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 9, canExport ? 7 : 13, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        active
                            ? Icons.stop_rounded
                            : Icons.directions_walk_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      active ? 'PDR 종료' : 'PDR 시작',
                      style: TextStyle(
                        color: active
                            ? const Color(0xFFB3261E)
                            : const Color(0xFF202124),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (canExport) ...[
              Container(width: 1, height: 24, color: AppColors.blue100),
              IconButton(
                key: shareButtonKey,
                tooltip: 'PDR 디버그 JSON 공유',
                onPressed: exporting ? null : onExport,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 44,
                ),
                icon: exporting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
