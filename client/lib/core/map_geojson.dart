import 'package:latlong2/latlong.dart' as ll;

/// MapLibre 소스에 밀어 넣는 GeoJSON을 만드는 최소 헬퍼.
///
/// 화면 코드에서 분리해 둔 이유는 **파일을 나눌 수 없게 만드는 걸림돌이었기
/// 때문이다.** Dart의 `_` 프라이버시는 클래스가 아니라 라이브러리(파일) 단위라,
/// 이 세 함수가 `outdoor_map_screen.dart` 안에 private으로 있는 한 그 파일에서
/// 레이어 그리기 코드를 한 줄도 떼어낼 수 없었다 — 떼어낸 쪽에서 이 함수들을
/// 부를 방법이 없다.
///
/// 그래서 이 파일은 "공용 유틸"이라서가 아니라 **분해의 선행 조건**으로 존재한다.
library;

/// 빈 FeatureCollection. 레이어를 지웠다 다시 만드는 대신 데이터만 비울 때 쓴다.
///
/// 레이어 제거·재생성은 층 전환이나 스타일 재로드와 경쟁해서 "레이어가 없다"는
/// 예외로 터지는데, 소스를 빈 컬렉션으로 덮어쓰면 그 경쟁이 아예 생기지 않는다.
Map<String, dynamic> emptyGeoJsonCollection() => {
  'type': 'FeatureCollection',
  'features': const <Map<String, dynamic>>[],
};

/// [features]를 담은 FeatureCollection.
Map<String, dynamic> geoJsonCollection(List<Map<String, dynamic>> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

/// 경로선 feature 하나. [style]이 어느 레이어가 이 선을 그릴지 가른다 —
/// `drive`(실선·파랑), `walk`(점선·회색), `indoor`(실선·야외 본선과 같은 파랑).
Map<String, dynamic> geoJsonLineFeature(
  List<ll.LatLng> points, {
  String style = 'walk',
  int? generation,
}) {
  final properties = <String, dynamic>{'style': style};
  if (generation != null) properties['routeGeneration'] = generation;
  return {
    'type': 'Feature',
    'properties': properties,
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final p in points) [p.longitude, p.latitude],
      ],
    },
  };
}
