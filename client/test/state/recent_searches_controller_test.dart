import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/state/recent_searches_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 최근 검색어 저장소가 지켜야 할 것을 고정한다.
/// 스펙은 `docs/client/naver-map-ui-ux-analysis.md`의 「J. 검색 빈 상태(idle)
/// 채우기」가 단일 출처다.
///
/// 여기서 막으려는 실패는 네 가지다.
/// 1. **첫 실행이 오류처럼 보이는 것** — 저장된 값이 없는 상태는 정상이다.
/// 2. **저장소 실패가 앱을 죽이는 것** — 부가 기능이므로 빈 목록으로 degrade한다.
/// 3. **목록이 무한히 자라거나 같은 검색어가 쌓이는 것**.
/// 4. **공백뿐인 입력이 목록을 더럽히는 것**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<RecentSearchesController> createController() async {
    final controller = RecentSearchesController(
      prefs: await SharedPreferences.getInstance(),
    );
    await controller.ready;
    return controller;
  }

  group('첫 실행', () {
    test('저장된 검색어가 없으면 빈 목록이 정상 상태다', () async {
      // Given: 저장소에 아무것도 없는 첫 실행
      // When: 컨트롤러를 만들고 로드가 끝나면
      final controller = await createController();

      // Then: 예외 없이 빈 목록이고 로드는 완료 상태다
      expect(controller.queries, isEmpty);
      expect(controller.isLoaded, isTrue);
    });
  });

  group('검색어 추가', () {
    test('추가한 검색어가 최신순으로 앞에 온다', () async {
      // Given: 빈 목록
      final controller = await createController();

      // When: 두 건을 차례로 검색하면
      await controller.add('탠디');
      await controller.add('스타벅스');

      // Then: 마지막에 검색한 것이 맨 앞이다
      expect(controller.queries, ['스타벅스', '탠디']);
    });

    test('같은 검색어를 다시 검색하면 중복 없이 맨 앞으로 올라온다', () async {
      // Given: 세 건이 쌓인 목록
      final controller = await createController();
      await controller.add('탠디');
      await controller.add('스타벅스');
      await controller.add('올리브영');

      // When: 가장 오래된 검색어를 다시 검색하면
      await controller.add('탠디');

      // Then: 개수는 그대로이고 위치만 맨 앞으로 바뀐다
      expect(controller.queries, ['탠디', '올리브영', '스타벅스']);
    });

    test('앞뒤 공백·대소문자만 다른 검색어도 같은 것으로 본다', () async {
      // Given: 영문 검색어가 저장된 목록
      final controller = await createController();
      await controller.add('ZARA');

      // When: 대소문자와 공백만 다르게 다시 검색하면
      await controller.add('  zara ');

      // Then: 한 건만 남고, 저장되는 값은 마지막에 입력한 원문(공백만 제거)이다
      expect(controller.queries, ['zara']);
    });

    test('빈 문자열과 공백뿐인 입력은 저장하지 않는다', () async {
      // Given: 빈 목록
      final controller = await createController();

      // When: 빈 문자열·공백·줄바꿈만 있는 입력을 추가하면
      await controller.add('');
      await controller.add('   ');
      await controller.add('\n\t');

      // Then: 아무것도 쌓이지 않는다
      expect(controller.queries, isEmpty);
    });

    test('길이 상한을 넘는 검색어는 잘라 넣지 않고 통째로 무시한다', () async {
      // Given: 빈 목록
      final controller = await createController();

      // When: 상한을 넘는 문자열을 추가하면
      await controller.add('가' * (RecentSearchesController.maxQueryLength + 1));

      // Then: 저장되지 않는다(잘라 저장하면 탭했을 때 다른 검색이 실행된다)
      expect(controller.queries, isEmpty);
    });
  });

  group('보관 개수 상한', () {
    test('상한을 넘으면 가장 오래된 검색어부터 버린다', () async {
      // Given: 상한만큼 꽉 찬 목록
      final controller = await createController();
      for (var i = 1; i <= RecentSearchesController.maxEntries; i++) {
        await controller.add('검색어$i');
      }

      // When: 한 건을 더 검색하면
      await controller.add('새검색어');

      // Then: 개수는 상한을 넘지 않고, 가장 오래된 '검색어1'이 밀려난다
      expect(controller.queries.length, RecentSearchesController.maxEntries);
      expect(controller.queries.first, '새검색어');
      expect(controller.queries, isNot(contains('검색어1')));
      expect(controller.queries.last, '검색어2');
    });
  });

  group('삭제', () {
    test('개별 삭제는 해당 검색어만 지운다', () async {
      // Given: 두 건이 있는 목록
      final controller = await createController();
      await controller.add('탠디');
      await controller.add('스타벅스');

      // When: 한 건을 지우면
      await controller.remove('탠디');

      // Then: 나머지는 남는다
      expect(controller.queries, ['스타벅스']);
    });

    test('전체 삭제는 목록을 비운다', () async {
      // Given: 두 건이 있는 목록
      final controller = await createController();
      await controller.add('탠디');
      await controller.add('스타벅스');

      // When: 전체 삭제하면
      await controller.clear();

      // Then: 빈 목록이 되고 첫 실행과 같은 상태로 돌아간다
      expect(controller.queries, isEmpty);
      expect(controller.isLoaded, isTrue);
    });
  });

  group('영속화', () {
    test('앱을 다시 켜도 저장한 검색어가 최신순 그대로 복원된다', () async {
      // Given: 검색어를 저장한 세션
      final first = await createController();
      await first.add('탠디');
      await first.add('스타벅스');

      // When: 같은 저장소로 컨트롤러를 새로 만들면
      final restored = await createController();

      // Then: 순서까지 그대로 복원된다
      expect(restored.queries, ['스타벅스', '탠디']);
    });

    test('저장값이 손상됐으면 목록 전체를 버리지 않고 읽을 수 있는 것만 살린다', () async {
      // Given: 문자열이 아닌 항목이 섞여 저장된 상태
      SharedPreferences.setMockInitialValues({
        'recent_searches_v1': jsonEncode(['탠디', 42, null, '스타벅스']),
      });

      // When: 컨트롤러가 이를 읽으면
      final controller = await createController();

      // Then: 문자열만 남기고 예외 없이 로드된다
      expect(controller.queries, ['탠디', '스타벅스']);
    });

    test('JSON 자체가 깨져 있으면 조용히 빈 목록으로 시작한다', () async {
      // Given: JSON으로 파싱할 수 없는 값이 저장된 상태
      SharedPreferences.setMockInitialValues({'recent_searches_v1': '{깨진 값'});

      // When: 컨트롤러가 이를 읽으면
      final controller = await createController();

      // Then: 예외 대신 빈 목록이다
      expect(controller.queries, isEmpty);
      expect(controller.isLoaded, isTrue);
    });
  });

  group('저장소 실패', () {
    test('읽기가 실패해도 앱이 죽지 않고 빈 목록으로 degrade한다', () async {
      // Given: 모든 호출이 실패하는 저장소
      final controller = RecentSearchesController(prefs: _FailingPreferences());

      // When: 로드를 기다리면
      await controller.ready;

      // Then: 예외가 새어 나오지 않고 빈 목록이다
      expect(controller.queries, isEmpty);
      expect(controller.isLoaded, isTrue);
    });

    test('쓰기가 실패해도 이번 세션의 목록은 메모리에 남는다', () async {
      // Given: 모든 호출이 실패하는 저장소
      final controller = RecentSearchesController(prefs: _FailingPreferences());
      await controller.ready;

      // When: 검색어를 추가하면
      await controller.add('탠디');

      // Then: 저장은 못 해도 화면에 보여줄 목록은 유지된다
      expect(controller.queries, ['탠디']);
    });
  });
}

/// 기기 저장소가 없거나 고장 난 상황을 흉내 낸다. 어떤 메서드를 불러도 예외를
/// 던지므로, 읽기·쓰기 어느 쪽이 실패해도 컨트롤러가 버티는지 확인할 수 있다.
class _FailingPreferences implements SharedPreferences {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('저장소를 사용할 수 없다');
}
