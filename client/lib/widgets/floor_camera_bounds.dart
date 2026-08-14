import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

/// 이 값보다 작게 움직이는 되돌림은 없던 일로 친다(약 1cm).
///
/// 되돌림은 `animateCamera`이고 그게 다시 `onCameraIdle`을 부른다. 경계에 딱
/// 붙은 카메라에서 부동소수 오차만큼의 차이를 매번 "밖으로 나갔다"고 읽으면
/// 그 왕복이 멈추지 않는다.
const _epsilonDeg = 1e-7;

/// 화면에서 이 거리보다 작은 경계 보정은 실행하지 않는다.
///
/// 위경도 차이만으로는 같은 오차가 줌 단계에 따라 0.1px일 수도, 수십 px일 수도
/// 있다. 사용자가 느끼는 것은 좌표 오차가 아니라 화면의 2차 이동이므로 픽셀을
/// 기준으로 판단한다. 10px 미만은 도면을 읽는 데 영향이 없지만, 손을 뗀 직후
/// 카메라가 한 번 더 움직였다는 느낌은 충분히 만든다.
const kCameraCorrectionDeadbandPx = 10.0;

/// [corrected]로 옮길 때 화면에서 보이는 거리가 데드밴드를 넘는지 판정한다.
///
/// [halfSpanLat]·[halfSpanLng]는 현재 화면이 덮는 위경도 범위의 절반이다.
/// 따라서 좌표 차이를 전체 범위(`halfSpan * 2`)로 나눈 뒤 뷰포트 크기를
/// 곱하면 회전된 지도에서도 충분히 보수적인 화면 거리 근사가 된다.
///
/// 화면 범위를 구하지 못했으면 기존처럼 보정한다. 계산 실패를 이유로 실제로
/// 도면이 사라질 만큼 밀린 카메라까지 방치하는 쪽이 더 큰 실패이기 때문이다.
bool shouldApplyCameraCorrection({
  required ll.LatLng current,
  required ll.LatLng corrected,
  required double halfSpanLat,
  required double halfSpanLng,
  required double viewportWidthPx,
  required double viewportHeightPx,
  double deadbandPx = kCameraCorrectionDeadbandPx,
}) {
  if (halfSpanLat <= 0 ||
      halfSpanLng <= 0 ||
      viewportWidthPx <= 0 ||
      viewportHeightPx <= 0 ||
      !halfSpanLat.isFinite ||
      !halfSpanLng.isFinite ||
      !viewportWidthPx.isFinite ||
      !viewportHeightPx.isFinite) {
    return true;
  }

  final dx =
      (corrected.longitude - current.longitude).abs() /
      (halfSpanLng * 2) *
      viewportWidthPx;
  final dy =
      (corrected.latitude - current.latitude).abs() /
      (halfSpanLat * 2) *
      viewportHeightPx;
  return sqrt(dx * dx + dy * dy) >= deadbandPx;
}

/// 카메라 중심이 허용 영역 밖으로 나갔으면 안으로 당긴 좌표를, 이미 안에
/// 있으면 null을 돌려준다.
///
/// **왜 필요한가** — 묶어 두지 않으면 사용자가 지도를 계속 밀어 도면이 화면에서
/// 사라진 뒤에도 얼마든지 더 나갈 수 있다. 그 상태에서는 자기가 어디로 얼마나
/// 움직였는지 알 방법이 없어 "지도가 없어졌다"가 된다.
///
/// **허용 영역은 bbox가 아니라 bbox를 화면 크기의 일부만큼 깎은 것이다.**
/// [halfSpanLat]·[halfSpanLng]는 지금 화면이 덮는 위경도 범위의 **절반**이다.
/// 중심만 bbox 안에 가두면 중심이 모서리에 있는 상태가 합법이라, 그 순간 화면의
/// 절반 이상이 건물 밖 빈 공간이 된다. 범위가 넓었던 게 아니라 화면 크기를
/// 계산에 안 넣었던 것이다. 안쪽으로 깎으면 뷰포트가 bbox 근처에 머문다.
///
/// 얼마나 깎을지는 [kFootprintDeflateRatio]가 정한다 — 화면 절반을 통째로 깎으면
/// 빈 공간이 한 픽셀도 안 생기지만 미는 느낌이 지나치게 빡빡해진다.
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
/// [userLocation]이 있으면 허용 영역을 **내 위치에서 화면 절반 이내**로 한 번 더
/// 좁힌다. 반경을 화면 절반으로 잡은 것은 그게 곧 "내 위치가 항상 화면 안에
/// 남는다"와 같은 말이기 때문이다 — 고정 미터 값으로 잡으면 줌아웃에서는 지도가
/// 잠기고 줌인에서는 한 화면보다 훨씬 넓게 밀린다. 화면 크기를 모르면
/// ([halfSpanLat]·[halfSpanLng]가 0) 이 제한은 걸리지 않는다. 반경이 정의되지
/// 않기 때문이다.
///
/// 도면 제한과 위치 제한의 교집합이 비면 **위치 쪽을 남긴다.** PDR이 도면 밖으로
/// 흘렀을 때 벌어지는데, 그때 빈 공간을 피하자고 사용자를 화면 밖에 두면 자기가
/// 어디 있는지 못 본다. 빈 공간보다 나쁘다.
///
/// footprint가 비어 있거나 한 축이 퇴화한 건물(실좌표 앵커 없음)에서는 **항상
/// null이다.** 기준이 없는데 되돌리면 엉뚱한 데로 끌고 간다 — 무한히 밀리는
/// 것보다 나쁜 상태다.
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
/// [halfSpan]은 회전된 뷰포트의 축정렬 bbox라 실제보다 넉넉하다
/// (`FloorPlanViewState._visibleHalfSpan`). 그만큼 데드밴드도 조금 넓어지는데,
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
