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
    required this.onPlaceLocation,
    this.placingLocation = false,
  });

  final MapMode mode;
  final ValueChanged<MapMode> onModeChanged;
  final VoidCallback onCalibrate;

  /// 위치 보정 버튼 옆에 놓인 "위치 지정" 버튼을 눌렀을 때 호출된다. 지도를
  /// 켜지 않은 채 건물에 들어와 자동 위치 추정이 되지 않을 때, 사용자가 직접
  /// 지도에서 본인 위치를 지정하는 흐름의 진입점이다. 실내 모드에서만
  /// 노출된다 — 야외 모드는 GPS로 이미 위치가 잡히므로 이 버튼이 필요없다.
  final VoidCallback onPlaceLocation;

  /// 사용자가 "위치 지정" 버튼을 눌러 지도 탭을 대기 중인지. true면 버튼을
  /// 눌린(선택된) 톤으로 표시해서 "지금 지도의 어딘가를 탭해야 한다"는 대기
  /// 상태임을 시각적으로 알린다.
  final bool placingLocation;

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mode == MapMode.indoor) ...[
                  _PlaceLocationButton(
                    onPressed: onPlaceLocation,
                    active: placingLocation,
                  ),
                  const SizedBox(width: 10),
                ],
                _CalibrateButton(onPressed: onCalibrate),
              ],
            ),
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
    return Tooltip(
      message: '위치 보정',
      child: Material(
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
      ),
    );
  }
}

/// 위치 보정 버튼 옆에 나란히 놓이는 "위치 지정" 버튼. 지도 없이 건물에
/// 들어와 자동 위치 추정이 아직 되지 않은 상태에서, 사용자가 지도 위 한 점을
/// 탭해 현재 위치를 직접 지정할 수 있게 해준다. 시각적 무게를 보정 버튼과
/// 맞추면서도 다른 액션임을 알 수 있도록 실내 톤(indoor)의 파란 아이콘을 쓴다.
///
/// [active]가 true이면 지도 탭 대기 중임을 알리기 위해 배경을 indoor 색으로
/// 채우고 아이콘을 흰색으로 바꿔 "눌린" 상태로 보인다. 사용자가 지도의
/// 아무 곳도 아직 탭하지 않은 시점에도 어떤 버튼이 현재 활성인지 헷갈리지
/// 않게 하는 것이 목적이다.
class _PlaceLocationButton extends StatelessWidget {
  const _PlaceLocationButton({required this.onPressed, this.active = false});

  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // 활성 상태는 채워진 indoor 색 + 흰 아이콘으로, 비활성은 흰 배경 + indoor
    // 아이콘 색으로. 홈/실내 세그먼트의 활성 표시와 시각 언어를 맞춘다.
    final backgroundColor = active ? AppColors.indoor : Colors.white;
    final iconColor = active ? Colors.white : AppColors.indoor;
    return Tooltip(
      message: active ? '지도를 탭해 위치를 지정' : '지도에서 내 위치 지정',
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        elevation: active ? 6 : 4,
        shadowColor: (active ? AppColors.indoor : Colors.black).withValues(
          alpha: active ? 0.35 : 0.18,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.edit_location_alt_outlined,
              size: 20,
              color: iconColor,
            ),
          ),
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
