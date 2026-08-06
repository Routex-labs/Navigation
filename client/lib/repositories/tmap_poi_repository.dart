import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/api_config.dart';
import '../models/outdoor_poi.dart';
import 'outdoor_poi_repository.dart';

/// TMAP(SK Open API) POI 통합검색 `GET /tmap/pois`.
/// https://openapi.sk.com/products/detail?linkMenuSeq=57
class TmapPoiRepository implements OutdoorPoiRepository {
  TmapPoiRepository({http.Client? client, String? appKey})
    : _client = client ?? http.Client(),
      _appKey = appKey ?? tmapAppKey;

  final http.Client _client;
  final String _appKey;

  @override
  bool get isAvailable => _appKey.isNotEmpty;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 1000,
    int limit = 10,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];

    // radius는 **km 단위 정수**다. 1을 넘겨야 1km이고, 1000을 넘기면 1000km가
    // 되어 전국 결과가 섞여 들어온다. 화면은 m로 말하는 게 자연스러우므로
    // 경계인 여기서 바꾼다. 올림하는 이유는 500m를 0km로 깎아 버리지 않기
    // 위해서다(0이면 TMAP이 반경 제한 없이 검색한다).
    final radiusKm = (radiusMeters / 1000).ceil().clamp(1, 33);

    final uri = Uri.parse('$tmapBaseUrl/pois').replace(
      queryParameters: {
        'version': '1',
        'searchKeyword': query,
        'centerLon': center.longitude.toString(),
        'centerLat': center.latitude.toString(),
        'radius': radiusKm.toString(),
        // 중심 좌표 기준 가까운 순. 이름 관련도 순(0)으로 두면 같은 브랜드의
        // 다른 지역 지점이 위로 올라와, 걸어갈 수 없는 후보가 첫 줄이 된다.
        'searchtypCd': 'R',
        'count': limit.clamp(1, 200).toString(),
        'resCoordType': 'WGS84GEO',
        'searchType': 'all',
        'multiPoint': 'N',
      },
    );

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'appKey': _appKey});
    } on Object {
      // 네트워크 실패는 실내 검색까지 막을 이유가 없다. 이 화면에서 POI는
      // 곁들이는 정보라, 조용히 빠지고 나머지 결과는 그대로 뜬다.
      return const [];
    }
    if (response.statusCode != 200) return const [];

    // TMAP은 한글 이름을 UTF-8로 내려주지만 charset을 헤더에 안 실어 줄 때가
    // 있다. http 패키지는 그 경우 latin1으로 디코딩해 "�"가 박히므로, 본문을
    // bodyBytes에서 직접 UTF-8로 읽는다.
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      return const [];
    }

    // 결과가 없으면 `searchPoiInfo`가 통째로 빠지거나 null로 온다. 중간 어느
    // 단계가 비어도 빈 목록으로 끝난다.
    final searchPoiInfo = body['searchPoiInfo'];
    if (searchPoiInfo is! Map<String, dynamic>) return const [];
    final pois = searchPoiInfo['pois'];
    if (pois is! Map<String, dynamic>) return const [];
    final list = pois['poi'];
    if (list is! List) return const [];

    final results = <OutdoorPoi>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final poi = OutdoorPoi.fromTmapJson(item);
      if (poi != null) results.add(poi);
    }
    return results;
  }
}
