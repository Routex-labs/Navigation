import 'package:flutter/material.dart';

import '../core/floor_switch_progress.dart';
import '../theme/app_theme.dart';

/// 층 전환이 오래 걸릴 때([floorSwitchMotifDelay] 초과) 지도 위 중앙에 띄우는
/// 에스컬레이터 모티프 — 정면에서 본 계단이 벨트처럼 위/아래로 계속 흐른다.
///
/// 스피너를 쓰지 않는 이유: 원형 스피너는 "무언가 기다린다"만 말하고 **무엇을**
/// 기다리는지 말하지 않는다. 계단이 위로 흐르면 "위층으로 가는 중", 아래로
/// 흐르면 "아래층으로 가는 중"이라, 기다림 자체가 지금 일어나는 일의 설명이
/// 된다. 방향은 호출부가 현재 층↔목표 층 순위 비교
/// ([floorSwitchDirectionBetween])로 정해 넘긴다.
///
/// 외부 패키지·에셋 없이 [CustomPainter]로만 그린다. 색은 전부 [AppColors]
/// 토큰 — 이전 층 도면이 그대로 보이는 지도 위에 바로 뜨므로, 흰 카드 배경이
/// 있어야 도면 무늬 위에서도 읽힌다(베일 없이 뜨는 근거). 흰 카드 + 파스텔
/// 파랑 계단이면 앱의 다른 오버레이(카드류)와 같은 톤으로 읽힌다.
class FloorSwitchEscalatorMotif extends StatefulWidget {
  const FloorSwitchEscalatorMotif({super.key, required this.direction});

  /// 계단이 흐르는 방향. 올라가는 전환이면 위로, 내려가는 전환이면 아래로.
  final FloorSwitchDirection direction;

  @override
  State<FloorSwitchEscalatorMotif> createState() =>
      _FloorSwitchEscalatorMotifState();
}

class _FloorSwitchEscalatorMotifState extends State<FloorSwitchEscalatorMotif>
    with SingleTickerProviderStateMixin {
  // 한 주기에 계단이 정확히 한 칸씩 흘러 이음새 없이 반복된다. 주기는 타이밍
  // 정책의 최소 표시 시간과 같은 상수를 본다 — "한 칸은 보여 준다"는 약속이
  // 두 곳에서 어긋나지 않게.
  late final AnimationController _belt = AnimationController(
    vsync: this,
    duration: floorSwitchMotifStepPeriod,
  )..repeat();

  @override
  void dispose() {
    _belt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.direction == FloorSwitchDirection.up;
    // RepaintBoundary로 묶어 매 프레임 다시 그리는 범위를 이 카드로 한정한다 —
    // 지도 화면 Stack 전체가 벨트 애니메이션에 끌려 다니지 않게.
    return RepaintBoundary(
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up
                  ? Icons.keyboard_double_arrow_up_rounded
                  : Icons.keyboard_double_arrow_down_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 36,
              height: 44,
              child: CustomPaint(
                painter: _EscalatorBeltPainter(animation: _belt, up: up),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 정면에서 본 에스컬레이터: 양옆 난간(고정) 사이로 계단의 앞모서리(가로 막대)
/// 들이 일정 간격으로 흐른다. 막대는 위·아래 가장자리에서 투명해지며 벨트가
/// 화면 밖으로 이어지는 느낌을 만든다.
class _EscalatorBeltPainter extends CustomPainter {
  _EscalatorBeltPainter({required this.animation, required this.up})
    : super(repaint: animation);

  final Animation<double> animation;
  final bool up;

  /// 계단 앞모서리 사이 간격(논리 px). 한 주기에 이만큼 이동해 이음새가 없다.
  static const _stepSpacing = 10.0;
  static const _stepThickness = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final railPaint = Paint()
      ..color = AppColors.blue100
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    // 난간은 움직이지 않는다 — 흐르는 것은 계단뿐이라는 대비가 벨트를 만든다.
    canvas.drawLine(Offset(1.5, 2), Offset(1.5, size.height - 2), railPaint);
    canvas.drawLine(
      Offset(size.width - 1.5, 2),
      Offset(size.width - 1.5, size.height - 2),
      railPaint,
    );

    // 진행도 0→1이 계단 한 칸 이동. 올라갈 때는 -y, 내려갈 때는 +y로 흐른다.
    final shift = animation.value * _stepSpacing * (up ? -1 : 1);
    final stepPaint = Paint();
    final stepWidth = size.width - 12; // 난간 안쪽으로.
    final left = (size.width - stepWidth) / 2;
    // 화면 밖 한 칸 여유를 두고 그려야 가장자리에서 칸이 생겨나며 들어온다.
    for (
      var y = -_stepSpacing + shift.remainder(_stepSpacing);
      y < size.height + _stepSpacing;
      y += _stepSpacing
    ) {
      // 가장자리 8px 구간에서 서서히 사라진다. clamp 없이 두면 화면 밖 칸이
      // 음수 불투명도를 요구해 assert에 걸린다.
      final edge = (y < size.height / 2 ? y : size.height - y) / 8.0;
      final alpha = edge.clamp(0.0, 1.0);
      if (alpha <= 0) continue;
      stepPaint.color = AppColors.blue300.withValues(alpha: alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y - _stepThickness / 2, stepWidth,
              _stepThickness),
          const Radius.circular(2),
        ),
        stepPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_EscalatorBeltPainter oldDelegate) =>
      oldDelegate.up != up || oldDelegate.animation != animation;
}
