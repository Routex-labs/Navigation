import 'package:latlong2/latlong.dart';

class PoiSearchResult {
  const PoiSearchResult({
    required this.name,
    required this.floor,
    required this.point,
    this.placeId,
    this.nodeId,
    this.category,
    this.subcategory,
  });

  final String name;
  final String floor;
  final LatLng point;

  /// 매장 상세 조회(`/buildings/{id}/places/{placeId}`)의 키. 백엔드 Store.id다.
  ///
  /// nullable인 이유는 이름으로 대신할 수 없기 때문이 아니라(오히려 이름은
  /// 유일 키가 아니다 — 에스컬레이터 152건·화장실 19건이 동명이고 매장 중에도
  /// 페어몬트 호텔 3건 같은 중복이 있다), **id 없이 저장된 이력이 기기에 남아
  /// 있어서**다. 저장한 장소는 이 필드가 도입되기 전 `건물+층+이름` 또는
  /// nodeId로만 저장됐고 이름 중복 때문에 소급 복원이 안전하지 않다.
  /// 그래서 이 값이 null이면 호출부는 상세 요청을 보내지 않고 코어 정보만
  /// 표시한다. 지도 탭·검색·카테고리 목록 경로에서는 항상 채워진다.
  final String? placeId;

  /// 경로탐색 시작/도착점으로 쓸 그래프 노드 ID. 매장의 entranceNodeId에서 온다.
  /// 없으면(예: 일부 POI) 실제 경로탐색은 불가능하다.
  final String? nodeId;

  /// 매장 대분류(예: 패션·뷰티·서비스). 매장 폴리곤 탭 흐름에서만 채워지고,
  /// 텍스트 검색/저장한 장소에서 온 경우엔 null일 수 있다.
  final String? category;

  /// 매장 소분류(예: 여성패션·남성패션). category와 함께만 의미 있음.
  final String? subcategory;
}
