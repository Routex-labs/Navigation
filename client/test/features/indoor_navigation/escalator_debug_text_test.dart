import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/debug/escalator_debug_text.dart';

EscalatorDetectionEvent _event({
  required String kind,
  required String reason,
  required double deltaM,
}) => EscalatorDetectionEvent(
  atMs: 0,
  kind: kind,
  reason: reason,
  deltaM: deltaM,
  fromFloorLabel: '1F',
);

void main() {
  group('describeEscalatorJudgement', () {
    test('평활값이 아직 없으면 Δ를 비워 둔다', () {
      final text = describeEscalatorJudgement(
        deltaM: null,
        armed: false,
        hasCandidate: false,
        phase: EscalatorPhase.idle,
      );

      expect(text, startsWith('Δ-'));
      expect(text, contains('무장X'));
      expect(text, contains('후보X'));
    });

    test('하강은 음수로, 상승은 부호를 붙여 적는다', () {
      final down = describeEscalatorJudgement(
        deltaM: -5.46,
        armed: true,
        hasCandidate: true,
        phase: EscalatorPhase.idle,
      );
      final up = describeEscalatorJudgement(
        deltaM: 6.2,
        armed: true,
        hasCandidate: true,
        phase: EscalatorPhase.idle,
      );

      expect(down, contains('Δ-5.5m'));
      expect(down, contains('무장O'));
      expect(down, contains('후보O'));
      expect(up, contains('Δ+6.2m'));
    });

    test('두 층을 한 번에 이동해 거부된 경우가 그대로 드러난다', () {
      // 1F→B2 가설: 한 층 6.2m의 두 배 근처에서 multiFloorUnsupported.
      final text = describeEscalatorJudgement(
        deltaM: -12.4,
        armed: true,
        hasCandidate: false,
        phase: EscalatorPhase.idle,
        lastEvent: _event(
          kind: 'rejected',
          reason: 'multiFloorUnsupported',
          deltaM: -12.4,
        ),
      );

      expect(text, contains('rejected:multiFloorUnsupported'));
      // 거부가 **어느 높이에서** 났는지가 원인 판단의 핵심이라 함께 적힌다.
      expect(text, contains('@-12.4m'));
    });

    test('거부 사유는 이벤트가 지나간 뒤에도 남는다', () {
      // 실시간 Δ는 baseline이 따라잡아 0으로 돌아왔지만, 마지막 이벤트는
      // 그대로 들고 있어야 사용자가 읽을 시간이 있다.
      final text = describeEscalatorJudgement(
        deltaM: -0.2,
        armed: false,
        hasCandidate: false,
        phase: EscalatorPhase.idle,
        lastEvent: _event(
          kind: 'rejected',
          reason: 'multiFloorUnsupported',
          deltaM: -12.4,
        ),
      );

      expect(text, contains('Δ-0.2m'));
      expect(text, contains('rejected:multiFloorUnsupported@-12.4m'));
    });

    test('이벤트가 없으면 판정 상태만 적는다', () {
      final text = describeEscalatorJudgement(
        deltaM: -1.0,
        armed: true,
        hasCandidate: false,
        phase: EscalatorPhase.idle,
      );

      expect(text, isNot(contains(':')));
    });
  });
}
