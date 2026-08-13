/// 에스컬레이터를 타고 있는 동안 화면이 쓰는 두 가지 계산.
///
/// 탑승부터 하차까지 우리는 **사용자의 수평 위치를 측정하지 못한다.** 걸음은
/// 멈춰 있고(발판 진동이 걸음으로 세어지므로 일부러 멈춘다), 층 도면은 중간에
/// 목적 층으로 갈아 끼워져 이전 층 좌표계가 무의미해진다. 예전에는 그 구간을
/// 불투명 스크림으로 덮어 버렸는데, 사용자 입장에서는 화면이 한 번 번쩍하고
/// 마커가 사라졌다가 다른 자리에 다시 나타나는 것으로 보였다.
///
/// 측정할 수 없다고 해서 아는 것이 없는 것은 아니다. **양 끝은 안다** — 어느
/// 노드에서 탔고(판정기), 어느 노드로 내리는지(경로·이름 규칙). 그래서 그 두
/// 점 사이를 시간으로 이어 마커를 흘려 보낸다. 이것은 측정값이 아니라 두 확정
/// 지점 사이의 **보간**이며, 하차가 확정되는 순간 실제 앵커가 도착 노드에
/// 잡히므로 연출이 끝나는 자리와 실제 위치가 어긋나지 않는다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 탑승 노드에서 도착 노드까지 마커가 흐르는 데 걸리는 시간.
///
/// 실제 탑승 시간(층고·속도에 따라 10~25초)과 맞추지 않는다. 이 활강은 "지금
/// 층을 옮기는 중"이라는 사실을 보여 주는 연출이고, 사용자는 그동안 화면이 아니라
/// 자기 발밑을 보고 있다. 도착 노드에 먼저 도달해 멈춰 있는 편이, 하차 확정이
/// 났는데 마커가 아직 중간에 있는 것보다 낫다 — 후자는 확정 순간 마커가 한 번
/// 순간이동한다.
///
/// 2.4초는 층 도면 크로스페이드(0.6초)를 넉넉히 덮으면서, 사람이 "움직이고
/// 있다"를 읽기에 충분한 길이다.
const escalatorGlideDuration = Duration(milliseconds: 2400);

/// 탑승 → 도착을 잇는 활강 한 건.
///
/// 시간을 밖에서 받는다(생성 시각·현재 시각). 티커를 들지 않으므로 위젯 없이
/// 검증할 수 있고, 화면은 프레임마다 [pointAt]을 물어 지도 소스만 갱신한다.
class EscalatorGlide {
  const EscalatorGlide({
    required this.from,
    required this.to,
    required this.startedAtMs,
    this.duration = escalatorGlideDuration,
  });

  /// 출발 층의 탑승 노드(WGS84).
  final LatLng from;

  /// 도착 층의 하차 노드(WGS84).
  ///
  /// **두 점 모두 절대 좌표다.** 층 로컬 m로 들고 있으면 도면이 갈아 끼워지는
  /// 순간 같은 숫자가 다른 자리를 가리켜 마커가 튄다.
  final LatLng to;

  final int startedAtMs;
  final Duration duration;

  /// 0(탑승) ~ 1(하차). 시작 전이면 0, 끝난 뒤에는 1로 머문다.
  double progressAt(int nowMs) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 1;
    return ((nowMs - startedAtMs) / total).clamp(0.0, 1.0);
  }

  bool isDoneAt(int nowMs) => progressAt(nowMs) >= 1;

  /// 지금 마커를 그릴 자리.
  ///
  /// 양 끝에서 부드럽게 붙도록 ease-in-out을 쓴다. 등속으로 흘리면 출발과
  /// 도착에서 각각 한 번씩 "탁" 걸리는 느낌이 난다 — 앞뒤 구간(고정된 탑승점,
  /// 고정된 하차점) 모두 속도가 0인 정지 상태이기 때문이다.
  LatLng pointAt(int nowMs) {
    final t = _easeInOut(progressAt(nowMs));
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  static double _easeInOut(double t) =>
      t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
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
