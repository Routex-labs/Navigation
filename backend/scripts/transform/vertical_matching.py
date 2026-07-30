"""결정적 최소비용 이분 매칭.

수직 전이 생성(vertical_transfers)이 "아래층 노드 ↔ 위층 노드"를 위치로 짝지을 때,
예전처럼 노드를 입력 순서대로 훑으며 가장 가까운 미사용 노드를 집으면 후보 거리가
비슷할 때 **입력 순서에 따라 결과가 달라진다**. 여기서는 전역 최적 할당(minimum-cost
matching)을 결정적으로 풀어 그 순서 의존성을 없앤다.

- **최적**: 순차 탐욕이 아니라 총비용이 최소가 되는 1:1 짝을 고른다.
- **결정적**: a·b를 id로 정렬해 고정된 비용 행렬을 만든 뒤 헝가리안 알고리즘을 돌리므로,
  입력 순서가 어떻든 같은 짝이 나온다(동점 최적해도 행렬이 고정이라 하나로 결정된다).
- **금지 쌍**: 반경 밖 등 이어선 안 되는 쌍은 cost=None으로 주면 매칭에서 빠진다.

scipy에 의존하지 않으려고 표준 O(n³) Kuhn-Munkres(헝가리안)를 직접 담았다. 수직 전이의
매칭 규모는 층쌍·방향당 노드 몇 개 수준이라 성능은 문제되지 않는다.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence


# 정사각 비용 행렬의 최소비용 완전 할당. 반환: 행 i에 할당된 열 인덱스 리스트.
# e-maxx의 결정적 헝가리안 구현(행/열 순서가 고정이면 결과도 고정).
def _hungarian(cost: list[list[float]]) -> list[int]:
    n = len(cost)
    if n == 0:
        return []
    inf = float("inf")
    # 1-indexed 보조 배열(0번은 가상 시작점).
    u = [0.0] * (n + 1)
    v = [0.0] * (n + 1)
    p = [0] * (n + 1)  # p[j] = 열 j에 할당된 행(1-indexed), 0이면 미할당
    way = [0] * (n + 1)
    for i in range(1, n + 1):
        p[0] = i
        j0 = 0
        minv = [inf] * (n + 1)
        used = [False] * (n + 1)
        while True:
            used[j0] = True
            i0 = p[j0]
            delta = inf
            j1 = -1
            for j in range(1, n + 1):
                if not used[j]:
                    cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
                    if cur < minv[j]:
                        minv[j] = cur
                        way[j] = j0
                    if minv[j] < delta:
                        delta = minv[j]
                        j1 = j
            for j in range(n + 1):
                if used[j]:
                    u[p[j]] += delta
                    v[j] -= delta
                else:
                    minv[j] -= delta
            j0 = j1
            if p[j0] == 0:
                break
        while j0:
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
    result = [0] * n
    for j in range(1, n + 1):
        if p[j] != 0:
            result[p[j] - 1] = j - 1
    return result


def min_cost_matching(
    a_ids: Sequence[str],
    b_ids: Sequence[str],
    cost: Callable[[str, str], float | None],
) -> list[tuple[str, str]]:
    """a와 b를 최소비용으로 1:1 짝짓는다. 금지 쌍(cost=None)은 제외.

    반환: [(a_id, b_id)] — 짝지어진 유효 쌍만, a_id 기준 정렬. 짝을 못 얻은 노드는 빠진다.
    """
    # 결정성의 핵심: 입력 순서와 무관하게 id로 정렬해 고정된 행렬을 만든다.
    a_sorted = sorted(a_ids)
    b_sorted = sorted(b_ids)
    if not a_sorted or not b_sorted:
        return []

    # 금지 쌍이 강제로 선택되지 않도록, 허용된 최대 비용보다 훨씬 큰 값을 벽으로 쓴다.
    allowed = [value for a in a_sorted for b in b_sorted if (value := cost(a, b)) is not None]
    wall = (max(allowed) + 1.0) * 1000.0 if allowed else 1.0

    # 헝가리안은 정사각 행렬을 요구하므로 max(len)으로 패딩한다. 패딩 행/열과 금지 쌍은 wall.
    size = max(len(a_sorted), len(b_sorted))
    matrix = [[wall] * size for _ in range(size)]
    for i, a in enumerate(a_sorted):
        for j, b in enumerate(b_sorted):
            value = cost(a, b)
            if value is not None:
                matrix[i][j] = value

    assignment = _hungarian(matrix)

    pairs: list[tuple[str, str]] = []
    for i, j in enumerate(assignment):
        if i < len(a_sorted) and j < len(b_sorted):
            # 패딩·금지(벽)로 억지로 이어진 쌍은 버린다 — 실제 허용된 짝만 남긴다.
            if cost(a_sorted[i], b_sorted[j]) is not None:
                pairs.append((a_sorted[i], b_sorted[j]))
    pairs.sort()
    return pairs
