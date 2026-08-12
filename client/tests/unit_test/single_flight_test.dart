import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/single_flight.dart';

void main() {
  test('돌고 있는 동안 들어온 요청은 실행하지 않는다', () async {
    final flight = SingleFlight();
    final gate = Completer<void>();
    var ran = 0;
    var duplicates = 0;

    final first = flight.run(() async {
      ran++;
      await gate.future;
    });
    // 첫 요청이 끝나기 전에 두 번 더 밀어 넣는다 — 실기기에서 본 모양이다.
    await flight.run(() async => ran++, onDuplicate: () => duplicates++);
    await flight.run(() async => ran++, onDuplicate: () => duplicates++);

    expect(ran, 1);
    expect(duplicates, 2);

    gate.complete();
    await first;
  });

  test('끝나면 다시 실행할 수 있다 — 한 번 쓰고 잠기면 안 된다', () async {
    final flight = SingleFlight();
    var ran = 0;

    await flight.run(() async => ran++);
    await flight.run(() async => ran++);

    expect(ran, 2);
    expect(flight.isBusy, isFalse);
  });

  test('작업이 예외를 던져도 잠금이 풀린다', () async {
    final flight = SingleFlight();

    // 여기서 새면 그 뒤로 대중교통이 영영 안 눌리는데, 화면에는 아무 반응이
    // 없어 원인을 찾기가 가장 어렵다.
    await expectLater(
      flight.run(() async => throw StateError('네트워크 실패')),
      throwsStateError,
    );

    expect(flight.isBusy, isFalse);
    var ran = 0;
    await flight.run(() async => ran++);
    expect(ran, 1);
  });

  test('onDuplicate를 안 줘도 조용히 버린다', () async {
    final flight = SingleFlight();
    final gate = Completer<void>();
    var ran = 0;

    final first = flight.run(() async {
      ran++;
      await gate.future;
    });
    await flight.run(() async => ran++);

    expect(ran, 1);
    gate.complete();
    await first;
  });
}
