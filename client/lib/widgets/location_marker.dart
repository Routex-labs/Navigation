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
class LocationMarker extends StatelessWidget {
  const LocationMarker({super.key, required this.mode, this.colorOverride});

  final LocationMode mode;
  final Color? colorOverride;

  @override
  Widget build(BuildContext context) {
    return Icon(
      mode.icon,
      color: colorOverride ?? mode.color,
      size: mode == LocationMode.indoor ? 14 : 24,
    );
  }
}
