/// 야외 지도 위 "실내 진입 오버레이"의 zoom 정책.
///
/// 화면 코드에서 분리해 둔 이유는 이 값들 사이의 관계가 서로 얽혀 있어서다.
/// 임계값 하나만 옮겨도 "도면이 다 보이기 전에 실내에서 튕겨 나가는" 증상이나
/// "이탈 순간 도면이 툭 끊기는" 증상이 조용히 되살아난다. 관계를 함수로
/// 고정하고 테스트로 지킨다.
library;

import 'dart:math' as math;

/// MapLibre zoom 0에서 적도 기준 픽셀당 미터.
///
/// **256 타일 규약(156543.03)이 아니라 512 타일 규약이다.** MapLibre(GL JS·
/// native 모두)의 zoom은 "세계가 512 논리 픽셀에 들어가는 zoom"이 0이라
/// `mpp = 78271.5 * cos(lat) / 2^zoom`이다. 실제 지도에서
/// `toScreenLocation`으로 픽셀 간격을 재 확인한 값이며(z=17에서 0.474 m/px →
/// K≈78,400), 156543을 쓰면 필요한 zoom이 정확히 1레벨 높게 나와 "도면이 다
/// 담기지도 않았는데 이탈" 증상의 원인이 된다.
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

/// 임계값을 잡을 때 기준으로 삼은 화면 폭(논리 px). 세로 모드 스마트폰의
/// 흔한 하한이며, 여기서 성립하면 더 넓은 화면에서는 자동으로 성립한다.
/// (반대로 데스크톱 Chrome처럼 넓은 화면에서는 이탈 임계값에서 건물 주변까지
/// 넓게 보이는데, 도면은 계속 그려지므로 기능상 문제는 없다.)
const referenceViewportWidthPx = 360.0;

/// 더현대 서울 위도. 임계값 산출의 기준점.
const referenceLatitude = 37.526;

/// 실내 오버레이가 zoom-interpolate로 나타나는 구간(**진입 전**).
///
/// 야외 지도를 훑는 동안 도면이 함부로 끼어들면 안 되므로 늦게 나타난다.
const indoorOverlayFadeInStartZoom = 16.5;
const indoorOverlayFadeInEndZoom = 17.5;

/// 실내 오버레이의 페이드 구간(**진입 후**).
///
/// 이미 실내에 들어온 뒤에는 층 전체를 보려고 축소하는 것이 정상 동작이다.
/// 진입 램프를 그대로 쓰면 그 축소 구간에서 도면이 흐려지다 사라지므로, 훨씬
/// 아래까지 100% 불투명을 유지한다. 가장 넓은 지하층(B3·B4)이 폭 360 px 화면에
/// 여백까지 두고 들어가는 zoom이 16.05이므로, 그보다 아래인 16.0까지는 도면이
/// 완전히 진하게 남아 있어야 한다.
///
/// 페이드가 0에 닿는 지점을 [indoorExitZoomThreshold]와 일치시킨 것이 중요하다.
/// 이탈하는 순간 램프가 진입 램프로 되돌아가는데, 그때 도면이 아직 진하면
/// 100% → 0으로 툭 끊긴다.
const indoorOverlayFadeOutStartZoom = indoorExitZoomThreshold;
const indoorOverlayFadeOutEndZoom = 16.0;

/// 이 zoom 이상으로 확대하면 "실내 진입" 의도로 보고 실내 UI 오버레이를 얹는다.
/// 진입 램프의 페이드가 끝나는 순간(=도면이 완전히 보이는 순간)과 맞춘다.
const indoorEntryZoomThreshold = indoorOverlayFadeInEndZoom;

/// 이 zoom 미만으로 축소하면 실내 오버레이를 접고 야외로 되돌아간다.
///
/// **진입 임계값과 같은 값을 쓰면 안 된다.** 두 값이 같으면 사용자가 층 전체를
/// 보려고 조금만 축소해도 즉시 야외로 튕겨 나간다. 더현대 서울의 지하는 지상
/// 보다 훨씬 넓다 — 층 도면은 정북 기준 53도 돌아가 있어서, 로컬 좌표로는
/// 295 x 148 m인 B3·B4가 화면(정북 정렬) 기준으로는 **286 x 305 m**를 차지한다.
/// 지상층(약 180 x 190 m)의 1.6배다.
///
/// 폭 360 px 화면에 이 286 m를 담으려면 z≈16.05까지 축소해야 하는데, 진입
/// 임계값 17.5에서 바로 이탈 판정이 나 "다 담기지도 않았는데 벗어나는" 증상이
/// 생겼다(17.5에서 보이는 폭은 121 m뿐이다).
///
/// 그래서 이탈은 fit zoom 16.05보다 확실히 아래인 15.6으로 내린다. 여기서
/// 보이는 폭이 450 m라 가장 넓은 지하층도 57% 여유를 두고 들어간다. 진입 17.5
/// 와의 사이 1.9 zoom이 히스테리시스 밴드이며, 그 안에서는 진입도 이탈도
/// 판정하지 않는다.
const indoorExitZoomThreshold = 15.6;

