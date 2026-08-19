import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_route_detail_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';

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
    // 첫 줄에만 "최적" — 배지 박스가 아니라 색 글자다.
    expect(find.text('최적'), findsOneWidget);
    expect(find.textContaining('1,600원'), findsOneWidget);
    // 버스 노선은 "간선:" 접두사를 떼고 번호만 남는다. 접두사를 적던 배지는
    // 없앴고(참조 캡처에 없다) 수단은 아이콘이 말한다.
    expect(find.text('472'), findsOneWidget);
    expect(find.text('수도권5호선'), findsOneWidget);
    // 승·하차 지점. 환승 횟수·도보 시간을 글자로 적던 자리는 구간 비율 막대가
    // 대신한다.
    expect(find.text('여의도역'), findsOneWidget);
    expect(find.text('광화문역'), findsOneWidget);
    // 카드는 늘 펼친 모양 하나다 — 접기 화살표는 두지 않는다.
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
  });

  /// 목록을 모달로 띄우고, **닫힐 때 돌려준 후보를 읽는 손잡이**를 준다.
  ///
  /// 진짜 라우트로 띄우는 이유는 상세가 그 위에 한 겹 더 쌓이는지, 시스템
  /// 뒤로가기가 위 한 겹만 벗기는지를 봐야 하기 때문이다.
  Future<TransitItinerary? Function()> openSheet(WidgetTester tester) async {
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
    return () => picked;
  }

  /// 상세 안의 `안내 시작`. 뒤에 깔린 화면에도 같은 글자가 있을 수 있어
  /// 상세 안으로 범위를 좁힌다.
  final startInDetail = find.descendant(
    of: find.byType(TransitRouteDetailSheet),
    matching: find.text('안내 시작'),
  );

  testWidgets('카드를 누르면 상세가 열릴 뿐 목록은 닫히지 않는다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsOneWidget);
    expect(find.byType(TransitRoutesSheet), findsOneWidget, reason: '목록이 닫히면 다른 후보로 돌아올 길이 없다');
    expect(picked(), isNull, reason: '상세를 여는 것만으로 경로가 확정되면 견주는 단계가 사라진다');
  });

  testWidgets('상세를 뒤로 닫으면 아무것도 고르지 않은 채 목록에 남는다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();
    // 시스템 뒤로가기는 위 한 겹만 벗긴다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(picked(), isNull);
  });

  testWidgets('견줘 본 뒤 안내 시작을 누른 그 경로를 돌려준다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    // 첫 경로를 열어 보고 뒤로 나온다.
    await tester.tap(find.text('30분'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 두 번째 경로를 열어 안내를 시작한다. 돌아오는 것은 **나중에 고른 쪽**이다.
    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();
    await tester.tap(startInDetail);
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(find.byType(TransitRoutesSheet), findsNothing, reason: '고른 뒤에는 목록도 함께 닫힌다');
    expect(picked()?.totalTimeSeconds, 2400);
  });

  testWidgets('필터로 좁힌 뒤 누르면 그 줄의 상세가 열린다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    // 좁히기 전 첫 줄은 버스(30분)다. 지하철만 남기면 첫 줄이 40분으로 바뀐다 —
    // 인덱스를 원본 목록에서 세면 여기서 30분짜리가 열린다.
    await tester.tap(find.text('지하철 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TransitItineraryCard).first);
    await tester.pumpAndSettle();
    await tester.tap(startInDetail);
    await tester.pumpAndSettle();

    expect(picked()?.totalTimeSeconds, 2400);
  });

  testWidgets('상세를 열었다 닫아도 좁혀 둔 필터가 그대로다', (tester) async {
    useTallViewport(tester);
    await openSheet(tester);

    await tester.tap(find.text('지하철 1'));
    await tester.pumpAndSettle();
    expect(find.byType(TransitItineraryCard), findsOneWidget);

    await tester.tap(find.byType(TransitItineraryCard).first);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 목록이 전체로 되돌아가면 방금 좁힌 일이 없던 셈이 된다.
    expect(find.byType(TransitItineraryCard), findsOneWidget);
    expect(find.text('30분'), findsNothing);
  });

  testWidgets('상세 위 시스템 뒤로가기는 루트의 뒤로가기 사다리까지 내려가지 않는다', (
    tester,
  ) async {
    useTallViewport(tester);
    // 루트 화면의 PopScope 자리. 실제 앱에서는 여기에 검색·안내·종료 확인으로
    // 이어지는 다섯 겹 사다리가 걸려 있다 - 상세를 닫는 뒤로가기가 여기 닿으면
    // 상세만이 아니라 그 아래 상태까지 한 겹 벗겨진다.
    var rootPops = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (_, _) => rootPops++,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => TransitRoutesSheet.show(
                  context,
                  routes: const TransitRoutes.ok([_busOnly, _withTransfer]),
                  destinationLabel: '여의도공원',
                  onCloseAll: () {},
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();
    expect(find.byType(TransitRouteDetailSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(rootPops, 0, reason: '상세를 닫는 뒤로가기가 루트 사다리까지 샜다');
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
