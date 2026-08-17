import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../domain/guidance/route_guidance.dart';
import '../../../widgets/eta_card.dart';

/// 안내 배너를 탭했을 때 올라오는 **경로 전체 단계 목록** 시트.
///
/// 걷는 중 배너는 "다음 한 수"만 말한다. 이 시트는 그 반대편이다 — 출발 전에(또는
/// 걷다 멈춰서) "전체가 어떻게 생겼는지"를 훑는 화면이라, 직진·회전·층 이동을
/// 처음부터 끝까지 편다. 둘을 한 화면에 섞지 않는 이유는 배너 주석에 있다:
/// 걸으면서 보는 화면에서 목록은 지도를 덮는 짐이다. 그래서 목록은 **눌렀을 때만**
/// 올라오고 닫으면 흔적이 없다.
void showRouteStepsSheet(
  BuildContext context, {
  required List<RouteStep> steps,
  required String destinationName,
}) {
  showModalBottomSheet<void>(
    context: context,
    // 곡률·표면은 시트 자신이 그린다([RoutexBottomSheet]).
    backgroundColor: Colors.transparent,
    // 목록이 길면 화면 절반까지만 차지하고 안에서 스크롤한다 — 시트가 지도를
    // 다 덮으면 "어디를 말하는지" 대조할 수 없다.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
    ),
    builder: (context) =>
        _RouteStepsSheet(steps: steps, destinationName: destinationName),
  );
}

class _RouteStepsSheet extends StatelessWidget {
  const _RouteStepsSheet({required this.steps, required this.destinationName});

  final List<RouteStep> steps;
  final String destinationName;

  @override
  Widget build(BuildContext context) => RoutexBottomSheet(
    showHandle: true,
    header: RoutexSheetHeader(
      title: '$destinationName까지',
      onClose: () => Navigator.of(context).pop(),
    ),
    // **목록에 뷰포트를 준다.** 손잡이나 머리 줄이 있는 시트는 본문을
    // `Column(mainAxisSize: min)` 안에 놓으므로, 감싸지 않으면 스크롤 뷰가 세로
    // 제약을 못 받아 콘텐츠 높이 그대로 커진다 — 스크롤이 아니라 **넘침**이 되고
    // 마지막 단계들이 잘린다(24단계에서 1,128px 넘쳤다).
    //
    // `expand: true`로도 뷰포트는 생기지만 그러면 세 단계짜리 경로에도 시트가
    // 화면 절반을 가져간다. 이 시트의 계약은 위 `showRouteStepsSheet` 주석대로
    // "길면 절반까지"이므로 loose fit이 맞다. 검증은
    // `test/screens/outdoor_map/widgets/route_steps_sheet_test.dart`.
    child: Flexible(
      child: SingleChildScrollView(
        child: RoutexStepList(
          steps: [
            for (final step in steps)
              () {
                final parts = routeStepParts(step);
                return RoutexStep(
                  // 도착 행은 어디에 도착하는지까지 말한다 — "도착" 한 단어는
                  // 목록의 마지막 줄로는 심심하다.
                  instruction: step.action == RouteGuidanceAction.arrived
                      ? '$destinationName 도착'
                      : parts.instruction,
                  // 걷는 중 배너와 같은 매핑 — 이유는 [routeGuidanceIcon]에.
                  icon: routeGuidanceIcon(step.action),
                  distance: parts.distance,
                  detail: parts.detail,
                );
              }(),
          ],
          // 지금 어느 단계인지는 아직 세지 않는다. 계약상 null은 "아직 출발하지
          // 않았다"는 뜻이고, 이 목록을 여는 자리가 대부분 그 상태다.
        ),
      ),
    ),
  );
}
