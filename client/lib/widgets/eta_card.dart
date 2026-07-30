import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../domain/route_guidance.dart';

/// 예상 도착 시간 카드 (design.md 공통 컴포넌트: EtaCard).
class EtaCard extends StatelessWidget {
  const EtaCard({
    super.key,
    required this.distanceMeters,
    required this.minutes,
    this.label = '목적지까지',
    this.instruction,
    this.onClose,
    this.onClosePointerDown,
  });

  final double distanceMeters;
  final int minutes;
  final String label;
  final RouteGuidanceInstruction? instruction;

  /// 있으면 카드 오른쪽에 "안내 종료" 버튼을 보여준다. 사용자가 길찾기로
  /// 직접 고른 경로를 취소할 때만 쓰고, 자동 안내(예: 건물 입구까지)에는
  /// null이라 버튼이 사라진다.
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onClosePointerDown;

  @override
  Widget build(BuildContext context) {
    final guidance = instruction;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: guidance == null
            ? _LegacyEtaContent(
                label: label,
                minutes: minutes,
                distanceMeters: distanceMeters,
                onClose: onClose,
                onClosePointerDown: onClosePointerDown,
              )
            : Row(
                children: [
                  _GuidanceIcon(action: guidance.action),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          guidance.primaryText,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '$label · 약 $minutes분 · ${distanceMeters.round()}m 남음',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (onClose != null) ...[
                    const SizedBox(width: 6),
                    Listener(
                      onPointerDown: (event) =>
                          onClosePointerDown?.call(event.position),
                      child: TextButton(
                        onPressed: onClose,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD93025),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('종료'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _GuidanceIcon extends StatelessWidget {
  const _GuidanceIcon({required this.action});

  final RouteGuidanceAction action;

  @override
  Widget build(BuildContext context) {
    final icon = switch (action) {
      RouteGuidanceAction.turnLeft => Icons.turn_left_rounded,
      RouteGuidanceAction.turnRight => Icons.turn_right_rounded,
      RouteGuidanceAction.escalator => Icons.escalator_rounded,
      RouteGuidanceAction.elevator => Icons.elevator_rounded,
      RouteGuidanceAction.arrived => Icons.flag_rounded,
      RouteGuidanceAction.straight => Icons.straight_rounded,
    };
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 30, color: const Color(0xFF1A73E8)),
    );
  }
}

class _LegacyEtaContent extends StatelessWidget {
  const _LegacyEtaContent({
    required this.label,
    required this.minutes,
    required this.distanceMeters,
    required this.onClose,
    required this.onClosePointerDown,
  });

  final String label;
  final int minutes;
  final double distanceMeters;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onClosePointerDown;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                  children: [
                    TextSpan(text: '약 $minutes분 '),
                    TextSpan(
                      text: '/ ${distanceMeters.round()}m',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 8),
          // "안내 종료"는 되돌리기 어려운 조작(경로/도착지 리셋)이므로
          // 색상은 부드럽되, 다른 카드 요소보다 명확히 눌러야 할 지점으로
          // 읽히도록 outlined 톤을 준다.
          Listener(
            onPointerDown: (event) => onClosePointerDown?.call(event.position),
            child: TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD93025),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0x33D93025)),
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('안내 종료'),
            ),
          ),
        ],
      ],
    );
  }
}
