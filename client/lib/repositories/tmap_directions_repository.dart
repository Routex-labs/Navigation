import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/api_config.dart';
import '../models/directions_route.dart';
import 'directions_repository.dart';

/// TMAP(SK Open API) 경로 안내.
///
/// - 보행자: POST `/routes/pedestrian` — https://openapi.sk.com/products/detail?linkMenuSeq=45
/// - 자동차: POST `/routes` — 같은 appKey로 호출한다.
///
/// 두 응답이 **같은 모양**이라 파싱을 한 곳에 모았다(FeatureCollection이고,
/// 총 거리·시간은 첫 Feature의 properties에만 들어 있으며, 선은 LineString
/// Feature들에 쪼개져 있다). 다른 것은 자동차 응답에만 요금 필드가 붙는 정도다.
class TmapDirectionsRepository implements DirectionsRepository {
  TmapDirectionsRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DirectionsRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return _request(
      Uri.parse('$tmapBaseUrl/routes/pedestrian?version=1'),
      origin: origin,
      destination: destination,
    );
  }

  @override
  Future<DirectionsRoute?> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return _request(
      Uri.parse('$tmapBaseUrl/routes?version=1'),
      origin: origin,
      destination: destination,
      // 0 = 교통최적+추천. 화면에 "내비 추천"으로 적는 값이라 여기서 고정한다 —
      // 옵션을 사용자에게 열어 두려면 그때 인자로 올린다.
      extra: const {'searchOption': '0', 'trafficInfo': 'N'},
    );
  }

  Future<DirectionsRoute?> _request(
    Uri uri, {
    required LatLng origin,
    required LatLng destination,
    Map<String, String> extra = const {},
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {'appKey': tmapAppKey},
        body: {
          'startX': origin.longitude.toString(),
          'startY': origin.latitude.toString(),
          'endX': destination.longitude.toString(),
          'endY': destination.latitude.toString(),
          'reqCoordType': 'WGS84GEO',
          'resCoordType': 'WGS84GEO',
          'startName': '출발지',
          'endName': '목적지',
          ...extra,
        },
      );
    } on Object {
      // 네트워크가 끊긴 경우다. 여기서 던지면 화면이 통째로 죽으므로, 다른
      // 실패(키 오류·경로 없음)와 같은 자리로 모아 호출부가 한 가지 안내만
      // 하게 한다.
      return null;
    }

    if (response.statusCode != 200) return null;

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object {
      return null;
    }
    final features = (body['features'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (features.isEmpty) return null;

    // totalDistance/totalTime은 첫 Feature의 properties에만 들어있다.
    final summary = features.first['properties'];
    if (summary is! Map<String, dynamic>) return null;
    final distanceMeters = _number(summary['totalDistance']);
    final durationSeconds = _number(summary['totalTime']);
    if (distanceMeters == null || durationSeconds == null) return null;

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
      durationSeconds: durationSeconds.round(),
      // 보행자 응답에는 없는 필드라 null로 남는다. 그 null이 곧 "이 수단엔
      // 요금 개념이 없다"는 뜻이다([DirectionsRoute.tollFareWon]).
      tollFareWon: _number(summary['totalFare'])?.round(),
      taxiFareWon: _number(summary['taxiFare'])?.round(),
    );
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}
