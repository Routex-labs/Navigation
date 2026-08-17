import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 안내 중에 카메라를 **내 위치로** 되돌리는 버튼.
///
/// 안내가 시작되면 chrome이 접혀 평소의 "위치 보정" 버튼이 사라지는데, 카메라는
/// 개요 연출로 물러선 뒤 **걸음을 따라가지 않는다** — 되돌릴 수단이 없으면 걷는
/// 내내 자기가 어디쯤인지 안 보이는 화면을 들고 있게 된다.
///
/// **위치 보정과 다른 것이다.** 그쪽은 PDR 앵커를 다시 잡는 추정 보정이고 이쪽은
/// 카메라 조작이다(안내 중 앵커를 다시 잡으면 진행률 기준이 걷는 도중 바뀐다).
/// 그래서 아이콘도 [Icons.near_me]로 달리 뒀다.
class GuidanceRecenterButton extends StatelessWidget {
  const GuidanceRecenterButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => RoutexMapControl(
    label: '내 위치로',
    icon: Icons.near_me,
    // 접히기 전의 위치 보정 버튼과 같은 tone이어야 같은 층위의 조작으로 읽힌다.
    tone: RoutexMapControlTone.accent,
    onPressed: onPressed,
  );
}
