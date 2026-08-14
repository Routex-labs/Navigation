import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/floor_switch_progress.dart';

/// 사람 조작 층 전환 연출의 타이밍 정책을 검증한다 — 빠른 전환에는 아무것도
/// 안 뜨고, 오래 걸릴 때만 에스컬레이터 모티프가 방향과 함께 뜨며, 일단 뜨면
/// 최소 표시(계단 한 칸)를 채운 뒤에 걷힌다. 크로스페이드 자체는 MapLibre
/// 컨트롤러가 필요해 여기서 못 돌리고, 상수 사이의 관계만 못 박는다.
///
/// 컨트롤러는 Timer로 도는 상태 기계라 [testWidgets]의 FakeAsync 존에서
/// `tester.pump(Duration)`으로 시간을 감아 검증한다(위젯은 띄우지 않는다).
void main() {
  group('floorSwitchRank', () {
    test('지상층은 양수, 지하층은 음수 순위다', () {
      expect(floorSwitchRank('1F'), 1);
      expect(floorSwitchRank('6F'), 6);
      expect(floorSwitchRank('B1'), -1);
      expect(floorSwitchRank('B4'), -4);
    });

    test('소문자 라벨도 같은 순위다', () {
      expect(floorSwitchRank('b2'), -2);
      expect(floorSwitchRank('3f'), 3);
    });

    test('숫자를 못 읽는 라벨은 0 — 방향을 단정하지 않는다', () {
      expect(floorSwitchRank('옥상'), 0);
      expect(floorSwitchRank(''), 0);
    });
  });

  group('floorSwitchDirectionBetween', () {
    test('순위가 높아지면 up, 낮아지면 down', () {
      expect(
        floorSwitchDirectionBetween('1F', '5F'),
        FloorSwitchDirection.up,
      );
      expect(
        floorSwitchDirectionBetween('B1', '1F'),
        FloorSwitchDirection.up,
      );
      expect(
        floorSwitchDirectionBetween('2F', 'B2'),
        FloorSwitchDirection.down,
      );
    });

    test('시작 층이 없거나 순위가 같으면 null — 모티프를 안 띄운다', () {
      expect(floorSwitchDirectionBetween(null, '3F'), isNull);
      expect(floorSwitchDirectionBetween('옥상', '루프'), isNull);
    });
  });

  group('타이밍 상수의 관계', () {
    test('즉시 교체 임계는 모티프 임계보다 짧다 — 즉시 교체된 전환에 모티프가 안 뜬다', () {
      expect(floorSwitchInstantSwapThreshold < floorSwitchMotifDelay, isTrue);
    });

    test('타일 폴링 주기는 즉시 교체 임계 이하다 — 캐시된 층의 준비 완료를 임계 안에 알아챈다', () {
      expect(
        floorSwitchTilesPollInterval <= floorSwitchInstantSwapThreshold,
        isTrue,
      );
    });

    test('크로스페이드는 단계로 나누어떨어진다 — 마지막 단계가 정확히 1.0에 닿는다', () {
      expect(floorSwitchCrossfadeSteps, greaterThan(0));
      expect(
        floorSwitchCrossfadeDuration.inMilliseconds %
            floorSwitchCrossfadeSteps,
        0,
      );
    });

    test('타일 대기 상한은 모티프 임계보다 훨씬 길다 — 무거운 층에서 모티프가 뜰 시간이 있다', () {
      expect(floorSwitchTilesReadyTimeout > floorSwitchMotifDelay * 2, isTrue);
    });

    test('모티프 최소 표시는 계단 한 칸이 흐르는 주기 이상이다', () {
      expect(
        floorSwitchMotifMinShown >= floorSwitchMotifStepPeriod,
        isTrue,
      );
    });
  });

  group('FloorSwitchProgressController', () {
    testWidgets('모티프 임계 안에 끝난 전환에는 아무것도 안 뜬다', (tester) async {
      final changes = <FloorSwitchDirection?>[];
      final controller = FloorSwitchProgressController(onChanged: changes.add);

      final token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(
        floorSwitchMotifDelay - const Duration(milliseconds: 50),
      );
      controller.finish(token);
      // 남은 타이머가 있어도 발화하지 않는지 충분히 감아 본다.
      await tester.pump(const Duration(seconds: 2));

      expect(changes, isEmpty);
      controller.dispose();
    });

    testWidgets('임계를 넘기면 모티프가 방향과 함께 뜨고, 한 칸 흐를 시간을 보장한다', (
      tester,
    ) async {
      final changes = <FloorSwitchDirection?>[];
      final controller = FloorSwitchProgressController(onChanged: changes.add);

      final token = controller.begin(FloorSwitchDirection.down);
      await tester.pump(floorSwitchMotifDelay);
      expect(controller.motifDirection, FloorSwitchDirection.down);

      // 모티프가 뜬 지 50ms 만에 완료 — 최소 표시를 채울 때까지 유지된다.
      await tester.pump(const Duration(milliseconds: 50));
      controller.finish(token);
      expect(controller.motifDirection, FloorSwitchDirection.down);

      await tester.pump(
        floorSwitchMotifMinShown - const Duration(milliseconds: 50),
      );
      expect(controller.motifDirection, isNull);
      expect(changes.last, isNull);
      controller.dispose();
    });

    testWidgets('최소 표시를 이미 채운 늦은 완료는 즉시 걷는다', (tester) async {
      final controller = FloorSwitchProgressController(onChanged: (_) {});

      final token = controller.begin(FloorSwitchDirection.up);
      // 무거운 층 시나리오 — 모티프가 뜨고도 한참 타일을 기다린다.
      await tester.pump(floorSwitchMotifDelay + const Duration(seconds: 3));
      expect(controller.motifDirection, FloorSwitchDirection.up);

      controller.finish(token);
      expect(controller.motifDirection, isNull);
      controller.dispose();
    });

    testWidgets('같은 토큰의 finish가 두 번 와도 무해하다 — 마무리와 호출부 정리가 겹친다', (
      tester,
    ) async {
      final changes = <FloorSwitchDirection?>[];
      final controller = FloorSwitchProgressController(onChanged: changes.add);

      final token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(
        floorSwitchMotifDelay + floorSwitchMotifMinShown,
      );
      controller.finish(token);
      final changesAfterFirst = List.of(changes);
      controller.finish(token);
      expect(changes, changesAfterFirst);
      controller.dispose();
    });

    testWidgets('연타하면 마지막 전환이 모티프의 주인이다 — 이전 완료는 걷지 못한다', (
      tester,
    ) async {
      final controller = FloorSwitchProgressController(onChanged: (_) {});

      final first = controller.begin(FloorSwitchDirection.up);
      await tester.pump(floorSwitchMotifDelay);
      expect(controller.motifDirection, FloorSwitchDirection.up);

      final second = controller.begin(FloorSwitchDirection.up);
      controller.finish(first); // 이전 탭 완료 — 무시돼야 한다.
      await tester.pump(const Duration(seconds: 2));
      expect(controller.motifDirection, FloorSwitchDirection.up);

      controller.finish(second);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.motifDirection, isNull);
      controller.dispose();
    });

    testWidgets('임계보다 빠른 연타가 이어져도 모티프는 첫 탭 기준으로 뜬다', (tester) async {
      final controller = FloorSwitchProgressController(onChanged: (_) {});

      // 400ms 간격 연타 — 탭마다 지연을 다시 걸면 모티프가 영영 못 뜨는데,
      // 그때가 바로 타일 로드가 제일 오래 겹치는 순간이다.
      var token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(const Duration(milliseconds: 400));
      token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(const Duration(milliseconds: 400));
      // 첫 탭에서 800ms가 지났으니 모티프가 떠 있어야 한다.
      expect(controller.motifDirection, FloorSwitchDirection.up);

      controller.finish(token);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.motifDirection, isNull);
      controller.dispose();
    });

    testWidgets('모티프가 떠 있는 중 방향이 바뀌면 즉시 갈아탄다', (tester) async {
      final controller = FloorSwitchProgressController(onChanged: (_) {});

      final first = controller.begin(FloorSwitchDirection.up);
      await tester.pump(floorSwitchMotifDelay);
      expect(controller.motifDirection, FloorSwitchDirection.up);

      final second = controller.begin(FloorSwitchDirection.down);
      controller.finish(first);
      expect(controller.motifDirection, FloorSwitchDirection.down);

      controller.finish(second);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.motifDirection, isNull);
      controller.dispose();
    });

    testWidgets('방향을 모르는 전환이 이어지면 떠 있던 모티프를 거둔다', (tester) async {
      final controller = FloorSwitchProgressController(onChanged: (_) {});

      controller.begin(FloorSwitchDirection.up);
      await tester.pump(floorSwitchMotifDelay);
      expect(controller.motifDirection, FloorSwitchDirection.up);

      final second = controller.begin(null);
      expect(controller.motifDirection, isNull);

      controller.finish(second);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.motifDirection, isNull);
      controller.dispose();
    });
  });
}
