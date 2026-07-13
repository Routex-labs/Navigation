import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/floor_plan.dart';

void main() {
  group('FloorPlan.approximateCurrentLocation', () {
    test('prefers the footprint centroid when available', () {
      final floorPlan = FloorPlan(
        footprint: const [
          LatLng(37.0, 127.0),
          LatLng(38.0, 129.0),
        ],
        corridors: const [
          [LatLng(1.0, 1.0)],
        ],
        pois: const [PoiMarker(name: '화장실', point: LatLng(2.0, 2.0))],
      );

      final location = floorPlan.approximateCurrentLocation();

      expect(location, const LatLng(37.5, 128.0));
    });

    test('falls back to the first corridor point when there is no footprint', () {
      final floorPlan = FloorPlan(
        corridors: const [
          [LatLng(37.1, 127.1), LatLng(37.2, 127.2)],
        ],
        pois: const [PoiMarker(name: '화장실', point: LatLng(2.0, 2.0))],
      );

      final location = floorPlan.approximateCurrentLocation();

      expect(location, const LatLng(37.1, 127.1));
    });

    test('falls back to the first POI when there is no footprint or corridor', () {
      final floorPlan = FloorPlan(
        pois: const [PoiMarker(name: '화장실', point: LatLng(37.3, 127.3))],
      );

      final location = floorPlan.approximateCurrentLocation();

      expect(location, const LatLng(37.3, 127.3));
    });

    test('returns null when no location data is available at all', () {
      const floorPlan = FloorPlan(pois: []);

      expect(floorPlan.approximateCurrentLocation(), isNull);
    });
  });
}
