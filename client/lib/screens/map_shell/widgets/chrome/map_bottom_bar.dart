import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 하단 바에서 전환 가능한 지도 모드. [outdoor]는 야외(GPS) 지도,
/// [indoor]는 실내 지도 화면에 대응한다.
/// "위치 지정" 버튼 아이콘. Material 아이콘 대신 전용 에셋을 쓰는 이유는
/// 에셋 파일 상단 주석에 있다 — 색을 알파로만 표현해 활성/비활성 두 상태에서
/// 같은 농담 차이를 유지해야 한다.
const _placeLocationIconAsset = 'assets/icons/place_location_pin.svg';

/// 지도 화면 하단 바. 위치 보정 버튼과 "위치 지정" 버튼으로 구성된다.
///
/// 예전에는 여기에 홈/실내 전환 세그먼트가 있었다. 실내가 별도 탭이던 시절의
/// 잔재인데, 실내 도면을 야외 지도 위 오버레이로 그리게 되면서 전환할 대상이
/// 없어졌다 — 건물에 들어가면 오버레이가 열리고 나오면 닫힌다.
class MapBottomBar extends StatelessWidget {
  const MapBottomBar({
    super.key,
    required this.onCalibrate,
    required this.onPlaceLocation,
    this.placingLocation = false,
    this.showPlaceLocation = true,
  });

  final VoidCallback onCalibrate;

  /// 위치 보정 버튼 옆에 놓인 "위치 지정" 버튼을 눌렀을 때 호출된다. 지도를
  /// 켜지 않은 채 건물에 들어와 자동 위치 추정이 되지 않을 때, 사용자가 직접
  /// 지도에서 본인 위치를 지정하는 흐름의 진입점이다. 야외 지도의 실내 진입
  /// 오버레이와 실내 지도 모두에서 노출한다.
  final VoidCallback onPlaceLocation;

  /// 사용자가 "위치 지정" 버튼을 눌러 지도 탭을 대기 중인지. true면 버튼을
  /// 눌린(선택된) 톤으로 표시해서 "지금 지도의 어딘가를 탭해야 한다"는 대기
  /// 상태임을 시각적으로 알린다.
  final bool placingLocation;

  /// 위치 지정 버튼 자체를 노출할지. 야외 모드에서 실내 진입 오버레이가 아직
  /// 켜지지 않았거나 층 정보가 준비되지 않은 상황에서는 상위가 false로 넘겨
  /// 버튼을 숨긴다 — 눌러도 의미가 없는 버튼을 노출해 혼란을 주지 않는다.
  final bool showPlaceLocation;

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
                if (showPlaceLocation) ...[
                  _PlaceLocationButton(
                    onPressed: onPlaceLocation,
                    active: placingLocation,
                  ),
                  const SizedBox(width: RoutexSpacing.controlGap),
                ],
                RoutexMapControl(
                  label: '위치 보정',
                  icon: Icons.my_location,
                  // 늘 강조되지만 선택 상태는 아니다 — 누를 때마다 같은 일을
                  // 하는 조작이다.
                  tone: RoutexMapControlTone.accent,
                  onPressed: onCalibrate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 위치 보정 버튼 옆에 나란히 놓이는 "위치 지정" 버튼. 지도 없이 건물에
/// 들어와 자동 위치 추정이 아직 되지 않은 상태에서, 사용자가 지도 위 한 점을
/// 탭해 현재 위치를 직접 지정할 수 있게 해준다.
///
/// 아이콘은 [_placeLocationIconAsset]이고 **색은 옆 위치 보정 버튼과 같은
/// [AppColors.primary]** 다. 예전에는 "다른 액션"임을 색으로 구분하려고 실내
/// 톤(indoor)을 썼는데, 나란히 붙은 두 원형 버튼의 파랑이 미묘하게 달라 색이
/// 바랜 것처럼 보였다. 두 버튼의 구분은 아이콘 모양이 맡는다.
///
/// [active]가 true이면 지도 탭 대기 중임을 알리기 위해 배경을 채우고 아이콘을
/// 흰색으로 바꿔 "눌린" 상태로 보인다. 사용자가 지도의 아무 곳도 아직 탭하지
/// 않은 시점에도 어떤 버튼이 현재 활성인지 헷갈리지 않게 하는 것이 목적이다.
class _PlaceLocationButton extends StatelessWidget {
  const _PlaceLocationButton({required this.onPressed, this.active = false});

  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => RoutexMapControl(
    label: active ? '지도를 탭해 위치를 지정' : '지도에서 내 위치 지정',
    // 대기 중이면 다음 지도 탭을 이 버튼이 가져간 상태다. 그때만 채워지고 한
    // 단계 앞으로 나온다.
    tone: active ? RoutexMapControlTone.active : RoutexMapControlTone.accent,
    glyphBuilder: (context, color, size) => SvgPicture.asset(
      _placeLocationIconAsset,
      width: size,
      height: size,
      // SVG는 색을 알파로만 들고 있다. srcIn이 RGB를 갈아치우고 알파는
      // 남기므로, 몸통(옅음)과 외곽선(진함)의 농담 차이가 두 상태에서 모두
      // 유지된다(에셋 파일 주석 참고).
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
    onPressed: onPressed,
  );
}
