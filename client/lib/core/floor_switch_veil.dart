/// 사람 조작으로 층이 바뀔 때 지도 위에 덮는 베일의 타이밍 정책.
///
/// 층을 바꾸면 MVT 소스를 통째로 갈아 끼우고 새 층 타일을 네트워크에서 받아
/// 온다. 그 사이 이전 층 도면이 그대로 남아 있다가 새 도면이 **툭** 바뀌는데,
/// 이 잔상이 로딩 지연으로 읽힌다. 베일을 얹으면 같은 지연이 "전환 중"으로
/// 읽힌다 — 지연을 없애는 게 아니라 의도된 것으로 보이게 하는 장치다.
///
/// 안내 중 층 전환 스크림(불투명, 입력 차단)과 달리 **반투명이고 입력을 막지
/// 않는다.** 층 훑기는 연속 조작이라, 매 탭마다 화면이 완전히 덮이고 잠기면
/// 훑는 리듬이 끊긴다.
///
/// 여기 있는 것은 "언제 덮고 언제 걷는가"의 **판단**뿐이다. 실제 페이드
/// 렌더링은 화면(outdoor_map_screen)의 AnimatedOpacity가, 오래 걸릴 때 띄우는
/// 에스컬레이터 모티프는 [FloorSwitchEscalatorMotif] 위젯이 맡는다. 판단을
/// 위젯에서 떼어 낸 이유는 시간 축 위의 상태 기계라 위젯 트리 없이 검증해야
/// 경우의 수(빠른 완료·연타·늦은 완료)를 다 돌려볼 수 있어서다.
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

/// 베일이 지도를 덮는 정도. 완전히 가리지 않아 "지도 위 같은 자리"라는 맥락은
/// 남기면서, 타일 교체 장면은 읽히지 않을 만큼 덮는다.
const floorSwitchVeilOpacity = 0.6;

/// 베일 페이드인. 짧게 — 덮는 동작 자체가 굼뜨면 조작 반응이 늦게 느껴진다.
const floorSwitchVeilFadeIn = Duration(milliseconds: 120);

/// 베일 페이드아웃. 걷힘은 카메라 재정렬·포커스 이동과 겹쳐 하나의 전환으로
/// 읽히도록 페이드인보다 길게 잡는다.
const floorSwitchVeilFadeOut = Duration(milliseconds: 300);

/// 전환이 이 시간 안에 끝나면 베일을 아예 띄우지 않는다.
///
/// 캐시된 층은 전환이 수십 ms에 끝나는데, 그때도 즉시 덮으면 페이드인이
/// 끝나기도 전에 페이드아웃이 시작돼 반쯤 덮인 베일이 **깜빡**하고 지나간다
/// (기존 층 선택기 경로의 실제 증상). 150ms는 사람이 "화면이 지웠다 다시
/// 그려졌다"고 인지하기 어려운 규모라, 그 안에 끝나는 전환은 가리지 않고
/// 그대로 보여 주는 편이 낫다.
const floorSwitchVeilShowDelay = Duration(milliseconds: 150);

/// 일단 띄운 베일이 화면에 머무는 최소 시간.
///
/// 페이드인(120ms)이 끝까지 가고, 완전히 덮인 상태가 한 박자(≈240ms) 유지된
/// 뒤에만 걷는다. 이보다 짧으면 페이드인·아웃이 겹쳐 어중간한 밝기에서
/// 꺾이는 게 보인다. 반드시 [floorSwitchVeilFadeIn]보다 길어야 한다.
const floorSwitchVeilMinShown = Duration(milliseconds: 360);

/// 전환이 이 시간을 넘기면 베일 위에 에스컬레이터 모티프를 띄운다.
///
/// 이 아래로는 "잠깐의 전환"이라 장식이 오히려 깜빡임이 되고, 이 위로는
/// 사용자가 기다림을 인지하기 시작하므로 "일하고 있다"는 신호가 필요하다.
/// 요구 범위 500~700ms의 중앙값.
const floorSwitchMotifDelay = Duration(milliseconds: 600);

