import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/app_menu_sheet.dart';

/// 햄버거 메뉴가 "목록"으로서 갖춰야 할 것을 고정한다.
///
/// 이 시트는 스스로 아무 동작도 하지 않고 고른 항목만 돌려준다. 그래서 검증
/// 기준은 두 가지다 — (1) 필요한 항목이 빠짐없이 떠 있는가, (2) 탭이 정확히
/// 그 항목의 [AppMenuAction]으로 되돌아오는가. 하나라도 어긋나면 메뉴는 있는데
/// 눌러도 엉뚱한 게 열리는, 가장 알아채기 어려운 형태로 깨진다.
void main() {
  Future<AppMenuAction?> openMenu(
    WidgetTester tester, {
    bool showPlaceLocation = true,
    bool debugEnabled = false,
  }) async {
    AppMenuAction? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await AppMenuSheet.show(
                  context,
                  showPlaceLocation: showPlaceLocation,
                  debugEnabled: debugEnabled,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('메뉴는 찾기·내 위치·개발자 항목을 목록으로 보여준다', (tester) async {
    await openMenu(tester);

    expect(find.text('저장한 장소'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('지도에서 내 위치 지정'), findsOneWidget);
    expect(find.text('위치 보정'), findsOneWidget);
    expect(find.text('디버그 설정'), findsOneWidget);
    // 어느 서버에 붙어 있는지는 진단의 밑바닥이라 토글이 아니라 항상 보인다.
    expect(find.textContaining('서버 · '), findsOneWidget);
    expect(find.textContaining('빌드 · '), findsOneWidget);
  });

  testWidgets('건물 밖에서는 위치 지정 항목을 감춘다', (tester) async {
    // 지정할 층이 없는 상태에서 눌러도 아무 일이 일어나지 않는 항목이다.
    // 하단 바의 같은 버튼과 노출 조건을 맞춘다.
    await openMenu(tester, showPlaceLocation: false);

    expect(find.text('지도에서 내 위치 지정'), findsNothing);
    expect(find.text('위치 보정'), findsOneWidget);
  });

  testWidgets('디버그 모드를 켜 두면 메뉴가 그 사실을 알린다', (tester) async {
    // 켜 둔 걸 잊은 채 지도에 진단 레이어가 겹쳐 보이는 상태를 여기서 알아챈다.
    await openMenu(tester, debugEnabled: true);

    expect(find.text('사용 중 · PDR 제어와 진단 레이어가 지도에 표시됩니다'), findsOneWidget);
  });

  testWidgets('항목을 누르면 그 항목의 동작이 그대로 돌아온다', (tester) async {
    for (final (key, expected) in <(String, AppMenuAction)>[
      ('app-menu-favorites', AppMenuAction.favorites),
      ('app-menu-directions', AppMenuAction.directions),
      ('app-menu-place-location', AppMenuAction.placeLocation),
      ('app-menu-calibrate', AppMenuAction.calibrate),
      ('app-menu-debug', AppMenuAction.debugSettings),
    ]) {
      AppMenuAction? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await AppMenuSheet.show(
                    context,
                    showPlaceLocation: true,
                    debugEnabled: false,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();

      expect(picked, expected, reason: key);
    }
  });
}
