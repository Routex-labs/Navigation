import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/screens/outdoor_map/indoor_entry_gps.dart';

/// GPS 기반 실내 진입/이탈 판정에 대한 회귀 테스트.
///
/// 예전 판정(`현재 > 직전 × 1.3`)이 실제로 놓치던 두 경우를 여기서 고정한다.
/// 둘 다 위젯 테스트로는 재현하기 어려웠다 — 실기기를 들고 입구를 드나들어야
/// 보이던 증상이라, 정책을 순수 함수로 떼어낸 이유 자체가 이 테스트다.
void main() {
  final entrance = ll.LatLng(37.5665, 126.9779);
  final base = DateTime(2024, 1, 1, 12);

  /// [entrance]에서 동쪽으로 [meters] 떨어진 좌표. 서울 위도에서 경도 1도는
  /// 약 88,240 m다.
  ll.LatLng east(double meters) =>
      ll.LatLng(entrance.latitude, entrance.longitude + meters / 88240);

  GpsFix fix({
    required int atSeconds,
    required double accuracy,
    required double metersFromEntrance,
  }) => GpsFix(
    at: base.add(Duration(seconds: atSeconds)),
    point: east(metersFromEntrance),
    accuracyMeters: accuracy,
  );

  IndoorEntryGpsDecision feed(List<GpsFix> fixes, {bool armed = true}) {
    final tracker = IndoorEntryGpsTracker();
    var last = IndoorEntryGpsDecision.none;
    for (final f in fixes) {
      tracker.record(f);
      last = tracker.decide(entrance: entrance, armed: armed);
    }
    return last;
  }

  group('진입', () {
    test('신호가 한 번에 무너지면 진입으로 본다', () {
      final decision = feed([
        fix(atSeconds: 0, accuracy: 9, metersFromEntrance: 25),
        fix(atSeconds: 4, accuracy: 10, metersFromEntrance: 12),
        fix(atSeconds: 8, accuracy: 45, metersFromEntrance: 5),
      ]);
      expect(decision, IndoorEntryGpsDecision.enter);
    });

    test('조금씩 여러 번에 나눠 나빠져도 진입으로 본다', () {
      // 예전 판정이 놓치던 경우다. 스텝마다 1.2배씩이라 `직전 × 1.3`을 한 번도
      // 넘지 못하지만, 실제로는 10 m에서 50 m로 5배 나빠졌다.
      final decision = feed([
        fix(atSeconds: 0, accuracy: 10, metersFromEntrance: 15),
        fix(atSeconds: 2, accuracy: 12, metersFromEntrance: 12),
        fix(atSeconds: 4, accuracy: 17, metersFromEntrance: 9),
        fix(atSeconds: 6, accuracy: 24, metersFromEntrance: 6),
        fix(atSeconds: 8, accuracy: 34, metersFromEntrance: 4),
      ]);
      expect(decision, IndoorEntryGpsDecision.enter);
    });

    test('저하 순간 좌표가 튀어 놓쳐도 다음 위치에서 다시 판정된다', () {
      // 예전 판정이 놓치던 두 번째 경우다. 저하가 시작된 표본의 좌표가 입구에서
      // 멀리 튀면 그 건은 진입이 아니었고, 예전에는 그때 비교 기준까지 나쁜 값으로
      // 덮여 이후 영영 성립하지 않았다.
      final tracker = IndoorEntryGpsTracker();
      tracker.record(fix(atSeconds: 0, accuracy: 10, metersFromEntrance: 12));
      expect(
        tracker.decide(entrance: entrance, armed: true),
        IndoorEntryGpsDecision.none,
      );

      tracker.record(fix(atSeconds: 3, accuracy: 55, metersFromEntrance: 90));
      expect(
        tracker.decide(entrance: entrance, armed: true),
        IndoorEntryGpsDecision.enter,
        reason: '무너진 좌표가 어디든, 창 안에 입구 앞의 신뢰 좌표가 있으면 성립한다',
      );

      // 여기서 화면이 놓쳤다 치더라도(예: 건물 미로드) 다음 표본에서 그대로 다시.
      tracker.record(fix(atSeconds: 6, accuracy: 60, metersFromEntrance: 8));
      expect(
        tracker.decide(entrance: entrance, armed: true),
        IndoorEntryGpsDecision.enter,
      );
    });

    test('신호가 멀쩡하면 입구 앞이어도 진입하지 않는다', () {
      final decision = feed([
        fix(atSeconds: 0, accuracy: 9, metersFromEntrance: 15),
        fix(atSeconds: 4, accuracy: 11, metersFromEntrance: 3),
      ]);
      expect(decision, IndoorEntryGpsDecision.none);
    });

    test('신호는 무너졌지만 입구 근처였던 적이 없으면 진입하지 않는다', () {
      final decision = feed([
        fix(atSeconds: 0, accuracy: 8, metersFromEntrance: 120),
        fix(atSeconds: 4, accuracy: 50, metersFromEntrance: 100),
      ]);
      expect(decision, IndoorEntryGpsDecision.none);
    });

    test('믿을 수 있는 좌표가 하나도 없으면 진입하지 않는다', () {
      // 접근 내내 신호가 나빴던 경우(도심 협곡 등). 입구 앞이라는 근거 자체가
      // 무너진 좌표뿐이므로 판단하지 않는다.
      final decision = feed([
        fix(atSeconds: 0, accuracy: 22, metersFromEntrance: 18),
        fix(atSeconds: 4, accuracy: 28, metersFromEntrance: 10),
        fix(atSeconds: 8, accuracy: 55, metersFromEntrance: 5),
      ]);
      expect(decision, IndoorEntryGpsDecision.none);
    });

    test('입구 앞이었던 순간이 창을 벗어나면 진입하지 않는다', () {
      // 입구를 지나쳐 한참 걸어간 뒤 신호가 나빠진 경우.
      final decision = feed([
        fix(atSeconds: 0, accuracy: 9, metersFromEntrance: 10),
        fix(atSeconds: 30, accuracy: 50, metersFromEntrance: 5),
      ]);
      expect(decision, IndoorEntryGpsDecision.none);
    });

    test('입구를 아직 모르면 판정하지 않는다', () {
      final tracker = IndoorEntryGpsTracker();
      tracker.record(fix(atSeconds: 0, accuracy: 9, metersFromEntrance: 10));
      tracker.record(fix(atSeconds: 4, accuracy: 50, metersFromEntrance: 5));
      expect(
        tracker.decide(entrance: null, armed: true),
        IndoorEntryGpsDecision.none,
      );
    });
  });

  group('재활성화', () {
    test('신뢰 좌표가 입구에서 충분히 멀면 다시 켠다', () {
      final decision = feed([
        fix(atSeconds: 0, accuracy: 8, metersFromEntrance: 60),
      ], armed: false);
      expect(decision, IndoorEntryGpsDecision.rearm);
    });

    test('신뢰 좌표여도 입구에 가까우면 다시 켜지 않는다', () {
      // 입구 30 m는 진입 반경(20 m) 밖이지만 재활성화 거리(40 m) 안이다. 이
      // 완충 구간이 없으면 경계에서 진입과 재활성화가 번갈아 일어난다.
      final decision = feed([
        fix(atSeconds: 0, accuracy: 8, metersFromEntrance: 30),
      ], armed: false);
      expect(decision, IndoorEntryGpsDecision.none);
    });

    test('신호가 나쁘면 멀리 있어도 다시 켜지 않는다', () {
      // 실내에서 밖을 탭해 GPS가 되살아난 상황. 좌표를 믿을 수 없으니 "나왔다"고
      // 볼 근거가 없다.
      final decision = feed([
        fix(atSeconds: 0, accuracy: 45, metersFromEntrance: 70),
      ], armed: false);
      expect(decision, IndoorEntryGpsDecision.none);
    });

    test('무장 상태에서는 재활성화를 판정하지 않는다', () {
      final decision = feed([
        fix(atSeconds: 0, accuracy: 8, metersFromEntrance: 60),
      ], armed: true);
      expect(decision, IndoorEntryGpsDecision.none);
    });
  });

  group('이탈 감시 (실내에서 GPS를 켜 둘지)', () {
    bool watch({
      required double pdrMetersFromEntrance,
      required bool watching,
    }) => shouldWatchGpsNearEntrance(
      pdrPoint: east(pdrMetersFromEntrance),
      entrance: entrance,
      watching: watching,
      graceExpired: false,
    );

    test('PDR이 입구 앞으로 들어오면 켠다', () {
      expect(watch(pdrMetersFromEntrance: 10, watching: false), isTrue);
    });

    test('켜는 반경 밖에서는 켜지 않는다', () {
      expect(watch(pdrMetersFromEntrance: 20, watching: false), isFalse);
    });

    test('한 번 켜지면 조금 멀어져도 유지한다', () {
      // 켜는 반경(15m)과 끄는 반경(25m) 사이. 여기서 상태가 바뀌면 PDR이 경계에서
      // 흔들릴 때마다 구독이 붙었다 끊겼다 한다.
      expect(watch(pdrMetersFromEntrance: 20, watching: true), isTrue);
    });

    test('입구에서 충분히 벗어나면 끈다', () {
      expect(watch(pdrMetersFromEntrance: 40, watching: true), isFalse);
    });

    test('PDR이 아직 말을 못 하면 유예 동안은 켜 둔다', () {
      // 진입 직후가 이 상태다. 앵커가 아직 없어 PDR 위치를 모르는데, 여기서
      // 꺼 버리면 들어오자마자 돌아 나가는 사용자를 놓친다.
      expect(
        shouldWatchGpsNearEntrance(
          pdrPoint: null,
          entrance: entrance,
          watching: false,
          graceExpired: false,
        ),
        isTrue,
      );
    });

    test('유예가 끝났는데도 PDR이 말을 못 하면 끈다', () {
      // 자동 앵커가 실패한 층 등. 무한정 켜 두면 실내 내내 GPS가 배터리를 쓴다.
      expect(
        shouldWatchGpsNearEntrance(
          pdrPoint: null,
          entrance: entrance,
          watching: true,
          graceExpired: true,
        ),
        isFalse,
      );
    });

    test('PDR이 말을 할 수 있으면 유예와 무관하게 거리로 정한다', () {
      // 유예가 끝났어도 입구 앞이면 계속 켜 두고, 유예가 남았어도 멀어지면 끈다.
      expect(
        shouldWatchGpsNearEntrance(
          pdrPoint: east(10),
          entrance: entrance,
          watching: true,
          graceExpired: true,
        ),
        isTrue,
      );
      expect(
        shouldWatchGpsNearEntrance(
          pdrPoint: east(40),
          entrance: entrance,
          watching: true,
          graceExpired: false,
        ),
        isFalse,
      );
    });

    test('입구를 모르면 켜지 않는다', () {
      expect(
        shouldWatchGpsNearEntrance(
          pdrPoint: east(10),
          entrance: null,
          watching: false,
          graceExpired: false,
        ),
        isFalse,
      );
    });
  });

  group('야외 판정', () {
    bool outdoors({
      required double accuracy,
      required double metersFromEntrance,
    }) => isOutdoorsFix(
      fix: fix(
        atSeconds: 0,
        accuracy: accuracy,
        metersFromEntrance: metersFromEntrance,
      ),
      entrance: entrance,
    );

    test('입구 앞에서 신뢰 좌표가 잡히면 밖으로 나온 것이다', () {
      expect(outdoors(accuracy: 8, metersFromEntrance: 10), isTrue);
    });

    test('신호가 나쁘면 밖으로 보지 않는다', () {
      // 실내에서 켠 GPS가 흔히 주는 값. 이걸로 나갔다고 보면 안에 있는 사용자의
      // 실내 도면이 제멋대로 닫힌다.
      expect(outdoors(accuracy: 45, metersFromEntrance: 10), isFalse);
    });

    test('PDR이 말한 입구와 GPS가 어긋나면 판정하지 않는다', () {
      // PDR은 "입구 앞"이라 해서 GPS를 켰는데 200m 밖이 잡혔다. 둘 중 하나가
      // 틀린 상태라 판단을 미룬다.
      expect(outdoors(accuracy: 8, metersFromEntrance: 200), isFalse);
    });
  });

  group('창 관리', () {
    test('창을 벗어난 표본은 버린다', () {
      final tracker = IndoorEntryGpsTracker();
      tracker.record(fix(atSeconds: 0, accuracy: 9, metersFromEntrance: 10));
      tracker.record(fix(atSeconds: 5, accuracy: 9, metersFromEntrance: 10));
      expect(tracker.sampleCount, 2);
      tracker.record(fix(atSeconds: 20, accuracy: 9, metersFromEntrance: 10));
      expect(tracker.sampleCount, 1);
    });

    test('시각이 전혀 흐르지 않아도 표본이 무한정 쌓이지 않는다', () {
      // 기기 시계가 멈추거나 플랫폼이 같은 시각을 반복해 주는 경우.
      final tracker = IndoorEntryGpsTracker();
      for (var i = 0; i < 300; i++) {
        tracker.record(fix(atSeconds: 0, accuracy: 9, metersFromEntrance: 10));
      }
      expect(tracker.sampleCount, lessThanOrEqualTo(64));
    });

    test('clear는 창을 비워 판정 근거를 없앤다', () {
      final tracker = IndoorEntryGpsTracker();
      tracker.record(fix(atSeconds: 0, accuracy: 9, metersFromEntrance: 10));
      tracker.clear();
      tracker.record(fix(atSeconds: 2, accuracy: 50, metersFromEntrance: 5));
      expect(
        tracker.decide(entrance: entrance, armed: true),
        IndoorEntryGpsDecision.none,
      );
    });
  });
}
