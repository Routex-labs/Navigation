/// 층 전환 판정([EscalatorTransitionDetector])의 근거를 지도 위 칩 한 줄로 옮긴다.
///
/// GPS 진입 판정 칩(`screens/outdoor_map/indoor_entry_gps.dart`의
/// `describeGpsBuildingJudgement`)과 같은 이유로 존재한다 — **안 걸렸을 때 원인을
/// 알 방법이 없기 때문이다.** 층이 안 바뀌었을 때 화면에 보이는 것은 "이전 층
/// 도면 그대로"뿐이고, 그 하나로는 아래 중 무엇인지 구분되지 않는다.
///
///   - 에스컬레이터 노드에 허가가 안 걸렸다(위치가 어긋남) → `무장X`
///   - 허가는 걸렸는데 고도가 문턱에 못 미쳤다 → `무장O · 후보X`, Δ가 작음
///   - 후보까지 갔는데 거부됐다 → `rejected:이유`
///
/// 특히 마지막 갈래의 `multiFloorUnsupported`는 **두 층을 한 번에 이동한 것으로
/// 보여 판정이 스스로 포기한** 경우다. 1F→B2처럼 연속으로 갈아타는 경로에서
/// 중간 하차가 확정되지 않으면 두 번의 이동이 한 후보로 합쳐져 여기에 걸린다.
/// 그때 Δ는 한 층(더현대 실측 6.2m)의 두 배 근처로 찍힌다 — 이 숫자가 화면에
/// 보이면 가설을 로그 없이도 그 자리에서 가릴 수 있다.
library;

import '../application/escalator_transition_detector.dart';

/// 판정기의 현재 상태를 한 줄로 옮긴다.
///
/// [deltaM]은 baseline 대비 누적 고도차다(하강은 음수). 평활값이나 baseline이
/// 아직 없으면 null이고, 그때는 "판정이 아직 돌지 않았다"는 뜻이라 `Δ-`로 적는다.
///
/// [lastEvent]는 마지막으로 나온 진단 이벤트다. 이벤트는 무슨 일이 일어난
/// 순간에만 나오므로, 호출자가 마지막 것을 들고 있다가 계속 넘겨야 한다 —
/// 거부된 이유는 거부된 뒤에도 화면에 남아 있어야 읽을 수 있다.
String describeEscalatorJudgement({
  required double? deltaM,
  required bool armed,
  required bool hasCandidate,
  required EscalatorPhase phase,
  EscalatorDetectionEvent? lastEvent,
}) {
  final delta = deltaM == null
      ? 'Δ-'
      : 'Δ${deltaM >= 0 ? '+' : ''}${deltaM.toStringAsFixed(1)}m';
  final line =
      '$delta · 무장${armed ? 'O' : 'X'} · 후보${hasCandidate ? 'O' : 'X'} '
      '· ${phase.name}';
  if (lastEvent == null) return line;
  // 이벤트의 delta는 그 순간의 값이라 위 실시간 Δ와 다르다. 거부가 어느 높이에서
  // 났는지가 곧 원인이므로 함께 적는다.
  final at = lastEvent.deltaM;
  final atText = '${at >= 0 ? '+' : ''}${at.toStringAsFixed(1)}m';
  return '$line · ${lastEvent.kind}:${lastEvent.reason}@$atText';
}
