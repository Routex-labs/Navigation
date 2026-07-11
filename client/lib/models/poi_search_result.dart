import 'package:latlong2/latlong.dart';

class PoiSearchResult {
  const PoiSearchResult({
    required this.name,
    required this.floor,
    required this.point,
    this.nodeId,
  });

  final String name;
  final String floor;
  final LatLng point;

  /// 경로탐색 시작/도착점으로 쓸 그래프 노드 ID. 매장의 entranceNodeId에서 온다.
  /// 없으면(예: 일부 POI) 실제 경로탐색은 불가능하다.
  final String? nodeId;
}
