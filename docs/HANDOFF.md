# 인계 — 2026-08-14 시점

다른 세션이 이 작업을 이어받을 때 **먼저 읽는 문서**다. 여기는 "지금 어디까지 왔고 다음에
무엇을 하나"만 적는다. 계획·기록의 내용은 각 문서가 단일 출처이므로 링크로 넘긴다.

## 한 줄 요약

야외 지도 갓클래스를 해체하는 중이고, **2026-08-17(월) 현장 검증이 다음 관문**이다.
실내 렌더링은 `starbucks` 검색으로 책상에서 눈으로 확인하며 진행한다(아래 함정 참고) —
현장이 꼭 필요한 것은 GPS 판정·PDR·에스컬레이터뿐이다.

**앱에서 닿지 않던 화면 6개와 실내 전용 도면을 지웠다(5,135줄).** 라우트가 `/` 하나만
남았다. 근거와 판정 방법은 [구조 개편 계획](client/structure-plan.md)의 "문제 4"에 있다.

## 브랜치 두 개 — 순서가 중요하다

```
main
 └─ claude/msa-solid-structure-review-ci8j9p-2   (+14)  버그 수정 3 · 분할 5 · 문서
     └─ refactor/outdoor-map-decomposition       (+37)  갓클래스 해체 + 구조 개편(진행 중)
```

해체 브랜치는 **앞 브랜치 위에 쌓여 있다.** 그래서 병합 순서는 반드시:

1. `claude/msa-...-2`를 먼저 `main`에 올린다(버그 수정이 들어 있어 사용자에게 값이 있다).
2. 그다음 해체 브랜치를 `main`에 rebase한다. 1번 커밋들이 이미 main에 있으므로 깨끗이 접힌다.

순서를 뒤집거나 해체 브랜치만 먼저 rebase하면 버그 수정 3건이 사라진다.

## 폰에 무엇을 올려 두나

개발 중에는 **해체 브랜치**를 폰에 올려 부팅과 로그를 확인한다. 하지만 **월요일 현장
검증은 `claude/msa-...-2` 기준으로 해야 한다** — 검증 대상이 "버그 수정이 실제로
먹었나"이지 해체가 아니고, 해체 브랜치로 나가면 문제가 났을 때 원인이 수정인지
해체인지 구분할 수 없다.

그래서 그때 깔려 있던 APK를 그대로 뽑아 두었다.

```
C:\Users\HANSUNG\apk-baseline\field-baseline-msa-branch-1.5.1.apk
```

현장에 나가기 전에 이걸 되돌린다. 빌드가 아니라 **그때 그 바이너리**라 다시 만들 필요가
없다.

```bash
adb install -r "C:/Users/HANSUNG/apk-baseline/field-baseline-msa-branch-1.5.1.apk"
```

## 월요일에 할 일

[현장 검증 체크리스트](client/field-verification-thehyundai.md)가 단일 출처다. 사용자가
폰으로 볼 수 있게 같은 내용을 웹 페이지로도 발행해 두었다(세션 로그의 artifact 링크).

우선순위 둘:

- **03 에스컬레이터** — "1회 탑승에 2층 점프"가 재현되는지와 그때 기압 변화(hPa).
  판정 알고리즘 재작성의 입력이 될 값이라, **고치지 말고 수치만 기록**한다.
- **08 마커 크기** — 층 전환 덮개의 점과 지도 마커가 같은 크기인지. 주석은 "같다"고
  단언하는데 상수를 따라가면 지도 쪽이 2배로 읽힌다. 눈으로 정해야 한다.

## 이어서 할 일

두 계획이 나란히 돈다. **[구조 개편](client/structure-plan.md)이 지금 주된 축**이고,
[해체 계획](client/outdoor-map-decomposition.md)은 야외 지도 클래스 내부용이다.

