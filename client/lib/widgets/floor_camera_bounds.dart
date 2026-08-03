import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

/// 카메라 중심이 층 도면 bbox 밖으로 나갔으면 가장자리로 당긴 좌표를,
/// 이미 안에 있으면 null을 돌려준다.
///
/// **왜 필요한가** — 묶어 두지 않으면 사용자가 지도를 계속 밀어 도면이 화면에서
/// 사라진 뒤에도 얼마든지 더 나갈 수 있다. 그 상태에서는 자기가 어디로 얼마나
/// 움직였는지 알 방법이 없어 "지도가 없어졌다"가 된다.
///
/// **여유를 두지 않는다.** bbox는 이미 모든 footprint 점을 포함하므로 건물
/// 가장자리도 그대로 화면 중앙에 놓을 수 있다. 처음에는 "가장자리를 중앙에 못
/// 놓을까 봐" bbox 절반만큼 넓혀 봤는데, 그 여유만큼 건물이 화면 밖으로 나가서
/// 되돌렸다.
///
/// **MapLibre의 `cameraTargetBounds`를 쓰지 않는 이유**는 호출부
/// (`FloorPlanViewState._pullBackIntoFootprint`) 주석에 적었다 — 이 조합에서는
/// 지도가 아예 렌더되지 않았다.
///
/// footprint가 비어 있거나 한 축이 퇴화한 건물(실좌표 앵커 없음)에서는 **항상
/// null이다.** 기준이 없는데 되돌리면 엉뚱한 데로 끌고 간다 — 무한히 밀리는
/// 것보다 나쁜 상태다.
ll.LatLng? clampToFootprint(ll.LatLng center, List<ll.LatLng> footprint) {
  if (footprint.length < 2) return null;

  var minLat = footprint.first.latitude;
  var maxLat = footprint.first.latitude;
  var minLng = footprint.first.longitude;
  var maxLng = footprint.first.longitude;
  for (final point in footprint) {
    minLat = min(minLat, point.latitude);
    maxLat = max(maxLat, point.latitude);
    minLng = min(minLng, point.longitude);
    maxLng = max(maxLng, point.longitude);
  }
  if (maxLat <= minLat || maxLng <= minLng) return null;

  final lat = center.latitude.clamp(minLat, maxLat);
  final lng = center.longitude.clamp(minLng, maxLng);
  // 이미 안에 있으면 카메라를 건드리지 않는다. 매번 animateCamera를 부르면
  // 가만히 둔 지도가 미세하게 떨린다.
  if (lat == center.latitude && lng == center.longitude) return null;
  return ll.LatLng(lat, lng);
}
