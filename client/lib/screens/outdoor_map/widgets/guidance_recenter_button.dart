import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 안내 중에 카메라를 **내 위치로** 되돌리는 버튼.
///
/// ## 왜 안내 전용으로 따로 두는가
///
/// 안내가 시작되면 지도 위 chrome이 통째로 접힌다(`shouldFoldGuidanceChrome`) —
/// 하단 바가 사라지므로 평소의 "위치 보정"(`MapBottomBar`) 버튼도 함께 사라진다.
/// 그 버튼이 곧 사용자가 화면을 자기 위치로 되돌리는 유일한 수단이었다.
///
/// 여기에 안내 시작 순간의 개요 연출이 겹친다. 카메라가 경로 전체를 담으러
/// 물러선 뒤 **걸음을 따라가지 않으므로**, 되돌릴 수단이 없으면 사용자는 걷는
/// 내내 자기가 어디쯤인지 보이지 않는 화면을 들고 있게 된다. 접힌 하단 바를
/// 통째로 되살리는 대신, 그 상황에서 실제로 필요한 조작 하나만 남긴 것이다.
///
/// ## 위치 보정과 다른 것
///
/// 이름은 비슷해도 하는 일이 다르다. "위치 보정"은 PDR 앵커를 다시 잡는
/// **추정 보정**이고, 이 버튼은 지도를 옮기기만 하는 **카메라 조작**이다.
/// 안내 중에 앵커를 다시 잡게 하면 진행률과 경로 이탈 판정의 기준이 걷는 도중
/// 통째로 바뀐다. 그래서 아이콘을 [Icons.near_me]로 달리 두어, 접히기 전에 보던
/// 위치 보정(`Icons.my_location`)과 같은 버튼으로 읽히지 않게 했다.
class GuidanceRecenterButton extends StatelessWidget {
  const GuidanceRecenterButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '내 위치로',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        // 지도에 붙은 조작이다(AppElevation.onMap) — 접히기 전의 위치 보정
        // 버튼과 같은 높이여야 같은 층위의 조작으로 읽힌다.
        elevation: AppElevation.onMap,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.near_me, size: 20, color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}
