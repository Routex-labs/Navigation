import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_client/models/discovery_result.dart';
import 'package:navigation_client/repositories/http_destination_repository.dart';

/// 백엔드 DestinationResponse(app/dto/query.py) 한 건. `/query/destination`
/// 전용 계약이다 — `/query/ai`는 DiscoveryResponse로 계약이 다르다(아래
/// `_discoveryBody` 참고).
Map<String, dynamic> _matchBody({
  String name = '스시코우지',
  String floorName = 'B1',
  String? entranceNodeId = 'FL-1:ND-1',
  Map<String, dynamic>? centroidWgs84 = const {'lat': 37.52, 'lng': 126.92},
}) => {
  'status': entranceNodeId == null ? 'ok_no_route' : 'ok',
  'query': '밥 먹을 곳',
  'match': {
    'store_id': 'ST-1',
    'name': name,
    'category': '음식점',
    'subcategory': '일식',
    'floor_id': 'FL-1',
    'floor_name': floorName,
    'entrance_node_id': entranceNodeId,
    'centroid_local_m': {'x': 12.3, 'y': 45.6},
    'centroid_wgs84': centroidWgs84,
  },
};

/// 백엔드 DiscoveryResponse(app/dto/query.py) 한 건. `/query/ai` 전용 계약.
Map<String, dynamic> _discoveryMatchJson({
  String storeId = 'ST-1',
  String name = '스시코우지',
  String floorName = 'B1',
  String? entranceNodeId = 'FL-1:ND-1',
  Map<String, dynamic>? centroidWgs84 = const {'lat': 37.52, 'lng': 126.92},
  Map<String, dynamic>? matchedFacets,
  String? reason,
}) => {
  'store_id': storeId,
  'name': name,
  'category': '음식점',
  'subcategory': '일식',
  'floor_id': 'FL-1',
  'floor_name': floorName,
  'entrance_node_id': entranceNodeId,
  'centroid_local_m': {'x': 12.3, 'y': 45.6},
  'centroid_wgs84': centroidWgs84,
  'matched_facets': matchedFacets,
  'reason': reason,
};

Map<String, dynamic> _discoveryBody({
  String mode = 'direct',
  String query = '밥 먹을 곳',
  String? question,
  List<Map<String, dynamic>> options = const [],
  List<Map<String, dynamic>> matches = const [],
}) => {
  'mode': mode,
  'query': query,
  'question': question,
  'options': options,
  'matches': matches,
};