/// 모티프 벨트에서 계단 한 칸이 흘러가는 주기. 위젯 애니메이션과 최소 표시
/// 시간이 같은 값을 봐야 "한 칸은 흐르는 걸 보여 준다"가 성립한다.
const floorSwitchMotifStepPeriod = Duration(milliseconds: 450);

/// 일단 띄운 모티프가 머무는 최소 시간. 계단 한 칸([floorSwitchMotifStepPeriod])
/// 은 흘러야 방향이 읽힌다 — 그 전에 걷으면 무엇이 떴는지도 모른 채 사라진다.
const floorSwitchMotifMinShown = floorSwitchMotifStepPeriod;

/// 화면이 그려야 하는 베일·모티프 상태. [FloorSwitchVeilController]가 바뀔
/// 때마다 콜백으로 내려 준다.
class FloorSwitchVeilState {
  const FloorSwitchVeilState({required this.veilVisible, this.motifDirection});

  final bool veilVisible;

  /// null이면 모티프 숨김. 방향이 있어야만 띄운다 — 방향 없는 벨트는 어느
  /// 층으로 가는지 아무것도 말해 주지 않는다.
  final FloorSwitchDirection? motifDirection;
}

/// 사람 조작 층 전환 한 건의 베일·모티프 타이밍을 구동하는 상태 기계.
///
/// 사용법: 전환 시작 때 [begin]으로 토큰을 받고, `_switchOverlayFloor`가
/// 끝나면(성공·실패 무관) 같은 토큰으로 [finish]를 부른다. 표시 지연·최소
/// 표시·모티프 지연은 전부 여기서 관리하므로 호출부는 기다릴 필요가 없다.
///
/// **연타를 견딘다** — 층 훑기처럼 전환이 겹치면 마지막 [begin]이 베일의
/// 주인이 되고, 앞선 전환의 [finish]는 무시된다. 토큰 없이 각자 걷으면 먼저
/// 끝난 이전 탭이 다음 탭이 덮어 둔 베일을 걷어 버려 타일 교체 장면이
/// 그대로 드러난다.
class FloorSwitchVeilController {
  FloorSwitchVeilController({required this.onChanged});

  /// 상태가 바뀔 때마다 호출된다. 화면은 여기서 setState한다.
  final void Function(FloorSwitchVeilState state) onChanged;

  int _token = 0;
  Timer? _showTimer;
  Timer? _motifTimer;

  bool _veilVisible = false;
  FloorSwitchDirection? _motifDirection;

  /// 모티프 타이머가 발화할 때 쓸 방향. 타이머 클로저에 방향을 캡처하면 연타로
  /// 방향이 바뀌었을 때 이전 탭의 방향이 떠 버리므로, 최신 [begin]이 갱신하는
  /// 필드를 발화 시점에 읽는다.
  FloorSwitchDirection? _pendingMotifDirection;

  // 최소 표시 시간은 경과 시간을 재지 않고 **표시 순간 거는 게이트 타이머**로
  // 지킨다. 걷기는 "전환이 끝났고(_dismissRequested) 열린 게이트가 다 지났을
  // 때"만 일어난다. Stopwatch로 재서 남은 시간만큼 걷기를 예약하는 방식은
  // 테스트의 가짜 시계(FakeAsync)가 Stopwatch를 감지 못해 검증이 불가능하고,
  // 타이머 두 종류(경과 측정 + 예약)가 섞여 상태가 더 늘어난다.
  Timer? _veilMinShownTimer;
  Timer? _motifMinShownTimer;
  bool _dismissRequested = false;

  bool get veilVisible => _veilVisible;
  FloorSwitchDirection? get motifDirection => _motifDirection;

