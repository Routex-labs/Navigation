import 'dart:math' as math;

import 'package:flutter/material.dart';

double cardinalScreenAngleDeg({
  required double northMapBearingDeg,
  required double cameraBearingDeg,
}) {
  final angle = (northMapBearingDeg - cameraBearingDeg) % 360;
  return angle < 0 ? angle + 360 : angle;
}

/// 지도와 별개로 화면 전체에 그리는 디버그용 절대 방위 격자.
///
/// 크기는 줌에 영향받지 않는 카메라 앱 격자선처럼 유지하고, 지도 bearing만
/// 반영해 실제 N/E/S/W가 화면에서 향하는 방향을 실시간으로 맞춘다.
class CardinalGridOverlay extends StatelessWidget {
  const CardinalGridOverlay({
    super.key,
    required this.northMapBearingDeg,
    required this.cameraBearingDeg,
  });

  final double northMapBearingDeg;
  final double cameraBearingDeg;

  @override
  Widget build(BuildContext context) {
    final angle = cardinalScreenAngleDeg(
      northMapBearingDeg: northMapBearingDeg,
      cameraBearingDeg: cameraBearingDeg,
    );
    return IgnorePointer(
      child: Semantics(
        label: '절대 방위 전체 화면 격자',
        child: CustomPaint(
          key: const ValueKey('cardinal-grid-overlay'),
          painter: _CardinalGridPainter(northScreenAngleDeg: angle),
        ),
      ),
    );
  }
}

class _CardinalGridPainter extends CustomPainter {
  const _CardinalGridPainter({required this.northScreenAngleDeg});

  final double northScreenAngleDeg;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radians = northScreenAngleDeg * math.pi / 180;
    final north = Offset(math.sin(radians), -math.cos(radians));
    final east = Offset(math.cos(radians), math.sin(radians));
    final linePaint = Paint()
      ..color = const Color(0x75455A64)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(
      _edgePoint(center, -north, size),
      _edgePoint(center, north, size),
      linePaint,
    );
    canvas.drawLine(
      _edgePoint(center, -east, size),
      _edgePoint(center, east, size),
      linePaint,
    );

    _paintLabel(canvas, size, center, north, 'N');
    _paintLabel(canvas, size, center, east, 'E');
    _paintLabel(canvas, size, center, -north, 'S');
    _paintLabel(canvas, size, center, -east, 'W');
  }

  Offset _edgePoint(Offset center, Offset direction, Size size) {
    final horizontal = direction.dx > 0
        ? (size.width - center.dx) / direction.dx
        : direction.dx < 0
        ? -center.dx / direction.dx
        : double.infinity;
    final vertical = direction.dy > 0
        ? (size.height - center.dy) / direction.dy
        : direction.dy < 0
        ? -center.dy / direction.dy
        : double.infinity;
    return center + direction * math.min(horizontal, vertical);
  }

  void _paintLabel(
    Canvas canvas,
    Size size,
    Offset center,
    Offset direction,
    String label,
  ) {
    final edge = _edgePoint(center, direction, size);
    final position = edge - direction * 18;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xCC455A64),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.white, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CardinalGridPainter oldDelegate) =>
      oldDelegate.northScreenAngleDeg != northScreenAngleDeg;
}
