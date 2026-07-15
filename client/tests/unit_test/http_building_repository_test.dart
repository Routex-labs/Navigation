import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_client/repositories/http_building_repository.dart';

void main() {
  group('getBuilding', () {
    test('caches the response so a second call skips the network', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'id': 'bldg-001',
            'name': '데모 건물',
            'floors': ['1F', '2F'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final first = await repository.getBuilding('bldg-001');
      final second = await repository.getBuilding('bldg-001');

      expect(first?.name, '데모 건물');
      expect(second?.name, '데모 건물');
      expect(requestCount, 1);
    });

    test('does not cache a 404 response', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('', 404);
      });
      final repository = HttpBuildingRepository(client: client);

      final first = await repository.getBuilding('unknown');
      final second = await repository.getBuilding('unknown');

      expect(first, isNull);
      expect(second, isNull);
      expect(requestCount, 2);
    });
  });

  group('getFloorGeoJson', () {
    test('caches per building+floor combination', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({'type': 'FeatureCollection', 'features': []}),
          200,
        );
      });
      final repository = HttpBuildingRepository(client: client);

      await repository.getFloorGeoJson('bldg-001', '1F');
      await repository.getFloorGeoJson('bldg-001', '1F'); // 같은 조합 → 캐시 재사용
      await repository.getFloorGeoJson('bldg-001', '2F'); // 다른 층 → 새 요청

      // 층마다 /floors/{floor} 요청 1번씩만, 캐시된 재호출은 요청 없음.
      expect(requestCount, 2);
    });

    test('does not call the separate /graph endpoint', () async {
      final requestPaths = <String>[];
      final client = MockClient((request) async {
        requestPaths.add(request.url.path);
        return http.Response(
          jsonEncode({'type': 'FeatureCollection', 'features': []}),
          200,
        );
      });
      final repository = HttpBuildingRepository(client: client);

      await repository.getFloorGeoJson('bldg-001', '1F');

      expect(requestPaths, ['/buildings/bldg-001/floors/1F']);
      expect(requestPaths.any((path) => path.endsWith('/graph')), isFalse);
    });

    test('maps navigation_graph edges into corridors_local_m', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'floor': '1F',
            'footprint_local_m': [],
            'stores': [],
            'pois': [],
            'navigation_graph': {
              'floor': {'id': '1F', 'name': '1층'},
              'nodes': [
                {'id': 'A', 'x_m': 0.0, 'y_m': 0.0},
                {'id': 'B', 'x_m': 1.0, 'y_m': 1.0},
              ],
              'edges': [
                {
                  'id': 'e1',
                  'from_node_id': 'A',
                  'to_node_id': 'B',
                  'geometry_local_m': [
                    [0.0, 0.0],
                    [1.0, 1.0],
                  ],
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final geojson = await repository.getFloorGeoJson('bldg-001', '1F');

      expect(geojson!['corridors_local_m'], [
        [
          [0.0, 0.0],
          [1.0, 1.0],
        ],
      ]);
    });
  });

  group('getShortestRoute', () {
    test('parses path points and caches per node pair', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'start_node_id': 'N1',
            'end_node_id': 'N2',
            'path_found': true,
            'node_ids': ['N1', 'N2'],
            'edge_ids': ['E1'],
            'coordinate_system': 'local_m',
            'path_points': [
              {'x': 0.0, 'y': 0.0},
              {'x': 5.0, 'y': 0.0},
            ],
            'path_points_wgs84': [
              {'lat': 37.5260, 'lng': 126.9280},
              {'lat': 37.5261, 'lng': 126.9281},
            ],
            'total_distance_m': 5.0,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final first = await repository.getShortestRoute(
        'bldg-001',
        '1F',
        'N1',
        'N2',
      );
      final second = await repository.getShortestRoute(
        'bldg-001',
        '1F',
        'N1',
        'N2',
      );

      expect(first?.distanceMeters, 5.0);
      expect(first?.points.length, 2);
      expect(second?.distanceMeters, 5.0);
      expect(requestCount, 1);
    });

    test('returns null for 404 and 400 without caching', () async {
      var requestCount = 0;
      final statuses = [404, 400];
      final client = MockClient((request) async {
        return http.Response('', statuses[requestCount++]);
      });
      final repository = HttpBuildingRepository(client: client);

      final notFound = await repository.getShortestRoute(
        'bldg-001',
        '1F',
        'N1',
        'N2',
      );
      final badRequest = await repository.getShortestRoute(
        'bldg-001',
        '1F',
        'N1',
        'N3',
      );

      expect(notFound, isNull);
      expect(badRequest, isNull);
      expect(requestCount, 2);
    });
  });

  group('getAllBuildings', () {
    test('caches the list and populates the per-id cache', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode([
            {
              'id': 'bldg-001',
              'name': '데모 건물',
              'floors': ['1F', '2F'],
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      await repository.getAllBuildings();
      await repository.getAllBuildings();
      final building = await repository.getBuilding('bldg-001');

      expect(requestCount, 1);
      expect(building?.name, '데모 건물');
    });
  });
}
