import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/geo_transform.dart';
import 'package:navigation_client/models/floor_graph.dart';

/// api/app/domain/georeference.py::fit_wgs84_transform과 api/app/queries/
/// geo_transform.py::fit_building_geo_transform의 포팅을 검증한다.
void main() {
  GraphNode node(double xM, double yM, {double? lat, double? lng}) =>
      GraphNode(id: 'n', type: 'corridor', xM: xM, yM: yM, lat: lat, lng: lng);

  test('3개 이상의 실측 대응점이 있으면 그 점들을 정확히 복원한다', () {
    // 임의의(비선형이 아닌) 6-DOF affine으로 생성한 대응점 4개.
    // 같은 변환에서 나온 데이터이므로 재피팅한 결과는 원래 좌표를 그대로 복원해야 한다.
    final nodes = [
      node(0.0, 0.0, lat: 37.500, lng: 127.000),
      node(10.0, 0.0, lat: 37.5001, lng: 127.0012),
      node(0.0, 10.0, lat: 37.5011, lng: 127.0002),
      node(10.0, 10.0, lat: 37.5012, lng: 127.0014),
    ];

    final transform = fitFloorGeoTransform(nodes);

    for (final n in nodes) {
      final (lat, lng) = transform.apply(n.xM, n.yM);
      expect(lat, closeTo(n.lat!, 1e-9));
      expect(lng, closeTo(n.lng!, 1e-9));
    }
  });

  test('실측 대응점이 3개 미만이면 서울시청 합성 앵커로 대체한다', () {
    final nodes = [node(0.0, 0.0), node(10.0, 0.0)];

    final transform = fitFloorGeoTransform(nodes);
    final (lat, lng) = transform.apply(0.0, 0.0);

    // geo_transform.py의 _SYNTHETIC_ANCHOR_LAT/LNG(서울시청)와 일치해야 한다.
    expect(lat, closeTo(37.5665, 1e-6));
    expect(lng, closeTo(126.9780, 1e-6));
  });
}
