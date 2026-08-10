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
          'type': 'demoInfo',
          'items': [
            {
              'label': '영업시간',
              'value': '화~목 10:30-20:00',
              'source': 'https://www.starbucks.co.kr/store/store_map.do',
              'confirmed_at': '2026-08-10',
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
    final demoInfo = detail.sections[2] as DemoInfoSection;
    final businessInfo = detail.sections[3] as BusinessInfoSection;

    expect(detail.sections, hasLength(4));
    expect(hero.items.single.localAsset, 'assets/place_details/starbucks_reserve_store_01.png');
    expect(menu.items.single.name, '카페 아메리카노');
    expect(menu.items.single.price, '4,700원');
    expect(menu.items.single.description, '진하고 풍부한 에스프레소 샷에 물을 더한 커피');
    expect(menu.items.single.imageAsset, 'assets/place_details/starbucks_reserve_menu.jpg');
    expect(demoInfo.items.single.label, '영업시간');
    expect(demoInfo.items.single.confirmedAt, '2026-08-10');
    expect(businessInfo.items.single.label, '대표번호');
    expect(businessInfo.items.single.value, '1522-3232');
  });

  // 서버는 값이 없는 선택 키를 빈 문자열로 채우지 않고 키 자체를 뺀다(계약 4-2 규칙 1).
  // 이 테스트가 없으면 `price`를 필수로 되돌려도 아무 데서도 실패하지 않고, 가격을
  // 공개하지 않는 매장에서 상세 시트가 통째로 죽는다.
  test('가격 없는 메뉴를 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '더현대서울(B2)R',
      'subtitle': 'B2 · 카페',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'menu',
          'items': [
            {
              'name': '리저브 콜드 브루',
              'image_asset': 'assets/place_details/starbucks_menu_reserve_cold_brew.jpg',
              'category': '리저브',
              'name_en': 'Reserve Cold Brew',
              'volume': '355ml',
              'calories': '5kcal',
              'caffeine': '190mg',
            },
          ],
        },
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-08-10'},
    });

    final item = (detail.sections.single as MenuSection).items.single;

    expect(item.price, isNull);
    expect(item.description, isNull);
    expect(item.category, '리저브');
    expect(item.nameEn, 'Reserve Cold Brew');
    expect(item.volume, '355ml');
    expect(item.calories, '5kcal');
    expect(item.caffeine, '190mg');
  });
}
