import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/route_guidance.dart';
import 'package:navigation_client/domain/guidance/route_movement.dart';
import 'package:navigation_client/domain/guidance/route_progress.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// 도착하면 안내를 스스로 끝내는 규칙을 고정한다.
///
/// 이 판단이 틀리면 두 방향 모두 사용자에게 손해다. 너무 잘 끝나면 도착지를
/// 고르자마자 경로가 사라져 "눌렀는데 아무 일도 안 일어났다"가 되고, 안 끝나면
/// 이미 도착한 경로가 ETA 카드로 지도를 계속 가린다. 그래서 여기서는 "언제
/// 켜지는가"뿐 아니라 **켜지면 안 되는 경우**를 함께 못박는다.
void main() {
  group('decideArrivalAutoClear', () {
    test('측정된 진행률과 함께 도착하면 자동 종료를 예약한다', () {
      expect(
        decideArrivalAutoClear(
          action: RouteGuidanceAction.arrived,
          hasMeasuredProgress: true,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.schedule,
      );
    });

    test('이미 세는 중이면 다시 걸지 않는다', () {
      // 매 걸음 다시 걸면 도착 지점에서 제자리걸음만 해도 카운트다운이 계속
      // 처음으로 돌아가 영원히 끝나지 않는다.
      expect(
        decideArrivalAutoClear(
          action: RouteGuidanceAction.arrived,
          hasMeasuredProgress: true,
          alreadyScheduled: true,
        ),
        ArrivalAutoClearDecision.keep,
      );
    });

    test('진행률이 없으면 도착 안내가 떠 있어도 예약하지 않는다', () {
      // 진행률이 없을 때의 "도착"은 걸어서 도착한 것이 아니라 경로 전체가 임계값
      // 보다 짧다는 뜻이다. 이걸 종료로 읽으면 바로 옆 매장으로 길을 찾는 순간
      // 경로가 사라진다.
      expect(
        decideArrivalAutoClear(
          action: RouteGuidanceAction.arrived,
          hasMeasuredProgress: false,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.cancel,
      );
    });

    test('도착이 아닌 안내는 예약을 걷어낸다', () {
      // 도착 지점을 지나쳐 다시 걷기 시작한 경우다. 예약이 남아 있으면 사용자가
      // 안내를 보는 중에 경로가 사라진다.
      for (final action in [
        RouteGuidanceAction.straight,
        RouteGuidanceAction.turnLeft,
        RouteGuidanceAction.wrongWay,
        RouteGuidanceAction.elevator,
        null,
      ]) {
        expect(
          decideArrivalAutoClear(
            action: action,
            hasMeasuredProgress: true,
            alreadyScheduled: true,
          ),
          ArrivalAutoClearDecision.cancel,
          reason: '$action',
        );
      }
    });
  });

  group('무엇이 도착으로 읽히는가 — buildRouteGuidance와의 연결', () {
    const localPoints = [LocalPoint(0, 0), LocalPoint(0, 30)];
    const wgs84Points = [LatLng(37, 127), LatLng(37.00027, 127)];

    RouteGuidanceInstruction guidance({
      RouteProgress? progress,
      bool allowArrival = true,
      String? transferMode,
      TravelDirectionState travelDirectionState = TravelDirectionState.forward,
    }) => buildRouteGuidance(
      localPoints: localPoints,
      wgs84Points: wgs84Points,
      progress: progress,
      travelDirectionState: travelDirectionState,
      allowArrival: allowArrival,
      transferMode: transferMode,
    );

    RouteProgress at(double remainingM) => RouteProgress(
      traveledM: 30 - remainingM,
      remainingM: remainingM,
      offsetM: 0.3,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 30 - remainingM),
    );

    test('남은거리가 임계값 안으로 들어와야 종료가 예약된다', () {
      expect(
        decideArrivalAutoClear(
          action: guidance(progress: at(9)).action,
          hasMeasuredProgress: true,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.cancel,
      );
      expect(
        decideArrivalAutoClear(
          action: guidance(progress: at(2)).action,
          hasMeasuredProgress: true,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.schedule,
      );
    });

    test('다층 경로 중간 층의 끝점은 도착이 아니라 환승이라 끝내지 않는다', () {
      // 세그먼트 끝에 닿았지만 목적지 층이 아니다. 여기서 경로를 지우면 사용자는
      // 엘리베이터 앞에서 나머지 층 안내를 잃는다.
      expect(
        decideArrivalAutoClear(
          action: guidance(progress: at(1), allowArrival: false).action,
          hasMeasuredProgress: true,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.cancel,
      );
      expect(
        decideArrivalAutoClear(
          action: guidance(
            progress: at(1),
            allowArrival: false,
            transferMode: 'elevator',
          ).action,
          hasMeasuredProgress: true,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.cancel,
      );
    });

    test('역주행 중에는 끝점 근처여도 끝내지 않는다', () {
      // 역주행 판단은 진행률이 아니라 traversal 상태기가 소유한다. 진행률의
      // headingErrorDeg는 제자리 회전에도 175°가 되므로 그것만으로 역주행이라
      // 부르지 않는다 — [TravelDirectionState.reverseConfirmed]만 안내를 뒤집는다.
      const nearEnd = RouteProgress(
        traveledM: 29,
        remainingM: 1,
        offsetM: 0.2,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
        projectedPoint: LocalPoint(0, 29),
        headingErrorDeg: 175,
      );
      expect(
        decideArrivalAutoClear(
          action: guidance(
            progress: nearEnd,
            travelDirectionState: TravelDirectionState.reverseConfirmed,
          ).action,
          hasMeasuredProgress: true,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.cancel,
      );
    });

    test('진행률 없이 그린 짧은 경로는 도착으로 읽히지만 종료되지는 않는다', () {
      // buildRouteGuidance는 진행률이 없으면 폴리라인 전체 길이를 남은거리로
      // 쓴다. 3m짜리 경로는 그리는 순간 "도착"이 된다 — 이 조합이 종료로
      // 이어지지 않는 것이 hasMeasuredProgress 가드의 존재 이유다.
      final shortRoute = buildRouteGuidance(
        localPoints: const [LocalPoint(0, 0), LocalPoint(0, 3)],
        wgs84Points: const [LatLng(37, 127), LatLng(37.000027, 127)],
        progress: null,
      );
      expect(shortRoute.action, RouteGuidanceAction.arrived);
      expect(
        decideArrivalAutoClear(
          action: shortRoute.action,
          hasMeasuredProgress: false,
          alreadyScheduled: false,
        ),
        ArrivalAutoClearDecision.cancel,
      );
    });
  });
}
