/// 대중교통 경로 오버레이(구간 선 + 수단 배지)의 등록·갱신.
///
/// 도보 경로와 소스를 나누는 이유는 **선의 성격이 다르기** 때문이다. 도보는
/// 한 가지 색 한 줄이지만 대중교통은 구간마다 노선색이 다르고 도보 구간만
/// 점선이라, 하나의 소스에 넣고 feature 속성으로 색·패턴을 갈라야 한다. 같은
/// 소스를 쓰면 도보 안내가 켜질 때마다 이 선의 색 표현식까지 다시 계산되어,
/// 안내를 바꿀 때 잠깐 엉뚱한 색으로 깜빡인다.
///
/// 어떤 경로를 보여줄지는 화면 상태가 정해 [TransitItinerary]를 그대로 넘기고,
/// 이 파일은 그것을 feature로 펼쳐 MapLibre 소스에 쓰는 일만 한다.
library;

import 'package:flutter/material.dart' show Color, Icons;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../map/geojson.dart';
import '../../map/route_style.dart';
import '../../models/transit_route.dart';
import '../../widgets/transit_style.dart';

const _transitSourceId = 'outdoor-transit';
const _transitRideLayerId = 'outdoor-transit-ride';
const _transitWalkLayerId = 'outdoor-transit-walk';
// 구간 시작점에 얹는 수단 배지(도보·버스·지하철).
const _transitBadgeSourceId = 'outdoor-transit-badge';
const _transitBadgeLayerId = 'outdoor-transit-badge-icon';

