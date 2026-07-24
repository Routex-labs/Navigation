import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/api_config.dart';
import '../models/poi_search_result.dart';
import 'destination_repository.dart';

/// api/app/routers/query.py의 POST /query/destination을 호출한다.
///
/// 백엔드는 매칭 최적 1건만 돌려주므로(app/repositories/query_search.py의
/// _rank가 tier+level+id로 정렬 후 첫 번째), 이 구현이 돌려주는 리스트는
/// 최대 원소 1개 또는 빈 리스트가 된다. 길찾기 시트가 여러 후보를 나열해
/// 훑는 UX는 백엔드가 상위 N개를 돌려줄 수 있게 확장될 때 함께 재검토한다.
///
/// 응답 스키마는 app/dto/query.py의 DestinationResponse와 정확히 맞춘다:
///   { "status": "ok" | "ok_no_route" | "no_match",
///     "query": "...",
///     "match": { store_id, name, category, subcategory, floor_id,
///                floor_name, entrance_node_id, centroid_local_m,
///                centroid_wgs84 } | null }
class HttpDestinationRepository implements DestinationRepository {
  HttpDestinationRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloor,
  }) async {
    // 백엔드는 text.min_length=1을 강제해 빈 문자열이면 422를 낸다. 시트를
    // 처음 열 때(_search('')) 등 정상 흐름에서도 빈 쿼리가 들어오므로,
    // HTTP를 아예 태우지 않고 조용히 빈 결과를 돌려준다.
    if (query.trim().isEmpty) return const [];

    final response = await _client.post(
      Uri.parse('$apiBaseUrl/query/destination'),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: utf8.encode(jsonEncode({
        'text': query,
        'building_id': buildingId,
        'current_floor': ?currentFloor,
      })),
    );

    // 건물이 없거나(404) 검증 실패(422) 등은 검색 UX 관점에서 "결과 없음"과
    // 같아서 그대로 빈 리스트를 돌려준다 — 시트가 계속 뜨도록 예외를 던지지
    // 않는다. 다른 5xx는 진짜 서버 장애이므로 호출자에게 전파한다.
    if (response.statusCode == 404 || response.statusCode == 422) {
      return const [];
    }
    if (response.statusCode >= 500) {
      throw http.ClientException(
        'destination query failed: ${response.statusCode}',
        response.request?.url,
      );
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final match = body['match'];
    if (match is! Map<String, dynamic>) return const [];

    // 서버는 centroid_wgs84가 null일 수 있다(건물에 실측 wgs84 앵커가 없어
    // GeoTransform을 못 피팅할 때 — thehyundai-seoul은 합성 앵커로 항상
    // 값이 있지만, 다른 건물이 붙었을 때 폴백을 지도 위 (0,0)으로 튀지
    // 않게 걸러낸다). 지도에 놓을 자리가 없으면 결과에서 뺀다.
    final centroidWgs84 = match['centroid_wgs84'];
    if (centroidWgs84 is! Map<String, dynamic>) return const [];
    final lat = (centroidWgs84['lat'] as num?)?.toDouble();
    final lng = (centroidWgs84['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return const [];

    return [
      PoiSearchResult(
        name: match['name'] as String,
        // 백엔드는 UI에 보여줄 층 라벨을 floor_name으로 준다(예: "B2").
        // Floor 테이블의 name 컬럼과 일치하므로 클라이언트가 이 값 그대로
        // 층 선택·필터에 쓸 수 있다.
        floor: match['floor_name'] as String,
        point: LatLng(lat, lng),
        // 온디바이스 다익스트라의 도착 노드. status == "ok_no_route"면
        // 서버가 이 필드를 null로 준다(입구 노드가 아직 스냅되지 않은
        // 매장) — 그 경우엔 nodeId 없이 후보만 노출하고 실제 경로 계산은
        // 시도되지 않게 둔다.
        nodeId: match['entrance_node_id'] as String?,
        category: match['category'] as String?,
        subcategory: match['subcategory'] as String?,
      ),
    ];
  }
}
