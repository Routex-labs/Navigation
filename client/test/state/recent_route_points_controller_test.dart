import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/directions_candidate.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 최근 출발지·목적지 저장소.
///
/// 최근 검색어와 달리 **문자열이 아니라 지점**을 담는다. 그래서 지켜야 할 것이
/// 하나 더 있다 — 노드와 층이 살아 돌아와야 다시 눌렀을 때 실내 경로가 선다.
void main() {
  DirectionsCandidate indoor({
    String title = '스타벅스 리저브',
    String nodeId = 'n-1',
    String floor = 'B2',
  }) => DirectionsCandidate(
    title: title,
    subtitle: floor,
    point: const LatLng(37.5, 127.0),
    nodeId: nodeId,
    floor: floor,
    buildingId: 'thehyundai-seoul',
  );

  DirectionsCandidate outdoor({String title = '여의도역'}) => DirectionsCandidate(
    title: title,
    subtitle: '서울 영등포구',
    point: const LatLng(37.52, 126.92),
  );

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  Future<RecentRoutePointsController> controller() async {
    final c = RecentRoutePointsController();
    await c.ready;
    return c;
  }

  test('첫 실행은 빈 목록이고 그것이 정상이다', () async {
    final c = await controller();
    expect(c.points, isEmpty);
    expect(c.isLoaded, isTrue);
  });

  test('최신순으로 쌓인다', () async {
    final c = await controller();
    await c.add(indoor(title: 'A', nodeId: 'n-a'));
    await c.add(indoor(title: 'B', nodeId: 'n-b'));

    expect(c.points.map((p) => p.title), ['B', 'A']);
  });

  test('같은 지점을 다시 쓰면 쌓지 않고 맨 앞으로 옮긴다', () async {
    final c = await controller();
    await c.add(indoor(title: 'A', nodeId: 'n-a'));
    await c.add(indoor(title: 'B', nodeId: 'n-b'));
    await c.add(indoor(title: 'A', nodeId: 'n-a'));

    expect(c.points.map((p) => p.title), ['A', 'B']);
  });

  test('상한을 넘으면 오래된 것부터 버린다', () async {
    final c = await controller();
    for (var i = 0; i < RecentRoutePointsController.maxEntries + 3; i++) {
      await c.add(indoor(title: '매장$i', nodeId: 'n-$i'));
    }

    expect(c.points, hasLength(RecentRoutePointsController.maxEntries));
    expect(c.points.first.title, '매장12');
    expect(c.points.map((p) => p.title), isNot(contains('매장0')));
  });

  test('이름이 빈 후보는 저장하지 않는다', () async {
    // 목록에 눌러도 뜻을 알 수 없는 줄이 생긴다.
    final c = await controller();
    await c.add(indoor(title: '   '));

    expect(c.points, isEmpty);
  });

  test('한 건 삭제와 전체 삭제', () async {
    final c = await controller();
    await c.add(indoor(title: 'A', nodeId: 'n-a'));
    await c.add(outdoor(title: 'B'));

    await c.remove(indoor(title: 'A', nodeId: 'n-a'));
    expect(c.points.map((p) => p.title), ['B']);

    await c.clear();
    expect(c.points, isEmpty);
  });

  test('다시 읽으면 노드와 층이 그대로 살아 있다', () async {
    // **이 테스트가 이 기능의 존재 이유다.** 좌표만 저장하면 최근 항목을 눌렀을
    // 때 실내 경로가 서지 않고 야외 걷기로 흘러간다.
    final first = await controller();
    await first.add(indoor());

    final second = await controller();
    expect(second.points, hasLength(1));
    final restored = second.points.single;
    expect(restored.nodeId, 'n-1');
    expect(restored.floor, 'B2');
    expect(restored.buildingId, 'thehyundai-seoul');
    expect(restored.isIndoorPoint, isTrue);
    expect(restored.point.latitude, closeTo(37.5, 1e-9));
  });

  test('야외 지점도 좌표까지 그대로 돌아온다', () async {
    final first = await controller();
    await first.add(outdoor());

    final second = await controller();
    final restored = second.points.single;
    expect(restored.isIndoorPoint, isFalse);
    expect(restored.point.longitude, closeTo(126.92, 1e-9));
  });

  test('저장된 값이 깨져 있으면 그 줄만 건너뛴다', () async {
    // 목록 전체를 버리면 한 줄 때문에 기록이 통째로 사라진다.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'recent_route_points_v1':
          '[{"title":"성한 줄","lat":37.5,"lng":127.0},'
          '{"title":"좌표 없음"},'
          '{"lat":1,"lng":2}]',
    });

    final c = await controller();
    expect(c.points.map((p) => p.title), ['성한 줄']);
  });

  test('저장 포맷이 통째로 깨져 있으면 빈 목록으로 시작한다', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'recent_route_points_v1': '이건 JSON이 아니다',
    });

    final c = await controller();
    expect(c.points, isEmpty);
    expect(c.isLoaded, isTrue);
  });

  test('로드가 끝나기 전에 추가해도 덮어쓰지 않는다', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'recent_route_points_v1': '[{"title":"예전 것","lat":37.5,"lng":127.0}]',
    });

    final c = RecentRoutePointsController();
    // ready를 기다리지 않고 곧바로 넣는다.
    await c.add(outdoor(title: '방금 것'));

    expect(c.points.map((p) => p.title), ['방금 것', '예전 것']);
  });
}
