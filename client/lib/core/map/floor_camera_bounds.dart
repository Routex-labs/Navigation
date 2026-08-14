import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

/// 이 값보다 작게 움직이는 되돌림은 없던 일로 친다(약 1cm). 되돌림이 다시
/// `onCameraIdle`을 불러 왕복이 멈추지 않는 것을 막는다.
const _epsilonDeg = 1e-7;

/// 카메라 중심이 허용 영역 밖으로 나갔으면 안으로 당긴 좌표를, 이미 안에
/// 있으면 null을 돌려준다.
///
/// **허용 영역은 bbox가 아니라 bbox를 화면 크기의 일부만큼 깎은 것이다**
/// ([kFootprintDeflateRatio]). [halfSpanLat]·[halfSpanLng]는 지금 화면이 덮는
/// 위경도 범위의 **절반**이다.
///
/// [userLocation]이 있으면 허용 영역을 내 위치에서 화면 절반 이내로 한 번 더
/// 좁힌다. 화면 크기를 모르면(두 span이 0) 이 제한은 걸리지 않는다. 도면 제한과
/// 위치 제한의 교집합이 비면 **위치 쪽을 남긴다.**
///
/// footprint가 비었거나 한 축이 퇴화한 건물에서는 **항상 null이다** — 기준이
/// 없는데 되돌리면 엉뚱한 데로 끌고 간다.
///
/// 각 판단의 근거는 `docs/client/camera-choreography-plan.md`의 4.12.
ll.LatLng? clampToFootprint(
  ll.LatLng center,
  List<ll.LatLng> footprint, {
  double halfSpanLat = 0,
  double halfSpanLng = 0,
  ll.LatLng? userLocation,
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

  var latRange = _deflate(minLat, maxLat, halfSpanLat * kFootprintDeflateRatio);
  var lngRange = _deflate(minLng, maxLng, halfSpanLng * kFootprintDeflateRatio);
  if (userLocation != null) {
    latRange = _intersectAround(latRange, userLocation.latitude, halfSpanLat);
    lngRange = _intersectAround(lngRange, userLocation.longitude, halfSpanLng);
  }

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

/// 허용 영역을 깎는 정도. 화면 절반([halfSpanLat]·[halfSpanLng])에 대한 비율이다.
///
/// **1.0이면 도면 밖 빈 공간이 한 픽셀도 안 생긴다** — 뷰포트가 통째로 bbox 안에
/// 갇힌다. 처음엔 그게 맞다고 봤는데, 실기기에서 "화면 중앙으로 당겨오는 게 너무
/// 빡세다"는 피드백이 나왔다. 이유가 둘이다.
///
///  - **bbox는 건물보다 넓다.** 도면은 L자·계단형인데 제한은 사각형이라, 실제
///    도면 가장자리는 이미 화면 안쪽 깊숙이 들어와 있다. 거기서 한 번 더 화면
///    절반을 깎으면 가장자리 매장을 보려고 밀 때마다 손을 떼는 순간 끌려온다.
///  - **빈 공간이 조금 보이는 건 손해가 아니다.** 원래 막으려던 것은 "도면이
///    화면에서 사라져 자기가 어디로 얼마나 움직였는지 모르는" 상태이고, 화면의
///    3/4에 도면이 남아 있으면 그 일은 일어나지 않는다.
///
/// 0.75는 **화면의 1/8까지 도면 밖 여백을 허용한다**는 뜻이다(깎지 않은 0.25가
/// 곧 여백 한도라 `halfSpan × 0.25` = 화면의 12.5%).
///
/// ⚠️ **0.5로 잡았다가 되돌렸다.** 화면 1/4까지 허용하니 실기기에서 도면이
/// **통째로 사라지는 자리**까지 밀렸다. bbox가 도면보다 훨씬 넓은 게 이유다 —
/// 1F 도면은 세로로 긴 비정형인데 제한은 사각형이라, bbox 모서리 근처는 애초에
/// 건물이 없는 빈 공간이다. 거기에 화면 1/4을 더 얹으면 남는 게 없다.
///
/// 즉 이 값은 "얼마나 넉넉한가"만이 아니라 **bbox와 실제 도면의 차이를 흡수할
/// 여유**까지 함께 쓴다. 더 풀고 싶으면 비율을 올리는 대신 제한을 bbox가 아니라
/// 도면 폴리곤 자체로 바꾸는 편이 맞다.
const kFootprintDeflateRatio = 0.75;

/// 추적 중 카메라를 내 위치로 다시 옮기기 전에 허용하는 **어긋남**. 화면 절반
/// ([halfSpanLat]·[halfSpanLng])에 대한 비율이다.
///
/// **왜 데드밴드가 필요한가** — 위치가 갱신될 때마다 카메라를 옮기면 사용자가
/// 화면 정중앙에 못으로 박힌 것처럼 된다. PDR은 한 걸음마다 값을 내놓으므로
/// 걷는 내내 지도가 끌려다니고, 정작 사용자는 그 사이에 도면을 읽을 수 없다.
/// 마커가 이 범위 안에 있는 동안에는 카메라를 가만히 둔다.
///
/// 0.35는 화면 절반의 35%, 즉 **화면 폭의 약 17.5%**까지 벗어나도 두겠다는
/// 뜻이다. 마커는 여전히 화면 가운데 언저리에 있고, 걸음마다 오던 미세한
/// 끌림은 사라진다. 키우면 더 조용해지지만 마커가 구석으로 밀리고, 0으로 두면
/// 예전처럼 매 걸음 따라간다.
const kFollowDeadbandRatio = 0.35;

/// 추적 중인 카메라를 [user] 자리로 다시 옮겨야 하는지.
///
/// 화면 크기를 모르면([halfSpanLat]·[halfSpanLng]가 0) **항상 옮긴다.** 데드밴드는
/// 화면 크기에 대한 비율이라 기준이 없으면 정의되지 않는데, 그때 안 옮기는 쪽을
/// 고르면 마커가 화면 밖으로 나가도 카메라가 영영 따라가지 않는다.
///
/// [halfSpan]은 회전된 뷰포트의 축정렬 bbox라 실제보다 넉넉하다.
/// 그만큼 데드밴드도 조금 넓어지는데,
/// 방향이 어느 쪽이든 "덜 따라간다" 쪽이라 안전한 오차다.
bool shouldRecenterFollow({
  required ll.LatLng camera,
  required ll.LatLng user,
  double halfSpanLat = 0,
  double halfSpanLng = 0,
}) {
  if (halfSpanLat <= 0 ||
      halfSpanLng <= 0 ||
      !halfSpanLat.isFinite ||
      !halfSpanLng.isFinite) {
    return true;
  }
  return (user.latitude - camera.latitude).abs() >
          halfSpanLat * kFollowDeadbandRatio ||
      (user.longitude - camera.longitude).abs() >
          halfSpanLng * kFollowDeadbandRatio;
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

/// [range]를 [user] ± [halfSpan]과 교차시킨다. 교집합이 비면 위치 쪽을 남긴다.
({double lo, double hi}) _intersectAround(
  ({double lo, double hi}) range,
  double user,
  double halfSpan,
) {
  if (!user.isFinite || !halfSpan.isFinite || halfSpan <= 0) return range;
  final nearLo = user - halfSpan;
  final nearHi = user + halfSpan;
  final lo = max(range.lo, nearLo);
  final hi = min(range.hi, nearHi);
  if (lo > hi) return (lo: nearLo, hi: nearHi);
  return (lo: lo, hi: hi);
}

/// 매장으로 카메라를 옮길 때 쓸 배율.
///
/// 실내 도면과 야외의 실내 진입 오버레이가 **같은 규칙을 써야** 같은 매장을
/// 같은 조작으로 골랐을 때 화면이 달라지지 않는다. 예전에는 두 화면에 같은
/// 삼항식이 각각 박혀 있었다.
///
/// - [keepZoom]이면 배율을 **그대로 둔다.** 카테고리를 고르는 것은 "저 업종이
///   어디 있나"를 훑는 행동이라, 화면이 확 당겨지면 방금 보던 층 전체의 배치를
///   잃는다. 이동만 하고 배율은 사용자가 맞춰 둔 값을 존중한다.
/// - 아니면 [storeFocusZoom]까지 당기되, **이미 더 가까이 들어가 있으면 그대로
///   둔다.** 목록에서 골랐다고 사용자가 확대해 둔 것을 되돌리면 맥락을 잃는다.
double focusZoomFor({
  required double currentZoom,
  required bool keepZoom,
  double storeFocusZoom = 19.0,
}) {
  if (keepZoom) return currentZoom;
  return currentZoom > storeFocusZoom ? currentZoom : storeFocusZoom;
}
