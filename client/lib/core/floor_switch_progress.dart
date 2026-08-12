/// 사람 조작으로 층이 바뀔 때의 전환 연출 타이밍 정책.
///
/// 층을 바꾸면 MVT 소스를 갈아 끼우고 새 층 타일을 네트워크에서 받아 온다.
/// 예전에는 그 사이를 흰 반투명 베일로 덮었는데, 실기기에서 덮개가 씌워졌다
/// 걷히는 장면이 **캡처 플래시처럼 번쩍**여 보였다. 그래서 덮개를 버리고
/// 카카오맵 방식으로 바꿨다 — **이전 층 도면을 그대로 계속 보여 주다가**, 새
/// 층 타일이 실제로 도착한 뒤에 새 도면을 이전 도면 위로 페이드인(크로스페이드)
/// 한다. 흰 화면은 어느 순간에도 없다.
///
/// "타일이 도착했다"는 판정은 고정 딜레이가 아니라 **실제 로드 신호**다 —
/// 화면이 새 소스의 footprint를 `querySourceFeatures`로 폴링해, 로드된 타일에
/// feature가 잡히는 순간을 준비 완료로 본다. 주차구역 폴리곤이 수백 개라 수 초
/// 걸리는 무거운 층(B3·5F·6F)에서도 이전 도면이 끝까지 유지되는 근거다.
/// (maplibre_gl의 `waitUntilMapTilesAreLoaded`는 native에서 no-op이라 못 쓴다.)
///
/// 여기 있는 것은 타이밍 **정책**(상수)과, 오래 걸릴 때 띄우는 에스컬레이터
/// 모티프의 "언제 띄우고 언제 거두는가" **판단**뿐이다. 실제 크로스페이드
/// 실행은 화면(outdoor_map_screen)이, 모티프 렌더링은
/// [FloorSwitchEscalatorMotif] 위젯이 맡는다. 판단을 위젯에서 떼어 낸 이유는
/// 시간 축 위의 상태 기계라 위젯 트리 없이 검증해야 경우의 수(빠른 완료·연타·
/// 늦은 완료)를 다 돌려볼 수 있어서다.
library;

import 'dart:async';

/// 층 전환의 수직 방향. 에스컬레이터 모티프가 계단을 흘릴 방향을 정한다.
enum FloorSwitchDirection { up, down }

/// 층 라벨을 비교 가능한 순위로 바꾼다. "1F" → 1, "B1" → -1.
///
/// `Building.floors`의 나열 순서에 기대지 않는 이유: 그 순서는 서버 응답
/// 순서일 뿐 위아래를 약속하지 않는다. 라벨 자체가 위아래를 말한다.
/// 숫자를 못 읽는 라벨(옥상 등 비표준)은 0 — 방향을 단정하지 않는다.
int floorSwitchRank(String label) {
  final m = RegExp(r'^(B?)(\d+)').firstMatch(label.toUpperCase());
  if (m == null) return 0;
  final n = int.parse(m.group(2)!);
  return m.group(1)!.isEmpty ? n : -n;
}

/// [from] 층에서 [to] 층으로 갈 때의 수직 방향. 판단할 수 없으면(시작 층이
/// 없거나 순위가 같음) null — 모티프는 틀린 방향을 보여 주느니 안 띄운다.
FloorSwitchDirection? floorSwitchDirectionBetween(String? from, String to) {
  if (from == null) return null;
  final delta = floorSwitchRank(to) - floorSwitchRank(from);
  if (delta > 0) return FloorSwitchDirection.up;
  if (delta < 0) return FloorSwitchDirection.down;
  return null;
}

/// 새 층 타일이 이 시간 안에 준비되면 크로스페이드 없이 즉시 교체한다.
///
/// 캐시된 층은 수십 ms에 준비되는데, 그때도 페이드를 돌리면 층 훑기(연타)의
/// 리듬마다 잔상이 겹쳐 끌리는 느낌을 준다. 150ms는 사람이 "지웠다 다시
/// 그려졌다"고 인지하기 어려운 규모라, 그 안에 끝나는 전환은 연출 없이
/// 곧바로 새 도면을 보여 주는 편이 낫다.
const floorSwitchInstantSwapThreshold = Duration(milliseconds: 150);

/// 새 도면이 이전 도면 위로 페이드인되는 시간. 카메라 재정렬(500ms)과 겹쳐
/// 하나의 전환으로 읽히도록, 짧지만 인지 가능한 길이로 잡는다.
const floorSwitchCrossfadeDuration = Duration(milliseconds: 300);

