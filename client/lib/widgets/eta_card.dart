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
    this.onStartGuidance,
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

  /// 있으면 "안내 시작" 버튼을 보여준다. 자동차 경로를 **계획 상태**로 그려 둔
  /// 동안만 준다 — 누르면 카메라가 현재 위치로 내려가 따라가기가 시작된다.
  ///
  /// 계획과 안내를 나누는 이유는 **두 화면이 답하는 질문이 다르기 때문**이다.
  /// 계획 화면은 "어디로 어떻게 가는가"라 경로 전체가 보여야 하고, 안내 화면은
  /// "지금 어디서 뭘 하는가"라 내 위치가 커야 한다. 경로를 그리자마자 위치로
  /// 확대해 버리면 사용자는 전체 경로를 한 번도 못 보고 안내에 들어간다.
  final VoidCallback? onStartGuidance;

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
                onStartGuidance: onStartGuidance,
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
      RouteGuidanceAction.wrongWay => Icons.u_turn_right_rounded,
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
        color: action == RouteGuidanceAction.wrongWay
            ? const Color(0xFFFCE8E6)
            : const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        size: 30,
        color: action == RouteGuidanceAction.wrongWay
            ? const Color(0xFFD93025)
            : const Color(0xFF1A73E8),
      ),
    );
  }
}

class _LegacyEtaContent extends StatelessWidget {
  const _LegacyEtaContent({
    required this.label,
    required this.minutes,
    required this.distanceMeters,
    required this.onClose,
    required this.onStartGuidance,
    required this.onClosePointerDown,
  });

  final String label;
  final int minutes;
  final double distanceMeters;
  final VoidCallback? onClose;
  final VoidCallback? onStartGuidance;
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
        // 이동 수단을 고르는 자리는 길찾기 화면 하나다. 예전에는 이 카드에도
        // "대중교통" 버튼이 있었는데, 안내가 이미 그려진 자리에서 수단이 또
        // 갈리면 같은 선택이 두 화면에 흩어진다 — 상단 초안 바의 행을 눌러
        // 길찾기 화면으로 돌아가면 거기서 세 수단을 한 줄로 고를 수 있다.
        if (onStartGuidance != null) ...[
          const SizedBox(width: 8),
          // "안내 시작"은 이 카드에서 **권하는** 다음 행동이라 채운 버튼이다.
          // 종료(외곽선)와 톤을 나눠, 운전 전에 눌러야 할 것이 무엇인지 색으로
          // 먼저 읽히게 한다.
          FilledButton(
            key: const ValueKey('eta-start-guidance'),
            onPressed: onStartGuidance,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('안내 시작'),
          ),
        ],
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
