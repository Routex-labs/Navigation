import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/korean_line_break.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/place_detail_sections.dart';

void main() {
  Widget subject(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('Place detail section renderers', () {
    testWidgets('summary renders its supplied text', (tester) async {
      await tester.pumpWidget(
        subject(const PlaceSummarySection(text: '한 줄 소개')),
      );

      expect(find.text(keepWordsWhole('한 줄 소개')), findsOneWidget);
    });

    testWidgets('key-value section renders each label and value', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceKeyValueSection(
            items: [
              PlaceKeyValue(label: '위치', value: 'B2 서편'),
              PlaceKeyValue(label: '안내', value: '에스컬레이터 옆'),
            ],
          ),
        ),
      );

      expect(find.text('위치'), findsOneWidget);
      expect(find.text(keepWordsWhole('B2 서편')), findsOneWidget);
      expect(find.text('안내'), findsOneWidget);
      expect(find.text(keepWordsWhole('에스컬레이터 옆')), findsOneWidget);
    });

    testWidgets('tags are individually visible chips', (tester) async {
      await tester.pumpWidget(
        subject(const PlaceTagsSection(tags: ['포장', '문화비소득공제'])),
      );

      expect(find.text('포장'), findsOneWidget);
      expect(find.text('문화비소득공제'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('notice exposes the message and expiry date', (tester) async {
      await tester.pumpWidget(
        subject(const PlaceNoticeSection(text: '팝업 운영', until: '2026-08-31')),
      );

      expect(find.text(keepWordsWhole('팝업 운영')), findsOneWidget);
      expect(find.text('2026-08-31까지'), findsOneWidget);
    });

    // 탭 핸들러가 없는 블록이라 버튼처럼 보이면 안 된다.
    testWidgets(
      'map section is a local visual hint without an image provider',
      (tester) async {
        await tester.pumpWidget(
          subject(const PlaceMapSection(floorLabel: 'B2')),
        );

        expect(find.text('B2 위치'), findsOneWidget);
        expect(find.byIcon(Icons.place_outlined), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      },
    );
  });
}
