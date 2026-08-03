import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/widgets/directions_sheet.dart';

/// 길찾기 시트의 "지도에서 선택"에 대한 회귀 테스트.
///
/// 이 줄이 필요한 이유: 지도에서 매장을 눌러 "출발지로 설정"하면 길찾기 시트가
/// 곧바로 열리는데, 그 사용자는 방금 지도를 보고 있었으므로 도착지도 지도에서
/// 고르려 한다. 그런데 시트가 지도를 덮고 있어 시트를 닫는 것 말고는 길이
/// 없었고, 닫으면 방금 지정한 출발지도 함께 사라졌다.
void main() {
  const store = DirectionsCandidate(
    title: 'MLB',
    subtitle: 'B2',
    point: LatLng(37.52, 126.92),
    nodeId: 'FL-2:ND-9',
    floor: 'B2',
  );

  /// 시트를 띄우고, 닫힐 때 돌아오는 결과를 담아 둔다.
  final holder = _ResultHolder();

  setUp(holder.reset);

  /// [initialOrigin]은 "출발지로 설정"에서 넘어온 상황을 재현한다.
  Future<void> openSheet(
    WidgetTester tester, {
    DirectionsCandidate? initialOrigin,
    List<DirectionsCandidate> results = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                holder.result = await DirectionsSheet.show(
                  context,
                  originLabel: '현재 위치',
                  initialOrigin: initialOrigin,
                  search: (query) async => results,
                );
                holder.settled = true;
              },
              child: const Text('길찾기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('길찾기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 시트가 닫히고 결과가 도착할 때까지 프레임을 진행한다.
  Future<DirectionsResult?> awaitResult(WidgetTester tester) async {
    for (var i = 0; i < 20 && !holder.settled; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(holder.settled, isTrue, reason: '시트가 닫히지 않았다');
    return holder.result;
  }

  testWidgets('검색창 아래에 "지도에서 선택"이 보인다', (WidgetTester tester) async {
    await openSheet(tester, initialOrigin: store);

    expect(find.text('지도에서 선택'), findsOneWidget);

    // 자리가 중요하다. 검색 입력 아래가 아니면 "검색으로 못 찾겠으면 지도에서
    // 고르세요"라는 흐름으로 읽히지 않는다.
    final destinationFieldBottom = tester
        .getRect(find.byType(TextField).last)
        .bottom;
    expect(
      tester.getRect(find.text('지도에서 선택')).top,
      greaterThan(destinationFieldBottom),
    );
  });

  testWidgets('"지도에서 선택"을 누르면 출발지를 지닌 채 시트가 닫힌다', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, initialOrigin: store);

    await tester.tap(find.text('지도에서 선택'));
    final result = await awaitResult(tester);

    expect(result, isNotNull);
    expect(result!.pickDestinationOnMap, isTrue);
    expect(result.destination, isNull);
    // 출발지가 함께 돌아오지 않으면 사용자가 방금 지정한 매장을 다시 골라야 한다.
    expect(result.origin?.title, 'MLB');
  });

  testWidgets('출발지가 없어도(현재 위치 출발) 지도에서 고를 수 있다', (
    WidgetTester tester,
  ) async {
    // 상단 바 길찾기 아이콘으로 바로 연 경우. origin이 null이면 호출자가
    // "현재 위치" 출발로 해석한다.
    await openSheet(tester);

    await tester.tap(find.text('지도에서 선택'));
    final result = await awaitResult(tester);

    expect(result!.pickDestinationOnMap, isTrue);
    expect(result.origin, isNull);
  });

  testWidgets('출발지 입력이 활성일 때는 "지도에서 선택"을 감춘다', (
    WidgetTester tester,
  ) async {
    // 지도에서 고르는 건 도착지 전용이다. 출발지 입력 중에 띄우면 "출발지를
    // 지도에서 고른다"는 뜻으로 읽히는데, 그건 지원하지 않는 동작이다.
    await openSheet(tester, initialOrigin: store);
    expect(find.text('지도에서 선택'), findsOneWidget);

    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('지도에서 선택'), findsNothing);
  });

  testWidgets('검색 결과를 고르면 지도 선택이 아니라 도착지로 확정된다', (
    WidgetTester tester,
  ) async {
    // "지도에서 선택"을 넣으면서 기존 경로가 깨지지 않았는지 함께 고정한다.
    await openSheet(
      tester,
      initialOrigin: store,
      results: const [
        DirectionsCandidate(
          title: '올리브영',
          subtitle: 'B1',
          point: LatLng(37.53, 126.93),
        ),
      ],
    );

    await tester.tap(find.text('올리브영'));
    final result = await awaitResult(tester);

    expect(result!.pickDestinationOnMap, isFalse);
    expect(result.destination?.title, '올리브영');
    expect(result.origin?.title, 'MLB');
  });
}

class _ResultHolder {
  DirectionsResult? result;
  bool settled = false;

  void reset() {
    result = null;
    settled = false;
  }
}
