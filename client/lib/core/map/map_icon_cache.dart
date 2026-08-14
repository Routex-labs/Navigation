/// 지도에 등록하는 아이콘 비트맵(PNG)의 프로세스 수명 캐시.
///
/// ## 왜 필요한가
///
/// MapLibre 심볼 레이어는 **미리 등록된 비트맵만** 참조할 수 있어서, 지도를 새로
/// 만들 때마다 아이콘을 오프스크린 렌더링해 `addImage`로 올린다. 실내 화면은
/// 층이 바뀔 때마다 지도 위젯을 통째로 다시 만들고(`ValueKey('$건물-$층')`),
/// 그때마다 카테고리 11장 + POI 5~6장 + 편의시설 7장 + 목적지 핀·현재 위치 3장,
/// 대략 **26장을 매번 다시 굽는다.** 캔버스에 글리프를 그리고 `toImage` →
/// `toByteData(png)`까지 가는 경로라 PNG 인코딩이 장당 붙고, 전부 UI 스레드
/// (`dart:ui`)에서 **순차로** 돈다.
///
/// 그림은 입력이 같으면 결과가 같다. 층을 오갈 때마다 다시 구울 이유가 없다.
///
/// ## 키는 addImage 이름을 그대로 쓴다
///
/// 등록 이름은 이미 "이 비트맵을 유일하게 가리키는 값"이라는 계약을 갖고 있다 —
/// 카테고리 이름·시설 이름·아이콘 codePoint가 들어가고, 디자인을 바꾸면 이름에
/// 박아 둔 버전/치수 토큰이 함께 바뀐다(`_destinationPinImageName`,
/// `_currentLocationImageName` 주석 참고). 그래서 이름을 키로 쓰면 "디자인이
/// 바뀌었는데 옛 그림이 캐시에서 나오는" 경우가 생기지 않는다.
///
/// ## Future를 캐시한다
///
/// 값이 아니라 Future를 담아, 같은 순간에 두 지도(실내 화면과 야외 오버레이)가
/// 같은 아이콘을 요청해도 렌더링은 한 번만 돌게 한다 —
/// `HttpBuildingRepository._shared`와 같은 이유다.
///
/// 실패는 캐시하지 않는다. 렌더링이 한 번 실패했다고 그 아이콘을 앱이 끝날
/// 때까지 못 그리게 두면, 지도가 영구히 아이콘 없는 상태로 굳는다.
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
