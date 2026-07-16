import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 하단 바에서 전환 가능한 지도 모드. [outdoor]는 야외(GPS) 지도,
/// [indoor]는 실내 지도 화면에 대응한다.
enum MapMode { outdoor, indoor }

/// 지도 화면(야외/실내) 공통 하단 바. 위치 보정 버튼(우상단) + 홈/실내
/// 전환 세그먼트로 구성된다. 화면 전환은 Navigator push 없이 [onModeChanged]
/// 콜백으로 상위(MapShellScreen)의 상태만 바꾼다 — 탭 전환처럼 즉시 반응해야
/// 하고, 이전 화면 스택이 쌓이면 안 되기 때문이다.
class MapBottomBar extends StatelessWidget {
  const MapBottomBar({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.onCalibrate,
  });

  final MapMode mode;
  final ValueChanged<MapMode> onModeChanged;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _CalibrateButton(onPressed: onCalibrate),
            const SizedBox(height: 10),
            _ModeSegment(mode: mode, onModeChanged: onModeChanged),
          ],
        ),
      ),
    );
  }
}

class _CalibrateButton extends StatelessWidget {
  const _CalibrateButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.my_location, size: 20, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({required this.mode, required this.onModeChanged});

  final MapMode mode;
  final ValueChanged<MapMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              label: '홈',
              icon: Icons.home_rounded,
              active: mode == MapMode.outdoor,
              onTap: () => onModeChanged(MapMode.outdoor),
            ),
            _ModeButton(
              label: '실내',
              icon: Icons.apartment_rounded,
              active: mode == MapMode.indoor,
              onTap: () => onModeChanged(MapMode.indoor),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: active ? Colors.white : AppColors.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
