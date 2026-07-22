import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/api_config.dart';
import '../models/poi_search_result.dart';
import 'destination_repository.dart';

/// api/app/routers/query.py의 POST /query/destination을 호출한다.
/// 백엔드는 아직 스텁이라 result가 항상 null이며, 실제 RAG가 붙으면
/// 응답 형태에 맞춰 파싱 로직만 갱신하면 된다.
class HttpDestinationRepository implements DestinationRepository {
  HttpDestinationRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    final response = await _client.post(
      Uri.parse('$apiBaseUrl/query/destination'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': query,
        'building_id': buildingId,
        'current_floor_id': ?currentFloorId,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = body['result'];
    if (result is! List) return [];

    return result
        .cast<Map<String, dynamic>>()
        .map(
          (poi) => PoiSearchResult(
            name: poi['name'] as String,
            floor: poi['floor'] as String,
            // 백엔드 RAG가 좌표를 내려주기 시작하면 여기서 파싱한다.
            point: LatLng(
              (poi['lat'] as num?)?.toDouble() ?? 0,
              (poi['lng'] as num?)?.toDouble() ?? 0,
            ),
          ),
        )
        .toList();
  }
}