| 다음 | 어디 |
|---|---|
| `escalator_transition_detector` 분해 (1,870줄, `onAltitude` 한 함수에 판정 6단계) | 구조 개편 |
| `map_shell_screen` 분해 (2,953줄) | 구조 개편 7단계 |
| 직접 테스트 없는 큰 모듈에 테스트 | 구조 개편 8단계 |

단계마다 쓰는 방식은 같다.

1. **테스트를 먼저 쓴다.** 그리고 **틀린 코드에서 실패하는지 반드시 확인한다** —
   4단계에서 이걸 건너뛰었다가 무력한 테스트를 만들었다(아래 함정).
2. 클래스를 만들고 옮긴다. 옮기면서 고치지 않는다.
3. **원본과 한 줄씩 대조한다.** 3단계에서 이 대조로 조용한 차이 3건을 잡았다 — 테스트로는
   안 잡히는 종류였다.
4. 게이트(계획서)를 통과하면 커밋하고 [이동 대장](client/outdoor-map-moves.md)에 한 줄.

## 화면 파일이 여덟 개로 갈렸다

`outdoor_map_screen.dart`(7,567줄)를 성격별 `part` 파일로 갈랐다. **본체 2,241줄.**
코드는 한 글자도 안 바뀌었다(토큰 대조로 확인). 어느 파일에 무엇이 있는지는
[이동 대장](client/outdoor-map-moves.md) 맨 위 표에 있고, 못 찾으면 이게 가장 빠르다.

```bash
grep -rn '심볼이름' client/lib/screens/outdoor_map/
```

**결합은 그대로다.** 여전히 한 클래스에 필드 150개다 — 읽기 쉬워졌을 뿐이니
"분리가 끝났다"고 읽지 않는다.

## 이 세션에서 배운 함정

새 세션이 모르면 반드시 한 번은 밟는 것들이다.

**책상에서는 실내 기능을 검증할 수 없다.** GPS 픽스가 들어올 때마다 "건물 안인가"를
판정하는데, 집·사무실 좌표는 `outside`가 확실하므로 실내 오버레이를 끄고 수동 지정한
위치를 버리고 카메라를 GPS로 옮긴다. 화면에서는 "위치가 갑자기 집으로 순간이동"으로
보인다. 버그가 아니다. 사용자가 실내 관련 증상을 보고하면 **어디서 테스트했는지 먼저 묻는다.**

**`flutter run`이 무선 ADB에서 자주 깨진다.** 디버그 서비스 포트 연결이 거부되거나 스트림이
끊긴다. 대신 이렇게 한다.

```bash
flutter build apk --debug --dart-define-from-file=config.local.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am force-stop com.navigation.navigation_client
adb shell monkey -p com.navigation.navigation_client -c android.intent.category.LAUNCHER 1
adb logcat -v time flutter:V FlutterError:V AndroidRuntime:E '*:S'   # 로그는 이걸로
```

폰 연결은 Tailscale이다(`adb connect 100.112.176.99:5555`, 포트 고정). 링크가 끊기면
`adb devices`가 offline으로 뜨므로 disconnect 후 재연결한다.

**`config.local.json`은 `D:/Navigation/client/`에 있다.** (사용자는 "e드라이브"라고 말했지만
실제로는 D다.) `.gitignore`라 워크스페이스마다 복사해야 하고, **다른 워크스페이스에서
복사할 때 키가 빠질 수 있다** — 실제로 `KAKAO_REST_KEY`가 없는 사본을 써서 대중교통 버튼이
통째로 사라진 적이 있다. 복사 후 키 4개(`API_BASE_URL` `TMAP_APP_KEY` `KAKAO_REST_KEY`
`VWORLD_API_KEY`)가 다 있는지 확인한다.

**~~에스컬레이터·층 전환 코드는 손대지 않는다.~~ 2026-08-14에 풀렸다.** 사용자가 클라이언트
쪽 층 전이 코드도 건드려도 된다고 정했다. 다만 **백엔드**의 수직 전이 생성
(`backend/scripts/transform/vertical_transfers.py`)은 여전히 재작성 예정이라 그대로 둔다 —
원래 이 금지는 그쪽 얘기였다.

