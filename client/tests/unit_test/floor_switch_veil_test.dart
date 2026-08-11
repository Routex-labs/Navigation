import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/floor_switch_veil.dart';

/// 사람 조작 층 전환 베일의 타이밍 정책을 검증한다 — 빠른 전환에는 베일이
/// 아예 안 뜨고, 일단 뜨면 최소 표시를 채우고, 오래 걸릴 때만 에스컬레이터
/// 모티프가 방향과 함께 뜬다.
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
    test('최소 표시가 페이드인보다 길어야 어중간한 밝기에서 안 꺾인다', () {
      expect(floorSwitchVeilMinShown > floorSwitchVeilFadeIn, isTrue);
    });

    test('모티프는 베일보다 늦게 뜬다 — 베일 없는 모티프가 없다', () {
      expect(floorSwitchMotifDelay > floorSwitchVeilShowDelay, isTrue);
    });

    test('모티프 최소 표시는 계단 한 칸이 흐르는 주기 이상이다', () {
      expect(
        floorSwitchMotifMinShown >= floorSwitchMotifStepPeriod,
        isTrue,
      );
    });
  });

  group('FloorSwitchVeilController', () {
    testWidgets('표시 지연 안에 끝난 전환에는 베일이 아예 안 뜬다', (tester) async {
      final states = <FloorSwitchVeilState>[];
      final controller = FloorSwitchVeilController(onChanged: states.add);

      final token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(floorSwitchVeilShowDelay - const Duration(milliseconds: 50));
      controller.finish(token);
      // 남은 타이머가 있어도 발화하지 않는지 충분히 감아 본다.
      await tester.pump(const Duration(seconds: 2));

      expect(states, isEmpty);
      controller.dispose();
    });

    testWidgets('지연을 넘긴 전환은 베일을 띄우고 최소 표시를 채운 뒤 걷는다', (
      tester,
    ) async {
      final states = <FloorSwitchVeilState>[];
      final controller = FloorSwitchVeilController(onChanged: states.add);

      final token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(floorSwitchVeilShowDelay);
      expect(controller.veilVisible, isTrue);
      expect(controller.motifDirection, isNull); // 모티프 임계 전.

      // 베일이 오른 지 100ms 만에 전환 완료 → 최소 표시를 채울 때까지 유지.
      await tester.pump(const Duration(milliseconds: 100));
      controller.finish(token);
      expect(controller.veilVisible, isTrue);

      await tester.pump(
        floorSwitchVeilMinShown - const Duration(milliseconds: 100),
      );
      expect(controller.veilVisible, isFalse);
      expect(states.last.veilVisible, isFalse);
      controller.dispose();
    });

    testWidgets('임계를 넘기면 모티프가 방향과 함께 뜨고, 한 칸 흐를 시간을 보장한다', (
      tester,
    ) async {
      final controller = FloorSwitchVeilController(onChanged: (_) {});

      final token = controller.begin(FloorSwitchDirection.down);
      await tester.pump(floorSwitchMotifDelay);
      expect(controller.veilVisible, isTrue);
      expect(controller.motifDirection, FloorSwitchDirection.down);

      // 모티프가 뜬 지 50ms 만에 완료 — 베일 최소 표시는 이미 지났지만
      // 모티프 최소 표시가 남아 함께 유지된다.
      await tester.pump(const Duration(milliseconds: 50));
      controller.finish(token);
      expect(controller.veilVisible, isTrue);
      expect(controller.motifDirection, FloorSwitchDirection.down);

      await tester.pump(
        floorSwitchMotifMinShown - const Duration(milliseconds: 50),
      );
      expect(controller.veilVisible, isFalse);
      expect(controller.motifDirection, isNull);
      controller.dispose();
    });

    testWidgets('연타하면 마지막 전환이 베일의 주인이다 — 이전 완료는 걷지 못한다', (
      tester,
    ) async {
      final controller = FloorSwitchVeilController(onChanged: (_) {});

      final first = controller.begin(FloorSwitchDirection.up);
      await tester.pump(floorSwitchVeilShowDelay);
      expect(controller.veilVisible, isTrue);

      final second = controller.begin(FloorSwitchDirection.up);
      controller.finish(first); // 이전 탭 완료 — 무시돼야 한다.
      await tester.pump(const Duration(seconds: 2));
      expect(controller.veilVisible, isTrue);

      controller.finish(second);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.veilVisible, isFalse);
      controller.dispose();
    });

    testWidgets('표시 지연보다 빠른 연타가 이어져도 베일은 첫 탭 기준으로 뜬다', (
      tester,
    ) async {
      final controller = FloorSwitchVeilController(onChanged: (_) {});

      // 100ms 간격 연타 — 탭마다 지연을 다시 걸면 베일이 영영 못 뜬다.
      var token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(const Duration(milliseconds: 100));
      token = controller.begin(FloorSwitchDirection.up);
      await tester.pump(const Duration(milliseconds: 100));
      // 첫 탭에서 150ms가 지났으니 베일이 떠 있어야 한다.
      expect(controller.veilVisible, isTrue);

      controller.finish(token);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.veilVisible, isFalse);
      controller.dispose();
    });

    testWidgets('모티프가 떠 있는 중 방향이 바뀌면 즉시 갈아탄다', (tester) async {
      final controller = FloorSwitchVeilController(onChanged: (_) {});

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
      final controller = FloorSwitchVeilController(onChanged: (_) {});

      controller.begin(FloorSwitchDirection.up);
      await tester.pump(floorSwitchMotifDelay);
      expect(controller.motifDirection, FloorSwitchDirection.up);

      final second = controller.begin(null);
      expect(controller.motifDirection, isNull);
      expect(controller.veilVisible, isTrue); // 베일은 계속 덮는다.

      controller.finish(second);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.veilVisible, isFalse);
      controller.dispose();
    });
  });
}
