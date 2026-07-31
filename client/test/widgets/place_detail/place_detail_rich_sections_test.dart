import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/place_detail/place_detail_rich_sections.dart';

void main() {
  Widget subject(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('Place rich detail renderers', () {
    testWidgets('hero carousel exposes every supplied local asset', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceHeroCarousel(
            images: [
              PlaceHeroImage(assetPath: 'assets/place_details/starbucks_reserve_store_01.png'),
              PlaceHeroImage(assetPath: 'assets/place_details/starbucks_reserve_store_02.png'),
            ],
          ),
        ),
      );

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('hero carousel is omitted when no local image is available', (tester) async {
      await tester.pumpWidget(subject(const PlaceHeroCarousel(images: [])));

      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('menu cards render name price description and image asset', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '카페 아메리카노',
                price: '4,700원',
                description: '진한 에스프레소와 물',
                imageAssetPath: 'assets/place_details/starbucks_reserve_menu.jpg',
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

    testWidgets('menu card supports a menu without optional fields', (tester) async {
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

    testWidgets('business information displays each key-value row', (tester) async {
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
      expect(find.text('서울 영등포구 여의대로 108'), findsOneWidget);
      expect(find.text('주차 지원 불가'), findsOneWidget);
    });
  });
}
