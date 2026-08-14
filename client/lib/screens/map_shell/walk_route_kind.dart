/// 도보 길찾기가 **다섯 갈래 중 어디로 가는지** 정하는 판정.
///
/// 출발지·도착지가 실내인지 야외인지, 지금 도면을 보고 있는지, 실내 위치가
/// 잡혔는지에 따라 부르는 지도 메서드가 통째로 달라진다. 그 판정이 지도 조작과
/// 한 함수에 섞여 있는 동안 갈래 하나가 **없는 채로 지나간 적이 있다** — 실내에서
/// 바깥으로 가는 길찾기가 통째로 빠져 있었고, 조건 둘을 모두 비껴간 요청이
/// 실내 경로 계산까지 흘러가 "도착지 노드 정보가 없어 경로를 계산할 수
/// 없습니다"만 뜨고 끝났다.
///
/// 그래서 판정만 여기로 뗐다. 지도도 위젯도 없이 시험된다.
library;

import '../../models/directions_candidate.dart';

/// 도보 길찾기의 갈래. 각각 부르는 지도 메서드가 다르다.
enum WalkRouteKind {
  /// 건물 안에서 건물 안으로. 실내 그래프만으로 이어진다.
  indoorToIndoor,

  /// 건물 밖에서 건물 안 매장으로. **가장 가까운 지상 출입구를 경유한다.**
  ///
  /// 목적지 좌표로 곧장 걷기 경로를 그리면 도착점이 건물 내부 좌표라 TMAP이
  /// 외벽 아무 곳으로나 안내하고 거기서 끝난다.
  outdoorToIndoor,

  /// 건물 안에서 바깥 목적지로.
  indoorToOutdoor,

  /// 순수 야외. TMAP 보행 경로.
  outdoor,

  /// 위 어디에도 안 걸린 나머지. 실내 경로 계산에 그대로 넘긴다 —
  /// 층이 다르면 다층(엘리베이터·에스컬레이터 포함), 같으면 단일 층으로 갈린다.
  indoorFallback,
}

/// 지도에서 찍은 이름 없는 야외 좌표인가.
///
/// [DirectionsCandidate.isIndoorPoint]의 반대가 **아니다.** 층만 있고 노드가
/// 없는(또는 그 반대인) 반쪽짜리 후보는 양쪽 다 거짓이라 어느 실내 갈래로도
/// 가지 않는다 — 실내 라우팅이 시작 노드나 층을 못 정해 조용히 끝나는 것보다
/// 야외 걷기 경로로 흘려보내는 편이 낫다.
bool _isOutdoorPoint(DirectionsCandidate c) =>
    c.floor == null && c.nodeId == null;

/// 어느 갈래로 갈지 정한다.
///
/// [indoorContextActive]는 지금 화면에 도면이 떠 있는지다. [indoorStartReady]는
/// 실내 위치(PDR 앵커)가 실제로 잡혀 있는지다. **둘은 다르다** — 도면은 건물을
/// 확대하거나 탭하기만 해도 켜지므로, 밖에 서 있는 사용자에게도 켜져 있다.
/// 그 차이를 뭉개면 밖에 있는 사용자가 "출발 위치를 먼저 지정해주세요"만 보고
/// 안내가 끝난다.
WalkRouteKind classifyWalkRoute({
  required DirectionsCandidate? origin,
  required DirectionsCandidate destination,
  required bool indoorContextActive,
  required bool indoorStartReady,
}) {
  final destinationIndoor = destination.isIndoorPoint;

  // 1) 실내 → 실내.
  //
  // **도면이 켜져 있을 때만** 탄다. 도면을 닫고 야외 지도를 보는 중이라면
  // 사용자의 위치는 GPS이지 실내 앵커가 아니다. 그때도 실내로 보내면 화면에는
  // GPS 위치 아이콘이 있는데 경로만 예전에 찍어둔 건물 안 앵커에서 뻗어 나간다.
  //
  // 도면만으로는 부족하다 — **출발점이 실제로 건물 안에 있어야 한다.** 출발지를
  // 명시하지 않았다면 실내 위치가 잡혀 있을 때만([indoorStartReady]) 탄다.
  // 명시했다면 그것도 실내 노드여야 한다. 건물 입구 같은 야외 후보라면 아래
  // 걷기 경로로 흘려보낸다.
  if (indoorContextActive &&
      destinationIndoor &&
      (origin == null ? indoorStartReady : origin.isIndoorPoint)) {
    return WalkRouteKind.indoorToIndoor;
  }

  // 2) 야외 → 실내. 문을 경유해 매장까지.
  //
  // 출발지가 실내 지점이면 여기로 보내지 않는다. 그건 건물 안 두 지점 사이의
  // 이동이라 "밖에서 문으로 들어간다"는 전제가 성립하지 않는다. 반대로 지도에서
  // 찍은 야외 좌표는 그대로 넘긴다 — GPS가 안 잡히거나 다른 곳에서 출발하는
  // 경로를 보려는 경우이고, 그때도 들어가는 문은 있어야 한다.
  //
  // **조건에 `!indoorContextActive`가 없는 것이 중요하다.** 도면이 켜져 있어도
  // 실내 위치가 없으면 사용자는 아직 밖에 있고, 그 경우 1)이 이미 통과시켜
  // 여기까지 흘려보낸다. 도면 유무로 다시 막으면 "건물 안에서 매장 고르기"로
  // 들어온 사용자가 매장을 눌러도 안내가 시작되지 않는다.
  if (destinationIndoor && (origin == null || _isOutdoorPoint(origin))) {
    return WalkRouteKind.outdoorToIndoor;
  }

  // 3) 실내 → 야외. 1)과 **대칭**으로 읽으면 된다 — 도면이 켜져 있고, 실내
  // 위치가 실제로 잡혀 있고(= 건물 안이다), 목적지에 실내 노드가 없다(= 바깥).
  //
  // 출발지를 따로 고른 경우는 제외한다. 그건 "지금 내가 있는 곳에서 나간다"가
  // 아니라 다른 지점 사이의 경로라, 실내 구간의 출발점을 현재 위치로 잡는 이
  // 흐름의 전제가 깨진다.
  if (indoorContextActive &&
      indoorStartReady &&
      origin == null &&
      destination.nodeId == null) {
    return WalkRouteKind.indoorToOutdoor;
  }

  // 4) 순수 야외.
  if (!indoorContextActive) return WalkRouteKind.outdoor;

  return WalkRouteKind.indoorFallback;
}
