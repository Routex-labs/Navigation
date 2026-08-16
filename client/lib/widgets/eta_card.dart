import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../domain/geo/distance_format.dart';
import '../domain/guidance/route_guidance.dart';

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
                onStartGuidance: onStartGuidance,
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
        Icon(routeGuidanceIcon(guidance.action), size: 24, color: accent),
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

/// 남은 거리 표기. 10 m 미만만 한 자리까지 보여 준다 — 도착 직전에 "0m"가
/// 몇 걸음 동안 붙어 있으면 안내가 멈춘 것처럼 보인다. 그 위는 [formatDistance]에
/// 맡겨 검색 결과·장소 상세와 같은 규칙(1 km부터 km)을 쓴다.
String _distanceLabel(double meters) {
  if (!meters.isFinite || meters < 0) return '';
  if (meters < 10) return '${meters.toStringAsFixed(1)}m';
  return formatDistance(meters);
}

/// 안내 지시별 아이콘. 걷는 중 배너와 경로 단계 목록([RouteStepsSheet])이
/// **같은 매핑**을 봐야 한다 — 목록에서 본 그림이 걷는 중 배너에 그대로 다시
/// 나와야 같은 지시로 읽힌다. 그래서 배너 전용 private이 아니라 public이다.
IconData routeGuidanceIcon(RouteGuidanceAction action) => switch (action) {
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
                      text: '/ ${formatDistance(distanceMeters)}',
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
        // **시작과 종료는 함께 뜨지 않는다.** 계획 상태에서 할 일은 출발뿐이고,
        // 안내 중에 할 일은 그만두는 것뿐이다. 둘을 나란히 두면 아직 출발도 안
        // 한 화면에 "종료"가 있어, 사용자는 무엇이 이미 시작됐는지부터 헷갈린다.
        // 계획을 접는 길은 상단 길찾기 바에 그대로 있다.
        if (onClose != null && onStartGuidance == null) ...[
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
