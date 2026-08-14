/// 야외 지도 위 "실내 진입 오버레이"의 zoom 정책.
///
/// 값들이 서로 얽혀 있다 — 임계값 하나만 옮겨도 "도면이 다 보이기 전에 튕겨
/// 나가는" 증상이나 "이탈 순간 도면이 툭 끊기는" 증상이 되살아난다. 각 값의
/// 근거와 관계도는 `docs/client/indoor-entry-rules.md`.
library;

import 'dart:math' as math;

import '../../../map/camera/zoom_math.dart';

/// 임계값을 잡을 때 기준으로 삼은 화면 폭(논리 px). 세로 모드 스마트폰의
/// 흔한 하한이며, 여기서 성립하면 더 넓은 화면에서는 자동으로 성립한다.
const referenceViewportWidthPx = 360.0;

/// 더현대 서울 위도. 임계값 산출의 기준점.
const referenceLatitude = 37.526;

/// 실내 오버레이가 zoom-interpolate로 나타나는 구간(**진입 전**).
///
/// 야외 지도를 훑는 동안 도면이 함부로 끼어들면 안 되므로 늦게 나타난다.
const indoorOverlayFadeInStartZoom = 16.5;
const indoorOverlayFadeInEndZoom = 17.5;

/// 실내 오버레이의 페이드 구간(**진입 후**). 0에 닿는 지점을
/// [indoorExitZoomThreshold]와 **일치시킨다** — 어긋나면 이탈 순간 툭 끊긴다.
const indoorOverlayFadeOutStartZoom = indoorExitZoomThreshold;
const indoorOverlayFadeOutEndZoom = 16.0;

/// 이 zoom 이상으로 확대하면 "실내 진입" 의도로 보고 실내 UI 오버레이를 얹는다.
/// 진입 램프의 페이드가 끝나는 순간(=도면이 완전히 보이는 순간)과 맞춘다.
const indoorEntryZoomThreshold = indoorOverlayFadeInEndZoom;

/// 이 zoom 미만으로 축소하면 오버레이를 접는다. **진입 임계값과 같으면 안 된다** —
/// 진입 17.5와의 사이 1.9 zoom이 히스테리시스 밴드다.
const indoorExitZoomThreshold = 15.6;

/// '홈'으로 야외에 돌아올 때 맞출 zoom. [indoorExitZoomThreshold]보다 **낮아야**
/// 한다 — 위에 있으면 다음 카메라 정지에서 다시 실내로 끌려 들어간다.
const outdoorReturnZoom = indoorExitZoomThreshold - 0.1;

/// 화면 폭 [viewportWidthPx]에서 실제로 쓸 진입 임계값. 절대 zoom만 쓰면 좁은
/// 화면에서 확대 진입이 통째로 죽는다(실측 표: indoor-entry-rules.md 2절).
///
/// [buildingWidthMeters]나 [viewportWidthPx]가 0 이하면 판정 근거가 없으므로
/// 보정 없이 기본 임계값을 그대로 돌려준다.
double indoorEntryZoomThresholdFor({
  required double buildingWidthMeters,
  required double viewportWidthPx,
  required double latitude,
}) {
  if (buildingWidthMeters <= 0 || viewportWidthPx <= 0) {
    return indoorEntryZoomThreshold;
  }
  final fitZoom = zoomToFitWidth(
    widthMeters: buildingWidthMeters,
    availablePx: viewportWidthPx,
    latitude: latitude,
  );
  return math.max(
    math.min(indoorEntryZoomThreshold, fitZoom),
    indoorOverlayFadeOutEndZoom,
  );
}

/// 건물을 **바깥에서 보여 줄 때** 진입 임계값에서 물러서는 폭(zoom 레벨).
///
/// zoom은 log2 스케일이라 0.7을 빼면 건물이 화면 폭의 약 62%를 차지한다 —
/// 건물 윤곽과 주변 길이 함께 보이는 "여기 있다"의 그림이다.
const exteriorViewZoomMargin = 0.7;

/// 검색에서 고른 건물의 **바깥 모습**을 보여 줄 zoom.
///
/// 진입 임계값과 한 파일에 두는 이유가 전부다 — **반드시 임계값보다 아래여야**
/// 한다. 각자 계산하면 좁은 화면에서 검색만 했는데 도면이 열린다.
double exteriorViewZoomFor({
  required double buildingWidthMeters,
  required double viewportWidthPx,
  required double latitude,
}) =>
    indoorEntryZoomThresholdFor(
      buildingWidthMeters: buildingWidthMeters,
      viewportWidthPx: viewportWidthPx,
      latitude: latitude,
    ) -
    exteriorViewZoomMargin;

