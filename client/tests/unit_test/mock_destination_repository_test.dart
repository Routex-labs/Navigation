import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/repositories/mock_building_repository.dart';
import 'package:navigation_client/repositories/mock_destination_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDestinationRepository repository;

  setUp(() {
    repository = MockDestinationRepository(MockBuildingRepository());
  });

  test('returns every POI across floors when the query is empty', () async {
    final results = await repository.searchDestinations('bldg-001', '');

    expect(results, hasLength(2));
    expect(results.map((r) => r.name), containsAll(['강의실 101', '강의실 201']));
  });

  test('filters POIs by name, case-insensitively', () async {
    final results = await repository.searchDestinations('bldg-001', '201');

    expect(results, hasLength(1));
    expect(results.single.name, '강의실 201');
    expect(results.single.floor, 2);
  });

  test('returns an empty list for an unknown building', () async {
    final results = await repository.searchDestinations('unknown', '');

    expect(results, isEmpty);
  });

  test('returns an empty list when nothing matches the query', () async {
    final results = await repository.searchDestinations('bldg-001', '화장실');

    expect(results, isEmpty);
  });
}