/// 하단 바에서 '홈'(야외)을 눌러 야외 지도로 돌아올 때 카메라를 맞출 zoom.
///
/// [indoorExitZoomThreshold]보다 **낮아야 한다.** 이 값이 이탈 임계값 위에
/// 있으면 오버레이를 닫아도 카메라는 "실내로 볼 수 있는 zoom"에 남는다. 그
/// 상태는 두 가지로 어긋난다 — 페이드 구간이 진입 램프로 되돌아가 도면이 반쯤
/// 보이고([indoorOverlayFadeExpr]), 다음 카메라 정지에서 다시 실내로 끌려
/// 들어갈 수 있다. 이탈 임계값 아래로 내리면 zoom 판정도 "야외"로 일치한다.
const outdoorReturnZoom = indoorExitZoomThreshold - 0.1;

/// 화면 폭 [viewportWidthPx]에서 실제로 쓸 진입 임계값.
///
/// [indoorEntryZoomThreshold]는 **절대 zoom**이라, 같은 값이라도 화면이 넓으면
/// 더 넓은 땅이 보인다. 이게 좁은 화면에서 확대 진입을 통째로 죽이고 있었다.
/// 더현대 서울(정북 정렬 폭 약 179 m, 위도 37.526) 기준으로:
///
/// | 화면 폭 | 건물이 화면에 담기는 zoom | z=17.5에서 보이는 폭 |
/// |---|---|---|
/// | 1400 px (데스크톱 Chrome) | 18.8 | 470 m — 건물이 여유롭게 담긴다 |
/// | 360 px (폰 세로) | 16.8 | 121 m — 건물의 68%만 보인다 |
///
/// 즉 데스크톱에서는 건물을 화면에 맞추기만 해도 17.5를 한참 넘겨 진입이
/// 저절로 발화하지만, 폰에서는 건물이 **화면 밖으로 넘칠 때까지** 확대해야
/// 닿는다. 사용자는 건물이 꽉 차는 z≈16.8에서 확대를 멈추므로 임계값에 영영
/// 닿지 않고, 건물을 직접 탭하는 경로만 남는다 — "실기기에서만 층 선택기와
/// 위치 지정 버튼이 안 뜬다"의 정체가 이것이었다.
///
/// 그래서 "건물이 화면 폭에 담기는 zoom"을 임계값의 상한으로 함께 쓴다.
///
/// **min을 쓰는 것이 핵심이다.** 두 값 중 낮은 쪽을 택하므로 이 보정으로
/// 진입이 지금보다 **어려워지는 화면은 없다.** 넓은 화면에서는 fit zoom이
/// 17.5보다 높게 나와 기존 17.5가 그대로 쓰인다(데스크톱 동작 불변).
///
/// 하한은 [indoorOverlayFadeOutEndZoom](16.0)이다. 두 가지를 동시에 지킨다.
///   - 진입 **후** 페이드 램프가 이 zoom에서 이미 100%라, 낮아진 임계값으로
///     들어가도 도면이 흐린 채로 진입하는 일이 없다.
///   - [indoorExitZoomThreshold](15.6)와의 히스테리시스 밴드가 남는다. 이
///     하한이 없으면 아주 넓은 건물 + 좁은 화면에서 진입 임계값이 이탈 임계값
///     아래로 내려가, 같은 zoom에서 진입과 이탈이 동시에 성립해 오버레이가
///     켜졌다 꺼졌다 진동한다.
///
/// [buildingWidthMeters]나 [viewportWidthPx]가 0 이하면(건물 미로드 등) 판정
/// 근거가 없으므로 보정 없이 기본 임계값을 그대로 돌려준다.
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

/// 건물을 **바깥에서 보여 줄 때** 진입 임계값에서 물러서는 폭(zoom 레벨).
///
/// zoom은 log2 스케일이라 0.7을 빼면 건물이 화면 폭의 약 62%를 차지한다 —
/// 건물 윤곽과 주변 길이 함께 보이는 "여기 있다"의 그림이다.
const exteriorViewZoomMargin = 0.7;

