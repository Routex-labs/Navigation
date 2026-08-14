import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 파일 **머리** 주석의 길이 상한.
///
/// 8줄이면 "한 문장 요약 + 지켜야 할 규칙 + 문서 경로"에 맞고, 파일을 열었을 때
/// 코드 첫 줄이 한 화면 안에 남는다. 처음엔 20줄이었는데 그 상한 아래에서도 머리가
/// 13줄까지 자라 있었다 — 상한은 실제 최대치 바로 위에 둬야 다시 자라지 않는다.
const _maxHeaderCommentLines = 8;

/// **한 덩어리** 주석의 길이 상한(머리 포함, 파일 어디서든).
///
/// 툴팁에 들어가는 길이가 기준이다. 이보다 길어진다는 건 그 자리에 설계 서사를
/// 쓰고 있다는 뜻이고, 서사는 `docs/`에 두고 경로로 가리켜야 한다.
///
/// 13은 지금 저장소의 최대치다. 낮추고 싶으면 먼저 코드를 줄이고 이 값을 내린다 —
/// 반대로 하면 통과시키려고 근거를 지우게 되고, 그러면 같은 실수를 다시 한다.
const _maxCommentBlockLines = 13;

/// 이 검사가 있는 이유.
///
/// 한때 `client/lib`에는 10줄이 넘는 머리 주석이 57개(1,122줄) 있었고 가장 긴
/// 것은 52줄이었다 — 그 파일은 전체가 72줄이라 **코드보다 주석이 앞에 더 많았다.**
/// 같은 것을 재 보면 Flutter SDK(`packages/flutter/lib/src/material`, 198파일)에는
/// 10줄 넘는 머리 주석이 **0개**다. Dart는 긴 설명을 파일 머리가 아니라 **선언
/// 위**에 두고(IDE 툴팁·`dart doc`이 거기서 읽는다), 설계 서사는 문서로 뺀다.
///
/// 주석 **총량**은 문제가 아니다. 재 보면 우리 비율(25%)은 Flutter material
/// (28.8%)·widgets(43.7%)과 같은 대역이다. 그래서 이 검사는 총량이 아니라
/// **한 자리에 쌓인 벽**만 잡는다.
void main() {
  test('lib/의 파일 머리 주석은 $_maxHeaderCommentLines줄을 넘지 않는다', () {
    final offenders = <String>[];

    for (final file in _dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      var length = 0;
      // 파일 첫 줄부터 이어지는 주석만 센다. 빈 줄이나 코드가 나오면 끝이다.
      // `// ignore_for_file`도 포함해서 센다 — 읽는 사람에게는 그것도 코드 첫
      // 줄까지 넘겨야 하는 줄이다.
      for (final line in lines) {
        if (!line.trimLeft().startsWith('//')) break;
        length++;
      }
      if (length > _maxHeaderCommentLines) {
        offenders.add('  ${file.path}: $length줄');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '파일 머리 주석이 $_maxHeaderCommentLines줄을 넘었다.\n'
          '${offenders.join('\n')}\n\n'
          '머리에는 한 문장 요약과 계약만 두고, "왜 이 설계인가"·버린 대안·측정\n'
          '로그는 docs/ 로 옮긴 뒤 경로를 한 줄로 가리킨다. 계약 수준의 설명은\n'
          '파일 머리가 아니라 **그 선언 위**에 두면 IDE 툴팁에서도 읽힌다.',
    );
  });

  test('lib/의 주석 한 덩어리는 $_maxCommentBlockLines줄을 넘지 않는다', () {
    final offenders = <String>[];

    for (final file in _dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      // 빈 줄이나 코드가 끼면 덩어리가 끊긴다. `///`와 `//`를 가르지 않는 이유는
      // 읽는 사람에게 둘 다 "코드가 나오기 전에 읽어야 하는 줄"이라서다.
      int? start;
      for (var i = 0; i <= lines.length; i++) {
        final isComment =
            i < lines.length && lines[i].trimLeft().startsWith('//');
        if (isComment) {
          start ??= i;
          continue;
        }
        if (start != null && i - start > _maxCommentBlockLines) {
          offenders.add('  ${file.path}:${start + 1}: ${i - start}줄');
        }
        start = null;
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '주석 한 덩어리가 $_maxCommentBlockLines줄을 넘었다.\n'
          '${offenders.join('\n')}\n\n'
          '선언 위 주석은 호출 계약(입력 범위·null의 뜻·실패 조건)까지다. 실측\n'
          '로그·버린 대안·검증 기준 표는 docs/ 에 두고 경로로 가리킨다 —\n'
          '지우라는 뜻이 아니라 자리를 옮기라는 뜻이다(AGENTS.md 「주석」).',
    );
  });
}

Iterable<File> _dartFilesUnder(String relativePath) sync* {
  // 테스트는 `client/`에서 돈다(`flutter test`의 작업 디렉터리).
  final root = Directory(relativePath);
  if (!root.existsSync()) {
    fail('$relativePath 를 찾지 못했다. 이 테스트는 client/ 에서 돌아야 한다.');
  }
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}
