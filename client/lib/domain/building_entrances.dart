/// 건물의 **지상 출입구**(1층 "출구")를 고르는 순수 로직.
///
/// 야외 GPS에서 실내 매장까지 경로를 한 줄로 이으려면 그 사이에 "어느 문으로
/// 들어가는가"가 반드시 끼어야 한다. 문을 안 고르면 야외 경로의 도착점이 건물
/// 안 좌표가 되어, TMAP이 건물 외벽 아무 곳으로나 안내한다.
///
/// 문은 데이터에 이미 있다 — 1층 `편의시설/교통` 소분류의 "출구"는 야외 좌표와
/// 실내 그래프 노드를 한 쌍으로 갖는다. 야외 경로는 좌표에서 끝내고 실내 경로는
/// 노드에서 시작하면 두 구간이 정확히 맞물린다.
///
/// 같은 소분류의 지하철역 마커는 노드가 비어 있어서, [groundEntrancesFrom]은
/// 소분류만이 아니라 **노드가 있는지**로 한 번 더 거른다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/floor_plan.dart';

/// 지상 출입구가 들어 있는 매장 소분류.
const kGroundEntranceSubcategory = '교통';

/// 안내 중인 문을 다른 문으로 바꾸려면 새 문이 이만큼 더 가까워야 한다(m).
///
/// 이 값이 0이면 문 선택이 GPS 오차를 그대로 따라 흔들린다. 실외 오차는 좋은
/// 조건에서도 10 m 안팎이고 건물 벽 옆에서는 더 나빠지는데, 더현대 서울의 문
/// 5개는 서로 40~100 m 떨어져 있으므로 두 문의 거리 차가 오차 범위 안으로
/// 들어오는 구간이 실제로 생긴다. 그 구간에서 사용자는 가만히 서 있는데 안내가
/// "서쪽 출구 → 남쪽 출구 → 서쪽 출구"로 튀는 화면을 본다.
///
/// 15 m는 실외 GPS 오차 한 눈금(= [trustedAccuracyMeters] 15 m)과 같은 값이다.
/// 오차만큼의 이득으로는 문을 바꾸지 않고, 그보다 확실히 가까워졌을 때만 바꾼다.
const kEntranceSwitchMarginMeters = 15.0;

/// 건물의 지상 출입구 하나.
class BuildingEntrance {
  const BuildingEntrance({
    required this.id,
    required this.name,
    required this.nodeId,
    required this.point,
  });

  /// 백엔드 Store.id. 같은 이름("출구")이 5개라 화면·로그에서 문을 구분하려면
  /// 이름이 아니라 이 값을 써야 한다.
  final String id;

  /// 원본 이름. 더현대 데이터에서는 전부 "출구"라 그대로는 구분에 못 쓴다 —
  /// 사용자에게 보일 문구는 [entranceDirectionLabel]로 만든다.
  final String name;

  /// **실내** 경로가 시작할 그래프 노드 id.
  final String nodeId;

  /// **야외** 도보 경로가 끝날 좌표(문 앞).
  ///
  /// [nodeId] 노드의 좌표와 7~12 m 떨어져 있다. 어긋난 게 아니라 문 바깥과 문
  /// 안쪽이라서 그렇고, 두 구간이 각자 맞는 좌표를 쓰는 편이 자연스럽다.
  final LatLng point;
}

/// 층 평면도에서 지상 출입구만 추린다. 없으면 빈 목록.
///
/// 호출자는 빈 목록을 **정상 상황으로** 다뤄야 한다. 출입구가 찍히지 않은
/// 건물이 있을 수 있고, 그때는 문을 경유하지 않는 기존 안내로 폴백하는 것이
/// 맞다 — 여기서 예외를 던지면 길찾기가 통째로 죽는다.
List<BuildingEntrance> groundEntrancesFrom(FloorPlan plan) {
  final entrances = <BuildingEntrance>[];
  for (final store in plan.stores) {
    if (store.subcategory != kGroundEntranceSubcategory) continue;
    final nodeId = store.entranceNodeId;
    // 노드가 없는 지점(지하철역 마커 등)은 실내 구간을 시작할 수 없으므로 제외.
    if (nodeId == null || nodeId.isEmpty) continue;
    entrances.add(
      BuildingEntrance(
        id: store.id,
        name: store.name,
        nodeId: nodeId,
        point: store.centroid,
      ),
    );
  }
  return entrances;
}

/// [from]에서 가장 가까운 문을 고른다. 후보가 없으면 null.
///
/// [current]를 주면 **그 문을 웃돈 없이 밀어내지 않는다** — 새 후보가
/// [switchMarginMeters]보다 확실히 가까울 때만 바꾼다. 근거는
/// [kEntranceSwitchMarginMeters] 주석.
///
/// [current]가 목록에 없으면(문 데이터가 갈린 경우) 이력이 없는 것으로 보고
/// 그냥 최근접을 고른다.
BuildingEntrance? nearestEntrance(
  List<BuildingEntrance> entrances,
  LatLng from, {
  BuildingEntrance? current,
  double switchMarginMeters = kEntranceSwitchMarginMeters,
}) {
  if (entrances.isEmpty) return null;

  BuildingEntrance? best;
  var bestDistance = double.infinity;
  for (final entrance in entrances) {
    final distance = wgs84DistanceMeters(from, entrance.point);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = entrance;
    }
  }

  BuildingEntrance? held;
  if (current != null) {
    for (final entrance in entrances) {
      if (entrance.id != current.id) continue;
      held = entrance;
      break;
    }
  }
  if (held == null) return best;
  if (best == null || best.id == held.id) return held;

  final heldDistance = wgs84DistanceMeters(from, held.point);
  // 이득이 마진에 못 미치면 쥐고 있던 문을 유지한다.
  return heldDistance - bestDistance > switchMarginMeters ? best : held;
}

/// 사용자에게 보일 문 이름을 만든다(예: "남쪽 출구").
///
/// 원본 이름이 5개 모두 "출구"라 그대로 쓰면 어느 문인지 알 수 없다. 건물
/// 중심에서 본 방위를 앞에 붙여 구분한다 — 백화점 안내에서 실제로 쓰는 표현과
/// 같은 형태고, 사용자가 지도를 안 봐도 어느 쪽인지 감이 잡힌다.
///
/// [buildingCenter]가 없으면(외곽선을 못 받은 건물) 방위를 계산할 근거가 없으니
/// 원본 이름을 그대로 돌려준다.
String entranceDirectionLabel(
  BuildingEntrance entrance,
  LatLng? buildingCenter,
) {
  if (buildingCenter == null) return entrance.name;
  final latDelta = entrance.point.latitude - buildingCenter.latitude;
  // 경도 1도는 위도 1도보다 짧다(cos 위도 배). 보정 없이 각을 재면 동서로
  // 납작한 건물에서 방위가 남북 쪽으로 쏠린다.
  final lngDelta =
      (entrance.point.longitude - buildingCenter.longitude) *
      _cosLatitude(buildingCenter.latitude);
  if (latDelta == 0 && lngDelta == 0) return entrance.name;

  const labels = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
  final bearing = (_atan2Degrees(lngDelta, latDelta) + 360) % 360;
  final index = (((bearing + 22.5) % 360) ~/ 45).toInt();
  return '${labels[index]}쪽 ${entrance.name}';
}

double _cosLatitude(double latitude) =>
    math.cos(latitude * math.pi / 180);

double _atan2Degrees(double y, double x) =>
    math.atan2(y, x) * 180 / math.pi;
