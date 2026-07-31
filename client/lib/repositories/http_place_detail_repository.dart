import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/place_detail.dart';
import 'place_detail_repository.dart';

/// 백엔드 place detail API를 호출한다. HTTP·디코딩·계약 오류는 전부 null로
/// 흡수한다. 상세가 부가 정보이므로 오류가 시트의 기본 길찾기를 막으면 안 된다.
class HttpPlaceDetailRepository implements PlaceDetailRepository {
  HttpPlaceDetailRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<PlaceDetail?> getPlaceDetail(String buildingId, String placeId) async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/places/$placeId'),
      );
      if (response.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      return PlaceDetail.fromJson(body);
    } catch (_) {
      return null;
    }
  }
}
