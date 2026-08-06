import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/repositories/tmap_poi_repository.dart';

// TMAP POI 통합검색(GET /tmap/pois) 응답 형태를 그대로 옮긴 픽스처.
// **좌표·거리가 전부 문자열**이라는 점이 이 픽스처의 핵심이다 — num으로 읽으면
// 실기기에서 첫 검색부터 예외로 죽는다.
const _sampleResponseBody = '''
{
  "searchPoiInfo": {
    "totalCount": "2",
    "count": "2",
    "page": "1",
    "pois": {
      "poi": [
        {
          "id": "1000001",
          "pkey": "1000001-1",
          "navSeq": "1",
          "collectionType": "poi",
          "name": "스타벅스 여의도IFC점",
          "telNo": "1522-3232",
          "frontLat": "37.52530",
          "frontLon": "126.92510",
          "noorLat": "37.52540",
          "noorLon": "126.92520",
          "upperAddrName": "서울",
          "middleAddrName": "영등포구",
          "lowerAddrName": "여의도동",
          "detailAddrName": "",
          "firstNo": "23",
          "secondNo": "0",
          "roadName": "국제금융로",
          "bizName": "",
          "upperBizName": "음식점",
          "middleBizName": "커피점/카페",
          "lowerBizName": "커피전문점",
          "radius": "0.235",
          "newAddressList": {
            "newAddress": [
              {
                "centerLat": "37.52530",
                "centerLon": "126.92510",
                "frontLat": "37.52530",
                "frontLon": "126.92510",
                "roadName": "국제금융로",
                "bldNo1": "10",
                "bldNo2": "0",
                "fullAddressRoad": "서울 영등포구 국제금융로 10"
              }
            ]
          }
        },
        {
          "id": "1000002",
          "name": "여의도한강공원 주차장",
          "telNo": "",
          "frontLat": "0",
          "frontLon": "0",
          "noorLat": "37.52810",
          "noorLon": "126.93330",
          "upperAddrName": "서울",
          "middleAddrName": "영등포구",
          "lowerAddrName": "여의도동",
          "detailAddrName": "",
          "firstNo": "8",
          "secondNo": "2",
          "upperBizName": "교통시설",
          "middleBizName": "주차장",
          "lowerBizName": "",
          "radius": "1.02"
        }
      ]
    }
  }
}
''';

void main() {
  test('문자열로 오는 좌표·거리를 파싱하고 입구(front) 좌표를 우선한다', () async {
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response.bytes(
        utf8.encode(_sampleResponseBody),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = TmapPoiRepository(client: client, appKey: 'test-key');

    final pois = await repository.searchNearby(
      '스타벅스',
      center: const LatLng(37.5260, 126.9270),
      radiusMeters: 1500,
    );

    expect(pois, hasLength(2));

    final first = pois.first;
    expect(first.name, '스타벅스 여의도IFC점');
    // front 좌표가 있으면 noor(대표점)가 아니라 front를 쓴다.
    expect(first.point, const LatLng(37.52530, 126.92510));
    expect(first.category, '커피전문점');
    expect(first.address, '서울 영등포구 국제금융로 10');
    expect(first.telNo, '1522-3232');
    // radius는 km 문자열이므로 m로 환산돼야 한다.
    expect(first.distanceMeters, closeTo(235, 0.001));

    // front가 "0"인 항목은 좌표 없음으로 보고 noor로 떨어진다.
    final second = pois[1];
    expect(second.point, const LatLng(37.52810, 126.93330));
    // 도로명 주소가 없으면 지번 주소를 조립한다(secondNo가 0이 아니면 "8-2").
    expect(second.address, '서울 영등포구 여의도동 8-2');
    expect(second.category, '주차장');
    expect(second.telNo, isNull);

    // 반경은 km 정수로 나가야 한다(1500m → 2km). 1000을 그대로 보내면 1000km다.
    expect(requested.queryParameters['radius'], '2');
    expect(requested.queryParameters['searchKeyword'], '스타벅스');
    expect(requested.queryParameters['resCoordType'], 'WGS84GEO');
  });

  test('결과가 없으면 빈 목록이다', () async {
    final client = MockClient((request) async {
      return http.Response('{"searchPoiInfo": null}', 200);
    });
    final repository = TmapPoiRepository(client: client, appKey: 'test-key');

    final pois = await repository.searchNearby(
      '없는가게',
      center: const LatLng(37.5260, 126.9270),
    );

    expect(pois, isEmpty);
  });

  test('오류 응답은 예외가 아니라 빈 목록으로 끝난다', () async {
    final client = MockClient((request) async {
      return http.Response('{"error": {"code": "INVALID_API_KEY"}}', 401);
    });
    final repository = TmapPoiRepository(client: client, appKey: 'test-key');

    expect(
      await repository.searchNearby(
        '스타벅스',
        center: const LatLng(37.5260, 126.9270),
      ),
      isEmpty,
    );
  });

  test('키가 없으면 사용 불가로 표시된다', () {
    expect(TmapPoiRepository(appKey: '').isAvailable, isFalse);
    expect(TmapPoiRepository(appKey: 'k').isAvailable, isTrue);
  });

  test('검색어가 비면 요청 자체를 보내지 않는다', () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('{}', 200);
    });
    final repository = TmapPoiRepository(client: client, appKey: 'test-key');

    expect(
      await repository.searchNearby(
        '   ',
        center: const LatLng(37.5260, 126.9270),
      ),
      isEmpty,
    );
    expect(called, isFalse);
  });
}
