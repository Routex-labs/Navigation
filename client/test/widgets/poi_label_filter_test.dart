import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/map/floor_facility_style.dart';

/// POI 이름 라벨 필터가 지키는 것은 하나다 — **사람에게 보여 줄 이름이 아닌 것을
/// 그리지 않는다.** 수직이동 POI의 `name`은 Studio 원본의 노드 식별자라
/// (`ES3-UP(TO2F)`·`EV1`) 도면에 그대로 나가면 매장명 사이에 영문 내부 코드가
/// 수십 개 뜬다.
void main() {
  test('수직이동 POI는 이름을 그리지 않는다', () {
    final filter = poiLabelFilter();

    expect(filter.first, 'all');
    for (final type in ['elevator', 'escalator', 'vertical-connection']) {
      expect(
        filter,
        // 중첩 리스트라 `contains`의 기본 `==`(동일성)로는 안 잡힌다.
        contains(
          equals([
            '!=',
            ['get', 'type'],
            type,
          ]),
        ),
        reason: '$type POI 이름은 Studio 내부 코드라 화면에 나가면 안 된다',
      );
    }
  });

  test('화장실·출구처럼 이름이 정보인 POI는 걸러내지 않는다', () {
    // 필터가 `type` 하나만 보므로, 막는 목록에 없는 type은 통과한다.
    // 목록이 늘어나 화장실까지 막히는 회귀를 여기서 잡는다.
    expect(kVerticalTransportPoiTypes, isNot(contains('toilet')));
    expect(kVerticalTransportPoiTypes, isNot(contains('exit')));
    expect(kVerticalTransportPoiTypes, isNot(contains('core-entrance')));
  });

  test('아이콘 매핑이 아는 수직이동 type은 모두 막혀 있다', () {
    // 아이콘은 붙는데 이름만 새는 상태를 막는다 — 새 데이터셋 대응으로
    // [kPoiIconByType]에 수직이동 type을 추가하면 여기서 걸린다.
    for (final type in kPoiIconByType.keys) {
      final isVertical =
          kPoiIconByType[type]!.codePoint ==
          kPoiIconByType['elevator']!.codePoint;
      if (!isVertical) continue;
      expect(
        kVerticalTransportPoiTypes,
        contains(type),
        reason: '$type은 엘리베이터 아이콘을 쓰는데 이름 필터에 빠져 있다',
      );
    }
  });
}