/// 크로스페이드를 몇 단계로 쪼개는가. maplibre_gl 바인딩에는 paint transition
/// (`fill-opacity-transition`)을 넘길 통로가 없어 Dart에서 setLayerProperties를
/// 단계적으로 보내 흉내 낸다. 단계가 많을수록 매끄럽지만 플랫폼 채널 호출도
/// 그만큼 는다(단계마다 fill 레이어 4개 × 전체 속성 교체).
const floorSwitchCrossfadeSteps = 6;

/// 새 소스의 타일 도착을 확인하는 폴링 주기. 짧을수록 준비 완료를 빨리
/// 알아채지만 채널 호출이 는다 — footprint 폴리곤은 층당 몇 개뿐이라 호출
/// 자체는 싸고, 120ms면 즉시 교체 임계(150ms)를 놓치지 않는다.
const floorSwitchTilesPollInterval = Duration(milliseconds: 120);

/// 타일 도착을 기다리는 상한. 네트워크가 죽는 등 feature가 영영 안 잡히면
/// 이전 도면을 무한정 붙들 수 없으므로, 이 시간이 지나면 페이드 없이 교체해
/// 버린다(사용자가 고른 층을 보여 주는 것이 우선이다). 무거운 층의 실측
/// 수 초를 여유 있게 덮는 값.
const floorSwitchTilesReadyTimeout = Duration(seconds: 12);

/// 전환이 이 시간을 넘기면 지도 위에 에스컬레이터 모티프를 띄운다.
///
/// 이 아래로는 "잠깐의 전환"이라 장식이 오히려 깜빡임이 되고, 이 위로는
/// 사용자가 기다림을 인지하기 시작하므로 "일하고 있다"는 신호가 필요하다.
/// 요구 범위 500~700ms의 중앙값. 모티프는 자체 카드 배경이 있어 이전 층
/// 도면이 그대로 보이는 위에서도 읽힌다 — 베일이 필요 없다.
const floorSwitchMotifDelay = Duration(milliseconds: 600);

/// 모티프 벨트에서 계단 한 칸이 흘러가는 주기. 위젯 애니메이션과 최소 표시
/// 시간이 같은 값을 봐야 "한 칸은 흐르는 걸 보여 준다"가 성립한다.
const floorSwitchMotifStepPeriod = Duration(milliseconds: 450);

/// 일단 띄운 모티프가 머무는 최소 시간. 계단 한 칸([floorSwitchMotifStepPeriod])
/// 은 흘러야 방향이 읽힌다 — 그 전에 걷으면 무엇이 떴는지도 모른 채 사라진다.
const floorSwitchMotifMinShown = floorSwitchMotifStepPeriod;

/// 사람 조작 층 전환 한 건의 에스컬레이터 모티프 타이밍을 구동하는 상태 기계.
///
/// 사용법: 전환 시작 때 [begin]으로 토큰을 받고, 전환의 **시각적 완료**(새
/// 도면 크로스페이드까지 끝난 시점 — 타일을 기다리는 동안이 아니라)에 같은
/// 토큰으로 [finish]를 부른다. 실패해도 반드시 부른다 — 안 그러면 모티프가
/// 영영 안 걷힌다. 표시 지연·최소 표시는 전부 여기서 관리하므로 호출부는
/// 기다릴 필요가 없다.
///
/// **연타를 견딘다** — 층 훑기처럼 전환이 겹치면 마지막 [begin]이 모티프의
/// 주인이 되고, 앞선 전환의 [finish]는 무시된다. 토큰 없이 각자 걷으면 먼저
/// 끝난 이전 탭이 다음 탭이 띄워 둔 모티프를 걷어 버려, 아직 타일을 기다리는
/// 중인데 "로딩 중" 신호만 사라진다.
class FloorSwitchProgressController {
  FloorSwitchProgressController({required this.onChanged});

  /// 모티프 상태가 바뀔 때마다 호출된다. null이면 숨김. 화면은 여기서
  /// setState한다. 방향이 있어야만 띄운다 — 방향 없는 벨트는 어느 층으로
  /// 가는지 아무것도 말해 주지 않는다.
  final void Function(FloorSwitchDirection? motifDirection) onChanged;

  int _token = 0;
  Timer? _motifTimer;
  FloorSwitchDirection? _motifDirection;

