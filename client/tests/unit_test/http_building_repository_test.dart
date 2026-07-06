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
          jsonEncode({'id': 'bldg-001', 'name': '데모 건물', 'floors': [1, 2]}),
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
        return http.Response(jsonEncode({'type': 'FeatureCollection', 'features': []}), 200);
      });
      final repository = HttpBuildingRepository(client: client);

      await repository.getFloorGeoJson('bldg-001', 1);
      await repository.getFloorGeoJson('bldg-001', 1); // 같은 조합 → 캐시 재사용
      await repository.getFloorGeoJson('bldg-001', 2); // 다른 층 → 새 요청

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
            {'id': 'bldg-001', 'name': '데모 건물', 'floors': [1, 2]},
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
