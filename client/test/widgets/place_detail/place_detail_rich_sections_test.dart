import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/place_detail/korean_line_break.dart';
import 'package:navigation_client/widgets/place_detail/place_detail_rich_sections.dart';

void main() {
  Widget subject(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('Place rich detail renderers', () {
    testWidgets('hero carousel exposes every supplied local asset', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceHeroCarousel(
            images: [
              PlaceHeroImage(
                assetPath:
                    'assets/place_details/starbucks_reserve_store_01.png',
              ),
              PlaceHeroImage(
                assetPath:
                    'assets/place_details/starbucks_reserve_store_02.png',
              ),
            ],
          ),
        ),
      );

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('hero carousel is omitted when no local image is available', (
      tester,
    ) async {
      await tester.pumpWidget(subject(const PlaceHeroCarousel(images: [])));

      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('menu cards render name price description and image asset', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '카페 아메리카노',
                price: '4,700원',
                description: '진한 에스프레소와 물',
                imageAssetPath:
                    'assets/place_details/starbucks_reserve_menu.jpg',
              ),
            ],
          ),
        ),
      );

      expect(find.text('메뉴'), findsOneWidget);
      expect(find.text('카페 아메리카노'), findsOneWidget);
      expect(find.text('4,700원'), findsOneWidget);
      expect(find.text('진한 에스프레소와 물'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('menu card supports a menu without optional fields', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [PlaceMenuItem(name: '오늘의 커피', price: '5,000원')],
          ),
        ),
      );

      expect(find.text('오늘의 커피'), findsOneWidget);
      expect(find.text('5,000원'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    // 가격을 공개하지 않는 출처(스타벅스 코리아 공식 사이트)가 있어서, 가격 자리를
    // 용량·칼로리·카페인이 대신 채운다. 지어낸 가격을 넣지 않기 위한 자리다.
    testWidgets('menu card falls back to volume, calories and caffeine', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '리저브 콜드 브루',
                nameEn: 'Reserve Cold Brew',
                volume: '355ml',
                calories: '5kcal',
                caffeine: '190mg',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Reserve Cold Brew'), findsOneWidget);
      expect(find.text('355ml · 5kcal · 190mg'), findsOneWidget);
    });

    // 푸드에는 영양정보가 없다. 빈 줄을 그리면 그만큼 카드 높이가 달라져 같은 줄의
    // 음료 카드와 어긋난다.
    testWidgets('menu card omits the meta line when nothing fills it', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [PlaceMenuItem(name: '플레인 베이글', description: '담백한 베이글')],
          ),
        ),
      );

      expect(find.text('플레인 베이글'), findsOneWidget);
      expect(find.text('담백한 베이글'), findsOneWidget);
      expect(find.byType(Text), findsNWidgets(3)); // 제목 + 이름 + 설명
    });

    testWidgets('menu tabs filter items by category in server order', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '리저브 콜드 브루', category: '리저브'),
              PlaceMenuItem(name: '카페 아메리카노', category: '에스프레소'),
              PlaceMenuItem(name: '카페 라떼', category: '에스프레소'),
            ],
          ),
        ),
      );

      // 첫 탭이 기본 선택. 다른 탭의 메뉴는 아직 그려지지 않는다.
      expect(find.text('리저브'), findsOneWidget);
      expect(find.text('에스프레소'), findsOneWidget);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('카페 아메리카노'), findsNothing);

      await tester.tap(find.text('에스프레소'));
      await tester.pumpAndSettle();

      expect(find.text('카페 아메리카노'), findsOneWidget);
      expect(find.text('카페 라떼'), findsOneWidget);
      expect(find.text('리저브 콜드 브루'), findsNothing);
    });

    // 가진 것만 탭에 넣으면 카테고리 없는 항목은 어느 탭에서도 안 보인다. 화면에는
    // 아무 이상이 없어 보이는 채로 메뉴가 사라지는 쪽이 더 나쁘다.
    testWidgets('menu tabs are dropped when any item lacks a category', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '리저브 콜드 브루', category: '리저브'),
              PlaceMenuItem(name: '오늘의 커피'),
            ],
          ),
        ),
      );

      expect(find.text('리저브'), findsNothing);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('오늘의 커피'), findsOneWidget);
    });

    // 누를 곳이 하나뿐인 탭은 아무것도 나누지 않으면서 자리만 차지한다.
    testWidgets('a single category renders no tab', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '리저브 콜드 브루', category: '리저브'),
              PlaceMenuItem(name: '리저브 나이트로', category: '리저브'),
            ],
          ),
        ),
      );

      expect(find.text('리저브'), findsNothing);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('리저브 나이트로'), findsOneWidget);
    });

    testWidgets('demo info shows one shared confirmation date', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceDemoInfoSection(
            items: [
              PlaceDemoInfo(
                label: '영업시간',
                value: '화~목 10:30-20:00',
                confirmedAt: '2026-08-10',
              ),
              PlaceDemoInfo(
                label: '주차',
                value: '주차 지원 불가',
                confirmedAt: '2026-08-10',
              ),
            ],
          ),
        ),
      );

      expect(find.text('영업 정보'), findsOneWidget);
      expect(find.text('영업시간'), findsOneWidget);
      expect(find.text('2026-08-10 확인'), findsOneWidget);
    });

    // 확인일이 다르면 하나로 묶을 수 없다. 묶는 순간 오래된 항목이 최근에 확인된
    // 것처럼 보인다.
    testWidgets('demo info keeps per-item dates when they differ', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceDemoInfoSection(
            items: [
              PlaceDemoInfo(
                label: '영업시간',
                value: '화~목 10:30-20:00',
                confirmedAt: '2026-08-10',
              ),
              PlaceDemoInfo(
                label: '주차',
                value: '주차 지원 불가',
                confirmedAt: '2026-07-30',
              ),
            ],
          ),
        ),
      );

      expect(find.text('영업시간 · 2026-08-10 확인'), findsOneWidget);
      expect(find.text('주차 · 2026-07-30 확인'), findsOneWidget);
      expect(find.text('2026-08-10 확인'), findsNothing);
    });

    testWidgets('business information displays each key-value row', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceBusinessInfoSection(
            items: [
              PlaceBusinessInfo(label: '주소', value: '서울 영등포구 여의대로 108'),
              PlaceBusinessInfo(label: '주차', value: '주차 지원 불가'),
            ],
          ),
        ),
      );

      expect(find.text('매장 정보'), findsOneWidget);
      expect(find.text('주소'), findsOneWidget);
      expect(find.text(keepWordsWhole('서울 영등포구 여의대로 108')), findsOneWidget);
      expect(find.text(keepWordsWhole('주차 지원 불가')), findsOneWidget);
    });
  });
}