/// 검색에서 고른 건물의 **바깥 모습**을 보여 줄 zoom.
///
/// 진입 임계값과 한 파일에 두는 이유가 이 함수의 전부다 — **이 값은 반드시
/// 임계값보다 아래여야 한다.** 검색 결과를 누르는 것은 "저 건물이 어디 있는지"를
/// 묻는 조작이고, 들어가는 것은 건물을 탭하는 별도 조작이다. 두 값을 각자
/// 계산하면 화면 폭이 좁은 기기에서 물러선 배율이 도로 임계값을 넘어, 검색만
/// 했는데 도면이 열린다(실제로 그랬다 — 한때 외곽선을 화면에 꼭 맞췄는데
/// 그 배율이 곧 [indoorEntryZoomThresholdFor]가 정의하는 진입 조건이었다).
///
/// 임계값에는 하한이 있으므로([indoorOverlayFadeOutEndZoom]) 여기서 뺀 결과는
/// 그 아래로 내려갈 수 있다. 야외에서만 쓰는 값이라 문제가 되지 않는다 —
/// 이탈 판정은 이미 실내일 때만 의미가 있다.
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
/// 백엔드 MVT는 요청 타일 경계로 지오메트리를 4096 유닛에 양자화하는데, 낮은
/// zoom(예: z=10)에서는 1 유닛이 10 m 이상이라 건물이 눈에 띄게 뒤틀린 채로
/// 저장된다. 그 저-zoom 타일이 캐시에 남으면 사용자가 다시 확대하는 순간
/// MapLibre가 부모 타일을 over-scale해 잠깐 보여줘 도면이 회전된 것처럼 보인다.
///
/// 그래서 최대한 높게 잡되, **도면이 조금이라도 보이는 zoom은 반드시 덮어야
/// 한다.** MapLibre가 요청하는 타일 z는 카메라 zoom의 내림이므로, opacity가
/// 0보다 큰 최저 카메라 zoom([indoorExitZoomThreshold] = 15.6)에서 타일 z는
/// 15다. 16으로 두면 이탈 직전 페이드 구간에서 도면이 통째로 비어 버린다.
///
/// z=15 타일은 이 위도에서 폭 약 970 m라 4096 유닛 양자화가 0.24 m/유닛이다.
/// 실제로 백엔드 타일을 디코드해 z=15/16/17의 B4 footprint를 비교하면 셋 다
/// 286.1 x 307 m로 0.1 m 안에서 일치했다 — 문제였던 z=10(10 m/유닛)과 달리
/// 육안으로 뒤틀림이 보이지 않는다.
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

/// [zoom]에서 실내 진입 상태를 어떻게 바꿔야 하는지 판정한다.
///
/// 두 임계값 사이는 [IndoorEntryTransition.keep]이다. 실내에 들어와 층 전체를
/// 보려고 축소하는 구간이 여기이며, 반대로 아직 진입하지 않았다면 이 구간에서
/// 도면만 옅게 보일 뿐 실내 UI는 뜨지 않는다.
///
/// [buildingNearby]는 카메라가 실내 도면이 있는 건물 근처인지
/// (`isIndoorBuildingNearCamera`, `indoor_entry_proximity.dart`)다. false면
/// 아무리 확대해도 [IndoorEntryTransition.enter]를 내지 않는다 — 건물이 없는
/// 지역을 확대했을 때 도면 한 장 없이 층 선택기·위치 지정 버튼만 뜨는 것을
/// 막는다. 대신 [IndoorEntryTransition.exit]도 내지 않는다: 이탈은 축소와
/// 건물 밖 탭으로만 판정해, 실내에서 도면 끝을 보려고 살짝 패닝했을 때 화면이
/// 야외로 튀지 않게 한다.
///
/// 이 파라미터는 기본값을 두지 않는다. 기본값 true를 두면 새 호출부가 값을
/// 빼먹는 순간 "확대만으로 실내 진입" 버그가 조용히 되살아난다.
///
/// [entryZoom]은 이 화면 폭에서 쓸 진입 임계값이며 [indoorEntryZoomThresholdFor]
/// 가 계산한다. 이것도 같은 이유로 기본값을 두지 않는다 — 기본값
/// [indoorEntryZoomThreshold]를 두면 호출부가 값을 빼먹는 순간 좁은 화면에서
/// 확대 진입이 발화하지 않는 버그가 조용히 되살아난다.
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
