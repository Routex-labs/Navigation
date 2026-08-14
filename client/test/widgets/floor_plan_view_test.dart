import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/floor_plan.dart';
import 'package:navigation_client/widgets/floor_plan_view.dart';

// MapLibre GL은 실제 렌더링/피처 조회(queryRenderedFeatures)를 네이티브
// 플랫폼 채널(또는 웹 JS 엔진)에 위임한다. flutter_test 위젯 테스트 환경에는
// 이 플랫폼 구현이 없어서, 예전 flutter_map 기반 테스트처럼 폴리곤을 실제로
// 탭해 onStoreSelected를 검증하는 건 더 이상 여기서 할 수 없다(브라우저/기기가
// 필요한 통합 테스트 영역). 이 테스트는 위젯이 초기 카메라 위치를 계산하며
// 예외 없이 빌드되는지만 확인한다.
void main() {
  testWidgets('FloorPlanView builds without throwing', (tester) async {
    final floorPlan = FloorPlan(
      footprint: const [LatLng(37.5260, 126.9280), LatLng(37.5270, 126.9290)],
      stores: const [
        StorePolygon(
          id: 'store-1',
          name: '테스트 매장',
          category: 'fashion',
          polygon: [
            LatLng(37.5261, 126.9281),
            LatLng(37.5262, 126.9281),
            LatLng(37.5262, 126.9282),
          ],
          centroid: LatLng(37.52615, 126.92815),
        ),
      ],
      pois: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: FloorPlanView(
              buildingId: 'test-building',
              floorName: '1F',
              floorPlan: floorPlan,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FloorPlanView), findsOneWidget);
  });
}
