import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 현재 지도 좌표에서 실제 진북이 향하는 bearing.
///
/// 더현대 도면은 local +x를 WGS84 동쪽으로 놓아 생성됐지만, 네이버 지도의
/// 북고정 캡처와 VWorld 외곽의 대응 변을 비교하면 local +x는 실제로 진북 기준
/// 약 51.5°를 향한다. 따라서 현재 도면 위 진북은 지도상의 북쪽에서 시계방향
/// 38.5°(= 90° - 51.5°) 방향이다.
class AbsoluteNorthReference {
  const AbsoluteNorthReference({
    required this.mapBearingDeg,
    required this.description,
  });

  final double mapBearingDeg;
  final String description;
}

const _theHyundaiNorthReference = AbsoluteNorthReference(
  mapBearingDeg: 38.5,
  description: '더현대 도면 기준 진북 +38.5°',
);

/// 검증된 건물만 절대 방위를 표시한다. 알 수 없는 건물에 0°를 적용하면
/// 잘못된 진북을 확정값처럼 보여주므로 null을 반환한다.
AbsoluteNorthReference? absoluteNorthReferenceForBuilding(String buildingId) =>
    switch (buildingId) {
      'thehyundai-seoul' => _theHyundaiNorthReference,
      _ => null,
    };

/// 카메라가 바라보는 bearing을 반영한 화면상의 시계방향 각도.
double absoluteDirectionScreenAngleDeg({
  required double mapBearingDeg,
  required double cameraBearingDeg,
}) {
  final normalized = (mapBearingDeg - cameraBearingDeg) % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

/// 지도 카메라 회전과 무관하게 실제 동·서·남·북이 화면에서 향하는 방향을
/// 보여주는 디버그용 compass rose.
class AbsoluteCardinalOverlay extends StatelessWidget {
  const AbsoluteCardinalOverlay({
    super.key,
    required this.reference,
    required this.cameraBearingDeg,
    this.showPhoneHeading = false,
    this.phoneHeadingDeg,
    this.phoneHeadingStable = false,
    this.phoneHeadingAccuracy,
  });

  final AbsoluteNorthReference reference;
  final double cameraBearingDeg;
  final bool showPhoneHeading;

  /// 휴대폰 상단이 향하는 센서 원본 방위. 0°=자북, 90°=동쪽.
  final double? phoneHeadingDeg;
  final bool phoneHeadingStable;
  final String? phoneHeadingAccuracy;

  @override
  Widget build(BuildContext context) {
    final northScreenAngleDeg = absoluteDirectionScreenAngleDeg(
      mapBearingDeg: reference.mapBearingDeg,
      cameraBearingDeg: cameraBearingDeg,
    );
    final measuredHeading = showPhoneHeading ? phoneHeadingDeg : null;
    final phoneScreenAngleDeg = measuredHeading == null
        ? null
        : absoluteDirectionScreenAngleDeg(
            mapBearingDeg: reference.mapBearingDeg + measuredHeading,
            cameraBearingDeg: cameraBearingDeg,
          );

    return IgnorePointer(
      child: Semantics(
        label: [
          reference.description,
          '카메라 ${cameraBearingDeg.toStringAsFixed(1)}°',
          if (measuredHeading != null)
            '폰 측정 ${measuredHeading.toStringAsFixed(1)}°',
        ].join(', '),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x337E57C2)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  key: const ValueKey('absolute-cardinal-compass'),
                  width: 94,
                  height: 94,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: northScreenAngleDeg * math.pi / 180,
                        child: CustomPaint(
                          size: const Size.square(78),
                          painter: const _CompassNeedlePainter(),
                        ),
                      ),
                      if (phoneScreenAngleDeg != null)
                        Transform.rotate(
                          angle: phoneScreenAngleDeg * math.pi / 180,
                          child: CustomPaint(
                            key: const ValueKey('phone-heading-needle'),
                            size: const Size.square(78),
                            painter: const _PhoneHeadingNeedlePainter(),
                          ),
                        ),
                      for (final direction in const [
                        (label: 'N', offsetDeg: 0.0, color: Color(0xFFD32F2F)),
                        (label: 'E', offsetDeg: 90.0, color: Color(0xFF455A64)),
                        (
                          label: 'S',
                          offsetDeg: 180.0,
                          color: Color(0xFF455A64),
                        ),
                        (
                          label: 'W',
                          offsetDeg: 270.0,
                          color: Color(0xFF455A64),
                        ),
                      ])
                        _CardinalLabel(
                          label: direction.label,
                          angleDeg: northScreenAngleDeg + direction.offsetDeg,
                          color: direction.color,
                        ),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF263238),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '절대 방위',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF37474F),
                  ),
                ),
                Text(
                  '도면 진북 +${reference.mapBearingDeg.toStringAsFixed(1)}°',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: const Color(0xFF6D4C9A),
                  ),
                ),
                if (showPhoneHeading) ...[
                  const SizedBox(height: 2),
                  Text(
                    measuredHeading == null
                        ? '폰 방위 측정 대기'
                        : '폰 ${measuredHeading.toStringAsFixed(0)}° · ${_headingQualityLabel()}',
                    key: const ValueKey('phone-heading-status'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: measuredHeading == null
                          ? const Color(0xFF78909C)
                          : _headingQualityColor(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _headingQualityLabel() {
    final accuracy = phoneHeadingAccuracy?.trim().toUpperCase();
    if (accuracy != null && accuracy.isNotEmpty && accuracy != 'UNKNOWN') {
      return accuracy;
    }
    return phoneHeadingStable ? 'STABLE' : '불안정';
  }

  Color _headingQualityColor() {
    final accuracy = phoneHeadingAccuracy?.toLowerCase();
    if (!phoneHeadingStable ||
        accuracy == 'low' ||
        accuracy == 'uncalibrated') {
      return const Color(0xFFF57C00);
    }
    return const Color(0xFF1976D2);
  }
}

class _CardinalLabel extends StatelessWidget {
  const _CardinalLabel({
    required this.label,
    required this.angleDeg,
    required this.color,
  });

  final String label;
  final double angleDeg;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const radius = 36.0;
    final radians = angleDeg * math.pi / 180;
    return Transform.translate(
      offset: Offset(math.sin(radians) * radius, -math.cos(radians) * radius),
      child: Text(
        label,
        key: ValueKey('absolute-cardinal-$label'),
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  const _CompassNeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFECEFF1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      center + Offset(0, radius - 10),
      center - Offset(0, radius - 10),
      Paint()
        ..color = const Color(0xFF90A4AE)
        ..strokeWidth = 1.5,
    );
    final northTip = center - Offset(0, radius - 5);
    final northNeedle = Path()
      ..moveTo(northTip.dx, northTip.dy)
      ..lineTo(center.dx - 5, center.dy + 5)
      ..lineTo(center.dx + 5, center.dy + 5)
      ..close();
    canvas.drawPath(northNeedle, Paint()..color = const Color(0xFFD32F2F));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PhoneHeadingNeedlePainter extends CustomPainter {
  const _PhoneHeadingNeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final tip = center - Offset(0, radius - 9);
    final paint = Paint()
      ..color = const Color(0xFF1976D2)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, tip + const Offset(0, 6), paint);
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 5, tip.dy + 10)
      ..lineTo(tip.dx + 5, tip.dy + 10)
      ..close();
    canvas.drawPath(arrow, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
