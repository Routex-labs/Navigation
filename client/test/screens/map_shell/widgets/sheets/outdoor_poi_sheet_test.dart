import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/outdoor_poi_sheet.dart';

/// 야외 장소 시트가 돌려주는 **조작 계약**에 대한 테스트.
///
/// 이 시트에는 한때 "대중교통" 버튼이 있었다. 상세는 "여기가 어디인가"를 보는
/// 자리라 이동 수단을 고르는 조작이 섞이면 안 되고, 그래서 매장 시트와 같은
/// 출발/도착 두 개로 맞췄다. 두 시트가 다시 갈라지지 않도록 여기서 못 박는다.
void main() {
  OutdoorPoi poi() => const OutdoorPoi(
    id: 'poi-1',
    name: '스타벅스 여의도점',
    point: LatLng(37.5665, 126.9780),
    category: '커피전문점',
    address: '서울 영등포구 여의대로 108',
    distanceMeters: 240,
  );

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OutdoorPoiSheet(poi: poi(), onCloseAll: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('길찾기 줄에는 출발·도착 둘만 있다', (WidgetTester tester) async {
    await pumpSheet(tester);

    expect(
      find.byKey(const ValueKey('outdoor-poi-actions')),
      findsOneWidget,
      reason: '테스트 전제(길찾기 줄이 그려짐)가 성립하지 않았다',
    );
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(
      find.text('대중교통'),
      findsNothing,
      reason: '수단은 길찾기에 들어간 뒤 상단 줄에서 고른다. 상세에 두면 조작이 두 군데로 갈린다',
    );
  });

  testWidgets('돌려주는 값은 출발·도착 둘뿐이다', (WidgetTester tester) async {
    // enum에 값을 되살리면 여기가 아니라 호출부의 switch가 조용히 깨진다.
    expect(OutdoorPoiAction.values, [
      OutdoorPoiAction.setOrigin,
      OutdoorPoiAction.setDestination,
    ]);
  });

  testWidgets('거리는 공용 포매터를 쓴다', (WidgetTester tester) async {
    await pumpSheet(tester);

    expect(find.textContaining('약 240m'), findsOneWidget);
  });
}
