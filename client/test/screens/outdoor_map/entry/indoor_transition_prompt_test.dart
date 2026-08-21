import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/entry/indoor_entry_gps.dart';
import 'package:navigation_client/screens/outdoor_map/entry/indoor_transition_prompt.dart';

GpsBuildingJudgement _judgement({
  required GpsBuildingVerdict verdict,
  double accuracyMeters = 12,
  double metersInside = 0,
  double metersOutside = 0,
  bool hasFootprint = true,
}) => GpsBuildingJudgement(
  verdict: verdict,
  accuracyMeters: accuracyMeters,
  metersInside: metersInside,
  metersOutside: metersOutside,
  hasFootprint: hasFootprint,
);

IndoorTransitionPrompt? _prompt({
  bool indoorEntered = false,
  bool indoorClaimed = true,
  GpsBuildingJudgement? judgement,
  bool weakExitApplied = false,
  bool outsideClockRunning = false,
}) => indoorTransitionPrompt(
  indoorEntered: indoorEntered,
  indoorClaimed: indoorClaimed,
  judgement: judgement,
  weakExitApplied: weakExitApplied,
  outsideClockRunning: outsideClockRunning,
);

void main() {
  group('진입 쪽', () {
    test('오차가 커서 자동 진입이 못 걸리는 좌표에도 버튼은 뜬다', () {
      // 이 기능이 있는 이유 그 자체다. 건물 안쪽 3 m인데 오차 45 m라
      // 판정은 unclear이고([decisiveAccuracyMeters]) 자동 진입은 안 걸린다.
      expect(
        _prompt(
          judgement: _judgement(
            verdict: GpsBuildingVerdict.unclear,
            accuracyMeters: 45,
            metersInside: 3,
          ),
        ),
        IndoorTransitionPrompt.enterIndoor,
      );
    });

    test('확실히 밖에 있으면 묻지 않는다', () {
      expect(
        _prompt(
          judgement: _judgement(
            verdict: GpsBuildingVerdict.outside,
            metersOutside: outdoorExitMarginMeters,
          ),
        ),
        isNull,
      );
    });

    test('외곽선을 모르면 안팎을 물을 수 없다', () {
      expect(
        _prompt(
          judgement: _judgement(
            verdict: GpsBuildingVerdict.unclear,
            hasFootprint: false,
          ),
        ),
        isNull,
      );
    });

    test('판정이 아직 한 건도 없으면 묻지 않는다', () {
      expect(_prompt(), isNull);
    });
  });

  group('이탈 쪽', () {
    test('약한 이탈이 걸리면 나가는 버튼이 뜬다', () {
      expect(
        _prompt(
          indoorEntered: true,
          weakExitApplied: true,
          judgement: _judgement(verdict: GpsBuildingVerdict.unclear),
        ),
        IndoorTransitionPrompt.exitOutdoor,
      );
    });

    test('바깥 지속 시계가 돌기 시작해도 뜬다', () {
      expect(
        _prompt(
          indoorEntered: true,
          outsideClockRunning: true,
          judgement: _judgement(
            verdict: GpsBuildingVerdict.unclear,
            metersOutside: 9,
          ),
        ),
        IndoorTransitionPrompt.exitOutdoor,
      );
    });

    test('도면만 구경하는 사람은 나가라는 말을 듣지 않는다', () {
      // 확대해서 연 실내 상태(앵커 없음·자동 진입 아님)에서는 좌표가 몇 km
      // 밖이라도 시계만 돌 뿐이다.
      expect(
        _prompt(
          indoorEntered: true,
          indoorClaimed: false,
          outsideClockRunning: true,
          judgement: _judgement(
            verdict: GpsBuildingVerdict.outside,
            metersOutside: 2000,
          ),
        ),
        isNull,
      );
    });

    test('안에 있는 것이 확실해지면 래치가 서 있어도 걷힌다', () {
      // 래치는 재진입 전까지 안 내려간다. 이 규칙이 없으면 문 앞을 지나쳐
      // 돌아선 사람에게 알림이 영영 붙어 있는다.
      expect(
        _prompt(
          indoorEntered: true,
          weakExitApplied: true,
          judgement: _judgement(
            verdict: GpsBuildingVerdict.inside,
            metersInside: 7,
          ),
        ),
        isNull,
      );
    });
  });
}
