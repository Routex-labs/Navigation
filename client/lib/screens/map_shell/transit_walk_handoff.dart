/// 대중교통에서 **내린 뒤 걷는 구간**으로 넘기는 규칙.
///
/// 이 두 함수는 같은 사고 하나에서 나왔다. 실기기에서, 하차 지점 **바로 옆에
/// 문이 있는데 건물을 빙 돌아 반대편 문으로 안내한** 화면을 봤다. 원인은 둘이
/// 겹친 것이었다.
///
/// 1. 마지막 구간을 `legs.last`로 잡았다. 카카오가 마지막에 도보 구간을 함께
///    주는 경우가 있는데, **그 구간의 끝점은 내린 자리가 아니라 우리가 보낸
///    목적지 좌표**다. 그걸 기준으로 문을 고르면 "목적지에서 가까운 문"이 되어
///    사용자가 내리는 자리와는 무관해진다.
/// 2. 그 도보 구간을 그대로 두었다. 우리가 문을 다시 골라도 지도에 그려진
///    도보는 옛 끝점으로 가서, 두 선이 서로 다른 곳을 가리킨다.
///
/// 둘 다 좌표 계산이라 지도 없이 시험된다. 그래서 여기로 뗐다.
library;

import 'package:latlong2/latlong.dart';

import '../../models/transit_route.dart';

/// **내린 자리** — 마지막으로 "타는" 구간이 끝나는 곳.
///
/// 도보 구간은 건너뛴다. 탈것 구간이 하나도 없으면(처음부터 끝까지 걷는 안내)
/// 마지막 구간의 끝을 쓰고, 그마저 점이 없으면 [fallback]으로 떨어진다.
LatLng transitDropPoint(
  TransitItinerary itinerary, {
  required LatLng fallback,
}) {
  if (itinerary.legs.isEmpty) return fallback;
  final lastRide = itinerary.legs.lastWhere(
    (leg) => !leg.mode.isWalk && leg.points.isNotEmpty,
    orElse: () => itinerary.legs.last,
  );
  return lastRide.points.isEmpty ? fallback : lastRide.points.last;
}

/// 카카오가 붙여 준 **마지막 도보 구간을 잘라 낸다.**
///
/// 잘라 내면 마지막이 "타는" 구간이 되므로 `fillTransitWalkLegs`가 우리 도보를
/// 대신 붙인다(TMAP 보행자 경로). 모양부터 다르다 — 카카오 도보는 정류장
/// 사이를 잇는 개략선이라 실제 보도를 따르지 않고 구불구불하게 떨어진다.
///
/// **구간이 하나뿐이면 자르지 않는다.** 그건 처음부터 끝까지 걷는 안내라 잘라
/// 내면 아무것도 남지 않는다.
TransitItinerary trimTrailingWalkLeg(TransitItinerary itinerary) {
  if (itinerary.legs.length <= 1) return itinerary;
  if (!itinerary.legs.last.mode.isWalk) return itinerary;
  return TransitItinerary(
    totalTimeSeconds: itinerary.totalTimeSeconds,
    totalWalkTimeSeconds: itinerary.totalWalkTimeSeconds,
    totalDistanceMeters: itinerary.totalDistanceMeters,
    transferCount: itinerary.transferCount,
    legs: itinerary.legs.sublist(0, itinerary.legs.length - 1),
    fare: itinerary.fare,
  );
}
