import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/api_config.dart';
import '../models/directions_route.dart';
import 'directions_repository.dart';

/// TMAP(SK Open API) 보행자 경로 안내 POST /routes/pedestrian 호출.
/// https://openapi.sk.com/products/detail?linkMenuSeq=45
class TmapDirectionsRepository implements DirectionsRepository {
  TmapDirectionsRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DirectionsRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final response = await _client.post(
      Uri.parse('$tmapBaseUrl/routes/pedestrian?version=1'),
      headers: {'appKey': tmapAppKey},
      body: {
        'startX': origin.longitude.toString(),
        'startY': origin.latitude.toString(),
        'endX': destination.longitude.toString(),
        'endY': destination.latitude.toString(),
        'startName': '현재 위치',
        'endName': '목적지',
      },
    );

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (body['features'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    if (features.isEmpty) return null;

    // totalDistance/totalTime은 첫 Feature의 properties에만 들어있다.
    final summary = features.first['properties'] as Map<String, dynamic>;
    final distanceMeters = (summary['totalDistance'] as num).toDouble();
    final durationSeconds = (summary['totalTime'] as num).round();

    final points = <LatLng>[];
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry?['type'] != 'LineString') continue;
      for (final coordinate in geometry!['coordinates'] as List<dynamic>) {
        final pair = coordinate as List<dynamic>;
        points.add(
          LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
        );
      }
    }

    return DirectionsRoute(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }
}
