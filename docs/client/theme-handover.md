# 전역 테마를 언제 Runtime Kit에 넘기나

포팅 [단계 8](https://github.com/Routex-labs/routex-design-system/blob/main/docs/navigation-app-porting-guide.md)의
마지막 항목은 "모든 제품 화면이 옮겨진 경우에만 전역 `RoutexTheme.light` 전환을 별도
검토한다"이다. 이 문서가 그 검토의 기록이고, **판정은 "아직 아니다"** 다.

조건과 남은 차이의 단일 출처는 문서가 아니라 테스트다 —
`client/test/theme/routex_theme_bridge_test.dart`의 "전역 전환 게이트". 목록이 비는 날
`AppTheme.light`를 `RoutexTheme.light`로 갈아 끼운다.

## 왜 지금이 아닌가 — 재 본 값

`AppTheme.light`를 `RoutexTheme.light`로 바꾸고 전체 테스트를 돌린 결과는
**1,555개 중 실패 2개**였고, 그 둘은 "전환하지 않았음"을 지키던 브리지 테스트 자신이다.
나머지 1,553개는 그대로 통과한다.

**그래서 테스트 통과는 이 변경의 근거가 되지 못한다.** 우리 테스트는 색과 글자 크기를
거의 검사하지 않으므로, 화면이 전부 바뀌어도 초록이다. 계산된 `ThemeData`를 직접 견줘야
차이가 보인다.

| 축 | 앱 | Runtime Kit | 전환하면 |
|---|---|---|---|
| `colorScheme.primary` | `0xFF4A87F1` (하늘) | `0xFF2563C7` (진파랑) | 앱이 `AppColors.primary`를 직접 읽는 자리는 그대로라 **한 화면에 두 파랑**이 선다 |
| `colorScheme.secondary` | `0xFF6C9BF2` (실내 강조) | 회색 계열 | Kit이 secondary를 지정하지 않아 seed에서 파생된 중립색이 온다 |
| `textTheme.bodyMedium` | 14 · 행간 기본 | 16 · 행간 1.5 | 크기를 명시하지 않은 글자가 커지고 **줄 간격이 늘어 시트가 세로로 팽창**한다 |
| `disabledColor` | 검정 38% | 불투명 회색 | Material 컨트롤의 비활성 표현이 바뀐다 |
| `dividerColor` | 앱 구성표 파생 | `borderSubtle` | 구분선 10개 파일이 함께 바뀐다 |
| 컴포넌트 테마 | 앱이 소유 | 없음 | `inputDecoration`·`card`·`filledButton`·`textButton`·`listTile`·`divider`·`progressIndicator`·`appBar`가 **한꺼번에 Material 기본으로 떨어진다** |

`AppColors` 직접 참조는 33개 파일 219건이다. 그중 상당수는 지도 그래픽(경로선·마커·핀)이고
**그건 남는 것이 맞다** — 가이드가 단계 7에서 map visual을 제품 UI와 갈랐다. 전환을 막는
것은 참조 수가 아니라 **아직 앱이 그리는 Material 위젯**이다.

| 위젯 | 곳 | 읽는 값 |
|---|---|---|
| `TextField` | 3 | `inputDecorationTheme` (알약 반경 26, `blue50` 채움) |
| `Card` | 3 | `cardTheme` (반경 16 + hairline 테두리) |
| `FilledButton` | 4 파일 | `filledButtonTheme` (세로 여백 16, 반경 18) |
| `TextButton` | 4 파일 | `textButtonTheme` |
| `ListTile` | 7 파일 | `listTileTheme` |
| `Divider` | 10 파일 | `dividerTheme` |
| `CircularProgressIndicator` | 6 파일 | `progressIndicatorTheme` |
| `AppBar` | 1 (PDR 디버그) | `appBarTheme` |

## 전환하려면 무엇이 먼저인가

순서가 있다. 색보다 **컴포넌트가 먼저**다 — 색만 바꾸면 두 출처가 한 화면에서 싸운다.

1. 위 표의 Material 위젯을 Runtime Kit 대응물로 옮긴다. 옮길 때마다 앱 테마에서 해당
   컴포넌트 테마를 지우고, 게이트 목록에서도 지운다.
2. `AppColors.primary`를 직접 읽는 제품 UI 자리를 `context.routexColors`로 옮긴다.
   지도 그래픽은 두고, 남는 `AppColors`는 map visual 전용으로 좁힌다.
3. `textTheme` 두 슬롯이 마지막이다. 크기·행간이 바뀌면 아직 안 옮긴 화면이 세로로
   넘치므로, 남은 화면이 없을 때 한다.
4. 게이트 목록이 비면 `AppTheme.light`를 `RoutexTheme.light`로 바꾸고 `_appOwned`를
   지운다.

## 이 검토에서 나온 공급처 수정

전환을 시도해 보지 않았으면 못 찾았을 결함이 하나 있었다.

`RoutexTheme.light`는 역할 슬롯 여덟만 채우는데 Material 슬롯은 열다섯이다. 남는 일곱
(`titleLarge`·`bodyLarge` 등)이 기본값으로 남아 **가족이 Roboto**였다. Roboto에는 한글이
없어 그 자리만 시스템 대체 글꼴로 떨어진다. `TextField`의 입력 글자가 `bodyLarge`라
검색창 하나 때문에 한 화면에 두 글꼴이 서는 식이다.

공급처에서 고쳤다(`ThemeData(fontFamily:, package:)`를 함께 준다). 크기·굵기는 Material
기본을 그대로 뒀다 — 남는 슬롯을 우리 역할에 매핑하는 것은 글꼴 결함과 별개 결정이다.

## 글꼴 두 벌은 유지한다

`Pretendard`가 앱 asset과 package asset에 한 벌씩, 합쳐 15.2MB 들어간다. 가이드는 한 벌로
줄일지를 단계 8에서 판단하라고 했고, **판정은 유지**다.

한 벌로 줄이려면 앱 선언을 지우고 앱 텍스트를 전부 package 가족으로 보내야 한다. 그러면
`DefaultTextStyle`을 거치지 않는 자리(`CustomPainter`의 `TextPainter`, 지도 마커 그리기)가
조용히 플랫폼 기본으로 떨어진다. 7.6MB는 앱 크기지 런타임 비용이 아니고, 지금은 데모
직전이다. 계약을 바꿀 이득이 위험보다 작다.

두 벌이 실제로 각각 쓰인다는 사실은 `client/test/core/pretendard_font_assets_test.dart`가
지킨다.