/// 실내 MVT 소스 minzoom. 이 미만에서는 타일 요청 자체가 나가지 않는다.
///
/// **도면이 조금이라도 보이는 zoom을 반드시 덮어야 한다** — 16으로 올리면 이탈
/// 직전 페이드 구간이 통째로 빈다(양자화 실측: `docs/client/map-style-rules.md` 0절).
const indoorTilesMinZoom = 15.0;

/// 실내 MVT 소스 maxzoom. 극한 확대(z>=19)에서는 tile 경계가 좁을수록 double
/// 좌표 → 4096 유닛 양자화의 상대 오차가 누적돼 도면이 미세하게 뒤틀리므로,
/// 그 이상에서는 z=18 타일을 over-scale한다(z=18은 ~150 m 폭, 0.04 m/유닛).
const indoorTilesMaxZoom = 18.0;

/// 카메라가 멈춘 시점의 zoom이 실내 진입 상태에 요구하는 변화.
enum IndoorEntryTransition {
  /// 실내 오버레이를 켠다(이미 켜져 있으면 유지).
  enter,

  /// 실내 오버레이를 접고 야외로 되돌아간다.
  exit,

  /// 히스테리시스 밴드 — 현재 상태를 그대로 둔다.
  keep,
}

/// [zoom]에서 실내 진입 상태를 어떻게 바꿔야 하는지 판정한다. 두 임계값 사이는
/// [IndoorEntryTransition.keep]이다.
///
/// [buildingNearby]가 false면 아무리 확대해도 진입하지 않고, 이탈도 내지 않는다
/// (이탈은 축소와 건물 밖 탭으로만 판정한다).
///
/// **[buildingNearby]와 [entryZoom]에 기본값을 두지 않는다.** 두면 새 호출부가
/// 값을 빼먹는 순간 각각의 버그가 조용히 되살아난다.
IndoorEntryTransition indoorEntryTransitionForZoom(
  double zoom, {
  required bool buildingNearby,
  required double entryZoom,
}) {
  if (zoom >= entryZoom) {
    return buildingNearby
        ? IndoorEntryTransition.enter
        : IndoorEntryTransition.keep;
  }
  if (zoom < indoorExitZoomThreshold) return IndoorEntryTransition.exit;
  return IndoorEntryTransition.keep;
}

/// 실내 오버레이(및 dim scrim)의 zoom-interpolate 페이드 표현식.
/// `[interpolate, [linear], [zoom], stop0_zoom, stop0_val, ...]` 형태의
/// MapLibre style expression이라, 카메라 이동 중에는 레이어 속성을 다시 쓰지
/// 않아도 실시간으로 반영된다.
List<Object> indoorOverlayFadeExpr({
  required bool entered,
  double maxOpacity = 1,
}) {
  final (startZoom, endZoom) = entered
      ? (indoorOverlayFadeOutStartZoom, indoorOverlayFadeOutEndZoom)
      : (indoorOverlayFadeInStartZoom, indoorOverlayFadeInEndZoom);
  return [
    'interpolate',
    ['linear'],
    ['zoom'],
    startZoom,
    0,
    endZoom,
    maxOpacity,
  ];
}

/// 크로스페이드 계수([crossfadeFactor])까지 반영한 오버레이 opacity 표현식.
///
/// **곱셈으로 감싸면 안 된다** — native가 속성 설정 자체를 거부하고 opacity가
/// 기본값 1로 굳는다. 계수는 끝 스톱 안에 곱해 넣어 zoom을 최상위 입력으로
/// 남긴다(오류 메시지와 근거: `docs/client/map-style-rules.md` 0절).
List<Object> indoorOverlayCrossfadeExpr({
  required bool entered,
  required double crossfadeFactor,
}) => indoorOverlayFadeExpr(
  entered: entered,
  maxOpacity: crossfadeFactor.clamp(0.0, 1.0).toDouble(),
);

/// [indoorOverlayFadeExpr]가 [zoom]에서 만들어 내는 실제 opacity. 표현식을
/// 직접 평가할 수 없는 테스트·검증용 미러다.
double indoorOverlayOpacityAt({
  required double zoom,
  required bool entered,
  double maxOpacity = 1,
}) {
  final (startZoom, endZoom) = entered
      ? (indoorOverlayFadeOutStartZoom, indoorOverlayFadeOutEndZoom)
      : (indoorOverlayFadeInStartZoom, indoorOverlayFadeInEndZoom);
  if (zoom <= startZoom) return 0;
  if (zoom >= endZoom) return maxOpacity;
  return maxOpacity * (zoom - startZoom) / (endZoom - startZoom);
}
