import 'package:latlong2/latlong.dart';

class PoiSearchResult {
  const PoiSearchResult({
    required this.name,
    required this.floor,
    required this.point,
  });

  final String name;
  final int floor;
  final LatLng point;
}
