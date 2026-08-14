import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/building_entrances.dart';
import 'package:navigation_client/models/transit_route.dart';

/// 대중교통에서 **내린 자리 기준으로 문을 고른다**는 규칙을 고정한다.
///
/// 실기기에서 본 증상: 버스에서 내린 바로 옆에 문이 있는데 건물을 빙 돌아
/// 반대편 문으로 안내했다. 원인은 두 가지가 겹친 것이었다.
///   1. 건물 후보의 좌표가 **검색하던 시점의 현재 위치** 기준으로 정해진 문이라,
///      한참 이동한 뒤에는 더 이상 가깝지 않다.
///   2. 카카오 응답의 마지막 구간이 도보일 때 그 끝점을 "내린 자리"로 착각했다 —
///      그건 우리가 보낸 목적지 좌표지 하차 지점이 아니다.
void main() {
  // 남쪽 문과 북쪽 문. 가운데를 건물로 본다.
  const southDoor = BuildingEntrance(
    id: 'door-s',
    name: '출구',
    nodeId: 'FL-1:ND-S',
    point: LatLng(37.5663, 126.9780),
  );
  const northDoor = BuildingEntrance(
    id: 'door-n',
    name: '출구',
    nodeId: 'FL-1:ND-N',
    point: LatLng(37.5667, 126.9780),
  );
  const doors = [southDoor, northDoor];

  TransitLeg ride(List<LatLng> points) => TransitLeg(
    mode: TransitMode.bus,
    points: points,
    sectionTimeSeconds: 600,
    distanceMeters: 3000,
  );

  TransitLeg walk(List<LatLng> points) => TransitLeg(
    mode: TransitMode.walk,
    points: points,
    sectionTimeSeconds: 300,
    distanceMeters: 300,
  );

  /// 화면이 쓰는 규칙과 같은 순서로 하차 지점을 고른다 —
  /// `map_shell_screen.dart`의 `_requestTransitRoute`.
  LatLng dropPointOf(List<TransitLeg> legs, LatLng fallback) {
    final lastRide = legs.lastWhere(
      (leg) => !leg.mode.isWalk && leg.points.isNotEmpty,
      orElse: () => legs.last,
    );
    return lastRide.points.isEmpty ? fallback : lastRide.points.last;
  }

  test('남쪽에서 내리면 남쪽 문으로 안내한다', () {
    const droppedSouth = LatLng(37.5658, 126.9780);
    expect(nearestEntrance(doors, droppedSouth)?.id, 'door-s');
  });

  test('북쪽에서 내리면 북쪽 문으로 안내한다', () {
    const droppedNorth = LatLng(37.5672, 126.9780);
    expect(nearestEntrance(doors, droppedNorth)?.id, 'door-n');
  });

  test('마지막 도보 구간의 끝점을 하차 지점으로 쓰지 않는다', () {
    // 버스는 남쪽에서 내려 주는데, 카카오가 붙여 준 도보는 북쪽 목적지 좌표에서
    // 끝난다. 도보 끝점을 기준으로 삼으면 북쪽 문이 뽑혀, 사용자는 내린 자리
    // 반대편으로 건물을 돌게 된다.
    const droppedSouth = LatLng(37.5658, 126.9780);
    const kakaoWalkEnd = LatLng(37.5670, 126.9780);
    final legs = [
      ride(const [LatLng(37.5600, 126.9780), droppedSouth]),
      walk(const [droppedSouth, kakaoWalkEnd]),
    ];

    final drop = dropPointOf(legs, kakaoWalkEnd);

    expect(drop, droppedSouth);
    expect(
      nearestEntrance(doors, drop)?.id,
      'door-s',
      reason: '하차 지점 기준이면 남쪽 문이어야 한다',
    );
    expect(
      nearestEntrance(doors, kakaoWalkEnd)?.id,
      'door-n',
      reason: '이 값이 예전에 쓰던 기준이고, 반대편 문이 뽑히는 것이 증상이었다',
    );
  });

  test('타는 구간이 하나도 없으면 마지막 구간을 그대로 쓴다', () {
    // 처음부터 끝까지 걷는 안내다. 자를 것도, 다시 고를 근거도 없다.
    const end = LatLng(37.5661, 126.9780);
    final legs = [
      walk(const [LatLng(37.5650, 126.9780), end]),
    ];

    expect(dropPointOf(legs, end), end);
  });
}
