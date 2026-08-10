import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/map_route_style.dart';

/// 경로선을 **수단별로 다르게 그린다**는 규칙을 고정한다.
///
/// 이 규칙들은 화면에서만 보이고 위젯 테스트로는 잡히지 않는다 — MapLibre
/// 플랫폼 뷰가 위젯 테스트에 없어서 레이어가 아예 안 뜬다. 그래서 스타일 값
/// 자체를 여기서 지킨다.
void main() {
  test('걷는 구간은 타는 구간과 색부터 다르다', () {
    // 정류장까지 걸어가는 길이 버스 노선과 같은 색이면, 어디서 내려 걸어야
    // 하는지를 선 굵기나 점선 여부로 추론해야 한다.
    expect(kRouteWalkColor, isNot(kRouteLineColor));
  });

  test('걷는 구간은 점선이다', () {
    // 횡단보도·건물 앞 광장처럼 "이 근처로 가라"에 가까운 구간이라, 도로를
    // 그대로 따라가는 자동차 실선과 성격이 다르다.
    expect(kRouteWalkDashArray, isNotEmpty);
    expect(kRouteWalkDashArray.every((v) => v > 0), isTrue);
  });

  test('실내 구간은 야외 본선과 같은 색이다', () {
    // 한 번의 안내가 문 앞에서 끊기지 않고 이어진다는 것을 색으로 말한다.
    // 밖에서는 파란 선을 따라오다 문을 지나면 다른 색이 되는 화면은, 사용자에게
    // 두 개의 안내로 읽힌다.
    expect(kRouteIndoorLineColor, kRouteLineColor);
  });

  test('수단 배지는 옆 글자보다 크게 찍힌다', () {
    // 화면에 찍히는 크기는 비트맵 한 변 × iconSize다. 처음엔 56px로 구웠는데
    // iconSize가 1보다 작아 실제로는 20px대였고, 매장 이름 글자보다 작아서
    // "여기서 내려 걷는다"는 경계가 눈에 안 들어왔다.
    //
    // iconSize는 zoom 보간 표현식이라(`['interpolate', ..., 13, s0, 18, s1]`)
    // **가장 작은 쪽 stop**으로 잰다. 거기서 읽히면 확대할수록 더 잘 읽힌다.
    final iconSize = routeModeBadgeProps(kRouteBusBadgeImageName).iconSize;
    final stops = (iconSize as List)
        .whereType<num>()
        .where((v) => v < 1)
        .toList();
    expect(stops, isNotEmpty, reason: 'iconSize 표현식의 형태가 바뀌었다');
    final smallest = stops.reduce((a, b) => a < b ? a : b);
    expect(
      kRouteModeBadgeCanvasSize * smallest,
      greaterThan(30),
      reason: '지도 위 글자(14px 안팎)보다 확실히 커야 경계가 읽힌다',
    );
  });

  test('배지 이름에 버전이 붙어 있다', () {
    // 웹 addImage는 같은 이름이 이미 있으면 새 비트맵을 버린다. 모양을 바꿀 때
    // 이름을 함께 올리지 않으면 살아 있는 지도에 반영되지 않는다.
    for (final name in [
      kRouteWalkBadgeImageName,
      kRouteBusBadgeImageName,
      kRouteSubwayBadgeImageName,
    ]) {
      expect(name, matches(RegExp(r'-v\d+$')));
    }
  });
}
