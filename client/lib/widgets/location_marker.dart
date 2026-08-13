import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 현재 위치 마커의 화면 크기(논리 px)와 색.
///
/// **지도 아이콘과 위젯이 같은 값을 봐야 한다.** 지도는 이 마커를 2배 캔버스에
/// 그려 넣고(`outdoor_map_screen.dart`), 층 전환 덮개는 같은 그림을 위젯으로
/// 그린다 — 두 벌로 두면 덮개가 마커를 "가져왔다"는 인상이 크기 차이 하나로
/// 깨진다. 코어 지름(16px)이 이 마커의 체감 크기를 정한다: 야외 GPS 도트(18px)
/// 보다 크고 정확도 원 테두리(44px)보다 작다.
const kLocationMarkerCoreRadiusPx = 8.0;
const kLocationMarkerRimRadiusPx = kLocationMarkerCoreRadiusPx + 2.5;
const kLocationMarkerColor = Color(0xFF1976D2);

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
  const LocationMarker({
    super.key,
    required this.mode,
    this.colorOverride,
    this.headingDegrees,
  });

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
