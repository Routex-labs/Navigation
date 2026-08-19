import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';

const _walkLeg = TransitLeg(
  mode: TransitMode.walk,
  sectionTimeSeconds: 300,
  distanceMeters: 380,
  points: [LatLng(37.5253, 126.9250), LatLng(37.5215, 126.9245)],
);

const _subwayLeg = TransitLeg(
  mode: TransitMode.subway,
  sectionTimeSeconds: 900,
  distanceMeters: 8000,
  points: [LatLng(37.5215, 126.9245), LatLng(37.5710, 126.9769)],
  routeName: '수도권5호선',
  routeColorHex: '#00A5DE',
  startName: '여의도역',
  endName: '광화문역',
  stationCount: 3,
);

const _busOnly = TransitItinerary(
  totalTimeSeconds: 1800,
  totalWalkTimeSeconds: 420,
  totalDistanceMeters: 11000,
  transferCount: 0,
  fare: 1600,
  legs: [
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 1380,
      distanceMeters: 10500,
      points: [LatLng(37.5250, 126.9240), LatLng(37.5660, 126.9775)],
      routeName: '간선:472',
      routeColorHex: '#0068B7',
    ),
  ],
);

const _withTransfer = TransitItinerary(
  totalTimeSeconds: 2400,
  totalWalkTimeSeconds: 600,
  totalDistanceMeters: 12000,
  transferCount: 1,
  fare: 1500,
  legs: [_walkLeg, _subwayLeg],
);

void main() {
  /// 결과 카드가 커져 기본 600px 뷰포트에는 한 장밖에 안 들어간다. `ListView`가
  /// 지연 생성이라 두 번째 줄은 위젯 자체가 안 만들어져, 높이를 안 키우면 이
  /// 파일의 단언이 "필터가 아니라 화면 높이"를 재게 된다.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('경로마다 소요 시간·요금·노선·정류장을 함께 적는다', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransitRoutesSheet(
            routes: const TransitRoutes.ok([_busOnly, _withTransfer]),
            destinationLabel: '여의도공원',
            onCloseAll: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('여의도공원까지 대중교통'), findsOneWidget);
    // 30분 / 40분 두 후보.
    expect(find.text('30분'), findsOneWidget);
    expect(find.text('40분'), findsOneWidget);
    // 첫 줄에만 "최적" 배지.
    expect(find.text('최적'), findsOneWidget);
    expect(find.textContaining('1,600원'), findsOneWidget);
    // 버스 노선은 "간선:" 접두사를 떼고 번호만 남고, 접두사는 수단 배지가 된다.
    expect(find.text('472'), findsOneWidget);
    expect(find.text('간선'), findsOneWidget);
    expect(find.text('수도권5호선'), findsOneWidget);
    // 승·하차 지점과 정류장 수. 환승 횟수·도보 시간을 글자로 적던 자리는
    // 구간 비율 막대가 대신한다.
    expect(find.text('여의도역'), findsOneWidget);
    expect(find.text('광화문역'), findsOneWidget);
    expect(find.text('3정류장'), findsOneWidget);
  });

  testWidgets('경로를 누르면 그 경로를 돌려준다', (tester) async {
    useTallViewport(tester);
    TransitItinerary? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await TransitRoutesSheet.show(
                  context,
                  routes: const TransitRoutes.ok([_busOnly, _withTransfer]),
                  destinationLabel: '여의도공원',
                  onCloseAll: () {},
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();

    expect(picked?.totalTimeSeconds, 2400);
  });

  testWidgets('요약 카드는 총 시간과 구간을 보여주고 안내 종료만 남긴다', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransitSummaryCard(
            itinerary: _withTransfer,
            label: '여의도공원까지',
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('40분'), findsOneWidget);
    expect(find.textContaining('1,500원'), findsOneWidget);

    // 이동 수단을 고르는 자리는 상단 이동 수단 줄 하나다. 카드에 "도보"를 다시
    // 두면 같은 선택이 두 군데로 흩어진다.
    expect(find.text('도보'), findsNothing);

    await tester.tap(find.text('안내 종료'));
    await tester.pump();
    expect(closed, isTrue);
  });
}
