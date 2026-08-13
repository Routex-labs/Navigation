import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/completed_route_history.dart';

void main() {
  const a = LatLng(37.0, 127.0);
  const b = LatLng(37.0, 127.0001);
  const c = LatLng(37.0, 127.0002);

  test('같은 층에서 이어지는 완료 구간은 하나의 회색선으로 합친다', () {
    final history = CompletedRouteHistory();

    history.append(scopeId: '1F', points: const [a, b]);
    history.append(scopeId: '1F', points: const [b, c]);

    expect(history.segmentsFor('1F'), const [
      <LatLng>[a, b, c],
    ]);
  });

  test('서로 다른 층과 멀리 떨어진 재탐색 구간은 직선으로 잇지 않는다', () {
    final history = CompletedRouteHistory();
    const far = LatLng(37.001, 127.001);
    const farEnd = LatLng(37.001, 127.0011);

    history.append(scopeId: '1F', points: const [a, b]);
    history.append(scopeId: '2F', points: const [a, c]);
    history.append(scopeId: '1F', points: const [far, farEnd]);

    expect(history.segmentsFor('1F'), hasLength(2));
    expect(history.segmentsFor('2F'), const [
      <LatLng>[a, c],
    ]);
  });

  test('반환된 선을 바꿔도 저장된 이력은 바뀌지 않는다', () {
    final history = CompletedRouteHistory();
    history.append(
      scopeId: CompletedRouteHistory.outdoorScope,
      points: const [a, b],
    );

    final copy = history.segmentsFor(CompletedRouteHistory.outdoorScope);
    expect(() => copy.first.add(c), throwsUnsupportedError);

    expect(history.segmentsFor(CompletedRouteHistory.outdoorScope), const [
      <LatLng>[a, b],
    ]);
  });
}
