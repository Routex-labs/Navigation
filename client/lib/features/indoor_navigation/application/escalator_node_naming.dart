/// 에스컬레이터 노드 이름에서 **탑승/도착과 상대 층**을 읽는다.
///
/// 원본(다비오 Studio) 데이터의 에스컬레이터 노드 이름은 규칙을 가진다.
///
/// ```
/// 2F: ES1-UP(TO3F)   3F로 올라가는 상행 "탑승" 지점
/// 2F: ES1-UP(FR1F)   1F에서 올라온 상행 "도착" 지점
/// 3F: ES1-UP(FR2F)   2F에서 올라온 상행 도착 지점  ← TO3F의 짝
/// 1F: ES3-UP(FRB1)   지하층 표기도 같은 규칙
/// 5F: ES-UP(TO6F)    그룹 라벨이 비어 있는 노드도 있다
/// ```
///
/// **왜 이름을 쓰는가.** 백엔드가 만드는 수직 전이 간선은 두 층의 에스컬레이터
/// 노드를 8m 반경 위치 근접으로 1:1 매칭한다
/// (`backend/scripts/transform/vertical_transfers.py`). 그런데 한 랜딩에는
/// 상행 탑승 노드와 상행 도착 노드가 1.5m 거리로 붙어 있어서, 그 매칭이
/// "탑승↔탑승"으로 이어질 수도 있다. 라우팅 결과는 어느 쪽이든 멀쩡해 보이므로
/// 이 어긋남은 드러나지 않는다. 도착 위치를 정할 때는 이름이 유일하게 정확한
/// 근거이고, 전이 간선은 폴백으로만 쓴다.
library;

/// 에스컬레이터 진행 방향.
enum EscalatorDirection { up, down }

/// 노드가 그 층에서 갖는 역할.
///
/// - [boarding]: `(TO○○)` — 여기서 타면 다른 층으로 간다.
/// - [arrival]: `(FR○○)` — 다른 층에서 타고 온 사람이 내리는 지점.
enum EscalatorNodeRole { boarding, arrival }

/// 파싱된 에스컬레이터 노드 이름.
class EscalatorNodeName {
  const EscalatorNodeName({
    required this.group,
    required this.direction,
    required this.role,
    required this.otherFloorLabel,
  });

  /// 에스컬레이터 뱅크 식별자(`ES1`, `ES2-1`…). 이름에 없으면 빈 문자열.
  final String group;

  final EscalatorDirection direction;
  final EscalatorNodeRole role;

  /// [EscalatorNodeRole.boarding]이면 갈 층, [EscalatorNodeRole.arrival]이면
  /// 타고 온 층의 라벨(`3F`·`B1`). 층 목록의 표시 이름과 같은 표기다.
  final String otherFloorLabel;

  /// 노드 이름을 파싱한다. 규칙과 다르면 null — 다른 건물 데이터에서 이름
  /// 규칙이 없을 수 있고, 그때는 층 전이 판정이 폴백 경로로 내려가야 한다.
  static EscalatorNodeName? tryParse(String? name) {
    final raw = name?.trim();
    if (raw == null || raw.isEmpty) return null;
    final match = _pattern.firstMatch(raw);
    if (match == null) return null;
    final directionToken = match.group(2)!.toUpperCase();
    final roleToken = match.group(3)!.toUpperCase();
    return EscalatorNodeName(
      // 그룹 라벨은 대소문자·공백 차이를 흡수해 비교한다. `ES2-1`처럼 하이픈이
      // 들어간 그룹이 있어 하이픈은 그대로 둔다.
      group: match.group(1)!.trim().toUpperCase(),
      direction: directionToken == 'UP'
          ? EscalatorDirection.up
          : EscalatorDirection.down,
      role: roleToken == 'TO'
          ? EscalatorNodeRole.boarding
          : EscalatorNodeRole.arrival,
      otherFloorLabel: match.group(4)!.trim().toUpperCase(),
    );
  }

  /// 이 노드가 [fromFloorLabel]에서 [direction]으로 올라온 사람의 **도착 지점**인지.
  ///
  /// 도착 노드를 새 층 그래프에서 찾을 때 쓴다. 문자열을 다시 조립해 비교하지
  /// 않고 구조로 비교하는 이유는, 원본에 `DN`과 `DOWN` 표기가 섞여 있어도
  /// 같은 뜻으로 다뤄야 하기 때문이다.
  bool isArrivalOf({
    required String group,
    required EscalatorDirection direction,
    required String fromFloorLabel,
  }) =>
      role == EscalatorNodeRole.arrival &&
      this.direction == direction &&
      this.group == group.trim().toUpperCase() &&
      otherFloorLabel == fromFloorLabel.trim().toUpperCase();

  /// `ES1-UP(TO3F)` 형태. 로그·테스트 가독성용이며 비교에는 쓰지 않는다.
  @override
  String toString() {
    final directionToken = direction == EscalatorDirection.up ? 'UP' : 'DN';
    final roleToken = role == EscalatorNodeRole.boarding ? 'TO' : 'FR';
    return '$group-$directionToken($roleToken$otherFloorLabel)';
  }

  // 그룹은 최소 매칭이라 `ES2-1-DN(TO1F)`에서 그룹이 `ES2-1`로 잡힌다.
  static final RegExp _pattern = RegExp(
    r'^(.*?)-(UP|DN|DOWN)\s*\(\s*(TO|FR)\s*([A-Za-z0-9]+)\s*\)$',
    caseSensitive: false,
  );
}
