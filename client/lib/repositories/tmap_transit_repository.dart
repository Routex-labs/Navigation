import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/api_config.dart';
import '../models/transit_route.dart';
import 'transit_repository.dart';

/// TMAP(SK Open API) 대중교통 경로안내 `POST /transit/routes`.
/// https://openapi.sk.com/products/detail?linkMenuSeq=137
///
/// 보행자 경로와 **다른 base URL**을 쓴다(`/transit`, `/tmap`이 아니다).
class TmapTransitRepository implements TransitRepository {
  TmapTransitRepository({http.Client? client, String? appKey})
    : _client = client ?? http.Client(),
      _appKey = appKey ?? tmapAppKey;

  final http.Client _client;
  final String _appKey;

  /// "출발지와 도착지가 700m 이내"라 경로를 만들지 않는 경우의 응답 코드.
  /// **HTTP 200으로 온다** — 상태 코드만 보면 성공이므로 본문을 봐야 안다.
  static const _statusTooClose = 11;

  @override
  bool get isAvailable => _appKey.isNotEmpty;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 5,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$tmapTransitBaseUrl/routes'),
        headers: {
          'appKey': _appKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'startX': origin.longitude.toString(),
          'startY': origin.latitude.toString(),
          'endX': destination.longitude.toString(),
          'endY': destination.latitude.toString(),
          'count': count.clamp(1, 10),
          'lang': 0,
          'format': 'json',
        }),
      );
    } on Object {
      return const TransitRoutes.failure(TransitRoutesStatus.failed);
    }
    if (response.statusCode != 200) {
      return const TransitRoutes.failure(TransitRoutesStatus.failed);
    }

    // POI 검색과 같은 이유로 bodyBytes에서 직접 UTF-8로 읽는다 — 노선명·
    // 정류장명이 한글이라 잘못 디코딩되면 그대로 화면에 깨져 나온다.
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      return const TransitRoutes.failure(TransitRoutesStatus.failed);
    }

    // 경로가 없을 때는 metaData 대신 result가 온다. 200이라고 성공으로 읽으면
    // 여기서 빈 목록이 나가고, 화면은 "네트워크 오류"와 구분하지 못한다.
    final result = body['result'];
    if (result is Map<String, dynamic>) {
      final status = result['status'];
      final code = status is num ? status.round() : int.tryParse('$status');
      return TransitRoutes.failure(
        code == _statusTooClose
            ? TransitRoutesStatus.tooClose
            : TransitRoutesStatus.noRoute,
      );
    }

    final metaData = body['metaData'];
    if (metaData is! Map<String, dynamic>) {
      return const TransitRoutes.failure(TransitRoutesStatus.noRoute);
    }
    final plan = metaData['plan'];
    if (plan is! Map<String, dynamic>) {
      return const TransitRoutes.failure(TransitRoutesStatus.noRoute);
    }
    final rawItineraries = plan['itineraries'];
    if (rawItineraries is! List) {
      return const TransitRoutes.failure(TransitRoutesStatus.noRoute);
    }

    final itineraries = <TransitItinerary>[];
    for (final item in rawItineraries) {
      if (item is! Map<String, dynamic>) continue;
      final itinerary = TransitItinerary.fromTmapJson(item);
      if (itinerary != null) itineraries.add(itinerary);
    }
    if (itineraries.isEmpty) {
      return const TransitRoutes.failure(TransitRoutesStatus.noRoute);
    }
    // 빠른 순으로 정렬한다. TMAP은 pathType(최소 시간·최소 환승·최소 도보)
    // 순으로 섞어 주는데, 목록 첫 줄이 가장 빠른 경로가 아니면 사용자는
    // 아래까지 훑어야 비교할 수 있다.
    itineraries.sort(
      (a, b) => a.totalTimeSeconds.compareTo(b.totalTimeSeconds),
    );
    return TransitRoutes.ok(itineraries);
  }
}
