import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'pdr_anchor.dart';

/// UI가 **호출**하는 명령 계약(UI → 로직).
///
/// 세션 lifecycle과 anchor 확정은 headless 컨트롤러가 소유한다. UI는 사용자 제스처를
/// 이 메서드로 전달만 한다.
abstract interface class IndoorNavigationIntents {
  /// 실내 안내 시작. anchor 확정 절차를 개시하고 센서 세션을 켠다.
  Future<void> startGuidance({required String floorId});

  /// 실내 안내 종료. 센서 세션을 끈다.
  Future<void> stopGuidance();

  /// 사용자가 지도에 현재 위치를 찍어 anchor 위치를 확정한다.
  /// [floorPointM]은 사용자가 지목한 floor local_m 좌표이고, [axes]는 PDR의
  /// east/north를 이 floor의 축 규약으로 바꾸는 변환이다.
  Future<void> confirmAnchorByPin({
    required PdrLocalPoint floorPointM,
    PdrToFloorAxes axes = const PdrToFloorAxes.identity(),
  });

  /// 사용자가 현재 진행 방향을 floor local_m 방향으로 맞춰 rotation을 확정한다.
  /// [floorDirection]은 위치가 아닌 단위와 무관한 방향 벡터다. 컨트롤러가 anchor
  /// 확정 때 받은 axes로 PDR 동·북 방향에 역변환한다.
  Future<void> confirmAnchorByFloorDirection({
    required PdrLocalPoint floorDirection,
  });

  /// 층 변경. PDR 세션을 reset하고 새 층 anchor 확정을 다시 요구한다.
  Future<void> changeFloor({required String floorId});
}
