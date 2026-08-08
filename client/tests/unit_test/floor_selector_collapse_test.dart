import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/floor_selector.dart';

/// 층 선택기가 **접힌 채로 열리고**, 펼쳐서 고르면 다시 접히는지 고정한다.
///
/// 층 목록은 지도 좌측을 세로로 길게 가리는데 사용자가 실제로 층을 바꾸는
/// 순간은 드물다. 평소에는 "지금 몇 층인지"만 남기고 바꿀 때만 펼치는 것이
/// 이 위젯의 존재 이유다 — 기본값이 펼침으로 돌아가면 그 이득이 사라진다.
void main() {
  testWidgets('처음에는 접혀서 현재 층만 보인다', (tester) async {
    await _pumpSelector(
      tester,
      floors: const ['B1', '1F', '2F'],
      selected: '1F',
    );

    expect(find.text('1F'), findsOneWidget);
    expect(find.text('B1'), findsNothing);
    expect(find.text('2F'), findsNothing);
  });

  testWidgets('토글을 누르면 전 층이 펼쳐진다', (tester) async {
    await _pumpSelector(
      tester,
      floors: const ['B1', '1F', '2F'],
      selected: '1F',
    );

    await tester.tap(find.byKey(const Key('floor-selector-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('B1'), findsOneWidget);
    expect(find.text('1F'), findsOneWidget);
    expect(find.text('2F'), findsOneWidget);
  });

  testWidgets('접힌 캡슐을 눌러도 펼쳐진다', (tester) async {
    // 화살표(20px)만 노리게 하면 지도 위에서 누르기 너무 작다.
    await _pumpSelector(
      tester,
      floors: const ['B1', '1F', '2F'],
      selected: '1F',
    );

    await tester.tap(find.text('1F'));
    await tester.pumpAndSettle();

    expect(find.text('B1'), findsOneWidget);
  });

  testWidgets('층을 고르면 알리고 다시 접힌다', (tester) async {
    final picked = <String>[];
    await _pumpSelector(
      tester,
      floors: const ['B1', '1F', '2F'],
      selected: '1F',
      onSelect: picked.add,
    );

    await tester.tap(find.byKey(const Key('floor-selector-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2F'));
    await tester.pumpAndSettle();

    expect(picked, ['2F']);
    // 층을 바꾼 직후가 바로 지도를 다시 봐야 하는 순간이다.
    expect(find.text('2F'), findsOneWidget);
    expect(find.text('B1'), findsNothing);
    expect(find.text('1F'), findsNothing);
  });

  testWidgets('층이 하나뿐이면 토글을 달지 않는다', (tester) async {
    await _pumpSelector(tester, floors: const ['1F'], selected: '1F');

    expect(find.text('1F'), findsOneWidget);
    expect(find.byKey(const Key('floor-selector-toggle')), findsNothing);
  });
}

/// 상위가 선택된 층을 소유하는 실제 사용 형태 그대로 띄운다. 콜백을 받고도
/// selectedFloor를 갱신하지 않으면 "고른 뒤 접힌 캡슐이 새 층을 가리키는지"를
/// 검증할 수 없다.
Future<void> _pumpSelector(
  WidgetTester tester, {
  required List<String> floors,
  required String selected,
  ValueChanged<String>? onSelect,
}) async {
  var current = selected;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.bottomLeft,
            child: FloorSelector(
              floors: floors,
              selectedFloor: current,
              onSelectFloor: (floor) {
                onSelect?.call(floor);
                setState(() => current = floor);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
