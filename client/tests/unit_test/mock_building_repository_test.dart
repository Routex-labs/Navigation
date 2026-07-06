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
    expect(buildings.first.id, 'bldg-001');
    expect(buildings.first.floors, [1, 2]);
  });

  test('returns the building by id', () async {
    final building = await repository.getBuilding('bldg-001');

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
    final geojson = await repository.getFloorGeoJson('bldg-001', 1);

    expect(geojson, isNotNull);
    expect(geojson!['type'], 'FeatureCollection');
  });

  test('returns null for an unknown floor', () async {
    final geojson = await repository.getFloorGeoJson('bldg-001', 99);

    expect(geojson, isNull);
  });
}
