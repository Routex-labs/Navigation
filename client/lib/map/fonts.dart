/// MapLibre 심볼 레이어가 요청하는 fontstack 이름.
///
/// 위젯 텍스트와 달리 지도 라벨은 Flutter가 그리지 않는다. MapLibre가
/// `GET /fonts/{fontstack}/{range}.pbf`로 서버 glyph를 받아 직접 그리므로,
/// 여기 적은 이름이 `backend/resources/fonts/` 아래 **디렉터리 이름과 정확히
/// 같아야 한다.** 하나라도 어긋나면 해당 폰트의 모든 범위를 못 찾고, 심볼
/// 레이어의 레이아웃이 끝나지 않아 같은 타일의 fill까지 통째로 안 그려진다.
///
/// 앱 UI 글꼴(`AppTheme.light`의 `fontFamily`)과 같은 가족으로 맞춰 둔다.
/// 한쪽만 바꾸면 지도 라벨과 시트 텍스트가 다른 글꼴로 보인다.
library;

const mapFontStackRegular = 'Pretendard Regular';
