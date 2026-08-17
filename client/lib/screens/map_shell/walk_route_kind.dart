/// 도보 길찾기가 **다섯 갈래 중 어디로 가는지** 정하는 판정.
///
/// 판정이 지도 조작과 한 함수에 섞여 있는 동안 갈래 하나(실내 → 야외)가 통째로
/// 빠져 있었고, 조건 둘을 비껴간 요청이 실내 경로 계산까지 흘러가 "도착지 노드
/// 정보가 없어..."만 뜨고 끝났다. 그래서 판정만 뗐다.
library;

import '../../models/route/directions_candidate.dart';

/// 도보 길찾기의 갈래. 각각 부르는 지도 메서드가 다르다.
enum WalkRouteKind {
  /// 건물 안 → 건물 안. 실내 그래프만으로 이어진다.
  indoorToIndoor,

  /// 건물 밖 → 건물 안 매장. **가장 가까운 지상 출입구를 경유한다** — 목적지
  /// 좌표로 곧장 그리면 도착점이 건물 내부라 TMAP이 외벽에서 끝낸다.
  outdoorToIndoor,

  /// 건물 안 → 바깥 목적지. **[outdoorToIndoor]의 거울상이다** — 목적지에서
  /// 가장 가까운 지상 출입구까지 실내로 안내하고, 건물을 나가면 그 문에서
  /// 바깥 경로가 이어진다. 출발점은 PDR 앵커일 수도, 사용자가 고른 실내
  /// 매장일 수도 있다.
  indoorToOutdoor,

  /// 순수 야외. TMAP 보행 경로.
  outdoor,

  /// 나머지. 실내 경로 계산에 그대로 넘겨 층으로 다층/단일이 갈린다.
  indoorFallback,
}

/// 지도에서 찍은 이름 없는 야외 좌표인가.
///
/// [DirectionsCandidate.isIndoorPoint]의 반대가 **아니다.** 층만 있고 노드가 없는
/// 반쪽 후보는 양쪽 다 거짓이라 야외 걷기로 흘러간다 — 실내 라우팅이 시작점을 못
/// 정해 조용히 끝나는 것보다 낫다.
bool _isOutdoorPoint(DirectionsCandidate c) =>
    c.floor == null && c.nodeId == null;

/// 어느 갈래로 갈지 정한다.
///
/// [indoorContextActive](도면이 떠 있는가)와 [indoorStartReady](실내 위치가 잡혔는가)
/// 는 **다르다** — 도면은 건물을 확대만 해도 켜지므로 밖에 선 사용자에게도 켜진다.
/// 뭉개면 밖에 있는 사용자가 "출발 위치를 먼저 지정해주세요"만 보고 끝난다.
///
/// 둘 다 **출발지를 고르지 않았을 때만** 쓴다. 고른 출발지가 건물 안 노드면 그
/// 자체가 시작점이라, 지금 어디에 서 있는지는 어느 갈래인지를 바꾸지 않는다.
WalkRouteKind classifyWalkRoute({
  required DirectionsCandidate? origin,
  required DirectionsCandidate destination,
  required bool indoorContextActive,
  required bool indoorStartReady,
}) {
  final destinationIndoor = destination.isIndoorPoint;

  // 1) 실내 → 실내.
  //
  // **출발지를 직접 골랐으면 도면이 떠 있는지는 상관없다.** 건물 밖에서 "거기는
  // 어떻게 되어 있지?" 하고 미리 보는 길이 그것이다 — 두 끝점이 다 건물 안 노드면
  // 밖에 서 있든 말든 그릴 수 있는 경로이고, 막아 두면 그 사람은 건물에 들어가기
  // 전까지 안을 볼 방법이 없다. 미리 보기와 실제 안내를 가르는 것은 이 판정이
  // 아니라 "안내 시작" 버튼이다.
  //
  // **출발지가 없을 때(=지금 있는 곳)는 예전 조건 그대로다.** 도면만 보고 태우면
  // 야외 지도를 보는 중에도 예전 앵커에서 경로가 뻗는다.
  if (destinationIndoor &&
      (origin == null
          ? (indoorContextActive && indoorStartReady)
          : origin.isIndoorPoint)) {
    return WalkRouteKind.indoorToIndoor;
  }

  // 2) 야외 → 실내. **조건에 `!indoorContextActive`가 없는 것이 중요하다** —
  // 도면이 켜져 있어도 실내 위치가 없으면 사용자는 아직 밖이고, 1)이 그 경우를
  // 여기로 흘려보낸다. 도면 유무로 다시 막으면 매장을 눌러도 안내가 시작되지 않는다.
  if (destinationIndoor && (origin == null || _isOutdoorPoint(origin))) {
    return WalkRouteKind.outdoorToIndoor;
  }

  // 3) 실내 → 야외. **1)과 판박이여야 한다.** 한때 `origin == null`을 달아
  // "지금 있는 곳에서 나간다"만 이 갈래로 보냈는데, 그러면 실내 매장을
  // 출발지로 고른 사용자가 아래 indoorFallback으로 떨어져 야외 목적지를 실내
  // 라우팅에 넘기고 "도착지 노드 정보가 없어..."만 봤다. 출발 노드가 이미
  // 있으면 PDR 앵커([indoorStartReady])는 필요 없다 — 그래서 조건 1)과 같은
  // 모양으로 갈린다.
  if (indoorContextActive &&
      destination.nodeId == null &&
      (origin == null ? indoorStartReady : origin.isIndoorPoint)) {
    return WalkRouteKind.indoorToOutdoor;
  }

  if (!indoorContextActive) return WalkRouteKind.outdoor;

  return WalkRouteKind.indoorFallback;
}
