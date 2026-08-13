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
///
/// ## 판정과 함께 근거를 돌려준다
///
/// [judgeBuildingFromGps]는 결론만이 아니라 그 결론을 만든 숫자
/// ([GpsBuildingJudgement])를 함께 돌려준다. 실기기 실험에서 "진입이 안 걸렸다"는
/// 관찰만으로는 원인이 셋 중 무엇인지 구분할 수 없기 때문이다 — 오차가 커서
/// 판정을 건너뛴 것인지, 아직 안쪽 문턱을 못 넘은 것인지, 외곽선이 없는 것인지.
///
/// 근거를 화면에서 **다시 계산하지 않는 것**이 핵심이다. 같은 거리를 두 곳에서
/// 재면 임계값을 조정한 순간 둘이 어긋나고, 그러면 현장에서 실제 판정과 다른
/// 숫자를 보면서 실험하게 된다. 사람 눈에 보일 한 줄은
/// [describeGpsBuildingJudgement]가 이 결과값 하나만 읽어서 만든다.
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
/// [indoorEnterInsetMeters]보다 크다. 실내에서 켜 둔 GPS는 좌표가 건물 밖으로
/// 튀는 일이 있는데, 그 한 건으로 실내 상태를 접으면 사용자는 건물 안에서 도면과
/// 위치 아이콘을 잃는다.
///
/// 예전 값은 20 m였다. 그때는 실기기 오차가 15~45 m로 널뛰어 큰 완충이 필요했지만,
/// 위치 스트림을 고친 뒤 오차가 11~15 m로 안정됐다. 20 m를 유지하면 문을 나와
/// **20 m를 더 걸어야** 야외로 전환돼, 사용자 눈에는 전환이 한 박자 늦게 보인다.
/// 12 m는 문을 나와 열 걸음 남짓이고, 지금 오차 수준에서 벽 안쪽 좌표가 여기까지
/// 튀지는 않는다.
const outdoorExitMarginMeters = 12.0;

/// 우리 외곽선과 실제 건물 벽 사이의 알려진 어긋남(m).
///
/// 백엔드가 주는 footprint는 실내 도면에서 뽑은 것이라 지도 타일에 그려진 건물
/// 윤곽보다 **조금 작다.** 실기기에서 건물 안으로 들어섰는데도 진입이 한 박자
/// 늦는 이유가 이것이다 — 사용자는 이미 벽 안인데 우리 외곽선 기준으로는 아직
/// 바깥이고, 거기서 [indoorEnterInsetMeters]를 또 넘어야 한다.
///
/// 그래서 판정에 쓰는 외곽선을 이만큼 **바깥으로 부풀린다.** 폴리곤을 실제로
/// 다시 만들지 않고 거리에 더하고 빼는 것으로 같은 효과를 낸다
/// ([judgeBuildingFromGps]).
///
/// 진입만 앞당기는 것이 아니라 **이탈은 그만큼 늦춘다**는 점이 중요하다. 한쪽만
/// 손보면 벽 근처에서 진입과 이탈이 서로를 밀어내며 화면이 깜빡인다. 부풀린
/// 외곽선 하나를 두 판정이 함께 쓰면 히스테리시스가 그대로 유지된다.
const footprintOutwardToleranceMeters = 6.0;

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

/// 판정 한 건과, 그 판정을 만든 숫자들.
///
/// 거리는 **판정이 실제로 쓴 값 그대로**다. 그래서 화면 진단(칩)과 동작이 어긋날
/// 수 없다.
class GpsBuildingJudgement {
  const GpsBuildingJudgement({
    required this.verdict,
    required this.accuracyMeters,
    required this.metersInside,
    required this.metersOutside,
    required this.hasFootprint,
  });

  /// 이 좌표가 말하는 건물 안팎.
  final GpsBuildingVerdict verdict;

  /// 이 좌표의 오차 반경(m). [decisiveAccuracyMeters]를 넘으면 나머지 거리가
  /// 어떻든 [GpsBuildingVerdict.unclear]다.
  final double accuracyMeters;

  /// 외곽선 **안쪽**으로 들어와 있는 거리(m). 밖이면 0.
  ///
  /// 오차가 커서 판정을 건너뛴 경우에도 채운다. "안에 있었는데 신호 때문에
  /// 안 걸렸다"와 "아직 문턱을 못 넘었다"를 그 자리에서 구분하기 위한 값이다.
  final double metersInside;

  /// 외곽선 **바깥**으로 나가 있는 거리(m). 안이면 0.
  final double metersOutside;

  /// 건물 외곽선을 알고 있었는지. false면 두 거리는 0이고 의미가 없다.
  final bool hasFootprint;
}

