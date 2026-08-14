import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/icon/icon_cache.dart';

/// 아이콘 캐시는 "같은 이름이면 한 번만 굽는다"와 "실패는 캐시하지 않는다"
/// 두 가지를 약속한다. 앞은 층 전환 속도의 근거이고, 뒤는 한 번의 렌더 실패가
/// 앱이 끝날 때까지 그 아이콘을 못 그리게 만드는 상태를 막는 안전장치다.
void main() {
  setUp(resetIconPngCacheForTest);

  test('같은 이름은 한 번만 굽는다', () async {
    var calls = 0;
    Future<Uint8List> render() async {
      calls++;
      return Uint8List.fromList([calls]);
    }

    expect(await cachedIconPng('a', render), Uint8List.fromList([1]));
    expect(await cachedIconPng('a', render), Uint8List.fromList([1]));
    expect(calls, 1);
  });

  test('이름이 다르면 따로 굽는다 — 디자인이 바뀌면 이름도 바뀐다', () async {
    var calls = 0;
    Future<Uint8List> render() async {
      calls++;
      return Uint8List.fromList([calls]);
    }

    expect(await cachedIconPng('a', render), Uint8List.fromList([1]));
    expect(await cachedIconPng('b', render), Uint8List.fromList([2]));
    expect(calls, 2);
  });

  test('같은 순간에 둘이 물어도 렌더는 한 번만 돈다', () async {
    var calls = 0;
    final completer = Completer<Uint8List>();
    Future<Uint8List> render() {
      calls++;
      return completer.future;
    }

    final first = cachedIconPng('a', render);
    final second = cachedIconPng('a', render);
    completer.complete(Uint8List.fromList([7]));

    expect(await first, Uint8List.fromList([7]));
    expect(await second, Uint8List.fromList([7]));
    expect(calls, 1);
  });

  test('실패는 캐시하지 않는다 — 다음 호출이 다시 굽는다', () async {
    var calls = 0;
    Future<Uint8List> flaky() async {
      calls++;
      if (calls == 1) throw StateError('첫 렌더 실패');
      return Uint8List.fromList([calls]);
    }

    await expectLater(cachedIconPng('a', flaky), throwsStateError);
    // 실패가 캐시에 남았다면 여기서도 같은 오류가 다시 나온다.
    expect(await cachedIconPng('a', flaky), Uint8List.fromList([2]));
    expect(calls, 2);
  });

  test('실패를 아무도 안 기다려도 처리되지 않은 비동기 오류로 새지 않는다', () async {
    // 캐시에서 지우려고 파생 future에서 오류를 다시 던지면, 그 파생 future는
    // 아무도 기다리지 않아 zone 오류로 샌다(테스트에서는 이 테스트의 실패로
    // 나타난다). 호출부가 오류를 제대로 받는 것과는 별개의 문제다.
    Future<Uint8List> failing() async => throw StateError('렌더 실패');

    await expectLater(cachedIconPng('a', failing), throwsStateError);
    // 파생 future의 오류가 마이크로태스크 큐를 통해 새어 나올 틈을 준다.
    await Future<void>.delayed(Duration.zero);
  });
}
