import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/transit_route.dart';
import 'package:navigation_client/repositories/tmap_transit_repository.dart';

// TMAP 대중교통 경로안내(POST /transit/routes) 응답 형태를 옮긴 픽스처.
//
// 확인 지점 세 가지:
//  1. 도보 구간은 passShape가 없고 steps[].linestring으로만 선이 온다.
//  2. 탈것 구간은 passShape.linestring 한 줄에 전체 선이 온다.
//  3. linestring은 "경도,위도" 순서다(우리 LatLng와 반대).
const _sampleResponseBody = '''
{
  "metaData": {
    "requestParameters": { "endY": "37.5665", "endX": "126.9780" },
    "plan": {
      "itineraries": [
        {
          "fare": { "regular": { "totalFare": 1500, "currency": { "symbol": "\\u20a9" } } },
          "totalTime": 2400,
          "totalWalkTime": 600,
          "transferCount": 1,
          "totalDistance": 12000,
          "totalWalkDistance": 750,
          "pathType": 1,
          "legs": [
            {
              "mode": "WALK",
              "sectionTime": 300,
              "distance": 380,
              "start": { "name": "출발지", "lon": 126.9250, "lat": 37.5253 },
              "end": { "name": "여의도역", "lon": 126.9245, "lat": 37.5215 },
              "steps": [
                { "distance": 180, "description": "국제금융로를 따라 이동", "linestring": "126.9250,37.5253 126.9248,37.5240" },
                { "distance": 200, "description": "여의도역 방면으로 이동", "linestring": "126.9248,37.5240 126.9245,37.5215" }
              ]
            },
            {
              "mode": "SUBWAY",
              "routeColor": "00A5DE",
              "route": "수도권5호선",
              "routeId": "110051",
              "sectionTime": 900,
              "distance": 8000,
              "start": { "name": "여의도역", "lon": 126.9245, "lat": 37.5215 },
              "end": { "name": "광화문역", "lon": 126.9769, "lat": 37.5710 },
              "passStopList": {
                "stationList": [
                  { "index": 0, "stationName": "여의도", "lon": "126.9245", "lat": "37.5215" },
                  { "index": 1, "stationName": "여의나루", "lon": "126.9325", "lat": "37.5270" },
                  { "index": 2, "stationName": "마포", "lon": "126.9455", "lat": "37.5395" },
                  { "index": 3, "stationName": "광화문", "lon": "126.9769", "lat": "37.5710" }
                ]
              },
              "passShape": { "linestring": "126.9245,37.5215 126.9325,37.5270 126.9455,37.5395 126.9769,37.5710" }
            },
            {
              "mode": "WALK",
              "sectionTime": 300,
              "distance": 370,
              "start": { "name": "광화문역", "lon": 126.9769, "lat": 37.5710 },
              "end": { "name": "도착지", "lon": 126.9780, "lat": 37.5665 }
            }
          ]
        },
        {
          "fare": { "regular": { "totalFare": 1600 } },
          "totalTime": 1800,
          "totalWalkTime": 420,
          "transferCount": 0,
          "totalDistance": 11000,
          "legs": [
            {
              "mode": "BUS",
              "route": "간선:472",
              "routeColor": "0068B7",
              "sectionTime": 1380,
              "distance": 10500,
              "start": { "name": "여의도환승센터", "lon": 126.9240, "lat": 37.5250 },
              "end": { "name": "시청앞", "lon": 126.9775, "lat": 37.5660 },
              "passShape": { "linestring": "126.9240,37.5250 126.9775,37.5660" }
            }
          ]
        }
      ]
    }
  }
}
''';