/// [fix]가 [footprint] 안팎 중 어디를 가리키는지 판정한다.
///
/// 지금 실내 상태인지는 **묻지 않는다.** 이 함수는 좌표 하나를 읽을 뿐이고,
/// 그 결과로 무엇을 할지(진입·이탈·무장)는 화면이 정한다. 상태를 넣기 시작하면
/// 같은 좌표가 상태에 따라 다르게 읽혀, 실기기 로그만 보고는 왜 그 판정이
/// 나왔는지 되짚을 수 없다.
GpsBuildingJudgement judgeBuildingFromGps({
  required GpsFix fix,
  required List<ll.LatLng>? footprint,
}) {
  if (footprint == null || footprint.length < 3) {
    return GpsBuildingJudgement(
      verdict: GpsBuildingVerdict.unclear,
      accuracyMeters: fix.accuracyMeters,
      metersInside: 0,
      metersOutside: 0,
      hasFootprint: false,
    );
  }
  // 오차가 커서 결론이 unclear로 정해진 경우에도 거리는 끝까지 잰다. 판정에는
  // 쓰이지 않지만 진단에는 이 값이 전부다 — 안 재고 0으로 두면 "건물 한가운데서
  // 신호가 나빴다"가 "건물 밖이었다"와 같은 화면으로 보인다.
  // 우리 외곽선을 [footprintOutwardToleranceMeters]만큼 바깥으로 부풀린 것과 같게
  // 만든다. 폴리곤을 다시 만들지 않고 거리를 옮기는 것으로 끝낸다 — 균일한 바깥
  // 버퍼는 "안쪽 거리 + tolerance, 바깥 거리 − tolerance"와 같은 뜻이다.
  //
  // 음수로 내려가지 않게 자른다. 두 값은 "안이면 안쪽 거리, 밖이면 바깥 거리,
  // 반대쪽은 0"이라는 약속 위에 서 있어서, 한쪽이 음수가 되면 진단 칩이 "바깥
  // -3.0m" 같은 읽을 수 없는 문구를 띄운다.
  final rawInside = metersInsidePolygon(fix.point, footprint);
  final rawOutside = metersToPolygon(fix.point, footprint);
  final metersInside = rawOutside > 0
      ? (footprintOutwardToleranceMeters - rawOutside).clamp(0.0, double.infinity)
      : rawInside + footprintOutwardToleranceMeters;
  final metersOutside = (rawOutside - footprintOutwardToleranceMeters).clamp(
    0.0,
    double.infinity,
  );
  return GpsBuildingJudgement(
    verdict: _verdictFrom(
      accuracyMeters: fix.accuracyMeters,
      metersInside: metersInside,
      metersOutside: metersOutside,
    ),
    accuracyMeters: fix.accuracyMeters,
    metersInside: metersInside,
    metersOutside: metersOutside,
    hasFootprint: true,
  );
}

/// 잰 거리로 결론을 내리는 사다리. 순서가 곧 정책이다.
GpsBuildingVerdict _verdictFrom({
  required double accuracyMeters,
  required double metersInside,
  required double metersOutside,
}) {
  if (accuracyMeters > decisiveAccuracyMeters) return GpsBuildingVerdict.unclear;
  if (metersInside >= indoorEnterInsetMeters) return GpsBuildingVerdict.inside;
  if (metersOutside >= outdoorExitMarginMeters) return GpsBuildingVerdict.outside;
  return GpsBuildingVerdict.unclear;
}

/// 판정 한 건을 실기기 화면에 띄울 한 줄로 만든다.
///
/// 예) `정확도 12m · 안쪽 3.1m · unclear · 무장O · +1.0s`
///
/// [armed]는 자동 진입이 무장돼 있는지다(화면 상태라 판정에는 안 들어간다).
/// 이 값이 없으면 "안이라고 판정했는데 왜 안 들어갔지"라는 흔한 상황에서 원인이
/// 화면에 안 보인다 — 직전 실험에서 건물 밖을 탭해 자동 진입이 꺼진 채로 걷고
/// 있는 경우다.
///
/// [sinceLastFix]는 **직전 좌표와의 간격**이다. 판정과는 무관하지만 같은 줄에
/// 둔다 — 판정이 이상할 때 "규칙이 틀렸다"와 "좌표가 늦게 온다"는 완전히 다른
/// 문제인데, 이 값이 없으면 화면만 보고는 둘을 구분할 수 없다. 첫 좌표에서는
/// 비교 대상이 없으므로 붙이지 않는다.
///
/// [fromStream]과 [streamRestarts]는 그 "좌표가 늦게 온다"를 **다시 두 갈래로**
/// 가른다. 간격이 벌어졌을 때 원인은 셋 중 하나인데, 화면에 이 둘이 없으면
/// 셋을 구분할 방법이 없다.
///
///   - `스트림` + 재시작 1 → 스트림은 살아 있는데 기기가 좌표를 늦게 준다.
///   - `직접` → 스트림이 조용하고 일회성 조회만 화면을 떠받치고 있다.
///   - 재시작이 계속 올라감 → 스트림이 죽고 다시 열리기를 반복한다.
String describeGpsBuildingJudgement(
  GpsBuildingJudgement judgement, {
  required bool armed,
  Duration? sinceLastFix,
  bool? fromStream,
  int? streamRestarts,
}) {
  final accuracy = '정확도 ${judgement.accuracyMeters.toStringAsFixed(0)}m';
  final place = !judgement.hasFootprint
      ? '외곽선 없음'
      : judgement.metersInside > 0
      ? '안쪽 ${judgement.metersInside.toStringAsFixed(1)}m'
      : '바깥 ${judgement.metersOutside.toStringAsFixed(1)}m';
  final verdict = judgement.verdict.name;
  var line = '$accuracy · $place · $verdict · 무장${armed ? 'O' : 'X'}';
  if (sinceLastFix != null) {
    final seconds = (sinceLastFix.inMilliseconds / 1000).toStringAsFixed(1);
    line = '$line · +${seconds}s';
  }
  if (fromStream != null) line = '$line · ${fromStream ? '스트림' : '직접'}';
  if (streamRestarts != null) line = '$line · 재시작$streamRestarts';
  return line;
}
