import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 현재 위치 마커 모드. 실외(GPS)/실내(PDR)에 따라 색과 아이콘이 다르다.
enum LocationMode {
  outdoor(color: AppColors.primary, icon: Icons.navigation),
  indoor(color: AppColors.indoor, icon: Icons.circle);

  const LocationMode({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}

/// 현재 위치를 나타내는 마커 아이콘 (design.md 공통 컴포넌트: LocationMarker).
///
/// [colorOverride]는 GPS 정확도 낮음 등 상태에 따라 기본 모드 색을 덮어써야 할 때 쓴다.
/// [headingDegrees]를 주면(북쪽 기준 시계방향 각도) 화살표 끝이 그 방향을
/// 가리키도록 회전시켜 진행 방향을 보여준다 — 없으면(실내 모드 등) 회전하지 않는다.
class LocationMarker extends StatelessWidget {
  const LocationMarker({super.key, required this.mode, this.colorOverride, this.headingDegrees});

  final LocationMode mode;
  final Color? colorOverride;
  final double? headingDegrees;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      mode.icon,
      color: colorOverride ?? mode.color,
      size: mode == LocationMode.indoor ? 14 : 24,
    );
    final heading = headingDegrees;
    if (heading == null) return icon;
    return Transform.rotate(angle: heading * (pi / 180), child: icon);
  }
}
