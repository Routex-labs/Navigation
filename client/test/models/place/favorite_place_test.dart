import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/place/favorite_place.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';

/// placeId(매장 상세 조회 키)를 저장한 장소에 얹으면서 지켜야 할 두 가지를
/// 고정한다.
///
/// 1. **이미 기기에 저장된 항목이 그대로 읽혀야 한다.** placeId 키가 없는
///    JSON은 이 앱을 이전 버전에서 쓰던 사용자의 SharedPreferences에 실제로
///    들어 있다. 여기서 예외가 나면 저장 목록 전체가 날아간다.
/// 2. **저장 키(key) 규칙이 바뀌면 안 된다.** key는 중복 저장을 막는 유일
///    식별자라, placeId를 섞는 순간 기존 항목과 새 항목이 다른 장소로
///    취급돼 목록에 같은 매장이 두 번 쌓인다.
void main() {
  const poi = PoiSearchResult(
    name: 'ETF베이커리',
    floor: 'B2',
    point: LatLng(37.5, 127.0),
    placeId: 'PO-abc123',
    nodeId: 'node-1',
    category: '식음료',
    subcategory: '카페·베이커리',
  );

  test('검색 결과에서 만들면 placeId가 함께 보존된다', () {
    final favorite = FavoritePlace.fromPoiSearchResult(
      poi,
      buildingId: 'thehyundai-seoul',
    );

    expect(favorite.placeId, 'PO-abc123');
    expect(favorite.toPoiSearchResult().placeId, 'PO-abc123');
  });

  test('placeId 키가 없는 예전 저장분도 읽히고 상세 키만 비어 있다', () {
    final favorite = FavoritePlace.fromJson(const {
      'buildingId': 'thehyundai-seoul',
      'name': '탠디',
      'floor': '2F',
      'lat': 37.5,
      'lng': 127.0,
      'nodeId': 'node-9',
    });

    expect(favorite.placeId, isNull);
    expect(favorite.name, '탠디');
    expect(favorite.toPoiSearchResult().placeId, isNull);
  });

  test('placeId가 생겨도 저장 키는 달라지지 않는다', () {
    const base = FavoritePlace(
      buildingId: 'thehyundai-seoul',
      name: '탠디',
      floor: '2F',
      lat: 37.5,
      lng: 127.0,
      nodeId: 'node-9',
    );
    const withPlaceId = FavoritePlace(
      buildingId: 'thehyundai-seoul',
      name: '탠디',
      floor: '2F',
      lat: 37.5,
      lng: 127.0,
      placeId: 'PO-xyz789',
      nodeId: 'node-9',
    );

    expect(withPlaceId.key, base.key);
  });

  test('직렬화 왕복에서 placeId가 유지된다', () {
    final favorite = FavoritePlace.fromPoiSearchResult(
      poi,
      buildingId: 'thehyundai-seoul',
    );

    final restored = FavoritePlace.fromJson(favorite.toJson());

    expect(restored.placeId, 'PO-abc123');
    expect(restored.key, favorite.key);
  });

  test('카테고리 보강 사본이 placeId를 잃지 않는다', () {
    final favorite = FavoritePlace.fromPoiSearchResult(
      poi,
      buildingId: 'thehyundai-seoul',
    ).copyWithCategory(category: '식음료', subcategory: '베이커리');

    expect(favorite.placeId, 'PO-abc123');
  });
}
