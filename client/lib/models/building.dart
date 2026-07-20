import 'package:latlong2/latlong.dart';

class Building {
  const Building({
    required this.id,
    required this.name,
    required this.floors,
    this.defaultFloor,
    this.entrance,
  });

  final String id;
  final String name;

  /// 엘리베이터 버튼판 순서(위층 → 아래층). 표시 순서일 뿐 기본 층이 아니다 —
  /// 지하층이 있는 건물은 첫 항목이 최상층이다.
  final List<String> floors;

  /// 앱이 처음 열 층(보통 출입구가 있는 1F). 백엔드가 목록 순서와 분리해
  /// 내려준다. 응답에 없는 구버전 백엔드면 null이고, [initialFloor]가 폴백한다.
  final String? defaultFloor;

  /// 건물 출입구의 야외(GPS) 좌표. 백엔드 응답에 없으면 null
  /// (야외 길찾기가 붙기 전 이전 스키마와의 호환을 위해 optional로 둔다).
  final LatLng? entrance;

  /// 지도를 열 때 선택할 층. default_floor가 오면 그것을, 아니면 목록의 첫
  /// 항목을 쓴다. 층이 하나도 없으면 null.
  String? get initialFloor {
    if (defaultFloor != null && floors.contains(defaultFloor)) {
      return defaultFloor;
    }
    return floors.isEmpty ? null : floors.first;
  }

  factory Building.fromJson(Map<String, dynamic> json) {
    final entrance = json['entrance'] as Map<String, dynamic>?;
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      floors: (json['floors'] as List<dynamic>).cast<String>(),
      defaultFloor: json['default_floor'] as String?,
      entrance: entrance == null
          ? null
          : LatLng(
              (entrance['lat'] as num).toDouble(),
              (entrance['lng'] as num).toDouble(),
            ),
    );
  }
}
