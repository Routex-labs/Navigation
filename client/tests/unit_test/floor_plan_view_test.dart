import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/floor_plan.dart';
import 'package:navigation_client/widgets/floor_plan_view.dart';

void main() {
  testWidgets('tapping a store polygon fires onStoreSelected and highlights it', (
    tester,
  ) async {
    final floorPlan = FloorPlan(
      footprint: const [LatLng(0, 0), LatLng(0, 80), LatLng(80, 80), LatLng(80, 0)],
      stores: const [
        StorePolygon(
          name: '테스트 매장',
          category: 'fashion',
          polygon: [LatLng(5, 5), LatLng(5, 75), LatLng(75, 75), LatLng(75, 5)],
          centroid: LatLng(40, 40),
        ),
      ],
      pois: const [],
    );

    StorePolygon? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: FloorPlanView(
              floorPlan: floorPlan,
              onStoreSelected: (store) => selected = store,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(selected, isNull);

    // 뷰포트를 채우도록 fit-to-viewport 되므로 중앙 탭이 매장 폴리곤 위에 떨어진다.
    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.name, '테스트 매장');
    expect(selected!.category, 'fashion');
  });
}