  /// 모티프 타이머가 발화할 때 쓸 방향. 타이머 클로저에 방향을 캡처하면 연타로
  /// 방향이 바뀌었을 때 이전 탭의 방향이 떠 버리므로, 최신 [begin]이 갱신하는
  /// 필드를 발화 시점에 읽는다.
  FloorSwitchDirection? _pendingMotifDirection;

  // 최소 표시 시간은 경과 시간을 재지 않고 **표시 순간 거는 게이트 타이머**로
  // 지킨다. 걷기는 "전환이 끝났고(_dismissRequested) 게이트가 지났을 때"만
  // 일어난다. Stopwatch로 재서 남은 시간만큼 걷기를 예약하는 방식은 테스트의
  // 가짜 시계(FakeAsync)가 Stopwatch를 감지 못해 검증이 불가능하다.
  Timer? _motifMinShownTimer;
  bool _dismissRequested = false;

  FloorSwitchDirection? get motifDirection => _motifDirection;

  /// 전환 시작. [direction]은 현재 층 → 목표 층의 수직 방향(모르면 null,
  /// 그 경우 모티프는 안 띄운다). 반환 토큰을 [finish]에 그대로 넘긴다.
  int begin(FloorSwitchDirection? direction) {
    final token = ++_token;
    // 직전 전환이 걷으려던 참이어도 새 전환이 이어졌으니 모티프는 내려오지
    // 않고 그대로 다음 전환을 알린다.
    _dismissRequested = false;

    _pendingMotifDirection = direction;
    if (direction == null) {
      _motifTimer?.cancel();
      _motifTimer = null;
      // 방향을 모르는 전환이 이어지면 떠 있던 모티프도 거둔다 — 방금까지의
      // 방향은 이미 다른 전환의 것이다.
      if (_motifDirection != null) {
        _motifDirection = null;
        _motifMinShownTimer?.cancel();
        _motifMinShownTimer = null;
        onChanged(null);
      }
    } else if (_motifDirection != null) {
      // 모티프가 이미 떠 있으면 방향만 갈아탄다(연타로 위→아래가 될 수 있다).
      if (_motifDirection != direction) {
        _motifDirection = direction;
        onChanged(direction);
      }
    } else {
      // 이미 대기 중인 타이머는 다시 걸지 않는다(??=) — 사용자 입장의 "기다린
      // 시간"은 훑기 첫 탭부터라, 탭마다 지연을 다시 걸면 표시 지연보다 빠르게
      // 연타하는 동안 모티프가 영영 못 뜬다. 그때가 바로 타일 로드가 제일
      // 오래 겹치는 순간이다.
      _motifTimer ??= Timer(floorSwitchMotifDelay, () {
        _motifTimer = null;
        _motifDirection = _pendingMotifDirection;
        if (_motifDirection == null) return;
        // 최소 표시 게이트. 이 타이머가 지나기 전에는 걷지 않는다.
        _motifMinShownTimer = Timer(floorSwitchMotifMinShown, () {
          _motifMinShownTimer = null;
          _maybeHide();
        });
        onChanged(_motifDirection);
      });
    }
    return token;
  }

  /// 전환의 시각적 완료. [begin]이 준 토큰과 다르면(그 사이 새 전환이
  /// 시작됐으면) 아무것도 하지 않는다 — 모티프의 주인은 마지막 전환이다.
  /// 같은 토큰으로 두 번 불려도 무해하다(멱등) — 크로스페이드 완료와 호출부
  /// 정리(finally)가 겹칠 수 있다.
  void finish(int token) {
    if (token != _token) return;
    _motifTimer?.cancel();
    _motifTimer = null;
    if (_motifDirection == null) return; // 임계 안에 끝났다 — 아무것도 안 떴다.
    _dismissRequested = true;
    _maybeHide();
  }

  /// 걷기 조건: 전환이 끝났고, 최소 표시 게이트가 안 남았을 때.
  void _maybeHide() {
    if (!_dismissRequested) return;
    if (_motifMinShownTimer != null) return;
    _dismissRequested = false;
    _motifDirection = null;
    onChanged(null);
  }

  /// 화면이 내려갈 때 호출한다. 남은 타이머가 dispose된 State에 setState하는
  /// 것을 막는다.
  void dispose() {
    _token++; // 이후 도착하는 finish는 토큰 검사에서 걸러진다.
    _motifTimer?.cancel();
    _motifMinShownTimer?.cancel();
  }
}
