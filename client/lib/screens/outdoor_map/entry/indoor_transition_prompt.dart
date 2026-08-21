/// 실내/실외 전환을 **사람이 확정하는** 갈래 — 자동 판정이 문턱을 못 넘는
/// 구간에서 띄울 버튼 하나를 고른다.
///
/// **새 판정을 만들지 않는다.** 이미 있는 세 값(GPS 판정 · 약한 이탈 래치 ·
/// 바깥 지속 시계)만 읽는다. 근거가 둘이 되면 버튼과 자동 갈래가 서로 다른
/// 순간에 다른 말을 하게 되고, 그때 어느 쪽이 옳은지 가릴 방법이 없다.
///
/// 검증 기준은 `test/screens/outdoor_map/entry/indoor_transition_prompt_test.dart`.
library;

import 'indoor_entry_gps.dart';

/// 지금 물어볼 전환 한 가지. 문구를 여기 두는 이유는 조건과 문장이 같이
/// 바뀌기 때문이다 — 떨어뜨려 두면 조건만 고치고 문장은 옛말이 된다.
enum IndoorTransitionPrompt {
  enterIndoor('건물 안에 계신가요?', '실내 지도로'),
  exitOutdoor('건물 밖으로 나오셨나요?', '실외 지도로');

  const IndoorTransitionPrompt(this.message, this.actionLabel);

  final String message;
  final String actionLabel;
}

/// 지금 띄울 전환 버튼. 물을 이유가 없으면 null.
///
/// [judgement]는 마지막 GPS 판정([judgeBuildingFromGps]), [weakExitApplied]와
/// [outsideClockRunning]은 이탈의 약한 근거 둘이다(`indoor_exit_evidence.dart`).
/// [indoorClaimed]는 **앱이 이 사람을 건물 안이라고 믿는지**다(자동 진입이었거나
/// 실내 앵커가 찍혀 있다). 자동 이탈이 쓰는 것과 같은 조건이라, 도면만 구경하려고
/// 확대해 연 사람에게는 나가라는 버튼이 뜨지 않는다.
IndoorTransitionPrompt? indoorTransitionPrompt({
  required bool indoorEntered,
  required bool indoorClaimed,
  required GpsBuildingJudgement? judgement,
  required bool weakExitApplied,
  required bool outsideClockRunning,
}) {
  // 외곽선을 모르면 안팎이라는 말 자체가 성립하지 않는다.
  if (judgement == null || !judgement.hasFootprint) return null;
  if (!indoorEntered) {
    // **오차를 보지 않는다.** 자동 진입을 막는 것이 바로 그 오차이고
    // ([decisiveAccuracyMeters]), 여기서는 사람이 그 자리를 대신 판단한다.
    // 남는 문턱은 거리뿐이고, 그 값은 확정 이탈과 같은 띠를 쓴다 —
    // 그만큼 밖에 있는 사람에게 "안에 계신가요"는 물을 말이 아니다.
    return judgement.metersOutside < outdoorExitMarginMeters
        ? IndoorTransitionPrompt.enterIndoor
        : null;
  }
  if (!indoorClaimed) return null;
  // 안에 있는 것이 확실하면 묻지 않는다. 약한 이탈 래치는 한 번 서면 재진입
  // 전까지 안 내려가서, 이 줄이 없으면 문 앞을 지나쳐 돌아선 사람에게 알림이
  // 영영 붙어 있는다.
  if (judgement.verdict == GpsBuildingVerdict.inside) return null;
  return weakExitApplied || outsideClockRunning
      ? IndoorTransitionPrompt.exitOutdoor
      : null;
}