  /// 전환 시작. [direction]은 현재 층 → 목표 층의 수직 방향(모르면 null,
  /// 그 경우 모티프는 안 띄운다). 반환 토큰을 [finish]에 그대로 넘긴다.
  int begin(FloorSwitchDirection? direction) {
    final token = ++_token;
    // 직전 전환이 걷으려던 참이어도 새 전환이 이어졌으니 베일은 내려오지 않고
    // 그대로 다음 전환을 덮는다.
    _dismissRequested = false;

    // **대기 중인 표시 타이머는 리셋하지 않는다.** 탭마다 지연을 다시 걸면
    // 표시 지연(150ms)보다 빠르게 연타하는 동안 베일이 영영 못 뜨는데, 그때가
    // 바로 타일 교체가 제일 요란한 순간이다. 지연은 "연속된 훑기"의 첫 탭
    // 기준으로 한 번만 잰다. 이미 떠 있으면 최소 표시 게이트도 처음 오른
    // 시점 것을 그대로 쓴다 — 매 탭마다 리셋하면 훑는 내내 걷히지 못한다.
    if (!_veilVisible && _showTimer == null) {
      // 표시를 [floorSwitchVeilShowDelay]만큼 미룬다. 그 안에 끝나는 전환은
      // 베일 없이 지나간다 — 깜빡임 방지의 핵심. 이 타이머는 [finish]나
      // [dispose]가 취소하므로 발화 시점엔 전환이 아직 도는 중이다.
      _showTimer = Timer(floorSwitchVeilShowDelay, () {
        _showTimer = null;
        _veilVisible = true;
        // 최소 표시 게이트. 이 타이머가 지나기 전에는 걷지 않는다.
        _veilMinShownTimer = Timer(floorSwitchVeilMinShown, () {
          _veilMinShownTimer = null;
          _maybeHide();
        });
        _notify();
      });
    }

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
        _notify();
      }
    } else if (_motifDirection != null) {
      // 모티프가 이미 떠 있으면 방향만 갈아탄다(연타로 위→아래가 될 수 있다).
      if (_motifDirection != direction) {
        _motifDirection = direction;
        _notify();
      }
    } else {
      // 이미 대기 중인 타이머는 다시 걸지 않는다(??=) — 표시 타이머와 같은
      // 이유로, 사용자 입장의 "기다린 시간"은 훑기 첫 탭부터다.
      _motifTimer ??= Timer(floorSwitchMotifDelay, () {
        _motifTimer = null;
        _motifDirection = _pendingMotifDirection;
        if (_motifDirection == null) return;
        // showDelay < motifDelay이므로 이 시점엔 베일이 이미 떠 있다.
        _motifMinShownTimer = Timer(floorSwitchMotifMinShown, () {
          _motifMinShownTimer = null;
          _maybeHide();
        });
        _notify();
      });
    }
    return token;
  }

  /// 전환 완료. [begin]이 준 토큰과 다르면(그 사이 새 전환이 시작됐으면)
  /// 아무것도 하지 않는다 — 베일의 주인은 마지막 전환이다.
  void finish(int token) {
    if (token != _token) return;
    _showTimer?.cancel();
    _showTimer = null;
    _motifTimer?.cancel();
    _motifTimer = null;
    if (!_veilVisible) return; // 표시 지연 안에 끝났다 — 아무것도 안 떴다.
    _dismissRequested = true;
    _maybeHide();
  }

  /// 걷기 조건: 전환이 끝났고, 열린 최소 표시 게이트가 하나도 안 남았을 때.
  /// 모티프가 베일보다 늦게 뜨므로 보통 모티프 게이트가 마지막에 닫힌다.
  void _maybeHide() {
    if (!_dismissRequested) return;
    if (_veilMinShownTimer != null || _motifMinShownTimer != null) return;
    _dismissRequested = false;
    _veilVisible = false;
    _motifDirection = null;
    _notify();
  }

  void _notify() {
    onChanged(
      FloorSwitchVeilState(
        veilVisible: _veilVisible,
        motifDirection: _motifDirection,
      ),
    );
  }

  /// 화면이 내려갈 때 호출한다. 남은 타이머가 dispose된 State에 setState하는
  /// 것을 막는다.
  void dispose() {
    _token++; // 이후 도착하는 finish는 토큰 검사에서 걸러진다.
    _showTimer?.cancel();
    _motifTimer?.cancel();
    _veilMinShownTimer?.cancel();
    _motifMinShownTimer?.cancel();
  }
}
