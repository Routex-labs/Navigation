import 'package:latlong2/latlong.dart';

class Building {
  const Building({
    required this.id,
    required this.name,
    required this.floors,
    this.entrance,
  });

  final String id;
  final String name;
  final List<int> floors;

  /// 건물 출입구의 야외(GPS) 좌표. 백엔드 응답에 없으면 null
  /// (야외 길찾기가 붙기 전 이전 스키마와의 호환을 위해 optional로 둔다).
  final LatLng? entrance;

  factory Building.fromJson(Map<String, dynamic> json) {
    final entrance = json['entrance'] as Map<String, dynamic>?;
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      floors: (json['floors'] as List<dynamic>).cast<int>(),
      entrance: entrance == null
          ? null
          : LatLng(
              (entrance['lat'] as num).toDouble(),
              (entrance['lng'] as num).toDouble(),
            ),
    );
  }
}
