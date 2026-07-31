import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:navigation_client/repositories/http_place_detail_repository.dart';

void main() {
  test('정상 상세 응답을 반환한다', () async {
    final repository = HttpPlaceDetailRepository(
      client: _FakeClient(
        (_) async => http.Response.bytes(utf8.encode(jsonEncode(_response)), 200),
      ),
    );

    final detail = await repository.getPlaceDetail('building-1', 'store-1');

    expect(detail?.id, 'store-1');
    expect(detail?.name, '테스트 매장');
  });

  test('HTTP 오류와 잘못된 응답은 null로 흡수한다', () async {
    final serverFailure = HttpPlaceDetailRepository(
      client: _FakeClient((_) async => http.Response('', 500)),
    );
    final malformedBody = HttpPlaceDetailRepository(
      client: _FakeClient((_) async => http.Response('{', 200)),
    );

    expect(await serverFailure.getPlaceDetail('building-1', 'store-1'), isNull);
    expect(await malformedBody.getPlaceDetail('building-1', 'store-1'), isNull);
  });

  test('네트워크 예외도 null로 흡수한다', () async {
    final repository = HttpPlaceDetailRepository(
      client: _FakeClient((_) => throw http.ClientException('offline')),
    );

    expect(await repository.getPlaceDetail('building-1', 'store-1'), isNull);
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

final _response = <String, Object?>{
  'kind': 'store',
  'id': 'store-1',
  'name': '테스트 매장',
  'subtitle': '1F · 패션',
  'category': '패션',
  'subcategory': '여성패션',
  'location': {
    'building_id': 'building-1',
    'floor_label': '1F',
    'position_local_m': {'x': 12.5, 'y': 4},
    'entrance_node_id': 'node-1',
  },
  'actions': [
    {'type': 'directions', 'label': '길찾기'},
  ],
  'sections': <Object?>[],
  'provenance': {'source': 'studio', 'updated_at': null},
};
