import 'package:flutter_test/flutter_test.dart';

import 'package:navigation_client/widgets/category_icon.dart';
import 'package:navigation_client/widgets/category_map_icon.dart';
import 'package:navigation_client/widgets/floor_facility_style.dart';

/// 지도 라벨에 붙는 대분류 아이콘의 규칙을 못 박는다.
///
/// 여기서 지키는 것은 셋이다.
///
/// 1. **아이콘이 두 개 뜨지 않는다.** 편의시설은 전용 아이콘 레이어가 이미
///    있으므로, 대분류 아이콘이 붙는 라벨 레이어에서 반드시 빠져야 한다.
/// 2. **이름이 아이콘 앞/뒤로 뒤집힌다.** `text-variable-anchor`가 두 값을
///    가져야 하고, 순서가 선호도다.
/// 3. **모든 대분류가 자기 아이콘을 갖는다.** 표현식에서 빠진 카테고리는 조용히
///    폴백 아이콘이 되어, 화면에서는 "분류가 없는 매장"과 구분되지 않는다.
void main() {
  /// `['==', ['get', 'name'], <값>]` 꼴에서 <값>만 뽑는다.
  List<String> nameOperands(List<Object> filter) => filter
      .skip(1) // 맨 앞의 'all'/'any'
      .cast<List<Object>>()
      .map((clause) => clause[2] as String)
      .toList();

  group('아이콘 표현식', () {
    test('모든 대분류가 자기 아이콘 이름을 갖는다', () {
      final expression = storeCategoryIconExpression();
      for (final category in categoryIconCategories) {
        expect(
          expression,
          contains(storeCategoryIconImageName(category)),
          reason:
              '$category가 표현식에서 빠지면 그 매장들이 폴백 아이콘으로 떨어진다. '
              '화면에서는 분류가 아예 없는 매장과 구분되지 않아 조용히 틀린다.',
        );
      }
    });

    test('match의 default는 폴백 아이콘이다', () {
      // match 표현식의 마지막 원소가 default. 분류가 없는 매장은 타일에
      // category 키 자체가 없어 여기로 떨어진다.
      expect(
        storeCategoryIconExpression().last,
        storeCategoryIconImageName(kStoreCategoryFallbackKey),
      );
    });

    test('match의 label 자리에는 문자열만 들어간다', () {
      // 배열을 label로 쓰는 형태는 MapLibre GL Native에서 조용히 매치 0건이 되는
      // 경로가 있다(category_map_filter.dart 주석). 이 규칙이 깨지면 실기기에서만
      // 아이콘이 전부 사라지고 웹에서는 멀쩡해 보인다.
      final expression = storeCategoryIconExpression();
      // [0] = 'match', [1] = ['get', 'category'], 이후 label/value 쌍, 마지막 default.
      for (var i = 2; i < expression.length - 1; i += 2) {
        expect(expression[i], isA<String>());
      }
    });

    test('등록 대상에 폴백이 포함된다', () {
      // 폴백 비트맵을 등록하지 않으면 분류 없는 매장이 아이콘 없이 그려지고
      // 로그도 남지 않는다.
      expect(storeCategoryIconKeys, contains(kStoreCategoryFallbackKey));
      expect(
        storeCategoryIconKeys.toSet().length,
        storeCategoryIconKeys.length,
        reason: '이름이 중복되면 addImage가 뒤엣것을 버린다.',
      );
    });
  });

  group('이름이 아이콘 앞/뒤로 뒤집힌다', () {
    test('앵커가 두 방향을 갖고, 오른쪽이 먼저다', () {
      // 값이 하나면 뒤집기가 아예 없고, 순서가 바뀌면 자리가 남는데도 이름이
      // 왼쪽에 붙어 읽는 방향과 어긋난다.
      expect(kStoreLabelVariableAnchor, ['left', 'right']);
    });

    test('아이콘과 글자 사이 여백이 붙지도 벌어지지도 않는다', () {
      // 이 값은 **아이콘 가장자리부터의 여백**이지 심볼 중심에서의 거리가
      // 아니다. 중심 거리로 오해해 아이콘 반지름/글자크기(≈0.85)를 넣었더니
      // 실기기에서 간격이 27px까지 벌어져 아이콘과 이름이 따로 놀았다.
      //
      // 실측으로 약 31.7px/em이라, 0.35를 넘으면 11px 이상 벌어진다.
      expect(kStoreLabelRadialOffset, greaterThan(0));
      expect(
        kStoreLabelRadialOffset,
        lessThanOrEqualTo(0.35),
        reason: '아이콘 반지름 기준으로 계산한 값을 다시 넣지 말 것 — 그 가정은 틀렸다.',
      );
    });

    test('아이콘이 이름보다 커지지 않는다', () {
      // 아이콘 폭이 심볼 폭에 그대로 더해져 붐비는 층의 라벨 개수를 깎는다.
      // 글자 크기의 1.5배를 넘기면 도면이 아이콘 밭이 되고 이름이 밀려난다.
      const textSizeAtZ16 = 9.0;
      const textSizeAtZ20 = 14.0;
      const canvasSize = 96.0;
      expect(
        (kStoreCategoryIconSizeIndoor[4] as double) * canvasSize,
        lessThan(textSizeAtZ16 * 1.5),
      );
      expect(
        (kStoreCategoryIconSizeIndoor[6] as double) * canvasSize,
        lessThan(textSizeAtZ20 * 1.5),
      );
    });
  });

  group('라벨 필터 — 아이콘이 두 개 뜨지 않는다', () {
    test('수직이동 시설은 매장명 라벨에서 빠진다', () {
      final excluded = nameOperands(storeLabelWithCategoryIconFilter());
      for (final name in kVerticalTransportStoreNames) {
        expect(excluded, contains(name));
      }
    });

    test('편의시설도 매장명 라벨에서 빠진다', () {
      final excluded = nameOperands(storeLabelWithCategoryIconFilter());
      for (final name in kStoreFacilityStyleByName.keys) {
        expect(
          excluded,
          contains(name),
          reason:
              '$name은 전용 아이콘 레이어가 이미 아이콘을 그린다. 여기서 빼지 않으면 '
              '같은 폴리곤에 시설 아이콘과 대분류 아이콘이 둘 다 뜬다.',
        );
      }
    });

    test('편의시설 라벨 필터는 뺀 집합을 정확히 되받는다', () {
      // 한쪽만 고치면 시설 이름이 지도에서 통째로 사라지거나(빼기만 하고 되받지
      // 않음) 아이콘이 두 개가 된다(되받기만 하고 빼지 않음).
      expect(
        nameOperands(facilityStoreLabelFilter()).toSet(),
        kStoreFacilityStyleByName.keys.toSet(),
      );
    });

    test('두 필터는 겹치지 않는다', () {
      final labelled = nameOperands(storeLabelWithCategoryIconFilter()).toSet();
      final facility = nameOperands(facilityStoreLabelFilter()).toSet();
      // 매장명 라벨 필터는 `!=`의 all이라 여기 적힌 이름이 곧 제외 대상이다.
      // 편의시설 필터가 고르는 이름은 전부 그 제외 목록 안에 있어야 한다.
      expect(facility.difference(labelled), isEmpty);
    });

    test('필터 형태는 == / != 비교만 쓴다', () {
      for (final filter in [
        storeLabelWithCategoryIconFilter(),
        facilityStoreLabelFilter(),
      ]) {
        for (final clause in filter.skip(1).cast<List<Object>>()) {
          expect(clause[0], anyOf('==', '!='));
          expect(clause[1], ['get', 'name']);
        }
      }
    });
  });

  testWidgets('아이콘 비트맵이 PNG로 만들어진다', (tester) async {
    // **runAsync가 필수다.** testWidgets 본문은 FakeAsync 위에서 돌고,
    // `Picture.toImage`/`Image.toByteData`의 Future는 엔진이 실제 시간에
    // 완료시킨다. 가짜 시간에서 기다리면 절대 풀리지 않아 테스트가 통째로
    // 10분 타임아웃까지 매달린다(실패로 한 번 확인했다).
    final bytes = await tester.runAsync(
      () => renderStoreCategoryIconPng('패션'),
    );
    expect(bytes, isNotNull);
    expect(bytes!, isNotEmpty);
    // PNG 시그니처. addImage가 받는 형식이 아니면 지도에서 조용히 무시된다.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