http.Response _json(Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('searchDestinationsAi', () {
    test('POST /query/ai를 계약대로 호출한다', () async {
      late http.Request captured;
      final repository = HttpDestinationRepository(
        client: MockClient((request) async {
          captured = request;
          return _json(_discoveryBody());
        }),
      );

      await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '밥 먹을 곳',
        currentFloorId: 'B2',
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, endsWith('/query/ai'));
      final body = jsonDecode(utf8.decode(captured.bodyBytes));
      expect(body, {
        'text': '밥 먹을 곳',
        'building_id': 'thehyundai-seoul',
        'current_floor_id': 'B2',
      });
    });

    test('current_floor_id가 없으면 아예 보내지 않는다', () async {
      late http.Request captured;
      final repository = HttpDestinationRepository(
        client: MockClient((request) async {
          captured = request;
          return _json(_discoveryBody());
        }),
      );

      await repository.searchDestinationsAi('thehyundai-seoul', '밥 먹을 곳');

      final body =
          jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body.containsKey('current_floor_id'), isFalse);
    });

    test('selected_facets를 실어 보낸다', () async {
      late http.Request captured;
      final repository = HttpDestinationRepository(
        client: MockClient((request) async {
          captured = request;
          return _json(_discoveryBody(mode: 'results'));
        }),
      );

      await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '신발',
        selectedFacets: {
          'styles': ['스포츠'],
        },
      );

      final body =
          jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['selected_facets'], {
        'styles': ['스포츠'],
      });
    });

    test('selected_facets가 없으면 아예 보내지 않는다', () async {
      late http.Request captured;
      final repository = HttpDestinationRepository(
        client: MockClient((request) async {
          captured = request;
          return _json(_discoveryBody());
        }),
      );

      await repository.searchDestinationsAi('thehyundai-seoul', '신발');

      final body =
          jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body.containsKey('selected_facets'), isFalse);
    });

    test('direct: matches 1건과 mode를 파싱한다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(
            _discoveryBody(matches: [_discoveryMatchJson()]),
          ),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '밥 먹을 곳',
      );

      expect(result.mode, DiscoveryMode.direct);
      expect(result.matches, hasLength(1));
      final match = result.matches.single;
      expect(match.storeId, 'ST-1');
      expect(match.name, '스시코우지');
      expect(match.floorName, 'B1');
      expect(match.floorId, 'FL-1');
      expect(match.entranceNodeId, 'FL-1:ND-1');
      expect(match.point.latitude, 37.52);
      expect(match.matchedFacets, isEmpty);
      expect(match.reason, isNull);
    });

    test('clarify: question·options·초기 후보를 함께 파싱한다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(
            _discoveryBody(
              mode: 'clarify',
              query: '신발',
              question: '어떤 스타일의 신발을 찾으세요?',
              options: const [
                {'facet': 'styles', 'value': '스포츠', 'label': '스포츠', 'count': 3},
                {'facet': 'styles', 'value': '캐주얼', 'label': '캐주얼', 'count': 4},
              ],
              matches: [
                _discoveryMatchJson(
                  storeId: 'ST-2',
                  name: '나이키 라이즈',
                  matchedFacets: const {
                    'styles': ['스포츠'],
                  },
                  reason: '스포츠 신발을 찾을 때 볼 만해요.',
                ),
              ],
            ),
          ),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '신발',
      );

      expect(result.mode, DiscoveryMode.clarify);
      expect(result.question, '어떤 스타일의 신발을 찾으세요?');
      expect(result.options, hasLength(2));
      expect(result.options.first.facet, 'styles');
      expect(result.options.first.value, '스포츠');
      expect(result.options.first.count, 3);
      expect(result.matches, hasLength(1));
      expect(result.matches.single.matchedFacets, {
        'styles': ['스포츠'],
      });
      expect(result.matches.single.reason, '스포츠 신발을 찾을 때 볼 만해요.');
    });

    test('results: 여러 후보를 그대로 담는다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(
            _discoveryBody(
              mode: 'results',
              matches: [
                _discoveryMatchJson(storeId: 'ST-1', name: '나이키 라이즈'),
                _discoveryMatchJson(storeId: 'ST-2', name: '아디다스 스타디움'),
              ],
            ),
          ),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '신발',
      );

      expect(result.mode, DiscoveryMode.results);
      expect(result.matches, hasLength(2));
    });

    test('no_match: matches가 비어 있다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async =>
              _json(_discoveryBody(mode: 'no_match', query: 'asdf')),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        'asdfqwer',
      );

      expect(result.mode, DiscoveryMode.noMatch);
      expect(result.matches, isEmpty);
    });

    test('degraded: 태그 기반 잔여 결과가 있으면 함께 담아 온다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(
            _discoveryBody(
              mode: 'degraded',
              matches: [_discoveryMatchJson()],
            ),
          ),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '신발',
      );

      expect(result.mode, DiscoveryMode.degraded);
      expect(result.matches, hasLength(1));
    });

    test('matched_facets·reason이 null이어도 파싱된다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(
            _discoveryBody(
              matches: [
                _discoveryMatchJson(matchedFacets: null, reason: null),
              ],
            ),
          ),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '밥 먹을 곳',
      );

      final match = result.matches.single;
      expect(match.matchedFacets, isEmpty);
      expect(match.reason, isNull);
    });

    test('알 수 없는 mode는 unknown으로 안전하게 폴백한다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(_discoveryBody(mode: 'future_mode')),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '밥',
      );

      expect(result.mode, DiscoveryMode.unknown);
    });

    test('ok_no_route는 nodeId 없이 1건으로 온다', () async {
      // 위치는 알지만 입구 노드가 없어 온디바이스 경로 계산이 불가능한 매장.
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(
            _discoveryBody(
              matches: [_discoveryMatchJson(entranceNodeId: null)],
            ),
          ),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '팝업',
      );

      expect(result.matches, hasLength(1));
      expect(result.matches.single.entranceNodeId, isNull);
    });

    test('wgs84 좌표가 없는 후보는 지도에 놓을 자리가 없어 제외한다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(
            _discoveryBody(
              matches: [
                _discoveryMatchJson(centroidWgs84: null),
                _discoveryMatchJson(storeId: 'ST-2'),
              ],
            ),
          ),
        ),
      );

      final result = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '밥',
      );

      expect(result.matches, hasLength(1));
      expect(result.matches.single.storeId, 'ST-2');
    });

    test('빈/공백 질의는 HTTP를 태우지 않고 no_match를 돌려준다', () async {
      // 백엔드가 min_length=1로 422를 내므로 굳이 왕복하지 않는다.
      var requestCount = 0;
      final repository = HttpDestinationRepository(
        client: MockClient((request) async {
          requestCount++;
          return _json(_discoveryBody());
        }),
      );

      expect(
        (await repository.searchDestinationsAi('b', '')).mode,
        DiscoveryMode.noMatch,
      );
      expect(
        (await repository.searchDestinationsAi('b', '   ')).mode,
        DiscoveryMode.noMatch,
      );
      expect(requestCount, 0);
    });

    test('404·422는 no_match로 흡수한다', () async {
      for (final status in [404, 422]) {
        final repository = HttpDestinationRepository(
          client: MockClient((request) async => http.Response('', status)),
        );
        final result = await repository.searchDestinationsAi(
          'thehyundai-seoul',
          '밥',
        );
        expect(
          result.mode,
          DiscoveryMode.noMatch,
          reason: '$status는 검색 UX에서 "결과 없음"과 같다',
        );
        expect(result.matches, isEmpty);
      }
    });

    test('5xx는 호출자에게 전파한다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient((request) async => http.Response('', 503)),
      );

      expect(
        () => repository.searchDestinationsAi('thehyundai-seoul', '밥'),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('searchDestinations', () {
    test('경량 검색은 /query/destination으로 간다', () async {
      // /query/destination은 DiscoveryResponse가 아니라 기존 DestinationResponse
      // 계약(_matchBody)을 그대로 쓴다 — /query/ai와 계약이 분리됐음을 못박는다.
      late http.Request captured;
      final repository = HttpDestinationRepository(
        client: MockClient((request) async {
          captured = request;
          return _json(_matchBody());
        }),
      );

      await repository.searchDestinations('thehyundai-seoul', 'MLB');

      expect(captured.url.path, endsWith('/query/destination'));
    });

    test('단일 match 객체를 파싱한다 (리스트가 아니다)', () async {
      final repository = HttpDestinationRepository(
        client: MockClient((request) async => _json(_matchBody())),
      );

      final results = await repository.searchDestinations(
        'thehyundai-seoul',
        '밥 먹을 곳',
      );

      expect(results, hasLength(1));
      expect(results.single.name, '스시코우지');
      expect(results.single.floor, 'B1');
      expect(results.single.nodeId, 'FL-1:ND-1');
      expect(results.single.category, '음식점');
      expect(results.single.point.latitude, 37.52);
    });

    test('no_match는 빈 결과다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async =>
              _json({'status': 'no_match', 'query': 'asdf', 'match': null}),
        ),
      );

      expect(
        await repository.searchDestinations('thehyundai-seoul', 'asdfqwer'),
        isEmpty,
      );
    });
  });
}
