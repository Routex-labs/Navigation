import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/place_detail.dart';

void main() {
  test('알 수 없는 섹션은 버리고 알려진 섹션은 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '테스트 매장',
      'subtitle': '1F · 패션',
      'category': '패션',
      'subcategory': '여성패션',
      'location': {
        'building_id': 'building-1',
        'floor_label': '1F',
        'position_local_m': {'x': 12.5, 'y': 4},
        'entrance_node_id': 'node-1',
      },
      'actions': [
        {'type': 'directions', 'label': '길찾기'},
      ],
      'sections': [
        {'type': 'summary', 'text': '한 줄 소개'},
        {'type': 'futureSection', 'value': '구버전은 무시'},
        {
          'type': 'keyValue',
          'items': [
            {'label': '위치', 'value': '1F 동편'},
          ],
        },
      ],
      'provenance': {'source': 'studio', 'updated_at': null},
    });

    expect(detail.kind, PlaceKind.store);
    expect(detail.location.positionLocalM?.x, 12.5);
    expect(detail.sections, hasLength(2));
    expect(detail.sections.first, isA<SummarySection>());
    expect(detail.sections.last, isA<KeyValueSection>());
  });

  test('확장된 매장 상세 섹션을 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '더현대서울(B2)R',
      'subtitle': 'B2 · 카페',
      'category': '식음료',
      'subcategory': '카페',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'hero',
          'items': [
            {'local_asset': 'assets/place_details/starbucks_reserve_store_01.png'},
          ],
        },
        {
          'type': 'menu',
          'items': [
            {
              'name': '카페 아메리카노',
              'price': '4,700원',
              'description': '진하고 풍부한 에스프레소 샷에 물을 더한 커피',
              'image_asset': 'assets/place_details/starbucks_reserve_menu.jpg',
            },
          ],
        },
        {
          'type': 'businessInfo',
          'items': [
            {'label': '대표번호', 'value': '1522-3232'},
          ],
        },
        {'type': 'futureSection'},
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-07-30'},
    });

    final hero = detail.sections[0] as HeroSection;
    final menu = detail.sections[1] as MenuSection;
    final businessInfo = detail.sections[2] as BusinessInfoSection;

    expect(detail.sections, hasLength(3));
    expect(hero.items.single.localAsset, 'assets/place_details/starbucks_reserve_store_01.png');
    expect(menu.items.single.name, '카페 아메리카노');
    expect(menu.items.single.price, '4,700원');
    expect(menu.items.single.description, '진하고 풍부한 에스프레소 샷에 물을 더한 커피');
    expect(menu.items.single.imageAsset, 'assets/place_details/starbucks_reserve_menu.jpg');
    expect(businessInfo.items.single.label, '대표번호');
    expect(businessInfo.items.single.value, '1522-3232');
  });
}
