import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../models/route/transit_route.dart';
import 'transit_repository.dart';

/// 카카오맵 대중교통 경로 조회 `GET /v2/routing/publictraffic`.
/// TMAP에서 옮긴 이유는 무료 제공량이다(TMAP 하루 10건 ↔ 카카오 1,000건).
///
/// **TMAP과 다른 점 셋.**
/// 1. 첫 승차 앞·마지막 하차 뒤 도보가 **응답에 없다**(공식 스펙). 빠진 양 끝은
///    화면이 채운다 — 후보가 15개 오는데 목록을 만들자고 보행자 API를 30번 부를
///    수는 없다.
/// 2. **"너무 가까움"을 알려주지 않는다** — 600m에도 12분짜리 버스를 `OK`로 준다.
///    그래서 부르기 전에 직선거리로 판단한다([_walkableMeters]).
/// 3. **후보 개수를 조절할 수 없다**(늘 전부, 실측 15개). 정렬한 뒤 우리가 자른다.
class KakaoTransitRepository implements TransitRepository {
  KakaoTransitRepository({http.Client? client, String? restApiKey})
    : _client = client ?? http.Client(),
      _restApiKey = restApiKey ?? kakaoRestApiKey;

  final http.Client _client;
  final String _restApiKey;

  /// 이 거리 안쪽이면 대중교통을 묻지 않고 [TransitRoutesStatus.tooClose]로
  /// 답한다. TMAP이 쓰던 기준과 같은 값으로 맞춰, 화면 문구("가까우니 걸어서
  /// 이동하세요")가 벤더를 바꿔도 같은 거리에서 뜨게 한다.
  static const _walkableMeters = 700.0;

  static const _distance = Distance();

  @override
  bool get isAvailable => _restApiKey.isNotEmpty;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 5,
  }) async {
    if (_distance.as(LengthUnit.Meter, origin, destination) < _walkableMeters) {
      _log('700m 이내라 호출하지 않음');
      return const TransitRoutes.failure(TransitRoutesStatus.tooClose);
    }

    // 좌표는 (x=경도, y=위도) 순서다. LatLng과 반대라 여기서 뒤집으면 응답이
    // STARTNODES_NULL로 오고, 화면에는 "대중교통 정보가 없다"로 보인다.
    final uri = Uri.parse('$kakaoTransitBaseUrl/publictraffic').replace(
      queryParameters: {
        'start_x': origin.longitude.toString(),
        'start_y': origin.latitude.toString(),
        'end_x': destination.longitude.toString(),
        'end_y': destination.latitude.toString(),
      },
    );

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'Authorization': 'KakaoAK $_restApiKey',
          'Accept': 'application/json',
        },
      );
    } on Object catch (error) {
      _log('요청 실패: $error');
      return const TransitRoutes.failure(TransitRoutesStatus.failed);
    }
    if (response.statusCode != 200) {
      // 401은 키가 틀렸거나 [제품 설정] > [카카오맵] 사용 설정이 꺼진 것이고,
      // 본문 `code: -10`은 쿼터 소진이다. 둘 다 사용자가 재시도해서 풀리지는
      // 않지만, 개발 중에 원인을 찾으려면 본문이 필요하다.
      _log('HTTP ${response.statusCode} — ${response.body}');
      return const TransitRoutes.failure(TransitRoutesStatus.failed);
    }

    // TMAP과 같은 이유로 bodyBytes에서 직접 UTF-8로 읽는다 — 노선명·정류장명이
    // 한글이라 잘못 디코딩되면 그대로 화면에 깨져 나온다.
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      return const TransitRoutes.failure(TransitRoutesStatus.failed);
    }

    final status = body['status'];
    if (status != 'OK') {
      _log('경로 없음 (status=$status)');
      return TransitRoutes.failure(_statusOf(status));
    }

    final rawRoutes = body['routes'];
    if (rawRoutes is! List) {
      return const TransitRoutes.failure(TransitRoutesStatus.noRoute);
    }

    final itineraries = <TransitItinerary>[];
    for (final route in rawRoutes) {
      if (route is! Map<String, dynamic>) continue;
      final itinerary = TransitItinerary.fromKakaoJson(route);
      if (itinerary != null) itineraries.add(itinerary);
    }
    if (itineraries.isEmpty) {
      return const TransitRoutes.failure(TransitRoutesStatus.noRoute);
    }

    // 빠른 순으로 정렬한 뒤 자른다. 카카오는 버스 우선·지하철 우선 묶음을 섞어
    // 주므로 첫 줄이 가장 빠른 경로가 아니고, 15개를 그대로 내보내면 사용자가
    // 목록 끝까지 훑어야 비교할 수 있다.
    itineraries.sort(
      (a, b) => a.totalTimeSeconds.compareTo(b.totalTimeSeconds),
    );
    final limit = count.clamp(1, itineraries.length);
    final trimmed = itineraries.take(limit).toList(growable: false);
    _log(
      '${itineraries.length}개 중 $limit개 (최단 ${trimmed.first.totalTimeSeconds}초)',
    );
    return TransitRoutes.ok(trimmed);
  }

  /// 카카오 `status` 문자열을 화면이 분기할 수 있는 상태로 좁힌다.
  ///
  /// 실호출로 확인한 값: 동일 좌표는 `EQUAL_POINTS`, 울릉도처럼 주변에 정류장이
  /// 없으면 `STARTNODES_NULL`이었다. 나머지는 문서 목록을 따랐다.
  static TransitRoutesStatus _statusOf(Object? status) {
    return switch (status) {
      // 출발·도착이 같은 점이면 갈 곳이 없다. 재시도가 아니라 "걸어가면 된다"에
      // 가까우므로 tooClose로 보낸다.
      'EQUAL_POINTS' => TransitRoutesStatus.tooClose,
      'STARTNODES_NULL' ||
      'ENDNODES_NULL' ||
      'NO_RESULTS' => TransitRoutesStatus.noRoute,
      // 우리가 파라미터를 잘못 보낸 경우다. 사용자에게는 일시 오류로 보이지만
      // 재시도해도 같은 결과이므로 로그로 남기고 failed로 둔다.
      'INVALID_REQUEST' => TransitRoutesStatus.failed,
      _ => TransitRoutesStatus.noRoute,
    };
  }

  void _log(String message) => debugPrint('[kakao-transit] $message');
}
