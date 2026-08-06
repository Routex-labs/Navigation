import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/widgets/directions_sheet.dart';

/// 길찾기 시트의 **지우기 X**와 **출발지↔도착지 교체**를 고정한다.
///
/// 두 기능 모두 "화면에 보이는 글자"와 "확정된 후보"라는 두 상태를 동시에
/// 건드린다. 한쪽만 바뀌면 화면은 멀쩡한데 시트를 닫는 순간 엉뚱한 경로가
/// 그려지고, 그 어긋남은 경로가 그려진 뒤에야 드러나 되짚기가 어렵다.
/// 그래서 여기서는 눈에 보이는 글자뿐 아니라 **닫힐 때 나오는 결과**까지
/// 함께 확인한다.
void main() {
  const point = LatLng(37.5, 127.0);

  DirectionsCandidate store(String name) => DirectionsCandidate(
    title: name,
    subtitle: 'B2',
    point: point,
    nodeId: 'node-$name',
    floor: 'B2',
  );

  late List<String> lightCalls;

  setUp(() {
    lightCalls = [];
  });

  Future<List<DirectionsCandidate>> light(String query) async {
    lightCalls.add(query);
    // 아무 글자에나 후보 하나를 돌려줘 경량 단계에서 결론이 나게 한다. 이
    // 테스트가 보려는 것은 검색 단계가 아니라 칸과 후보의 일관성이다.
    return query.trim().isEmpty ? const [] : [store(query.trim())];
  }

  /// 경량 디바운스(300ms)와 응답 반영을 통과시킨다. `pumpAndSettle`은 프레임이
  /// 예약된 동안만 시간을 미므로, 화면이 조용한 사이에 도는 타이머는 이렇게
  /// 명시적으로 넘겨야 한다.
  Future<void> settleSearch(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
  }

  void useTallView(WidgetTester tester) {
    // 기본 800x600에서는 시트 목록이 몇 줄 안 남아 행이 화면 밖으로 밀린다.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 닫힘을 관찰할 필요가 없는 경우. 시트를 화면에 직접 얹는다 — 이때
  /// `Navigator.pop`은 눌러 봐야 소용이 없으므로 **교체 버튼을 누르는
  /// 테스트에는 쓰지 않는다.**
  Future<void> pumpBare(
    WidgetTester tester, {
    DirectionsCandidate? initialOrigin,
    DirectionsCandidate? initialDestination,
  }) async {
    useTallView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectionsSheet(
            originLabel: '현재 위치',
            search: light,
            initialOrigin: initialOrigin,
            initialDestination: initialDestination,
          ),
        ),
      ),
    );
    await settleSearch(tester);
  }

  /// 실제 앱과 같이 모달로 띄운다. 시트가 닫혔는지, 무엇을 들고 닫혔는지를
  /// 봐야 하는 테스트는 이쪽을 쓴다.
  late DirectionsResult? result;
  late bool closed;

  Future<void> openSheet(
    WidgetTester tester, {
    DirectionsCandidate? initialOrigin,
    DirectionsCandidate? initialDestination,
  }) async {
    result = null;
    closed = false;
    useTallView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await DirectionsSheet.show(
                  context,
                  originLabel: '현재 위치',
                  search: light,
                  initialOrigin: initialOrigin,
                  initialDestination: initialDestination,
                );
                closed = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await settleSearch(tester);
  }

  IconButton swapButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const Key('directions-swap')));

  String fieldText(WidgetTester tester, {required bool origin}) {
    final field = origin
        ? find.byType(TextField).first
        : find.byType(TextField).last;
    return tester.widget<TextField>(field).controller!.text;
  }

  testWidgets('X는 글자가 있을 때만 보인다', (tester) async {
    await pumpBare(tester);

    // 출발지 칸에는 "현재 위치"라는 안내문이 값처럼 들어 있어 X가 보인다 —
    // 이 글자를 지우는 것이 곧 "출발지를 다시 고르겠다"는 조작이다.
    expect(find.byKey(const Key('directions-clear-origin')), findsOneWidget);
    // 도착지 칸은 비어 있으므로 X가 아예 그려지지 않는다(자리도 차지하지 않는다).
    expect(find.byKey(const Key('directions-clear-destination')), findsNothing);

    await tester.enterText(find.byType(TextField).last, '다이슨');
    await settleSearch(tester);

    expect(
      find.byKey(const Key('directions-clear-destination')),
      findsOneWidget,
    );
  });

  testWidgets('출발지 X는 확정된 출발지까지 비워 교체를 잠근다', (tester) async {
    await pumpBare(tester, initialOrigin: store('나이키'));

    // 실제 후보가 출발지에 있으니 교체할 수 있다.
    expect(swapButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('directions-clear-origin')));
    await settleSearch(tester);

    expect(fieldText(tester, origin: true), '');
    // 글자만 지우고 후보를 남겼다면 여기서 여전히 눌렸을 것이다. 그 상태로
    // 교체하면 사용자가 지웠다고 믿는 매장이 도착지로 올라간다.
    expect(swapButton(tester).onPressed, isNull);
    // 지운 자리에 "현재 위치"를 다시 채우지 않는다 — 되돌리는 길은 목록 맨 위
    // 고정 행이다.
    expect(find.widgetWithText(ListTile, '현재 위치'), findsOneWidget);
  });

  testWidgets('도착지 X는 확정된 도착지까지 비워 출발지 선택만으로 닫히지 않게 한다', (
    tester,
  ) async {
    await openSheet(tester, initialDestination: store('다이슨'));

    await tester.tap(find.byKey(const Key('directions-clear-destination')));
    await settleSearch(tester);
    expect(fieldText(tester, origin: false), '');

    // 출발지 칸으로 옮겨 "현재 위치"를 고른다. 도착지 후보가 남아 있었다면
    // _afterOriginPicked가 "도착지는 이미 있다"고 보고 시트를 닫았을 것이다.
    await tester.tap(find.byType(TextField).first);
    await settleSearch(tester);
    await tester.tap(find.widgetWithText(ListTile, '현재 위치'));
    await tester.pumpAndSettle();

    expect(closed, isFalse);
    expect(result, isNull);
    expect(find.byKey(const Key('directions-swap')), findsOneWidget);
  });

  testWidgets('출발지가 현재 위치면 교체할 수 없다', (tester) async {
    await pumpBare(tester, initialDestination: store('다이슨'));

    // "현재 위치"는 후보 객체가 없어 도착지 자리로 옮길 수 없다. 눌리게 두고
    // 안에서 되돌리면 사용자는 버튼이 고장났다고 읽으므로 아예 잠근다.
    expect(swapButton(tester).onPressed, isNull);
    expect(swapButton(tester).tooltip, contains('현재 위치는 도착지로'));
  });

  testWidgets('교체하면 두 칸이 뒤집히고 그 조합으로 곧바로 닫힌다', (tester) async {
    await openSheet(
      tester,
      initialOrigin: store('나이키'),
      initialDestination: store('다이슨'),
    );

    expect(swapButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('directions-swap')));
    // 닫힘 전환이 끝나기 전 한 프레임. 칸에 적힌 글자가 이미 뒤집혀 있어야
    // 한다 — 여기서 어긋나면 다음 줄의 결과와도 어긋난다.
    await tester.pump();
    expect(fieldText(tester, origin: true), '다이슨');
    expect(fieldText(tester, origin: false), '나이키');

    await tester.pumpAndSettle();

    // 확정 버튼이 없는 시트라, 교체만 하고 열어 두면 방금 만든 조합을 제출할
    // 방법이 없다. 그래서 교체는 곧바로 결과를 들고 닫는다.
    expect(closed, isTrue);
    expect(result!.origin!.title, '다이슨');
    expect(result!.destination!.title, '나이키');
  });

  testWidgets('도착지가 비어 있어도 교체할 수 있다 — 현재 위치에서 출발하는 경로가 된다', (
    tester,
  ) async {
    await openSheet(tester, initialOrigin: store('나이키'));

    await tester.tap(find.byKey(const Key('directions-swap')));
    await tester.pump();
    // 출발지는 값이 아니라 안내문("현재 위치")으로 돌아간다.
    expect(fieldText(tester, origin: true), '현재 위치');
    expect(fieldText(tester, origin: false), '나이키');

    await tester.pumpAndSettle();

    expect(result!.origin, isNull);
    expect(result!.destination!.title, '나이키');
  });

  testWidgets('검색이 도는 중에 교체해도 늦게 온 응답이 목록을 덮지 않는다', (tester) async {
    await openSheet(
      tester,
      initialOrigin: store('나이키'),
      initialDestination: store('다이슨'),
    );
    lightCalls.clear();

    // 디바운스가 아직 안 끝난 시점에 교체를 누른다.
    await tester.enterText(find.byType(TextField).last, '다이');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('directions-swap')));
    await tester.pumpAndSettle();
    await settleSearch(tester);

    // 교체가 대기 중이던 디바운스를 끊고, 닫히면서 dispose가 새 타이머까지
    // 취소한다. 하나라도 새면 이미 닫힌 시트의 응답이 뒤늦게 돌아온다.
    expect(lightCalls, isEmpty);
    // 확정되지 않은 타이핑("다이")은 후보가 아니라 검색어라 뒤집을 대상이
    // 아니다. 교체는 확정된 후보만 옮긴다.
    expect(result!.origin!.title, '다이슨');
    expect(result!.destination!.title, '나이키');
  });
}
