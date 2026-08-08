/// 검색 결과를 **보행 거리** 오름차순으로 다시 세운다.
///
/// 실외 지도의 "가까운 순"은 직선거리다. 실내에서 직선거리는 자주 거짓말을
/// 한다 — 벽 하나 사이로 10m인 매장이 반대편 에스컬레이터를 돌아 120m일 수
/// 있다. 우리는 온디바이스 다익스트라가 있으므로 실제 보행 비용으로 세운다.
///
/// **여기서 경로를 새로 계산하지 않는다.** 화면은 이미 `reachableFrom`을 한 번
/// 돌려 전 노드 결과를 들고 있고(`SearchPanel.reachByNodeId`), 이 함수는 그
/// 맵을 조회만 한다. 그래서 추가 계산 비용이 0이다. 결과 수만큼 다익스트라를
/// 되돌리는 구현으로 바꾸지 마라.
///
/// 설계 근거와 검증 기준은 `docs/client/search-input-assist.md` M절이 단일
/// 출처다.
library;

import '../models/poi_search_result.dart';
import 'dijkstra.dart';

/// [results]를 [reachByNodeId]의 거리 오름차순으로 정렬한 **새 목록**을 만든다.
///
/// [reachByNodeId]는 사용자 현재 위치에서 출발한 `reachableFrom` 결과다.
/// 입력 목록은 건드리지 않는다.
///
/// 정렬하지 않기로 판단한 경우에는 사본을 만들지 않고 [results]를 그대로
/// 돌려준다 — "순서를 손대지 않았다"를 가장 싸고 분명하게 표현하는 방법이다.
///
/// ## 정렬하지 않는 경우 (실패 조건을 먼저 정한 것)
///
/// - **[fromSemantic]이 true일 때.** 의미 검색(`/query/ai`)은 유사도순으로
///   오는데, 그걸 거리로 다시 세우면 "뜻이 가장 잘 맞는 매장"이 아래로
///   내려간다. 두 순서는 우열이 아니라 **의미가 다른 순서**라, 섞으면 위쪽이
///   무엇을 뜻하는지 사용자가 알 수 없게 된다.
/// - **[reachByNodeId]가 null이거나 비었을 때.** PDR 미시작·측위 실패면 거리를
///   아무도 모른다. 이때 억지로 정렬하면 "거리를 아는 몇 건만 위로 올라온
///   목록"이 되는데, 이건 정렬 안 한 목록보다 나쁘다 — 사용자는 위쪽이 가깝다고
///   읽지만 사실이 아니다. 그래서 **전부 정렬하거나 전혀 정렬하지 않는다.**
///
/// ## 거리를 모르는 매장
///
/// `nodeId`가 null인 매장(경로 안내 불가)과 [reachByNodeId]에 키가 없는 매장
/// (그래프가 끊겨 도달 불가)은 **정렬에서 빼고 목록 끝에** 원래 상대 순서를
/// 유지한 채 붙인다. 거리를 0으로 치면 맨 앞으로, 무한대로 치면 "가장 먼 매장"
/// 으로 보이는데 둘 다 거짓이다. 모른다는 사실은 순서가 아니라 화면의
/// `경로 안내 불가` 문구가 말한다.
///
/// ## 왜 [fromSemantic]을 호출부 판단에 맡기지 않고 필수 인자로 받나
///
/// "의미 검색이면 아예 부르지 않는다"로 두면 규칙이 위젯 코드의 `if` 한 줄로만
/// 존재한다. 나중에 생기는 두 번째 호출부는 그 `if`를 모른 채 정렬만 부르고,
/// 아무것도 깨지지 않은 채 조용히 틀린다. 필수 명명 인자로 두면 **새 호출부는
/// 이 질문에 답하지 않고는 컴파일되지 않고**, 규칙의 근거도 여기 한 곳에만
/// 남는다. `SearchPanel`이 이미 같은 뜻의 `_fromSemantic` 상태를 들고 있어
/// 배선은 그 값을 그대로 넘기면 끝이라, 호출부가 규칙을 다시 쓰다가 뒤집을
/// 여지도 없다.
List<PoiSearchResult> sortedByWalkingDistance({
  required List<PoiSearchResult> results,
  required Map<String, NodeReach>? reachByNodeId,
  required bool fromSemantic,
}) {
  if (fromSemantic) return results;
  final reach = reachByNodeId;
  if (reach == null || reach.isEmpty) return results;

  // 거리를 아는 것만 정렬 대상으로 뽑는다. index는 아래 동점 처리에 쓴다.
  final ranked = <({int index, PoiSearchResult store, double distanceM})>[];
  // 거리를 모르는 것은 여기 모았다가 뒤에 그대로 붙인다. 훑는 순서가 곧 입력
  // 순서라, 따로 정렬하지 않는 것만으로 상대 순서가 보존된다.
  final unknown = <PoiSearchResult>[];

  for (var index = 0; index < results.length; index++) {
    final store = results[index];
    final nodeId = store.nodeId;
    final found = nodeId == null ? null : reach[nodeId];
    if (found == null) {
      unknown.add(store);
      continue;
    }
    ranked.add((index: index, store: store, distanceM: found.distanceM));
  }

  // **Dart의 `List.sort`는 안정 정렬이 아니다.** 같은 노드를 공유하는 인접
  // 매장(푸드코트 한 줄처럼)은 거리가 정확히 같아서, 그대로 두면 호출할
  // 때마다 순서가 뒤바뀔 수 있다. 원래 인덱스를 2차 기준으로 넣어 동점을
  // 입력 순서로 깨면, 정렬 알고리즘이 무엇이든 결과가 하나로 정해진다.
  //
  // 표시하는 값이 `distanceM`이므로 정렬 기준도 `distanceM`이다. `costM`은
  // 수직 전이 선호가 인코딩된 튜닝값이라, 그걸로 세우면 화면에 적힌 거리가
  // 뒤죽박죽인 목록이 나온다.
  ranked.sort((a, b) {
    final byDistance = a.distanceM.compareTo(b.distanceM);
    if (byDistance != 0) return byDistance;
    return a.index.compareTo(b.index);
  });

  return [for (final entry in ranked) entry.store, ...unknown];
}
