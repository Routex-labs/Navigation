import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/search/name_siblings.dart';
import 'package:navigation_client/domain/search/store_suggestions.dart';
import 'package:navigation_client/models/store_index_entry.dart';

/// 설계와 검증 기준은 `docs/client/search-result-list-ux.md` S절이 단일 출처다.

StoreSuggestion _suggestion(
  String name, {
  SuggestionKind kind = SuggestionKind.prefix,
  String floor = '1F',
}) => (
  stores: [
    StoreIndexEntry(
      id: 'PO-$name',
      name: name,
      floorId: 'FL-$floor',
      floorName: floor,
      entranceNodeId: 'ND-$name',
    ),
  ],
  kind: kind,
);

List<String> _names(List<StoreSuggestion> list) => [
  for (final s in list) s.stores.first.name,
];

void main() {
  group('S. 확정된 매장의 형제 고르기', () {
    test('확정된 매장을 빼고 나머지를 순서 그대로 돌려준다', () {
      final result = nameSiblings(
        suggestions: [
          _suggestion('구찌'),
          _suggestion('구찌 뷰티'),
          _suggestion('구찌 선글라스', floor: '2F'),
        ],
        confirmedName: '구찌',
      );

      expect(_names(result), ['구찌 뷰티', '구찌 선글라스']);
    });

    test('확정된 매장이 목록 중간에 있어도 정확히 하나만 빠진다', () {
      final result = nameSiblings(
        suggestions: [
          _suggestion('타임 닥터'),
          _suggestion('타임'),
          _suggestion('타임옴므'),
        ],
        confirmedName: '타임',
      );

      expect(_names(result), ['타임 닥터', '타임옴므']);
    });

    // 표기만 다른 같은 이름을 서로 다른 매장으로 세면 같은 줄이 두 번 그려진다.
    // 후보를 묶을 때 쓴 정규화(storeMatchKey)와 같은 잣대여야 한다.
    test('표기가 달라도 같은 이름이면 빠진다', () {
      final result = nameSiblings(
        suggestions: [_suggestion('물품 보관함'), _suggestion('물품보관함 B')],
        confirmedName: '물품보관함',
      );

      expect(_names(result), ['물품보관함 B']);
    });

    test('형제가 없으면 빈 목록이다', () {
      expect(
        nameSiblings(suggestions: [_suggestion('크록스')], confirmedName: '크록스'),
        isEmpty,
      );
    });
  });

  group('S. 적용하지 않는 경우', () {
    // 서버는 카테고리로도 확정한다(tier 1). 그때 후보 목록에 든 것들은 그 매장의
    // 형제가 아니라 이름에 질의가 든 남남이다.
    test('확정된 매장이 후보에 없으면 형제를 만들지 않는다', () {
      final result = nameSiblings(
        suggestions: [_suggestion('커피 리브레'), _suggestion('커피빈')],
        confirmedName: '블루보틀',
      );

      expect(result, isEmpty);
    });

    // 교정은 "표기가 비슷한 이름이 있다"는 추측이다. 서버가 정답을 확정한 화면에
    // 추측을 형제라며 얹지 않는다.
    test('교정 후보는 형제가 아니다', () {
      final result = nameSiblings(
        suggestions: [
          _suggestion('구찌'),
          _suggestion('구지', kind: SuggestionKind.correction),
          _suggestion('구찌 뷰티'),
        ],
        confirmedName: '구찌',
      );

      expect(_names(result), ['구찌 뷰티']);
    });

    // 교정 후보만 남으면 결과적으로 형제가 없다.
    test('교정 후보만 있으면 빈 목록이다', () {
      expect(
        nameSiblings(
          suggestions: [
            _suggestion('구찌'),
            _suggestion('구지', kind: SuggestionKind.correction),
          ],
          confirmedName: '구찌',
        ),
        isEmpty,
      );
    });

    // 인덱스를 못 받았거나(로드 실패) 야외라 후보를 안 만든 경우.
    test('후보가 없으면 빈 목록이다', () {
      expect(nameSiblings(suggestions: const [], confirmedName: '구찌'), isEmpty);
    });

    // 구두점만 있는 이름은 정규화하면 아무것도 안 남는다. 빈 키로 비교하면
    // 아무 후보나 "같은 이름"이 된다.
    test('정규화하면 비는 이름은 형제를 만들지 않는다', () {
      expect(
        nameSiblings(suggestions: [_suggestion('구찌')], confirmedName: '...'),
        isEmpty,
      );
    });
  });
}
