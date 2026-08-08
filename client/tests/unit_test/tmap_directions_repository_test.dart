import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/repositories/tmap_directions_repository.dart';

// 실제 TMAP 보행자 경로 API(POST /routes/pedestrian) 응답을 그대로 캡처한 픽스처.
// (2026-07-06, 시청 근처 출발지/목적지 200m 남짓 도보 경로로 실제 검증함)
const _sampleResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97784881268932, 37.56814892738826] },
      "properties": { "totalDistance": 265, "totalTime": 228, "pointType": "SP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97784881268932, 37.56814892738826],
          [126.97758217189669, 37.56809337350867],
          [126.97732664120262, 37.56803781982844]
        ]
      },
      "properties": { "distance": 48, "time": 36 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97732664120262, 37.56803781982844] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97732664120262, 37.56803781982844],
          [126.97735166479588, 37.56712403764582],
          [126.97738499564204, 37.56710459606009]
        ]
      },
      "properties": { "distance": 105, "time": 105 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97738499564204, 37.56710459606009] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97738499564204, 37.56710459606009],
          [126.97738499902333, 37.56698516550335]
        ]
      },
      "properties": { "distance": 13, "time": 9 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97738499902333, 37.56698516550335] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97738499902333, 37.56698516550335],
          [126.97736001136667, 37.56662965083942]
        ]
      },
      "properties": { "distance": 41, "time": 30 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97736001136667, 37.56662965083942] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97736001136667, 37.56662965083942],
          [126.97789607606079, 37.5665435593568]
        ]
      },
      "properties": { "distance": 58, "time": 48 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97789607606079, 37.5665435593568] },
      "properties": { "pointType": "EP" }
    }
  ]
}
''';

void main() {
  test(
    'parses distance/time from the first feature and flattens the path',
    () async {
      final client = MockClient((request) async {
        return http.Response(
          _sampleResponseBody,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = TmapDirectionsRepository(client: client);

      final route = await repository.getWalkingRoute(
        origin: const LatLng(37.56814892738826, 126.97784881268932),
        destination: const LatLng(37.5665435593568, 126.97789607606079),
      );

      expect(route, isNotNull);
      expect(route!.distanceMeters, 265);
      expect(route.durationSeconds, 228);
      // 시작점과 끝점이 실제 경로 좌표와 일치하는지 확인
      expect(
        route.points.first,
        const LatLng(37.56814892738826, 126.97784881268932),
      );
      expect(
        route.points.last,
        const LatLng(37.5665435593568, 126.97789607606079),
      );
      expect(route.points, isNotEmpty);
    },
  );

  test('returns null on a non-200 response', () async {
    final client = MockClient((request) async {
      return http.Response('{"error": {"code": "INVALID_API_KEY"}}', 403);
    });
    final repository = TmapDirectionsRepository(client: client);

    final route = await repository.getWalkingRoute(
      origin: const LatLng(37.5665, 126.9780),
      destination: const LatLng(37.5670, 126.9790),
    );

    expect(route, isNull);
  });
}
