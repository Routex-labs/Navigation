/// MapLibre의 zoom과 실제 미터를 오가는 계산.
///
/// **정책이 아니라 산수다.** 어느 배율에서 실내로 넘어갈지 같은 판단은 여기 없고
/// (`screens/outdoor_map/entry/indoor_entry_zoom.dart`), "이 폭을 담으려면 zoom이
/// 얼마인가"만 있다. 그래서 지도 표현 쪽(라벨 크기)과 화면 정책 쪽이 같은 식을
/// 나눠 쓸 수 있다 — 두 벌로 두면 한쪽만 고쳐 조용히 어긋난다.
library;

import 'dart:math' as math;

/// MapLibre zoom 0에서 적도 기준 픽셀당 미터.
///
/// **256 타일 규약(156543.03)이 아니라 512 타일 규약이다.** 실기기에서 재 확인한
/// 값이고, 156543을 쓰면 필요한 zoom이 1레벨 높게 나온다.
const metersPerPixelAtZoom0Equator = 78271.5170;

/// 위도 [latitude]에서 폭 [widthMeters]가 [availablePx] 논리 픽셀 안에 들어오는
/// 최대(=가장 확대된) zoom. 이보다 확대하면 잘린다.
double zoomToFitWidth({
  required double widthMeters,
  required double availablePx,
  required double latitude,
}) {
  final mppAtLat =
      metersPerPixelAtZoom0Equator * math.cos(latitude * math.pi / 180);
  return math.log(mppAtLat * availablePx / widthMeters) / math.ln2;
}

/// [zoom]에서 [availablePx] 논리 픽셀에 담기는 실제 폭(m).
double visibleWidthMeters({
  required double zoom,
  required double availablePx,
  required double latitude,
}) {
  final mppAtLat =
      metersPerPixelAtZoom0Equator * math.cos(latitude * math.pi / 180);
  return mppAtLat * availablePx / math.pow(2, zoom);
}

/// 돌려 세운 건물이 화면에 담기는 zoom.
///
/// 건물을 세로로 세운 뒤([building_orientation.dart]) 그 직사각형을 화면에
/// 맞출 때 쓴다. 가로·세로 **둘 다** 담겨야 하므로 두 제약 중 더 축소해야 하는
/// 쪽을 고른다 — 한쪽만 보면 나머지 축이 화면 밖으로 잘린다.
///
/// [widthMeters]는 화면 가로에 놓이는 변(짧은 축), [heightMeters]는 세로에
/// 놓이는 변(긴 축)이다. 세로로 세운다는 것이 곧 이 대응을 뜻한다.
double zoomToFitRotatedBox({
  required double widthMeters,
  required double heightMeters,
  required double viewportWidthPx,
  required double viewportHeightPx,
  required double latitude,
}) {
  final byWidth = zoomToFitWidth(
    widthMeters: widthMeters,
    availablePx: viewportWidthPx,
    latitude: latitude,
  );
  final byHeight = zoomToFitWidth(
    widthMeters: heightMeters,
    availablePx: viewportHeightPx,
    latitude: latitude,
  );
  return math.min(byWidth, byHeight);
}
