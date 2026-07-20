import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBuildingRepository repository;

  setUp(() {
    repository = MockBuildingRepository();
  });

  test('returns the sample building in the list', () async {
    final buildings = await repository.getAllBuildings();

    expect(buildings, hasLength(1));
    expect(buildings.first.id, 'thehyundai-seoul');
    // 층 목록은 위층부터(엘리베이터 버튼판 순서), 처음 열 층은 따로 내려온다.
    expect(buildings.first.floors, ['2F', '1F']);
    expect(buildings.first.initialFloor, '1F');
  });

  test('returns the building by id', () async {
    final building = await repository.getBuilding('thehyundai-seoul');

    expect(building, isNotNull);
    expect(building!.name, '데모 건물');
    expect(building.entrance?.latitude, 37.5665);
    expect(building.entrance?.longitude, 126.9779);
  });

  test('returns null for an unknown building id', () async {
    final building = await repository.getBuilding('unknown');

    expect(building, isNull);
  });

  test('returns floor geojson for a known floor', () async {
    final geojson = await repository.getFloorGeoJson('thehyundai-seoul', '1F');

    expect(geojson, isNotNull);
    expect(geojson!['type'], 'FeatureCollection');
  });

  test('returns null for an unknown floor', () async {
    final geojson = await repository.getFloorGeoJson('thehyundai-seoul', '99F');

    expect(geojson, isNull);
  });

  test('returns null route when the mock floor has no matching store entrance', () async {
    // sample_building.json은 GeoJSON POI만 있고 매장/entranceNodeId가 없어서
    // 항상 null이다 - 실제 그래프 기반 경로는 HttpBuildingRepository에서만 나온다.
    final route = await repository.getShortestRoute('thehyundai-seoul', '1F', 'N1', 'N2');

    expect(route, isNull);
  });
}
