import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  TransitLeg leg({
    required TransitMode mode,
    int seconds = 600,
    String? routeName,
    String? startName,
    String? endName,
    int stationCount = 0,
  }) => TransitLeg(
    mode: mode,
    sectionTimeSeconds: seconds,
    distanceMeters: 500,
    points: const [],
    routeName: routeName,
    startName: startName,
    endName: endName,
    stationCount: stationCount,
  );

  final ride = TransitItinerary(
    totalTimeSeconds: 1140,
    totalWalkTimeSeconds: 300,
    totalDistanceMeters: 3000,
    transferCount: 0,
    fare: 1500,
    legs: [
      leg(mode: TransitMode.walk, seconds: 60),
      leg(
        mode: TransitMode.bus,
        seconds: 660,
        routeName: '지선:7613',
        startName: '삼부아파트',
        endName: '공덕역2번출구',
        stationCount: 2,
      ),
      leg(mode: TransitMode.walk, seconds: 240),
    ],
  );

  Widget card(TransitItinerary itinerary, {bool expanded = false}) => wrap(
    TransitItineraryCard(
      itinerary: itinerary,
      fastest: true,
      expanded: expanded,
      onExpanded: (_) {},
      onTap: () {},
    ),
  );

  testWidgets('소요·요금·노선·정류장 수를 적는다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.text('19분'), findsOneWidget);
    expect(find.text('1,500원'), findsOneWidget);
    expect(find.text('7613'), findsOneWidget);
    expect(find.text('삼부아파트'), findsOneWidget);
    expect(find.text('공덕역2번출구'), findsOneWidget);
    expect(find.textContaining('2정류장'), findsOneWidget);
  });

  testWidgets('첫 줄이면 최적 배지를 단다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.text('최적'), findsOneWidget);
  });

  testWidgets('도착 시각을 함께 적는다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.textContaining('도착'), findsWidgets);
  });

  testWidgets('요금이 없으면 요금 칸을 그리지 않는다', (tester) async {
    final noFare = TransitItinerary(
      totalTimeSeconds: 1140,
      totalWalkTimeSeconds: 300,
      totalDistanceMeters: 3000,
      transferCount: 0,
      legs: ride.legs,
    );
    await tester.pumpWidget(card(noFare));

    expect(find.textContaining('원'), findsNothing);
  });

  testWidgets('탈것이 없으면 승하차 줄을 그리지 않는다', (tester) async {
    final walkOnly = TransitItinerary(
      totalTimeSeconds: 600,
      totalWalkTimeSeconds: 600,
      totalDistanceMeters: 700,
      transferCount: 0,
      legs: [leg(mode: TransitMode.walk, seconds: 600)],
    );
    await tester.pumpWidget(card(walkOnly));

    expect(find.text('하차'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('총 소요가 0이어도 던지지 않는다', (tester) async {
    final zero = TransitItinerary(
      totalTimeSeconds: 0,
      totalWalkTimeSeconds: 0,
      totalDistanceMeters: 0,
      transferCount: 0,
      legs: [leg(mode: TransitMode.walk, seconds: 0)],
    );
    await tester.pumpWidget(card(zero));

    expect(tester.takeException(), isNull);
  });

  testWidgets('펼치면 구간별 줄이 나온다', (tester) async {
    await tester.pumpWidget(card(ride, expanded: true));

    expect(find.text('상세보기'), findsOneWidget);
    // 접혀 있을 때는 없던 도보 구간 시간이 펼치면 보인다.
    expect(find.textContaining('도보'), findsWidgets);
  });
}
