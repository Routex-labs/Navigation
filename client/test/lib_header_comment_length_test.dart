import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 파일 **머리** 주석의 길이 상한.
///
/// 20줄이면 "요약 + 계약 + 문서 링크"에 넉넉하다. 이걸 넘긴다는 건 설계 서사를
/// 코드 입구에 쌓고 있다는 뜻이고, 그러면 파일을 열 때마다 코드 첫 줄까지
/// 스크롤해야 한다.
const _maxHeaderCommentLines = 20;

/// 이 검사가 있는 이유.
///
/// 한때 `client/lib`에는 10줄이 넘는 머리 주석이 57개(1,122줄) 있었고 가장 긴
/// 것은 52줄이었다 — 그 파일은 전체가 72줄이라 **코드보다 주석이 앞에 더 많았다.**
/// 같은 것을 재 보면 Flutter SDK(`packages/flutter/lib/src/material`, 198파일)에는
/// 10줄 넘는 머리 주석이 **0개**다. Dart는 긴 설명을 파일 머리가 아니라 **선언
/// 위**에 두고(IDE 툴팁·`dart doc`이 거기서 읽는다), 설계 서사는 문서로 뺀다.
///
/// 주석 **총량**은 문제가 아니다. 재 보면 우리 비율(28%)은 Flutter material
/// (28.8%)·widgets(43.7%)과 같은 대역이고, 선언당 주석 길이는 오히려 우리가 더
/// 짧다. 그래서 이 검사는 총량이 아니라 **입구를 막은 벽**만 잡는다.
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
