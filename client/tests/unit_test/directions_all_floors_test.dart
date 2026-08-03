import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/widgets/directions_sheet.dart';

/// 길찾기 검색 범위에 대한 회귀 테스트.
///
/// 예전에는 현재 층으로 좁혀 검색하고 "전체 층에서 찾기" 스위치로 넓히게 했다.
/// 길찾기를 여는 이유 자체가 대개 "지금 층에 없는 곳으로 가려고"라 기본값이
/// 사용자 의도의 반대였고, 찾는 매장이 결과에 아예 없어 매번 토글을 켜야 했다.
/// 지금은 토글 없이 항상 건물 전체를 뒤진다.
void main() {
  /// 지금 보고 있는 층이 B2라고 할 때, 다른 층(4F·B1) 매장까지 후보로 들어온다.
  const results = [
    DirectionsCandidate(
      title: 'MLB',
      subtitle: 'B2',
      point: LatLng(37.52, 126.92),
      nodeId: 'FL-2:ND-9',
      floor: 'B2',
    ),
    DirectionsCandidate(
      title: '스타벅스',
      subtitle: '4F',
      point: LatLng(37.521, 126.921),
      nodeId: 'FL-8:ND-3',
      floor: '4F',
    ),
  ];

  /// 시트가 검색을 위임할 때 실제로 넘어온 질의들. 층 파라미터가 아예 없다는
  /// 것은 타입으로 보장되므로(콜백 시그니처가 query 하나뿐), 여기서는 검색이
  /// 정상적으로 한 번 이상 불렸는지만 확인한다.
  late List<String> queries;

  Future<void> openSheet(WidgetTester tester) async {
    queries = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => DirectionsSheet.show(
                context,
                originLabel: '현재 위치',
                search: (query) async {
                  queries.add(query);
                  return results;
                },
              ),
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

  testWidgets('층 범위 토글이 시트에 없다', (WidgetTester tester) async {
    await openSheet(tester);

    expect(find.text('전체 층에서 찾기'), findsNothing);
    expect(find.text('전체 층에서 찾는 중'), findsNothing);
    // 스위치 자체가 남아 있으면 다른 문구로 되살아난 것이다.
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('다른 층 매장도 후보 목록에 그대로 뜬다', (WidgetTester tester) async {
    await openSheet(tester);

    expect(queries, isNotEmpty, reason: '시트가 열리면서 검색을 한 번은 위임해야 한다');
    // 지금 층(B2)이 아닌 4F 매장이 걸러지지 않고 남아 있어야 한다. 이게 이번
    // 변경의 핵심이다 — 예전에는 토글을 켜기 전까지 이 줄이 아예 없었다.
    expect(find.text('스타벅스'), findsOneWidget);
    expect(find.text('MLB'), findsOneWidget);
  });

  testWidgets('결과 줄에 층이 함께 보여 어느 층인지 알 수 있다', (WidgetTester tester) async {
    await openSheet(tester);

    // 전체 층을 뒤지는 대신, 어느 층 매장인지는 각 줄이 알려줘야 한다. 층 표시가
    // 없으면 사용자는 지금 층 매장인 줄 알고 고른다.
    expect(find.text('4F'), findsWidgets);
    expect(find.text('B2'), findsWidgets);
  });
}