**실내 도면은 책상에서도 눈으로 확인할 수 있다 — `starbucks`를 친다.** `adb shell input
text`는 한글을 못 보내지만 검색이 로마자를 한글로 맞춰 주므로, `starbucks`를 치면
"스타벅스 리저브 · 더현대 서울 · B2"가 1위로 뜬다. 그 줄을 누르면 카메라가 **B2로 층까지
전환**되며 실내 오버레이가 그려진다. 등록·층 전환·강조·라벨·아이콘이 한 번에 눈에 걸리는
가장 싼 검증이다. 절차는 [해체 계획](client/outdoor-map-decomposition.md)에 명령까지 적어 뒀다.

이걸 모르면 "실내는 현장에서만 확인된다"고 착각해 단계마다 검증 없이 넘어가게 된다.
**현장이 꼭 필요한 것은 GPS 판정·PDR·에스컬레이터뿐이다.**

**모의 MethodChannel 핸들러 안의 지연은 가짜 시계를 쓰지 않는다.** `tester.pump`로
앞당길 수 없는 **실제 시계**라, 핸들러에 `Future.delayed`를 넣어 "native가 느리게
응답하는" 상황을 만들 수 없다. 4단계에서 세션 정지 경합을 이 방법으로 재현하려다,
검증하려던 코드를 통째로 지워도 통과하는 테스트를 만들었다. 시간이 걸리는 native 응답에
기대는 동작은 위젯 테스트 말고 **그 조각을 직접 부르는 단위 테스트**로 잡는다
(본보기: `client/test/screens/outdoor_map/pdr_session_lifecycle_test.dart`).

그리고 그 사고의 교훈은 더 일반적이다 — **테스트가 통과하는 것만 보고 넘어가지 않는다.
고치려는 코드를 잠시 망가뜨려 그 테스트가 실패하는지 확인한다.**

## 열려 있는 것

| 항목 | 상태 |
|---|---|
| 출발↔도착 맞바꾸기(⇅)가 안 눌림 | **가설 단계.** `_canSwapRouteEndpoints`가 거짓이면 버튼이 비활성이 되는데, 야외에서 실내 출발지가 비워지고 `_reachByNodeId`도 없으면 그 상태가 된다. 현장에서 "버튼이 흐린지"만 보면 확정된다 |
| 안내 시작 시 위치가 집으로 순간이동 | **설계된 동작**으로 결론. 위 함정 참고. 건물 안에서도 일어나면 별개 버그다 |
| 마커 vs 층 전환 덮개 크기 | 현장 항목 08 |
| 레이어 등록 순서 보장 | 호출 순서 + 주석뿐. `MapLibreMapController`를 흉내 내는 테스트 하네스가 없어 테스트로 못 묶었다. 리팩터 전에도 같은 방식이라 **새로 생긴 위험은 아니다** |
| GPS 스트림 재시작이 잦다 | 폰 진단 칩에서 3분 만에 `재시작2`가 찍혔다. `GpsSession`이 설계대로 되살린 것이라 **증상은 없지만**, 스트림이 왜 그렇게 자주 죽는지는 안 봤다. 현장에서 이 숫자가 계속 오르는지 함께 본다 |

## 검증 명령 (CI와 같은 것)

```powershell
cd client
flutter analyze                             # 0건이어야 한다
flutter test test/                          # 1,397개
flutter test integration_test/ -d windows   # 부팅 테스트(CI는 linux)
```

테스트는 `test/` 한 곳에 있고 **`lib/`의 디렉터리 구조를 그대로 미러한다.** 예전에는
`tests/unit_test/`에 83개가 평면으로 쌓여 있었는데, CI가 그쪽만 돌려서 `test/` 아래
337개가 한 번도 실행되지 않은 적이 있다.

해체 브랜치에서는 여기에 **공개 API 19개 불변** 확인이 더 붙는다(계획서의 게이트).
