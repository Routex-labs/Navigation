import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/building.dart';

/// 층 목록 순서와 "처음 열 층"의 분리를 검증한다. 지하층이 생기면서
/// floors.first(=최상층)를 기본 층으로 쓰던 방식이 6F로 열리는 문제를 냈다.
void main() {
  test('default_floor를 처음 열 층으로 쓴다', () {
    final building = Building.fromJson({
      'id': 'thehyundai-seoul',
      'name': '더현대 서울',
      'floors': ['6F', '5F', '4F', '3F', '2F', '1F', 'B1', 'B2'],
      'default_floor': '1F',
    });

    expect(building.floors.first, '6F');
    expect(building.initialFloor, '1F');
  });

  test('default_floor가 없는 응답은 목록 첫 층으로 폴백한다', () {
    final building = Building.fromJson({
      'id': 'legacy',
      'name': '구버전 백엔드',
      'floors': ['2F', '1F'],
    });

    expect(building.defaultFloor, isNull);
    expect(building.initialFloor, '2F');
  });

  test('default_floor가 층 목록에 없으면 무시한다', () {
    final building = Building.fromJson({
      'id': 'stale',
      'name': '없는 층을 가리키는 응답',
      'floors': ['2F', '1F'],
      'default_floor': 'B9',
    });

    expect(building.initialFloor, '2F');
  });

  test('층이 없으면 열 층도 없다', () {
    final building = Building.fromJson({
      'id': 'empty',
      'name': '층 없음',
      'floors': <String>[],
    });

    expect(building.initialFloor, isNull);
  });
}
