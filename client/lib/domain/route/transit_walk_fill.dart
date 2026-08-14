import 'package:latlong2/latlong.dart';

import '../../models/directions_route.dart';
import '../../models/transit_route.dart';

/// 카카오 대중교통 경로에 빠져 있는 **앞뒤 도보 구간**을 채운다.
///
/// 카카오는 "무엇을 어디서 타고 내리는지"만 답한다. 그래서 응답의 첫 구간은
/// 이미 버스·지하철에 타 있는 상태에서 시작하고, 마지막 구간은 내리는 순간
/// 끝난다. 출발지에서 첫 정류장까지, 마지막 정류장에서 목적지까지 걸어가는
/// 구간은 아예 없다(역 안에서 갈아타는 환승 도보는 온다).
///
/// 그대로 지도에 그리면 사용자가 서 있는 자리에서 한참 떨어진 허공에서 선이
/// 시작한다. 목적지 쪽도 마찬가지여서, 내린 다음 어디로 가야 하는지가 화면에
/// 없다. 여기서 두 구간을 [TransitLeg]로 만들어 앞뒤에 붙이면 지도·목록·카메라가
/// 모두 손대지 않은 채로 완전한 경로를 본다.
///
/// **총 시간·거리는 건드리지 않는다.** 카카오 `totalTime`에는 이 도보가 이미
/// 포함돼 있다(실측: steps 합보다 786초 큼 ≒ 807m 도보). 여기서 다시 더하면
/// 목록에 뜨는 소요 시간이 실제보다 길어진다.
///
/// [head]·[tail]은 [DirectionsRepository.getWalkingRoute]의 결과다. 둘 중 하나가
/// null이면(네트워크 실패 등) 그 구간은 직선으로 잇는다 — 실제 보도 모양은
/// 아니지만, 비워 두면 지도 위 경로가 그 구간만 툭 끊겨서 사용자가 어느 쪽으로
/// 가야 할지 알 수 없게 된다.
TransitItinerary fillTransitWalkLegs(
  TransitItinerary itinerary, {
  required LatLng origin,
  required LatLng destination,
  DirectionsRoute? head,
  DirectionsRoute? tail,
}) {
  if (itinerary.legs.isEmpty) return itinerary;

  final first = itinerary.legs.first;
  final last = itinerary.legs.last;

  final legs = <TransitLeg>[
    // 이미 도보로 시작하면 카카오가 준 것을 그대로 둔다. 앞에 하나를 더 붙이면
    // 도보 구간이 둘 연달아 나오고, 목록에 "도보 → 도보 → 버스"가 찍힌다.
    if (!first.mode.isWalk)
      _walkLeg(
        route: head,
        from: origin,
        to: first.points.isEmpty ? origin : first.points.first,
        endName: first.startName,
      ),
    ...itinerary.legs,
    if (!last.mode.isWalk)
      _walkLeg(
        route: tail,
        from: last.points.isEmpty ? destination : last.points.last,
        to: destination,
        startName: last.endName,
      ),
  ];

  return TransitItinerary(
    totalTimeSeconds: itinerary.totalTimeSeconds,
    totalWalkTimeSeconds: itinerary.totalWalkTimeSeconds,
    totalDistanceMeters: itinerary.totalDistanceMeters,
    transferCount: itinerary.transferCount,
    legs: legs,
    fare: itinerary.fare,
  );
}

/// 붙일 도보 구간 하나. [route]가 없으면 [from]-[to] 직선으로 떨어진다.
///
/// 시간·거리는 [route]가 있을 때만 채운다. 직선일 때 거리를 지어내면 목록의
/// 구간 시간이 실제와 달라지는데, 그 숫자는 총계와 달리 검증할 근거가 없다.
TransitLeg _walkLeg({
  required DirectionsRoute? route,
  required LatLng from,
  required LatLng to,
  String? startName,
  String? endName,
}) {
  final points = (route != null && route.points.length >= 2)
      ? route.points
      : <LatLng>[from, to];
  return TransitLeg(
    mode: TransitMode.walk,
    sectionTimeSeconds: route?.durationSeconds ?? 0,
    distanceMeters: route?.distanceMeters ?? 0,
    points: points,
    startName: startName,
    endName: endName,
  );
}
