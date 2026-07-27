import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'corridor_replay_harness.dart';

/// 2026-07-27 실측 두 세션을 재생해 복도 보정의 회귀를 막는다.
///
/// 두 로그 모두 B2에서 시작점 근처로 되돌아온 왕복이다. 실측에서는 보정 경로가
/// 무너졌고(아이폰 정지, 안드로이드 한 복도 미끄러짐), 이 테스트는 그 실패가
/// 되살아나지 않는지 본다.
void main() {
  group('아이폰 B2 서쪽 왕복 재생', () {
    // 실측: T자 교차점(157.7, 131.3)에서 28.1초 멈춘 뒤 북쪽 간선을 잘못 타고
    // 다시 멈췄다. 106.67m를 걸었는데 보정은 22.86m만 그렸다(비율 0.21).
    late CorridorReplayRun run;

    setUpAll(() {
      run = CorridorReplay.load('pdr_v10_ios_b2_west.json').run();
    });

    test('걸은 거리의 대부분이 보정 경로에 남는다', () {
      // 실측 0.21 -> 빔 교체 후 0.65. 아직 목표(0.9)에는 못 미친다.
      // 남은 손실은 서쪽 구간에서 나란한 복도를 잘못 골라 되돌아 나오는 데서
      // 생긴다. 회귀를 막는 선에서 현재값 바로 아래에 문턱을 둔다.
      expect(
        run.distanceRetention,
        greaterThan(0.6),
        reason:
            '실측 0.21. 미해결 구간의 이동이 버려지면 마커는 영원히 뒤처진다. '
            '실제 유지율 ${run.distanceRetention.toStringAsFixed(2)}',
      );
    });

    test('걷는 동안 확정 위치가 오래 멈추지 않는다', () {
      // 실측 28.1초 -> 5.1초. 남은 5초는 확정 걸음이 배치로 몰려 오는 구간의
      // 입력 공백이라 tracker가 아니라 pedometer 쪽 지연이다.
      expect(
        run.longestStallSeconds,
        lessThan(6.0),
        reason:
            '실측 28.1초 정지. 실제 ${run.longestStallSeconds.toStringAsFixed(1)}초',
      );
    });

    test('서쪽 우회 복도를 실제로 지나간다', () {
      // 그래프상 서진은 T자에서 남 4.7m -> 서 11.9m(y=126.6) -> 북 4.6m 로
      // 꺾어야 한다. 사용자는 이 구간을 대각선으로 질렀다.
      final bounds = run.correctedBounds;
      expect(
        bounds.minEast,
        lessThan(150),
        reason:
            '원본은 east 122까지 갔다. 보정이 157.7에서 막히면 서쪽 우회를 '
            '전혀 못 탄 것. 실제 최소 east ${bounds.minEast.toStringAsFixed(1)}',
      );
    });

    test('교차점에서 28초씩 얼어붙지 않는다', () {
      // 실측 실패의 핵심은 "북쪽으로 갔다"가 아니라 "T자 교차점(157.7,131.3)에
      // 도달한 뒤 28초 동안 그 자리에 있었다"였다. 지금은 그 지점을 지나
      // 서쪽 우회로로 진입한다.
      final atJunction = run.samples.where(
        (sample) =>
            (sample.result.correctedPosition -
                    const PdrLocalPoint(157.707, 131.263))
                .distance <
            0.5,
      );
      expect(
        atJunction.length,
        lessThan(run.samples.length ~/ 4),
        reason:
            'T자 교차점에 머문 샘플 ${atJunction.length}/${run.samples.length}',
      );
    });

    test('배치 도착 때만 preview가 튀지 않는다', () {
      // 실측: 배치 도착 시 평균 5.17m / 3m 초과 21건, 그 외 평균 1.29m.
      // 재생성이 사라지면 두 분포가 비슷해져야 한다.
      final onBatch = run.previewJumpsOnBatch;
      final elsewhere = run.previewJumpsElsewhere;
      final batchMean = onBatch.reduce((a, b) => a + b) / onBatch.length;
      final elseMean =
          elsewhere.reduce((a, b) => a + b) / elsewhere.length;
      expect(
        batchMean,
        lessThan(elseMean * 3 + 0.5),
        reason:
            '배치 도착 평균 ${batchMean.toStringAsFixed(2)}m vs '
            '그 외 ${elseMean.toStringAsFixed(2)}m. 확정 배치가 preview를 '
            '되감으면 여기서만 커진다',
      );
    });

    test('preview가 3m 넘게 순간이동하지 않는다', () {
      expect(
        run.previewJumpsOver(3),
        lessThanOrEqualTo(12),
        reason: '실측 30건. 실제 ${run.previewJumpsOver(3)}건',
      );
    });
  });

  group('갤럭시 B2 동쪽 왕복 재생', () {
    // 실측: 거리 유지율은 0.84로 나쁘지 않았지만 모양이 완전히 틀렸다.
    // 원본은 north 107.5~131.9를 오갔는데 보정은 north 131.3 한 줄에 머물렀다.
    late CorridorReplayRun run;

    setUpAll(() {
      run = CorridorReplay.load('pdr_v10_android_b2_east.json').run();
    });

    test('동서 복도를 벗어나 멀리 헤매지 않는다', () {
      // 주의: 이 세션의 원본은 복도 대비 약 28도 회전해 있었다(원본은 north
      // 107.5까지 내려갔지만 사용자는 동서 복도를 왕복했다). 즉 지상 진실은
      // "north 131.3 복도"이고, 원본의 남하는 heading 오차다. 원본을 진실로
      // 삼아 남쪽으로 따라 내려가면 오히려 틀린다.
      final bounds = run.correctedBounds;
      expect(
        bounds.maxNorth - bounds.minNorth,
        lessThan(15),
        reason:
            '복도 폭을 크게 벗어나면 회전 오차를 실제 이동으로 오인한 것. '
            'north ${bounds.minNorth.toStringAsFixed(1)}~'
            '${bounds.maxNorth.toStringAsFixed(1)}',
      );
    });

    test('동서 복도 전 구간을 왕복한다', () {
      final bounds = run.correctedBounds;
      expect(bounds.minEast, lessThan(176));
      expect(bounds.maxEast, greaterThan(205));
    });

    test('한 간선에만 붙어 있지 않다', () {
      expect(
        run.visitedEdgeIds.toSet().length,
        greaterThan(3),
        reason: '실제 방문 간선 ${run.visitedEdgeIds.toSet().length}개',
      );
    });

    test('걷는 동안 확정 위치가 오래 멈추지 않는다', () {
      expect(
        run.longestStallSeconds,
        lessThan(3.0),
        reason:
            '실측 14.7초 정지. 실제 ${run.longestStallSeconds.toStringAsFixed(1)}초',
      );
    });

    test('걸은 거리의 대부분이 보정 경로에 남는다', () {
      // 1을 넘을 수 있다. 윈도우 안에서 1등이 바뀌면 최근 구간이 다시 그려져
      // 경로가 약간 지그재그로 남기 때문이다. 과도한 초과는 그 재작성이 너무
      // 잦다는 뜻이라 위쪽도 함께 막는다.
      expect(run.distanceRetention, greaterThan(0.9));
      expect(
        run.distanceRetention,
        lessThan(1.25),
        reason: '실제 유지율 ${run.distanceRetention.toStringAsFixed(2)}',
      );
    });
  });
}
