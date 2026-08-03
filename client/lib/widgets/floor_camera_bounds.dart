import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

/// 이 값보다 작게 움직이는 되돌림은 없던 일로 친다(약 1cm).
///
/// 되돌림은 `animateCamera`이고 그게 다시 `onCameraIdle`을 부른다. 경계에 딱
/// 붙은 카메라에서 부동소수 오차만큼의 차이를 매번 "밖으로 나갔다"고 읽으면
/// 그 왕복이 멈추지 않는다.
const _epsilonDeg = 1e-7;

/// 카메라 중심이 허용 영역 밖으로 나갔으면 안으로 당긴 좌표를, 이미 안에
/// 있으면 null을 돌려준다.
///
/// **왜 필요한가** — 묶어 두지 않으면 사용자가 지도를 계속 밀어 도면이 화면에서
/// 사라진 뒤에도 얼마든지 더 나갈 수 있다. 그 상태에서는 자기가 어디로 얼마나
/// 움직였는지 알 방법이 없어 "지도가 없어졌다"가 된다.
///
/// **허용 영역은 bbox가 아니라 bbox를 화면 크기만큼 깎은 것이다.**
/// [halfSpanLat]·[halfSpanLng]는 지금 화면이 덮는 위경도 범위의 **절반**이다.
/// 중심만 bbox 안에 가두면 중심이 모서리에 있는 상태가 합법이라, 그 순간 화면의
/// 절반 이상이 건물 밖 빈 공간이 된다. 범위가 넓었던 게 아니라 화면 크기를
/// 계산에 안 넣었던 것이다. 절반만큼 안쪽으로 깎으면 뷰포트 자체가 bbox 안에
/// 머물러 빈 공간이 아예 생기지 않는다.
///
/// **이건 여유(margin)를 두는 것의 반대다.** 예전에 "가장자리를 화면 중앙에 못
/// 놓을까 봐" bbox를 절반만큼 **넓혀** 봤다가 그 여유만큼 건물이 화면 밖으로
/// 나가서 되돌린 적이 있다. 지금은 넓히는 게 아니라 깎는다. 대신 건물 가장자리를
/// 화면 정중앙에 놓을 수는 없게 되는데, 가장자리는 화면 **끝**에 보이면 되는
/// 것이라 잃는 게 없다.
///
/// 화면이 건물보다 크면(줌아웃) 깎기가 뒤집힌다(하한 > 상한). 그 축은 bbox
/// 중점 하나로 붕괴시켜 건물을 화면 가운데 고정한다 — 뒤집힌 범위를 그대로
/// `clamp`에 넘기면 `ArgumentError`가 난다.
///
/// **MapLibre의 `cameraTargetBounds`를 쓰지 않는 이유**는 호출부
/// (`FloorPlanViewState._pullBackIntoFootprint`) 주석에 적었다 — 이 조합에서는
/// 지도가 아예 렌더되지 않았다.
///
/// footprint가 비어 있거나 한 축이 퇴화한 건물(실좌표 앵커 없음)에서는 **항상
/// null이다.** 기준이 없는데 되돌리면 엉뚱한 데로 끌고 간다 — 무한히 밀리는
/// 것보다 나쁜 상태다.
ll.LatLng? clampToFootprint(
  ll.LatLng center,
  List<ll.LatLng> footprint, {
  double halfSpanLat = 0,
  double halfSpanLng = 0,
}) {
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

  final latRange = _deflate(minLat, maxLat, halfSpanLat);
  final lngRange = _deflate(minLng, maxLng, halfSpanLng);

  final lat = center.latitude.clamp(latRange.lo, latRange.hi);
  final lng = center.longitude.clamp(lngRange.lo, lngRange.hi);
  // 이미 안에 있으면 카메라를 건드리지 않는다. 매번 animateCamera를 부르면
  // 가만히 둔 지도가 미세하게 떨린다.
  if ((lat - center.latitude).abs() < _epsilonDeg &&
      (lng - center.longitude).abs() < _epsilonDeg) {
    return null;
  }
  return ll.LatLng(lat, lng);
}

/// [lo]~[hi] 구간을 양쪽에서 [halfSpan]만큼 깎는다. 다 깎여 뒤집히면 중점
/// 하나로 붕괴시킨다.
({double lo, double hi}) _deflate(double lo, double hi, double halfSpan) {
  if (!halfSpan.isFinite || halfSpan <= 0) return (lo: lo, hi: hi);
  final deflatedLo = lo + halfSpan;
  final deflatedHi = hi - halfSpan;
  if (deflatedLo > deflatedHi) {
    final mid = (lo + hi) / 2;
    return (lo: mid, hi: mid);
  }
  return (lo: deflatedLo, hi: deflatedHi);
}