/// 대중교통 소스·레이어를 스타일에 등록한다. **호출 순서가 곧 레이어 순서다**
/// — 도보 경로 레이어 바로 다음에 불러, 두 안내가 잠깐 겹치는 순간에도
/// 사용자가 방금 고른 대중교통 선이 가려지지 않게 한다.
Future<void> registerTransitLayers(MapLibreMapController controller) async {
  // 색은 feature 속성에서 읽는다(`['get', 'color']`). 구간마다 노선색이 달라
  // 레이어를 노선 수만큼 만들 수는 없고, 만들었다면 경로를 바꿀 때마다
  // 레이어를 지웠다 다시 등록해야 한다.
  await controller.addSource(
    _transitSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    _transitSourceId,
    _transitRideLayerId,
    const LineLayerProperties(
      lineColor: ['get', 'color'],
      lineWidth: 5.5,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    // 탈것 구간만. 도보는 아래 점선 레이어가 따로 그린다.
    filter: [
      '==',
      ['get', 'walk'],
      false,
    ],
    enableInteraction: false,
  );
  await controller.addLineLayer(
    _transitSourceId,
    _transitWalkLayerId,
    // 걷는 구간은 **노선색을 따르지 않는다.** 정류장까지 걸어가는 길이 버스
    // 노선과 같은 색이면, 어디서 내려 걸어야 하는지를 점선 여부만으로 읽어야
    // 한다. 회색으로 빼 두면 "여기는 타는 구간이 아니다"가 색에서 먼저 온다.
    const LineLayerProperties(
      lineColor: kRouteWalkColor,
      lineWidth: 3.5,
      lineDasharray: kRouteWalkDashArray,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: [
      '==',
      ['get', 'walk'],
      true,
    ],
    enableInteraction: false,
  );

  // 구간 시작 배지. 선과 **소스를 나눈다** — 점 feature를 선 소스에 섞으면
  // 선 레이어 필터가 그 점까지 훑고, 반대로 배지 필터가 선을 훑는다.
  await controller.addSource(
    _transitBadgeSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addImage(
    kRouteWalkBadgeImageName,
    await renderModeBadgeIcon(
      Icons.directions_walk_rounded,
      const Color(0xFF8A9199),
    ),
  );
  await controller.addImage(
    kRouteBusBadgeImageName,
    await renderModeBadgeIcon(
      Icons.directions_bus_rounded,
      const Color(0xFF0068B7),
    ),
  );
  await controller.addImage(
    kRouteSubwayBadgeImageName,
    await renderModeBadgeIcon(Icons.subway_rounded, const Color(0xFF3A5DAE)),
  );
  // **아이콘 이름마다 레이어를 하나씩 둔다.** `iconImage`에 `['get', ...]`
  // 표현식을 넣는 방식은 이 바인딩에서 조용히 실패할 수 있어(아이콘이 아예 안
  // 뜨고 오류도 없다), 이름을 상수로 박고 필터로 가른다.
  for (final entry in const {
    kRouteWalkBadgeImageName: _transitBadgeLayerId,
    kRouteBusBadgeImageName: '$_transitBadgeLayerId-bus',
    kRouteSubwayBadgeImageName: '$_transitBadgeLayerId-subway',
  }.entries) {
    await controller.addSymbolLayer(
      _transitBadgeSourceId,
      entry.value,
      routeModeBadgeProps(entry.key),
      filter: [
        '==',
        ['get', 'icon'],
        entry.key,
      ],
      enableInteraction: false,
    );
  }
}

/// 대중교통 경로선을 지도에 반영한다. [itinerary]가 null이면 소스를 비운다.
///
/// 구간(leg)마다 feature를 나눠 색과 도보 여부를 속성으로 실어 보낸다 —
/// 레이어 두 개(탈것 실선 / 도보 점선)가 그 속성으로 필터해 각자 그린다.
Future<void> syncTransitLayer(
  MapLibreMapController controller,
  TransitItinerary? itinerary,
) async {
  if (itinerary == null) {
    await controller.setGeoJsonSource(
      _transitSourceId,
      emptyGeoJsonCollection(),
    );
    await controller.setGeoJsonSource(
      _transitBadgeSourceId,
      emptyGeoJsonCollection(),
    );
    return;
  }
  final features = <Map<String, dynamic>>[];
  final badges = <Map<String, dynamic>>[];
  for (final leg in itinerary.legs) {
    if (leg.points.length < 2) continue;
    features.add({
      'type': 'Feature',
      'properties': {
        'color': transitLegColorHex(leg),
        'walk': leg.mode.isWalk,
      },
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final p in leg.points) [p.longitude, p.latitude],
        ],
      },
    });
    // 배지는 **구간이 시작하는 자리**에 찍는다. 끝점에 찍으면 다음 구간의
    // 시작점과 같은 자리라 두 아이콘이 겹치고, 사용자는 어느 쪽이 지금부터
    // 시작하는 수단인지 알 수 없다.
    final icon = _badgeImageFor(leg.mode);
    if (icon == null) continue;
    badges.add({
      'type': 'Feature',
      'properties': {'icon': icon},
      'geometry': {
        'type': 'Point',
        'coordinates': [
          leg.points.first.longitude,
          leg.points.first.latitude,
        ],
      },
    });
  }
  await controller.setGeoJsonSource(
    _transitSourceId,
    features.isEmpty ? emptyGeoJsonCollection() : geoJsonCollection(features),
  );
  await controller.setGeoJsonSource(
    _transitBadgeSourceId,
    badges.isEmpty ? emptyGeoJsonCollection() : geoJsonCollection(badges),
  );
}

/// 기차·고속버스·항공은 아이콘을 따로 굽지 않았다. 이 데모의 안내 범위(도심
/// 대중교통)에서는 나오지 않고, 굳이 버스 아이콘을 돌려 쓰면 사용자가 버스로
/// 읽는다 — 없는 것보다 나쁘다.
String? _badgeImageFor(TransitMode mode) => switch (mode) {
  TransitMode.walk => kRouteWalkBadgeImageName,
  TransitMode.bus => kRouteBusBadgeImageName,
  TransitMode.subway => kRouteSubwayBadgeImageName,
  _ => null,
};
