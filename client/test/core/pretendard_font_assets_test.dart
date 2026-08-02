import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('실제로 쓰는 Pretendard weight를 모두 번들한다', () {
    const assets = {
      'assets/fonts/Pretendard-Regular.otf': 400,
      'assets/fonts/Pretendard-Medium.otf': 500,
      'assets/fonts/Pretendard-SemiBold.otf': 600,
      'assets/fonts/Pretendard-Bold.otf': 700,
      'assets/fonts/Pretendard-ExtraBold.otf': 800,
    };
    final pubspec = File('pubspec.yaml').readAsStringSync();

    for (final entry in assets.entries) {
      expect(File(entry.key).existsSync(), isTrue, reason: entry.key);
      expect(pubspec, contains(entry.key));
      if (entry.value != 400) {
        expect(
          pubspec,
          contains('${entry.key}\n          weight: ${entry.value}'),
        );
      }
    }
  });

  test('UI·지도·목업 지도는 Pretendard만 참조한다', () {
    final appTheme = File('lib/theme/app_theme.dart').readAsStringSync();
    final mapFonts = File('lib/core/map_fonts.dart').readAsStringSync();
    final mockMaps = [
      'assets/mock/demo_floor_map_v5.svg',
      'assets/mock/hyundai_floor_map.svg',
    ].map((path) => File(path).readAsStringSync());

    expect(appTheme, contains("fontFamily: 'Pretendard'"));
    expect(mapFonts, contains("mapFontStackRegular = 'Pretendard Regular'"));
    for (final mockMap in mockMaps) {
      expect(mockMap, contains('Pretendard'));
      expect(mockMap, isNot(contains('Noto Sans CJK KR')));
      expect(mockMap, isNot(contains('NanumSquare')));
      expect(mockMap, isNot(contains('Apple SD Gothic Neo')));
    }
  });
}
