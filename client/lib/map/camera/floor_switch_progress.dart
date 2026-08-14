/// 사람 조작으로 층이 바뀔 때의 전환 연출 타이밍 정책. 덮개를 씌우지 않고 새 층
/// 타일이 실제로 도착한 뒤 크로스페이드한다 — 흰 화면은 어느 순간에도 없다.
///
/// 여기 있는 것은 타이밍 **정책**과 모티프 표시 **판단**뿐이라 위젯 트리 없이
/// 검증한다. 값마다의 근거는 `docs/client/camera-choreography-plan.md` 4.13.
library;

import 'dart:async';

import '../../domain/geo/floor_label.dart';

/// 층 전환의 수직 방향. 에스컬레이터 모티프가 계단을 흘릴 방향을 정한다.
enum FloorSwitchDirection { up, down }

/// 층 라벨을 비교 가능한 순위로 바꾼다. 규칙은 [floorLabelRank]가 소유한다 —
/// 층 판정기도 같은 규칙으로 인접 층을 찾으므로, 두 벌로 두면 한쪽만 고쳐진다.
int floorSwitchRank(String label) => floorLabelRank(label);

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
/// 캐시된 층까지 페이드를 돌리면 층 훑기(연타)마다 잔상이 겹쳐 끌린다.
const floorSwitchInstantSwapThreshold = Duration(milliseconds: 150);

/// 새 도면이 이전 도면 위로 페이드인되는 시간. 카메라 재정렬(500ms)과 겹쳐
/// 하나의 전환으로 읽히도록, 짧지만 인지 가능한 길이로 잡는다.
const floorSwitchCrossfadeDuration = Duration(milliseconds: 300);

/// 안내 중 자동 층 전환(에스컬레이터)의 페이드인 시간. 사람 조작보다 **두 배**
/// 느리고, 마커 활강([escalatorGlideDuration])보다는 짧다.
const floorSwitchGuidedCrossfadeDuration = Duration(milliseconds: 600);

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
/// 이 아래는 장식이 깜빡임이 되고, 위로는 "일하고 있다"는 신호가 필요하다.
const floorSwitchMotifDelay = Duration(milliseconds: 600);

/// 모티프 벨트에서 계단 한 칸이 흘러가는 주기. 위젯 애니메이션과 최소 표시
/// 시간이 같은 값을 봐야 "한 칸은 흐르는 걸 보여 준다"가 성립한다.
const floorSwitchMotifStepPeriod = Duration(milliseconds: 450);

/// 일단 띄운 모티프가 머무는 최소 시간. 계단 한 칸([floorSwitchMotifStepPeriod])
/// 은 흘러야 방향이 읽힌다 — 그 전에 걷으면 무엇이 떴는지도 모른 채 사라진다.
const floorSwitchMotifMinShown = floorSwitchMotifStepPeriod;

/// 층 전환 한 건의 모티프 타이밍을 구동하는 상태 기계.
///
/// [begin]으로 토큰을 받고 **시각적 완료**(크로스페이드까지 끝난 시점)에 같은
/// 토큰으로 [finish]를 부른다. 실패해도 반드시 부른다 — 안 그러면 영영 안 걷힌다.
///
/// **연타를 견딘다** — 마지막 [begin]이 모티프의 주인이 되고 앞선 [finish]는
/// 무시된다. 토큰이 없으면 이전 탭이 다음 탭의 모티프를 걷어 버린다.
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
