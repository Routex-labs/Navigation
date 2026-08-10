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
                    'assets/place_details/starbucks_store_01.jpg',
              ),
              PlaceHeroImage(
                assetPath:
                    'assets/place_details/starbucks_store_04.jpg',
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

    // 한 줄에 이름·영문명·설명·가격이 다 오면 무엇이 제목인지 흐려진다. 영문명은
    // 골라서 팝업을 연 사람에게만 필요하다.
    testWidgets('menu row drops the english name and keeps the description', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '리저브 콜드 브루',
                nameEn: 'Reserve Cold Brew',
                description: '깊고 부드러운 풍미의 커피',
                volume: '355ml',
                calories: '5kcal',
                caffeine: '190mg',
                imageAssetPath:
                    'assets/place_details/starbucks_menu_americano.jpg',
              ),
            ],
          ),
        ),
      );

      expect(find.text('메뉴'), findsOneWidget);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('깊고 부드러운 풍미의 커피'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      // 줄에는 없다. 여기가 새면 제목이 다시 흐려진 것이다.
      expect(find.text('Reserve Cold Brew'), findsNothing);
      expect(find.textContaining('355ml'), findsNothing);
      expect(find.textContaining('5kcal'), findsNothing);
    });

    // 가격은 설명 아래에 온다. 지금 데이터에는 없지만 자리는 계약으로 고정한다 —
    // 공식 가격 출처가 생기면 데이터만 채우면 되게.
    testWidgets('menu row shows the price under the description', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '카페 아메리카노',
                description: '진한 에스프레소와 물',
                price: '4,700원',
              ),
            ],
          ),
        ),
      );

      expect(find.text('4,700원'), findsOneWidget);
    });

    testWidgets('tapping a card opens the detail popup', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '리저브 콜드 브루',
                nameEn: 'Reserve Cold Brew',
                description: '깊고 부드러운 풍미의 커피',
                volume: '355ml',
                calories: '5kcal',
                caffeine: '190mg',
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('리저브 콜드 브루'));
      await tester.pumpAndSettle();

      expect(find.text(keepWordsWhole('깊고 부드러운 풍미의 커피')), findsOneWidget);
      expect(find.text('355ml'), findsOneWidget);
      expect(find.text('5kcal'), findsOneWidget);
      expect(find.text('190mg'), findsOneWidget);
      expect(find.text('용량'), findsOneWidget);
    });

    // 푸드에는 영양정보가 없다. 라벨만 남은 빈 표를 그리면 "정보가 없다"가 아니라
    // "못 불러왔다"로 읽힌다.
    testWidgets('popup omits the nutrition block when there is none', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '플레인 베이글', description: '담백한 베이글'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('플레인 베이글'));
      await tester.pumpAndSettle();

      expect(find.text(keepWordsWhole('담백한 베이글')), findsOneWidget);
      expect(find.text('용량'), findsNothing);
      expect(find.text('칼로리'), findsNothing);
      expect(find.text('카페인'), findsNothing);
    });

    // 눌렀는데 카드에 이미 있는 이름만 다시 나오는 팝업은 막다른 길이다. 한 번
    // 겪으면 다음 카드도 안 누르게 되므로 아예 안 눌리게 한다.
    testWidgets('a card with nothing more to show is not tappable', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [PlaceMenuItem(name: '오늘의 커피', nameEn: 'Coffee of the Day')],
          ),
        ),
      );

      await tester.tap(find.text('오늘의 커피'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });

    // 카드 높이를 상수로 박아 두면 기기 글자 크기 설정이 커졌을 때 넘친다. 실제로
    // `BOTTOM OVERFLOWED BY 2.0 PIXELS`가 떴다.
    testWidgets('menu card does not overflow at a large text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: PlaceMenuSection(
                  items: [
                    PlaceMenuItem(
                      name: '초콜릿 크림 칩 프라푸치노',
                      nameEn: 'Chocolate Cream Chip Frappuccino',
                      volume: '355ml',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    // 메뉴 사진은 402x420이라 폭에 맞춰 채우면 세로가 42% 잘린다. 잘린 사진은
    // 아무도 못 알아채므로(컵 윗부분이 원래 그런 줄 안다) 계약으로 고정한다.
    testWidgets('menu photo is not cropped', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '카페 아메리카노',
                imageAssetPath:
                    'assets/place_details/starbucks_menu_americano.jpg',
              ),
            ],
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);

      // 사진 영역이 원본 비율(402/420)을 따라야 여백도 잘림도 없다.
      final box = tester.getSize(find.byType(Image));
      expect(box.width / box.height, closeTo(402 / 420, 0.01));
    });

    // 세로 목록이라 줄이 늘어날수록 다른 섹션이 화면 밖으로 밀린다. 상한을 넘는
    // 만큼은 더보기 뒤로 보낸다.
    testWidgets('a category over the cap gets a 더보기 row', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 6; index++)
                PlaceMenuItem(name: '메뉴 $index', description: '설명 $index'),
            ],
          ),
        ),
      );

      expect(find.text('더보기'), findsOneWidget);
      expect(find.text('메뉴 0'), findsOneWidget);
      expect(find.text('메뉴 4'), findsNothing);
      // 개수는 적지 않는다. 눌러서 나온 목록에 이미 전부 있다.
      expect(find.text('6종'), findsNothing);
    });

    testWidgets('a category within the cap has no 더보기 row', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 4; index++)
                PlaceMenuItem(name: '메뉴 $index'),
            ],
          ),
        ),
      );

      expect(find.text('더보기'), findsNothing);
    });

    // 팝업으로 띄우지 않고 그 자리에서 펼친다. 목록을 보러 팝업을 여는 것은
    // 목록을 두 번 만드는 일이다.
    testWidgets('더보기 expands the rest in place', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 6; index++)
                PlaceMenuItem(name: '메뉴 $index', description: '설명 $index'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('더보기'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      for (var index = 0; index < 6; index++) {
        expect(find.text('메뉴 $index'), findsOneWidget);
      }
      // 다 펼쳤으면 더보기는 사라진다.
      expect(find.text('더보기'), findsNothing);
    });

    // 탭을 옮기면 다시 접는다. 카테고리마다 펼침 상태를 들고 있으면, 돌아왔을 때
    // 어디까지 펼쳤는지 기억나지 않는 목록이 열려 있다.
    testWidgets('changing the category collapses the list again', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 6; index++)
                PlaceMenuItem(name: '리저브 $index', category: '리저브'),
              PlaceMenuItem(name: '아메리카노', category: '에스프레소'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('더보기'));
      await tester.pumpAndSettle();
      expect(find.text('리저브 5'), findsOneWidget);

      await tester.tap(find.text('에스프레소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('리저브').last);
      await tester.pumpAndSettle();

      expect(find.text('더보기'), findsOneWidget);
      expect(find.text('리저브 5'), findsNothing);
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
      expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
      expect(find.byIcon(Icons.local_parking_outlined), findsOneWidget);
      expect(find.text('2026-08-10 확인'), findsOneWidget);
      // 라벨은 아이콘이 대신하므로 글자로 남지 않는다.
      expect(find.text('영업시간'), findsNothing);
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

      expect(find.text('2026-08-10 확인'), findsOneWidget);
      expect(find.text('2026-07-30 확인'), findsOneWidget);
    });

    // 링크는 앱 밖으로 나간다. 그 사실이 줄에서 보여야 해서 화살표(>)가 아니라
    // 바깥으로 나가는 아이콘을 쓴다.
    testWidgets('links show a label and an external-link affordance', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceLinksSection(
            items: [
              PlaceLinkItem(
                label: '공식 사이트',
                url: 'https://www.starbucks.co.kr/index.do',
              ),
              PlaceLinkItem(
                label: '인스타그램',
                url: 'https://www.instagram.com/starbuckskorea',
              ),
            ],
          ),
        ),
      );

      expect(find.text('링크'), findsOneWidget);
      expect(find.text('공식 사이트'), findsOneWidget);
      expect(find.text('인스타그램'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
      expect(find.byIcon(Icons.language_outlined), findsOneWidget);
    });

    testWidgets('business information replaces the label with an icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceBusinessInfoSection(
            items: [
              PlaceBusinessInfo(label: '주소', value: '서울 영등포구 여의대로 108'),
            ],
          ),
        ),
      );

      expect(find.text('매장 정보'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsOneWidget);
      expect(find.text('주소'), findsNothing);
      expect(find.text(keepWordsWhole('서울 영등포구 여의대로 108')), findsOneWidget);
    });

    // 데이터는 사람이 쓰는 자유 문자열이라 언제든 새 라벨이 들어온다. 아무 아이콘이나
    // 물리면 그 값이 무슨 뜻인지가 화면에서 사라지므로, 모르는 라벨은 글자로 남긴다.
    testWidgets('an unmapped label keeps its text', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceBusinessInfoSection(
            items: [
              PlaceBusinessInfo(label: '반려동물 동반', value: '가능'),
            ],
          ),
        ),
      );

      expect(find.text('반려동물 동반'), findsOneWidget);
      expect(find.text(keepWordsWhole('가능')), findsOneWidget);
    });
  });
}
