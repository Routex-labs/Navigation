/// 야외 지도의 "GPS 기반 실내 진입/이탈" 판정 정책.
///
/// zoom 정책([indoor_entry_zoom.dart])과 짝을 이룬다. 화면 코드에서 분리한 이유도
/// 같다 — 이 판정은 위치 스트림에 얽혀 있어서, 화면 안에 묻어 두면 실기기를 들고
/// 건물을 드나들어야만 검증할 수 있다.
///
/// ## 무엇을 판정하는가
///
/// **"지금 이 좌표가 건물 외곽선 안인가"** 하나다. 판정 결과는 셋이다 —
/// 안([GpsBuildingVerdict.inside])·밖([GpsBuildingVerdict.outside])·모름
/// ([GpsBuildingVerdict.unclear]).
///
/// ## 왜 "입구 근처에서 신호가 무너짐"을 버렸는가
///
/// 예전 판정은 **"신호가 멀쩡했을 때 입구 20 m 안에 있었는데, 지금 오차가 30 m를
/// 넘었다"** 였다. 실내에서는 GPS가 반드시 무너진다는 전제였는데, 실기기에서
/// 그 전제가 성립하지 않았다.
///
///   - 건물 안으로 들어가도 **입구 부근에서는 오차가 한동안 작게 유지된다.**
///     그래서 "무너짐" 조건이 서지 않아 진입이 발화하지 않았고, 정작 사용자는
///     이미 건물 안이었다.
///   - 무너짐이 뒤늦게(건물 중심 쪽으로 한참 들어간 뒤) 오면, 그때는 창
///     (10초)이 이미 지나 "입구 앞이었다"는 근거가 사라져 있었다.
///
/// 즉 저 판정은 **신호 품질**이라는 간접 증거로 위치를 추론했다. 지금은 좌표를
/// 직접 본다 — 오차가 작다는 것은 그 좌표를 믿어도 된다는 뜻이므로, 믿을 수 있는
/// 좌표가 건물 안을 가리키면 그것이 곧 진입이다. 신호가 좋을수록 판정이 잘 되는
/// 방향이라, 예전과 달리 GPS가 예상보다 잘 잡히는 것이 문제가 되지 않는다.
///
/// ## 히스테리시스는 거리로 만든다
///
/// "안"은 외곽선에서 [indoorEnterInsetMeters]만큼 **안쪽**, "밖"은
/// [outdoorExitMarginMeters]만큼 **바깥**을 요구한다. 그 사이(벽 주변 완충 구간)는
/// 모름이라 상태를 바꾸지 않는다. 벽에 붙어 선 사람의 좌표가 안팎으로 흔들려도
/// 화면이 실내/야외를 오가지 않게 하는 유일한 장치다.
///
/// 두 값이 비대칭인 것은 의도다. 잘못 들어가는 비용(밖에 있는데 실내 도면이 뜸)
/// 보다 잘못 나오는 비용(안에 있는데 PDR 추적이 끊김)이 크므로, 나가는 쪽을 더
/// 엄격하게 잡는다.
library;

import 'package:latlong2/latlong.dart' as ll;

import 'indoor_entry_proximity.dart';

/// 진입/이탈 판정에 쓸 수 있는 좌표의 최대 오차(m).
///
/// 이 값을 넘는 좌표는 안팎 어느 쪽 근거로도 쓰지 않는다. 더 조이면(예: 10 m)
/// 도심에서 건물 벽에 가려 오차가 커진 순간에 진입이 통째로 죽고, 풀면 오차
/// 반경이 건물 폭에 육박해 "안"이라는 판정 자체가 의미를 잃는다. 20 m는 데모
/// 건물(폭 약 180 m)의 1/9이라, 이 오차로 안쪽 5 m 지점이 잡혔다면 실제 위치가
/// 건물 밖일 여지는 좁다.
const decisiveAccuracyMeters = 20.0;

/// 외곽선에서 이만큼 안쪽에 찍혀야 "들어왔다"고 본다(m).
///
/// 0으로 두면 문 앞에 서 있는 사람의 좌표가 벽을 넘나들 때마다 진입이 발화한다.
/// 5 m는 회전문·자동문을 통과하면 곧바로 넘는 거리라 진입이 늦어지지 않는다.
const indoorEnterInsetMeters = 5.0;

/// 외곽선에서 이만큼 바깥에 찍혀야 "나왔다"고 본다(m).
///
/// [indoorEnterInsetMeters]보다 훨씬 크다. 실내에서 켜 둔 GPS는 좌표가 건물 밖
/// 으로 튀는 일이 흔한데, 그 한 건으로 실내 상태를 접으면 사용자는 건물 안에서
/// 도면과 위치 아이콘을 잃는다. 20 m면 문을 나와 몇 걸음 걸은 뒤라 확실하다.
const outdoorExitMarginMeters = 20.0;

/// 판정에 쓰는 위치 한 건.
class GpsFix {
  const GpsFix({required this.point, required this.accuracyMeters});

  final ll.LatLng point;

  /// 오차 반경(m). **작을수록 정확하다.**
  final double accuracyMeters;
}

/// 좌표 한 건이 말하는 "건물 안팎".
enum GpsBuildingVerdict {
  /// 건물 안. 야외 상태였다면 실내로 들어갈 근거다.
  inside,

  /// 건물 밖. 실내 상태였다면 나갈 근거이고, 야외 상태라면 자동 진입을 다시
  /// 무장할 근거다.
  outside,

  /// 판단하지 않는다 — 오차가 크거나, 외곽선을 모르거나, 벽 주변 완충 구간.
  unclear,
}

/// [fix]가 [footprint] 안팎 중 어디를 가리키는지 판정한다.
///
/// 지금 실내 상태인지는 **묻지 않는다.** 이 함수는 좌표 하나를 읽을 뿐이고,
/// 그 결과로 무엇을 할지(진입·이탈·무장)는 화면이 정한다. 상태를 넣기 시작하면
/// 같은 좌표가 상태에 따라 다르게 읽혀, 실기기 로그만 보고는 왜 그 판정이
/// 나왔는지 되짚을 수 없다.
GpsBuildingVerdict judgeBuildingFromGps({
  required GpsFix fix,
  required List<ll.LatLng>? footprint,
}) {
  if (footprint == null || footprint.length < 3) {
    return GpsBuildingVerdict.unclear;
  }
  if (fix.accuracyMeters > decisiveAccuracyMeters) {
    return GpsBuildingVerdict.unclear;
  }
  if (metersInsidePolygon(fix.point, footprint) >= indoorEnterInsetMeters) {
    return GpsBuildingVerdict.inside;
  }
  if (metersToPolygon(fix.point, footprint) >= outdoorExitMarginMeters) {
    return GpsBuildingVerdict.outside;
  }
  return GpsBuildingVerdict.unclear;
}
