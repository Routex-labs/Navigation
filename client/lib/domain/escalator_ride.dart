/// 에스컬레이터를 타고 있는 동안 화면이 쓰는 계산들.
///
/// 탑승부터 하차까지 우리는 **사용자의 수평 위치를 측정하지 못한다.** 걸음은
/// 멈춰 있고(발판 진동이 걸음으로 세어지므로 일부러 멈춘다), 층 도면은 중간에
/// 목적 층으로 갈아 끼워져 이전 층 좌표계가 무의미해진다.
///
/// 측정할 수 없다고 해서 아는 것이 없는 것은 아니다. **양 끝과 높이를 안다** —
/// 어느 노드에서 탔고(판정기), 어느 노드로 내리는지(경로·이름 규칙), 그리고
/// 지금까지 몇 미터를 오르내렸는지(기압 Δ). 그래서 마커는 두 점 사이를
/// **기압 진행률**로 흐른다([escalatorRideProgressTarget]). 예전에는 고정
/// 2.4초로 흘렸는데, 실제 탑승(20~35초)이 끝나기 한참 전에 연출이 끝나 "점이
/// 끝까지 안 내려온다"로 보였고, 걷는 사람에게는 반대로 너무 느렸다. 기압으로
/// 흘리면 서 있든 걷든 **몸이 시간을 정한다** — 점이 끝에 닿는 순간이 곧 하차
/// 확정 순간이다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 하차 지점 카메라 정렬 시간이자, 양 끝을 몰라 활강을 못 걸었을 때 스크림
/// 카드가 자체 재생하는 길이.
///
/// 마커 활강 자체는 이 시간을 쓰지 않는다 — 진행률이 기압에서 나온다.
const escalatorGlideDuration = Duration(milliseconds: 2400);

/// 표시 진행률을 목표 쪽으로 끌어당기는 틱 주기.
///
/// 기압 샘플은 기기에 따라 0.18~1.07초 간격이라 그대로 그리면 점이 툭툭
/// 끊긴다. 이 주기로 [escalatorRideProgressEase]만큼씩 따라가고, 덮개 카드의
/// 점도 같은 주기를 보간해 그린다.
const escalatorGlideSampleInterval = Duration(milliseconds: 60);

/// 같은 에스컬레이터의 실측 층고를 아직 모를 때 쓰는 기본값(m).
///
/// 더현대 실측 한 층 4.4~6.2m의 가운데이며, 2026-08-13 B1↔B2 실측
/// (0.7 hPa ≈ 5.8m)과 같다. 한 번 확정하고 나면 그 에스컬레이터 그룹의 실측
/// Δ를 대신 쓴다.
const escalatorDefaultFloorHeightM = 5.8;

/// 하차 확정 전 진행률 상한.
///
/// 층고 추정이 실제보다 작으면 진행률이 하차 전에 1에 닿는다. 1은 "도착"을
/// 말하는 값이라 추정으로는 채우지 않는다 — 확정(landed)만이 1을 채운다.
const escalatorRideProgressCap = 0.95;

/// 표시 진행률이 목표를 따라가는 지수 평활 계수(틱당).
///
/// 60ms 틱 기준 시정수 약 0.5초 — 기압 샘플이 1초 간격(iOS)이어도 점이
/// 끊기지 않고, 하차 확정(목표 1.0)에는 반 초 안에 붙는다.
const escalatorRideProgressEase = 0.12;

/// 기압 누적 변화로 계산한 탑승 진행률 목표.
///
/// [deltaTowardsM]는 이동 방향으로 잰 누적 변화(상행이면 +Δ, 하행이면 -Δ의
/// 절댓값 방향 정렬), [swapDeltaM]는 도면을 교체한 순간의 그 값이다. 활강은
/// 교체 순간 시작하므로 그 지점을 0으로, 남은 높이([expectedTotalM] -
/// [swapDeltaM])를 1로 정규화한다.
///
/// [escalatorRideProgressCap]에서 멈춘다 — 이 값은 추정이고, 끝맺음은 하차
/// 확정 이벤트가 한다. 남은 높이가 1m 미만으로 추정되면 1m로 잡는다(층고
/// 추정 오류로 진행률이 즉시 상한에 붙는 것 방지).
double escalatorRideProgressTarget({
  required double deltaTowardsM,
  required double swapDeltaM,
  required double expectedTotalM,
}) {
  final remainingM = math.max(expectedTotalM - swapDeltaM, 1.0);
  return ((deltaTowardsM - swapDeltaM) / remainingM).clamp(
    0.0,
    escalatorRideProgressCap,
  );
}

