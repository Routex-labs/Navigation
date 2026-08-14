/// 지도에 등록하는 아이콘 비트맵(PNG)의 프로세스 수명 캐시.
///
/// 층을 바꿀 때마다 지도 위젯을 다시 만들면서 아이콘 26장을 UI 스레드에서 순차로
/// 다시 굽고 있었다. 그림은 입력이 같으면 결과가 같다.
///
/// - **키는 `addImage` 이름**이다. 그 이름이 이미 "이 비트맵을 유일하게 가리키는
///   값"이고 디자인을 바꾸면 이름의 버전/치수 토큰도 바뀐다.
/// - **값이 아니라 Future를 담는다.** 두 지도가 같은 아이콘을 동시에 요청해도
///   렌더링은 한 번만 돈다.
/// - **실패는 캐시하지 않는다.** 한 번 실패로 앱이 끝날 때까지 못 그리게 두면
///   지도가 영구히 아이콘 없는 상태로 굳는다.
library;

import 'dart:async';
import 'dart:typed_data';

final _pngByImageName = <String, Future<Uint8List>>{};

/// [imageName]으로 이미 구운 PNG가 있으면 그것을, 없으면 [render]로 굽고
/// 캐시해서 돌려준다.
Future<Uint8List> cachedIconPng(
  String imageName,
  Future<Uint8List> Function() render,
) {
  final cached = _pngByImageName[imageName];
  if (cached != null) return cached;

  final future = render();
  _pngByImageName[imageName] = future;
  // 지우기만 하고 오류는 여기서 삼킨다. `catchError`에서 다시 throw하면 아무도
  // 기다리지 않는 **파생 future**가 오류로 끝나 처리되지 않은 비동기 오류가 된다
  // (앱에서는 zone 오류 핸들러로, 테스트에서는 그 테스트의 실패로 나타난다).
  // 오류 자체는 [future]를 await하는 호출부가 이미 받으므로, 여기서 한 번 더
  // 흘릴 이유가 없다.
  unawaited(
    future.then<void>((_) {}, onError: (Object _) {
      _pngByImageName.remove(imageName);
    }),
  );
  return future;
}

/// 테스트에서 캐시를 비운다. 프로덕션 코드에서 부를 일은 없다 — 아이콘은 앱이
/// 살아 있는 동안 바뀌지 않는다.
void resetIconPngCacheForTest() => _pngByImageName.clear();
