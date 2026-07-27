import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_client/repositories/http_destination_repository.dart';

/// 백엔드 DestinationResponse(app/dto/query.py) 한 건. /query/destination과
/// /query/ai가 **같은 계약**을 쓰므로 두 경로 모두 이 모양으로 응답한다.
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
          return _json(_matchBody());
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
          return _json(_matchBody());
        }),
      );

      await repository.searchDestinationsAi('thehyundai-seoul', '밥 먹을 곳');

      final body =
          jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body.containsKey('current_floor_id'), isFalse);
    });

    test('단일 match 객체를 파싱한다 (리스트가 아니다)', () async {
      final repository = HttpDestinationRepository(
        client: MockClient((request) async => _json(_matchBody())),
      );

      final results = await repository.searchDestinationsAi(
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

    test('ok_no_route는 nodeId 없이 1건으로 온다', () async {
      // 위치는 알지만 입구 노드가 없어 온디바이스 경로 계산이 불가능한 매장.
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(_matchBody(entranceNodeId: null)),
        ),
      );

      final results = await repository.searchDestinationsAi(
        'thehyundai-seoul',
        '팝업',
      );

      expect(results, hasLength(1));
      expect(results.single.nodeId, isNull);
    });

    test('no_match는 빈 결과다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async =>
              _json({'status': 'no_match', 'query': 'asdf', 'match': null}),
        ),
      );

      expect(
        await repository.searchDestinationsAi('thehyundai-seoul', 'asdfqwer'),
        isEmpty,
      );
    });

    test('wgs84 좌표가 없으면 지도에 놓을 자리가 없어 제외한다', () async {
      final repository = HttpDestinationRepository(
        client: MockClient(
          (request) async => _json(_matchBody(centroidWgs84: null)),
        ),
      );

      expect(
        await repository.searchDestinationsAi('thehyundai-seoul', '밥'),
        isEmpty,
      );
    });

    test('빈/공백 질의는 HTTP를 태우지 않는다', () async {
      // 백엔드가 min_length=1로 422를 내므로 굳이 왕복하지 않는다.
      var requestCount = 0;
      final repository = HttpDestinationRepository(
        client: MockClient((request) async {
          requestCount++;
          return _json(_matchBody());
        }),
      );

      expect(await repository.searchDestinationsAi('b', ''), isEmpty);
      expect(await repository.searchDestinationsAi('b', '   '), isEmpty);
      expect(requestCount, 0);
    });

    test('404·422는 결과 없음으로 흡수한다', () async {
      for (final status in [404, 422]) {
        final repository = HttpDestinationRepository(
          client: MockClient((request) async => http.Response('', status)),
        );
        expect(
          await repository.searchDestinationsAi('thehyundai-seoul', '밥'),
          isEmpty,
          reason: '$status는 검색 UX에서 "결과 없음"과 같다',
        );
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
      // 두 메서드가 같은 파싱을 공유하므로, 경로가 갈리는지를 못박아 둔다.
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
  });
}