/// 탑승 → 도착을 잇는 활강 한 건.
///
/// 진행률을 밖에서 받는다(기압이 정한다). 티커를 들지 않으므로 위젯 없이
/// 검증할 수 있고, 화면은 표시 진행률이 바뀔 때마다 [pointAtProgress]를 물어
/// 지도 소스만 갱신한다.
class EscalatorGlide {
  const EscalatorGlide({required this.from, required this.to});

  /// 출발 층의 탑승 노드(WGS84).
  final LatLng from;

  /// 도착 층의 하차 노드(WGS84).
  ///
  /// **두 점 모두 절대 좌표다.** 층 로컬 m로 들고 있으면 도면이 갈아 끼워지는
  /// 순간 같은 숫자가 다른 자리를 가리켜 마커가 튄다.
  final LatLng to;

  /// [progress](0=탑승, 1=하차)에서 마커를 그릴 자리.
  ///
  /// 등속(선형)이다 — 진행률 자체가 실제 오르내린 높이에서 나오므로, 여기에
  /// 완화 곡선을 또 얹으면 화면 위치가 물리 위치에서 벗어난다. 표시가 끊기지
  /// 않게 하는 평활은 진행률 쪽([escalatorRideProgressEase])이 맡는다.
  LatLng pointAtProgress(double progress) {
    final t = progress.clamp(0.0, 1.0);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }
}

/// 하차 지점에서 두 점이 이만큼은 떨어져 있어야 방향을 말한다.
///
/// 에스컬레이터는 비스듬히 올라가므로 탑승 노드와 도착 노드는 수평으로도
/// 10m 안팎 떨어진다. 그런데 도면 데이터가 두 노드를 같은 자리에 찍어 둔
/// 층(엘리베이터처럼 수직으로만 그린 경우)이 있고, 그때 두 점의 방위각은
/// 좌표 오차가 만드는 **아무 방향**이다. 그런 값으로 지도를 돌리면 내리자마자
/// 엉뚱한 쪽이 화면 위에 온다 — 차라리 돌리지 않는 편이 낫다.
const escalatorExitBearingMinSeparationM = 3.0;

/// 에스컬레이터를 내리는 순간 사용자가 바라보는 방향(북 기준 시계방향).
///
/// 탑승 노드 → 도착 노드 방위각이다. 몸이 에스컬레이터 진행 방향을 향한 채
/// 실려 올라가므로, 내리는 순간의 정면이 곧 이 방향이다.
///
/// **경로 방향이 아니다.** 예전에는 층이 바뀌면 카메라를 새 층 경로의 긴 축에
/// 맞췄는데, 그러면 내리자마자 화면이 "앞으로 갈 방향"으로 돌아가 있어서 지금
/// 내 몸이 어느 쪽을 보고 있는지와 어긋난다. 사용자는 화면과 몸을 맞추는
/// 것부터 다시 해야 했다.
///
/// 두 점이 [escalatorExitBearingMinSeparationM]보다 가까우면 null — 방향을
/// 단정하지 않는다. 호출부는 그때 카메라 각도를 그대로 둔다.
double? escalatorExitBearingDeg({
  required LatLng boarding,
  required LatLng arrival,
  double minSeparationM = escalatorExitBearingMinSeparationM,
}) {
  const metersPerDegreeLat = 111320.0;
  final meanLatRad = (boarding.latitude + arrival.latitude) * math.pi / 360;
  final eastM =
      (arrival.longitude - boarding.longitude) *
      math.cos(meanLatRad) *
      metersPerDegreeLat;
  final northM = (arrival.latitude - boarding.latitude) * metersPerDegreeLat;
  if (math.sqrt(eastM * eastM + northM * northM) < minSeparationM) return null;
  final deg = math.atan2(eastM, northM) * 180 / math.pi;
  return deg < 0 ? deg + 360 : deg;
}
