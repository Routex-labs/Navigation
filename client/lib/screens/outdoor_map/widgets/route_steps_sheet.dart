import 'package:flutter/material.dart';

import '../../../domain/route_guidance.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/eta_card.dart';

/// 안내 배너를 탭했을 때 올라오는 **경로 전체 단계 목록** 시트.
///
/// 걷는 중 배너는 "다음 한 수"만 말한다([EtaCard]의 한 줄 규칙). 이 시트는 그
/// 반대편이다 — 출발 전에(또는 걷다 멈춰서) "전체가 어떻게 생겼는지"를 훑는
/// 화면이라, 직진·회전·층 이동을 처음부터 끝까지 편다. 둘을 한 화면에 섞지
/// 않는 이유는 배너 주석에 있다: 걸으면서 보는 화면에서 목록은 지도를 덮는
/// 짐이다. 그래서 목록은 **눌렀을 때만** 올라오고 닫으면 흔적이 없다.
void showRouteStepsSheet(
  BuildContext context, {
  required List<RouteStep> steps,
  required String destinationName,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // 목록이 길면 화면 절반까지만 차지하고 안에서 스크롤한다 — 시트가 지도를
    // 다 덮으면 "어디를 말하는지" 대조할 수 없다.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
    ),
    builder: (context) => _RouteStepsSheet(
      steps: steps,
      destinationName: destinationName,
    ),
  );
}

class _RouteStepsSheet extends StatelessWidget {
  const _RouteStepsSheet({required this.steps, required this.destinationName});

  final List<RouteStep> steps;
  final String destinationName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '$destinationName까지',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: steps.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 56, color: Color(0x11000000)),
              itemBuilder: (context, index) {
                final step = steps[index];
                final arrived = step.action == RouteGuidanceAction.arrived;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    // 걷는 중 배너와 같은 매핑 — 이유는 [routeGuidanceIcon]에.
                    routeGuidanceIcon(step.action),
                    size: 22,
                    color: arrived
                        ? const Color(0xFFD93025)
                        : AppColors.primary,
                  ),
                  title: Text(
                    // 도착 행은 어디에 도착하는지까지 말한다 — "도착" 한 단어는
                    // 목록의 마지막 줄로는 심심하다.
                    arrived ? '$destinationName 도착' : routeStepText(step),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: arrived ? FontWeight.w800 : FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
