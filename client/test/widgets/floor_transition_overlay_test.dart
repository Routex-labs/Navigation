import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';
import 'package:navigation_client/widgets/floor_transition_overlay.dart';

FloorTransitionUiState _state(
  FloorTransitionStage stage, {
  bool canUndo = false,
  String from = 'B1',
  String to = '1F',
  bool goingUp = true,
}) => FloorTransitionUiState(
  stage: stage,
  fromFloorLabel: from,
  toFloorLabel: to,
  goingUp: goingUp,
  canUndo: canUndo,
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
        (FloorTransitionStage.arrived, '1F 도착으로 보고 위치를 옮겼습니다'),
      ]) {
        await tester.pumpWidget(
          _host(FloorTransitionBanner(state: _state(stage))),
        );
        expect(find.text(expected), findsOneWidget);
      }
    });

    testWidgets('되돌리기는 층을 실제로 옮긴 뒤에만 노출한다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionBanner(
            state: _state(FloorTransitionStage.moving),
            onUndo: () {},
          ),
        ),
      );
      expect(
        find.text('아니에요'),
        findsNothing,
        reason: '아직 층을 옮기지 않았으면 되돌릴 것이 없다',
      );

      var undone = false;
      await tester.pumpWidget(
        _host(
          FloorTransitionBanner(
            state: _state(FloorTransitionStage.arrived, canUndo: true),
            onUndo: () => undone = true,
          ),
        ),
      );
      await tester.tap(find.text('아니에요'));
      expect(undone, isTrue);
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
                canUndo: true,
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
}
