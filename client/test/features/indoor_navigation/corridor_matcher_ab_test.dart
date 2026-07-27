@Tags(['diag'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/floor_map_matcher.dart';

import 'corridor_replay_harness.dart';

/// 구 [FloorMapMatcher](전체 경로 전역 매칭) vs 현 빔 서치 A/B.
///
/// 두 방식은 입력이 같다 — 같은 원본 floor 경로를 서로 다르게 그래프에 붙인다.
/// 구 방식은 매 갱신마다 경로 전체를 다시 매칭해서 복구가 공짜인 대신 시간적
/// 일관성이 없고, 신 방식은 가설을 이어 가며 최근 구간만 다시 그린다.
///
///   flutter test --tags diag test/features/indoor_navigation/corridor_matcher_ab_test.dart
void main() {
  for (final fixture in [
    'pdr_v10_ios_b2_west.json',
    'pdr_v10_android_b2_east.json',
    'pdr_v10_ios_b2_loop.json',
  ]) {
    test('A/B $fixture', () {
      final replay = CorridorReplay.load(fixture);
      final graph = CorridorReplay.loadGraph();
      final raw = replay.floorPath;

      final old = FloorMapMatcher(graph).matchRoutedPath(raw);
      final beam = replay.run().last.correctedPath;

      String report(String label, List<dynamic> path) {
        final points = path.cast<dynamic>();
        return label;
      }

      final oldLen = CorridorReplayRun.lengthOf(old);
      final beamLen = CorridorReplayRun.lengthOf(beam);
      final oldTp = CorridorReplayRun.teleportsOf(old);
      final beamTp = CorridorReplayRun.teleportsOf(beam);
      double minOf(Iterable<double> v) => v.reduce((a, b) => a < b ? a : b);
      double maxOf(Iterable<double> v) => v.reduce((a, b) => a > b ? a : b);

      // ignore: avoid_print
      print(
        '\n=== $fixture (${replay.platform}) ===\n'
        '원본 ${CorridorReplayRun.lengthOf(raw).toStringAsFixed(1)}m, '
        '걸음거리 ${replay.expectedDistanceM.toStringAsFixed(1)}m\n'
        '                 길이      점수   2m초과점프  합계      east범위        north범위\n'
        '구 FloorMapMatcher ${oldLen.toStringAsFixed(1).padLeft(6)}m ${old.length.toString().padLeft(5)} '
        '${oldTp.length.toString().padLeft(6)}건 '
        '${(oldTp.isEmpty ? 0 : oldTp.reduce((a, b) => a + b)).toStringAsFixed(0).padLeft(6)}m  '
        '${minOf(old.map((p) => p.eastM)).toStringAsFixed(0)}~${maxOf(old.map((p) => p.eastM)).toStringAsFixed(0)}  '
        '${minOf(old.map((p) => p.northM)).toStringAsFixed(0)}~${maxOf(old.map((p) => p.northM)).toStringAsFixed(0)}\n'
        '신 빔 서치         ${beamLen.toStringAsFixed(1).padLeft(6)}m ${beam.length.toString().padLeft(5)} '
        '${beamTp.length.toString().padLeft(6)}건 '
        '${(beamTp.isEmpty ? 0 : beamTp.reduce((a, b) => a + b)).toStringAsFixed(0).padLeft(6)}m  '
        '${minOf(beam.map((p) => p.eastM)).toStringAsFixed(0)}~${maxOf(beam.map((p) => p.eastM)).toStringAsFixed(0)}  '
        '${minOf(beam.map((p) => p.northM)).toStringAsFixed(0)}~${maxOf(beam.map((p) => p.northM)).toStringAsFixed(0)}',
      );
      expect(report, isNotNull);
    });
  }
}
