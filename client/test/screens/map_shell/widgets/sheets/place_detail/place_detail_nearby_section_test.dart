import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/store/nearby_stores.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/place_detail_nearby_section.dart';

void main() {
  NearbyStore nearby(String name, double distanceM, {String floor = 'B2'}) => (
    store: StoreIndexEntry(
      id: name,
      name: name,
      floorId: 'floor',
      floorName: floor,
      subcategory: '카페·베이커리',
    ),
    reach: NodeReach(distanceM: distanceM, costM: distanceM),
  );

  Widget subject(Widget child) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('이름·층·거리를 한 줄에 그린다', (tester) async {
    await tester.pumpWidget(
      subject(
        PlaceNearbySection(stores: [nearby('탬버린즈', 24)], onSelect: (_) {}),
      ),
    );

    expect(find.text('근처 매장'), findsOneWidget);
    expect(find.text('탬버린즈'), findsOneWidget);
    // 층과 거리는 한 줄에 붙는다. 거리 문구는 검색 결과 목록과 같은 함수
    // (reachLabel)가 만든다.
    expect(find.textContaining('B2 · '), findsOneWidget);
    expect(find.textContaining('24'), findsOneWidget);
  });

  // "근처 매장 (없음)"은 정보가 아니라 고장으로 읽힌다.
  testWidgets('고를 것이 없으면 제목까지 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      subject(const PlaceNearbySection(stores: [], onSelect: null)),
    );

    expect(find.text('근처 매장'), findsNothing);
  });

  testWidgets('줄을 누르면 그 매장을 알린다', (tester) async {
    StoreIndexEntry? picked;
    await tester.pumpWidget(
      subject(
        PlaceNearbySection(
          stores: [nearby('탬버린즈', 24)],
          onSelect: (store) => picked = store,
        ),
      ),
    );

    await tester.tap(find.text('탬버린즈'));
    await tester.pumpAndSettle();

    expect(picked?.name, '탬버린즈');
  });

  // 사진이 없어 세로로 쌓으면 글자만 다섯 줄이 된다. 가로로 밀면 "곁다리로 더
  // 있다"가 모양만으로 전해지고 세로 자리도 한 칸만 쓴다.
  testWidgets('가로로 밀 수 있는 목록이다', (tester) async {
    await tester.pumpWidget(
      subject(
        PlaceNearbySection(
          stores: [
            for (var index = 0; index < 5; index++)
              nearby('매장 $index', 10.0 + index),
          ],
          onSelect: (_) {},
        ),
      ),
    );

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.scrollDirection, Axis.horizontal);

    // 화면 밖의 카드도 밀면 나온다. 세로 높이는 한 칸만 쓴다.
    expect(find.text('매장 0'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('매장 4'), findsOneWidget);
  });
}
