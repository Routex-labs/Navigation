import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';
import 'package:navigation_client/widgets/floor_transition_overlay.dart';

FloorTransitionUiState _state(
  FloorTransitionStage stage, {
  String from = 'B1',
  String to = '1F',
  bool goingUp = true,
}) => FloorTransitionUiState(
  stage: stage,
  fromFloorLabel: from,
  toFloorLabel: to,
  goingUp: goingUp,
);

Widget _host(Widget child, {double textScale = 1.0, Size? size}) => MediaQuery(
  data: MediaQueryData(
    textScaler: TextScaler.linear(textScale),
    size: size ?? const Size(390, 844),
  ),
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('FloorTransitionBanner', () {
    testWidgets('단계마다 다른 문구를 그린다', (tester) async {
      for (final (stage, expected) in [
        (FloorTransitionStage.boarding, '에스컬레이터 탑승을 감지했습니다'),
        (FloorTransitionStage.moving, '에스컬레이터로 이동 중 · B1 → 1F'),
        (FloorTransitionStage.swapping, '1F 지도로 전환하는 중'),
        (FloorTransitionStage.arrived, '1F로 이동했습니다'),
      ]) {
        await tester.pumpWidget(
          _host(FloorTransitionBanner(state: _state(stage))),
        );
        expect(find.text(expected), findsOneWidget);
      }
    });

    testWidgets('되돌리기 같은 조작을 두지 않는다', (tester) async {
      // 층 전환은 "맞나요?"라고 되묻지 않는다. 기압이 일상적으로 몇 미터씩
      // 움직이는 일이 없어서, 되묻는 비용이 판정을 의심하게 만드는 값보다 크다.
      await tester.pumpWidget(
        _host(
          FloorTransitionBanner(state: _state(FloorTransitionStage.arrived)),
        ),
      );

      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('작은 화면 + 큰 글자 배율에서도 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 288,
            child: FloorTransitionBanner(
              state: _state(
                FloorTransitionStage.moving,
                from: 'B2',
                to: '지하 1층 식품관',
              ),
            ),
          ),
          textScale: 2,
          size: const Size(320, 568),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('FloorTransitionScrim', () {
    testWidgets('전환 중에는 뒤쪽 입력을 막는다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                Positioned.fill(
                  child: FloorTransitionScrim(
                    opacity: 1,
                    fadeIn: Duration.zero,
                    fadeOut: Duration.zero,
                    state: _state(FloorTransitionStage.swapping),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Scaffold), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isFalse);
      expect(find.text('B1'), findsOneWidget);
      expect(find.text('1F'), findsOneWidget);
    });

    testWidgets('덮개가 옅어지는 동안에는 입력이 통과한다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                Positioned.fill(
                  child: FloorTransitionScrim(
                    opacity: 0.5,
                    fadeIn: Duration.zero,
                    fadeOut: Duration.zero,
                    state: _state(FloorTransitionStage.swapping),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Scaffold), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isTrue, reason: '절반쯤 걷힌 화면을 계속 막아 두면 전환이 끝나도 먹통으로 느껴진다');
      expect(
        find.text('지도를 전환하는 중'),
        findsOneWidget,
        reason: '층 라벨 옆에 지금 무슨 일이 일어나는지 한 줄이 있어야 한다',
      );
    });

    testWidgets('스크림이 걷히면 뒤쪽 입력이 다시 통과한다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                const Positioned.fill(
                  child: FloorTransitionScrim(
                    opacity: 0,
                    fadeIn: Duration.zero,
                    fadeOut: Duration.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Scaffold), warnIfMissed: false);
      await tester.pump();
      expect(
        tapped,
        isTrue,
        reason: '투명한 스크림이 화면 전체 입력을 계속 먹으면 전환 뒤 앱이 먹통이 된다',
      );
    });
  });
  group('층 전환 연출 — 두 층을 세로로 잇는다', () {
    // 층 이동은 수직 사건이다. 가로로 `B1 → B2`라고 적으면, 지하로 내려가는데
    // 화면에서는 오른쪽으로 가는 그림이라 방향 감각이 한 번 꼬인다.

    /// 화면에 그려진 [label] 텍스트의 세로 중심.
    double centerYOf(WidgetTester tester, String label) =>
        tester.getCenter(find.text(label)).dy;

    testWidgets('내려갈 때는 출발 층이 위, 도착 층이 아래다', (tester) async {
      await tester.pumpWidget(
        _host(
          const FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: null,
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        centerYOf(tester, 'B1'),
        lessThan(centerYOf(tester, 'B2')),
        reason: '지하로 내려가는데 도착 층이 위에 있으면 방향이 거꾸로 읽힌다',
      );
    });

    testWidgets('올라갈 때는 출발 층이 아래, 도착 층이 위다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: '1F',
              goingUp: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(centerYOf(tester, '1F'), lessThan(centerYOf(tester, 'B1')));
    });

    testWidgets('두 층 라벨과 단계 문구를 함께 보여 준다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('B1'), findsOneWidget);
      expect(find.text('B2'), findsOneWidget);
      expect(find.textContaining('이동 중'), findsOneWidget);
    });

    testWidgets('점은 지도 마커와 같은 진행률로 움직인다', (tester) async {
      // 덮개는 마커를 가리는 것이 아니라 데려간다. 진행률이 활강과 같은 값이라
      // 걷히는 순간 점이 있던 자리에 마커가 서 있다.
      final progress = ValueNotifier<double>(0);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            progress: progress,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();
      final dot = find.byKey(const Key('floor-transition-dot'));
      final startY = tester.getCenter(dot).dy;

      progress.value = 1;
      // 샘플 사이를 프레임 단위로 잇는 보간이 붙어 있어 한 프레임으로는 다 안 간다.
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(dot).dy,
        greaterThan(startY),
        reason: '내려가는 전환이면 점도 아래로 내려가야 한다',
      );
    });

    testWidgets('진행률을 받으면 자체 반복 애니메이션을 돌리지 않는다', (tester) async {
      // 반복 재생은 덮개가 길어질 때 같은 장면을 두 번 보여 준다.
      final progress = ValueNotifier<double>(0.4);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            progress: progress,
            state: _state(FloorTransitionStage.moving, goingUp: false),
          ),
        ),
      );

      // 자체 애니메이션이 돌고 있으면 pumpAndSettle이 타임아웃으로 실패한다.
      await tester.pumpAndSettle();
    });

    testWidgets('캡션은 가는 방향 쪽에 붙는다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();
      // 내려갈 때는 캡션이 아래 라벨보다 아래에 있다.
      expect(
        tester.getCenter(find.textContaining('이동 중')).dy,
        greaterThan(tester.getCenter(find.text('B2')).dy),
      );

      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: '1F',
              goingUp: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getCenter(find.textContaining('이동 중')).dy,
        lessThan(tester.getCenter(find.text('1F')).dy),
      );
    });

    testWidgets('스크림이 걷히면 반복 애니메이션도 멈춘다', (tester) async {
      // 보이지도 않는 위젯이 매 프레임 rebuild를 요청하면 안 된다.
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 0,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(FloorTransitionStage.moving, goingUp: false),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      // 애니메이션이 계속 돌면 pumpAndSettle이 타임아웃으로 실패한다.
      await tester.pumpAndSettle();
    });
  });
}