void main() {
  test('구간·요금·정거장 수를 파싱하고 빠른 순으로 정렬한다', () async {
    late String requestBody;
    final client = MockClient((request) async {
      requestBody = request.body;
      return http.Response.bytes(
        utf8.encode(_sampleResponseBody),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = TmapTransitRepository(
      client: client,
      appKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: const LatLng(37.5253, 126.9250),
      destination: const LatLng(37.5665, 126.9780),
    );

    expect(routes.status, TransitRoutesStatus.ok);
    expect(routes.itineraries, hasLength(2));

    // 응답 순서(2400초 → 1800초)가 아니라 소요 시간 오름차순이어야 한다.
    final fastest = routes.itineraries.first;
    expect(fastest.totalTimeSeconds, 1800);
    expect(fastest.transferCount, 0);
    expect(fastest.fare, 1600);
    expect(fastest.legs.single.mode, TransitMode.bus);
    // "간선:472"에서 종류 접두사를 떼고 번호만 남긴다.
    expect(fastest.legs.single.shortLabel, '472');
    expect(fastest.legs.single.routeColorHex, '#0068B7');

    final withTransfer = routes.itineraries[1];
    expect(withTransfer.legs, hasLength(3));
    expect(withTransfer.fare, 1500);
    expect(withTransfer.rideLegs, hasLength(1));

    // 도보 구간: passShape가 없고 steps 두 개가 이어 붙어야 한다.
    final walk = withTransfer.legs.first;
    expect(walk.mode, TransitMode.walk);
    expect(walk.points.first, const LatLng(37.5253, 126.9250));
    expect(walk.points.last, const LatLng(37.5215, 126.9245));

    // 탈것 구간: passShape 한 줄 + 정거장 3칸(목록 4건 - 1).
    final subway = withTransfer.legs[1];
    expect(subway.mode, TransitMode.subway);
    expect(subway.stationCount, 3);
    expect(subway.startName, '여의도역');
    expect(subway.endName, '광화문역');
    expect(subway.points, hasLength(4));
    expect(subway.points.last, const LatLng(37.5710, 126.9769));

    // steps도 passShape도 없는 마지막 도보 구간은 start·end 두 점으로 잇는다.
    final lastWalk = withTransfer.legs.last;
    expect(lastWalk.points, hasLength(2));
    expect(lastWalk.points.last, const LatLng(37.5665, 126.9780));

    final sent = jsonDecode(requestBody) as Map<String, dynamic>;
    expect(sent['startX'], '126.925');
    expect(sent['startY'], '37.5253');
    expect(sent['format'], 'json');
  });

  test('700m 이내(status 11)는 200이어도 tooClose로 구분한다', () async {
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode('{"result": {"status": 11, "message": "출발지와 도착지가 가깝습니다."}}'),
        200,
      );
    });
    final repository = TmapTransitRepository(
      client: client,
      appKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: const LatLng(37.5253, 126.9250),
      destination: const LatLng(37.5258, 126.9255),
    );

    expect(routes.status, TransitRoutesStatus.tooClose);
    expect(routes.itineraries, isEmpty);
  });

  test('다른 result 코드는 경로 없음이다', () async {
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode('{"result": {"status": 13, "message": "도착지 인근에 대중교통 정보가 없습니다."}}'),
        200,
      );
    });
    final repository = TmapTransitRepository(
      client: client,
      appKey: 'test-key',
    );

    expect(
      (await repository.getTransitRoutes(
        origin: const LatLng(37.5253, 126.9250),
        destination: const LatLng(38.5665, 128.9780),
      )).status,
      TransitRoutesStatus.noRoute,
    );
  });

  test('HTTP 오류는 failed로 구분한다 — 재시도가 의미 있는 유일한 상태다', () async {
    final client = MockClient((request) async {
      return http.Response('{"error": {"code": "QUOTA_EXCEEDED"}}', 429);
    });
    final repository = TmapTransitRepository(
      client: client,
      appKey: 'test-key',
    );

    expect(
      (await repository.getTransitRoutes(
        origin: const LatLng(37.5253, 126.9250),
        destination: const LatLng(37.5665, 126.9780),
      )).status,
      TransitRoutesStatus.failed,
    );
  });
}
