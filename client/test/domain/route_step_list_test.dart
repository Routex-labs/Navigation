import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route_guidance.dart';
import 'package:navigation_client/models/floor_graph.dart';

/// 경로 전체 단계 목록의 검증.
///
/// 회전 판정이 실시간 안내([buildRouteGuidance])와 같은 임계값을 쓰는지가
/// 핵심이다 — 목록에는 회전이 있는데 걷다 보면 배너에 안 나오는(또는 반대)
/// 어긋남이 이 테스트가 막는 사고다.
void main() {
  const lat0 = 37.526;
  const lng0 = 126.928;
  const metersPerDegLat = 111320.0;
  // cos(37.526°) ≈ 0.7931
  final metersPerDegLng =
      metersPerDegLat * 0.7930999260;

  /// 층 로컬 좌표(동쪽 x, 북쪽 y — m)를 wgs84로 옮긴 점.
  LatLng geo(double xM, double yM) =>
      LatLng(lat0 + yM / metersPerDegLat, lng0 + xM / metersPerDegLng);

  RouteStepLeg leg({
    required List<(double, double)> pointsM,
    String floorLabel = '1F',
    String? transferModeToNext,
    String? nextFloorLabel,
  }) => (
    wgs84Points: [for (final (x, y) in pointsM) geo(x, y)],
    localPoints: [for (final (x, y) in pointsM) LocalPoint(x, y)],
    floorLabel: floorLabel,
    transferModeToNext: transferModeToNext,
    nextFloorLabel: nextFloorLabel,
  );

  List<RouteGuidanceAction> actionsOf(List<RouteStep> steps) =>
      [for (final s in steps) s.action];

  group('경로 단계 목록', () {
    test('곧은 경로는 직진 한 줄과 도착뿐이다', () {
      final steps = buildRouteStepList([
        leg(pointsM: [(0, 0), (0, 40), (0, 80)]),
      ]);
      expect(actionsOf(steps), [
        RouteGuidanceAction.straight,
        RouteGuidanceAction.arrived,
      ]);
      expect(steps.first.distanceM, closeTo(80, 0.5));
    });

    test('ㄱ자 경로는 직진-우회전-직진으로 편다', () {
      // 북쪽으로 40 m 간 뒤 동쪽으로 30 m — 오른쪽으로 90도 꺾는 경로.
      final steps = buildRouteStepList([
        leg(pointsM: [(0, 0), (0, 40), (30, 40)]),
      ]);
      expect(actionsOf(steps), [
        RouteGuidanceAction.straight,
        RouteGuidanceAction.turnRight,
        RouteGuidanceAction.straight,
        RouteGuidanceAction.arrived,
      ]);
      expect(steps[0].distanceM, closeTo(40, 0.5));
      expect(steps[2].distanceM, closeTo(30, 0.5));
    });

    test('왼쪽으로 꺾으면 좌회전이다', () {
      final steps = buildRouteStepList([
        leg(pointsM: [(0, 0), (0, 40), (-30, 40)]),
      ]);
      expect(actionsOf(steps), contains(RouteGuidanceAction.turnLeft));
      expect(actionsOf(steps), isNot(contains(RouteGuidanceAction.turnRight)));
    });

    test('완만한 굽음(35도 미만)은 회전으로 적지 않는다', () {
      // 20도씩 꺾이는 경로 — 실시간 안내도 이걸 회전이라 부르지 않는다.
      final steps = buildRouteStepList([
        leg(pointsM: [(0, 0), (0, 30), (10.9, 60)]),
      ]);
      expect(actionsOf(steps), [
        RouteGuidanceAction.straight,
        RouteGuidanceAction.arrived,
      ]);
      // 회전이 없으니 두 변이 하나의 직진으로 합쳐진다.
      expect(steps.first.distanceM, closeTo(30 + 31.9, 0.8));
    });

    test('짧은 변(1.5m 미만) 꼭짓점은 회전 후보가 아니다', () {
      // 노드 스냅 잔털 — 1 m짜리 지그재그가 회전으로 읽히면 목록이 소음이 된다.
      final steps = buildRouteStepList([
        leg(pointsM: [(0, 0), (0, 30), (1, 30.5), (1, 60)]),
      ]);
      expect(actionsOf(steps), [
        RouteGuidanceAction.straight,
        RouteGuidanceAction.arrived,
      ]);
    });

    test('다층 경로는 층 사이에 탑승 단계가 끼고 층 라벨이 붙는다', () {
      final steps = buildRouteStepList([
        leg(
          pointsM: [(0, 0), (0, 40)],
          floorLabel: '1F',
          transferModeToNext: 'escalator',
          nextFloorLabel: 'B1',
        ),
        leg(pointsM: [(0, 0), (15, 0)], floorLabel: 'B1'),
      ]);
      expect(actionsOf(steps), [
        RouteGuidanceAction.straight,
        RouteGuidanceAction.escalator,
        RouteGuidanceAction.straight,
        RouteGuidanceAction.arrived,
      ]);
      final transfer = steps[1];
      expect(transfer.fromFloor, '1F');
      expect(transfer.toFloor, 'B1');
      expect(routeStepText(transfer), '에스컬레이터 탑승 · 1F → B1');
    });

    test('엘리베이터 환승도 같은 형태로 편다', () {
      final steps = buildRouteStepList([
        leg(
          pointsM: [(0, 0), (0, 20)],
          floorLabel: '1F',
          transferModeToNext: 'elevator',
          nextFloorLabel: '3F',
        ),
        leg(pointsM: [(0, 0), (0, 10)], floorLabel: '3F'),
      ]);
      expect(actionsOf(steps), contains(RouteGuidanceAction.elevator));
      expect(routeStepText(steps[1]), '엘리베이터 탑승 · 1F → 3F');
    });

    test('로컬 좌표가 없으면 wgs84로 거리를 잰다', () {
      final steps = buildRouteStepList([
        (
          wgs84Points: [geo(0, 0), geo(0, 40), geo(30, 40)],
          localPoints: const <LocalPoint>[],
          floorLabel: '1F',
          transferModeToNext: null,
          nextFloorLabel: null,
        ),
      ]);
      expect(actionsOf(steps), [
        RouteGuidanceAction.straight,
        RouteGuidanceAction.turnRight,
        RouteGuidanceAction.straight,
        RouteGuidanceAction.arrived,
      ]);
      expect(steps[0].distanceM, closeTo(40, 0.8));
    });

    test('빈 입력이면 도착 행도 만들지 않는다', () {
      expect(buildRouteStepList(const []), isEmpty);
      expect(
        buildRouteStepList([leg(pointsM: [(0, 0)])]),
        isEmpty,
      );
    });

    test('표시 문구는 배너와 같은 반올림 단위를 쓴다', () {
      expect(
        routeStepText(
          const RouteStep(
            action: RouteGuidanceAction.straight,
            distanceM: 43,
          ),
        ),
        '45미터 직진',
      );
      expect(
        routeStepText(const RouteStep(action: RouteGuidanceAction.turnLeft)),
        '좌회전',
      );
    });
  });
}
