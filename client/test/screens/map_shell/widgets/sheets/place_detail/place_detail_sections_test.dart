import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/place_detail_sections.dart';
import 'package:routex_design_system/routex_design_system.dart';

void main() {
  Widget subject(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('Place detail section renderers', () {
    testWidgets('summary renders its supplied text', (tester) async {
      await tester.pumpWidget(
        subject(const PlaceSummarySection(text: '한 줄 소개')),
      );

      expect(
        find.text(RoutexTypography.keepWordsWhole('한 줄 소개')),
        findsOneWidget,
      );
    });

    testWidgets('summary balances a paragraph without adding a line', (
      tester,
    ) async {
      const text =
          '1979년, 돌과 바람이 전부였던 제주의 땅에서 시작해 최고의 차를 '
          '생산하기까지, 오설록의 차가 특별한 이유를 만나보세요.';
      await tester.pumpWidget(
        subject(
          const SizedBox(width: 350, child: PlaceSummarySection(text: text)),
        ),
      );

      final rendered = tester.widget<Text>(find.byType(Text).last).data!;
      expect(rendered, contains('\n'));
      expect(rendered.split('\n').last.length, greaterThan(10));
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
      expect(
        find.text(RoutexTypography.keepWordsWhole('B2 서편')),
        findsOneWidget,
      );
      expect(find.text('안내'), findsOneWidget);
      expect(
        find.text(RoutexTypography.keepWordsWhole('에스컬레이터 옆')),
        findsOneWidget,
      );
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

      expect(
        find.text(RoutexTypography.keepWordsWhole('팝업 운영')),
        findsOneWidget,
      );
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
