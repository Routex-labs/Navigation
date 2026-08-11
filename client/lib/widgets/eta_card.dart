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
    this.destinationName,
    this.destinationFloor,
    this.onClose,
    this.onClosePointerDown,
  });

  final double distanceMeters;
  final int minutes;
  final String label;
  final RouteGuidanceInstruction? instruction;

  /// 도착 안내에 적을 목적지 이름·층. 둘 다 있으면 도착 순간 배너가 매장을
  /// 가리키는 카드로 바뀐다 — 없으면 지시 문구 한 줄 그대로다.
  final String? destinationName;
  final String? destinationFloor;

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
        // 안내 한 줄은 위아래를 조인다 — 배너가 얇을수록 도면이 넓어진다.
        // 두 줄인 legacy 쪽은 예전 여백을 유지해야 글자가 답답하지 않다.
        padding: guidance == null
            ? const EdgeInsets.fromLTRB(16, 14, 12, 14)
            : const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: guidance == null
            ? _LegacyEtaContent(
                label: label,
                minutes: minutes,
                distanceMeters: distanceMeters,
                onClose: onClose,
                onClosePointerDown: onClosePointerDown,
              )
            : (guidance.action == RouteGuidanceAction.arrived &&
                  destinationName != null)
            // 도착은 "다음에 무엇을 할지"가 없는 유일한 상태다. 남은
            // 거리도 0이라, 같은 한 줄 배너로 그리면 `0 m`만 붙은 이상한
            // 줄이 된다. 대신 **어디에 도착했는지**를 말한다.
            ? _ArrivalRow(
                name: destinationName!,
                floor: destinationFloor,
                onClose: onClose,
                onClosePointerDown: onClosePointerDown,
              )
            : _GuidanceRow(
                guidance: guidance,
                onClose: onClose,
                onClosePointerDown: onClosePointerDown,
              ),
      ),
    );
  }
}

/// 안내 중 배너 본문. **한 줄이다** — 아이콘 · 지시 문구 · 다음 조작까지 거리.
///
/// 예전에는 두 줄이었다(큰 문구 + `목적지까지 · 약 N분 · Nm 남음`). 걸으면서
/// 보는 화면에서 실제로 쓰는 정보는 **다음에 무엇을 할지와 몇 미터 남았는지**
/// 둘뿐인데, 나머지가 그만큼 지도를 덮고 있었다. 총 소요·총 남은거리는 걷는
/// 동안 계속 바뀌면서도 당장의 행동을 바꾸지 않는다.
///
/// 거리는 총 남은거리가 아니라 [RouteGuidanceInstruction.distanceToActionM],
/// 즉 **다음 조작까지**의 거리다. "오른쪽 통로로 이동 92 m"에서 92 m는 그
/// 모퉁이까지이지 목적지까지가 아니다 — 두 값을 섞으면 사용자는 92 m를 걷고도
/// 모퉁이가 안 나오는 화면을 본다.
class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({
    required this.guidance,
    required this.onClose,
    required this.onClosePointerDown,
  });

  final RouteGuidanceInstruction guidance;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onClosePointerDown;

  @override
  Widget build(BuildContext context) {
    final wrongWay = guidance.action == RouteGuidanceAction.wrongWay;
    final accent = wrongWay ? const Color(0xFFD93025) : AppColors.primary;
    return Row(
      children: [
        Icon(_iconFor(guidance.action), size: 24, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            guidance.primaryText,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _distanceLabel(guidance.distanceToActionM),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 4),
          // 한 줄에는 "종료" 글자를 놓을 자리가 없다. 다만 **없앨 수는 없다** —
          // 안내 중에는 지도 위 chrome이 접혀 있어(`shouldFoldGuidanceChrome`)
          // 이 버튼이 화면에서 빠져나가는 유일한 수단이다.
          Listener(
            onPointerDown: (event) => onClosePointerDown?.call(event.position),
            child: IconButton(
              key: const Key('eta-card-close'),
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.muted,
              tooltip: '안내 종료',
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }
}

/// 도착 안내. 지시 배너가 아니라 **목적지를 가리키는 카드**다.
///
/// 안내가 끝났음을 알리는 동시에 "여기가 그 매장"임을 확인시켜 준다 — 지도에는
/// 같은 순간 그 매장 폴리곤이 강조된다.
class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({
    required this.name,
    required this.floor,
    required this.onClose,
    required this.onClosePointerDown,
  });

  final String name;
  final String? floor;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onClosePointerDown;

  @override
  Widget build(BuildContext context) {
    final where = (floor == null || floor!.isEmpty)
        ? '목적지에 도착했습니다'
        : '$floor · 목적지에 도착했습니다';
    return Row(
      children: [
        const Icon(Icons.place, size: 24, color: Color(0xFFD93025)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                where,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 8),
          // 도착에서는 X가 아니라 체크다. 같은 동작(안내를 끝낸다)이지만 여기서는
          // 취소가 아니라 확인이라, 아이콘이 다르면 사용자가 "실패했나" 하고
          // 망설이지 않는다.
          Listener(
            onPointerDown: (event) => onClosePointerDown?.call(event.position),
            child: IconButton(
              key: const Key('eta-card-close'),
              onPressed: onClose,
              icon: const Icon(Icons.check_circle, size: 24),
              color: AppColors.primary,
              tooltip: '안내 종료',
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }
}

/// 남은 거리 표기. 10 m 미만은 한 자리까지 보여 준다 — 도착 직전에 "0 m"가
/// 몇 걸음 동안 붙어 있으면 안내가 멈춘 것처럼 보인다.
String _distanceLabel(double meters) {
  if (!meters.isFinite || meters < 0) return '';
  if (meters < 10) return '${meters.toStringAsFixed(1)} m';
  return '${meters.round()} m';
}

IconData _iconFor(RouteGuidanceAction action) => switch (action) {
  RouteGuidanceAction.wrongWay => Icons.u_turn_right_rounded,
  RouteGuidanceAction.turnLeft => Icons.turn_left_rounded,
  RouteGuidanceAction.turnRight => Icons.turn_right_rounded,
  RouteGuidanceAction.escalator => Icons.escalator_rounded,
  RouteGuidanceAction.elevator => Icons.elevator_rounded,
  RouteGuidanceAction.arrived => Icons.flag_rounded,
  RouteGuidanceAction.straight => Icons.straight_rounded,
};

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
