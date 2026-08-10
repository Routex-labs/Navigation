/// 야외 지도 위 "실내 진입 오버레이"의 zoom 정책.
///
/// 화면 코드에서 분리해 둔 이유는 이 값들 사이의 관계가 서로 얽혀 있어서다.
/// 임계값 하나만 옮겨도 "도면이 다 보이기 전에 실내에서 튕겨 나가는" 증상이나
/// "이탈 순간 도면이 툭 끊기는" 증상이 조용히 되살아난다. 관계를 함수로
/// 고정하고 테스트로 지킨다.
///
/// ## zoom 진입은 **위치 조건과 함께** 돌아왔다
///
/// 예전에는 임계값 이상으로 확대하면 그것만으로 실내 오버레이가 켜졌다. 확대는
/// "저 건물을 자세히 보고 싶다"는 뜻이지 "저 안에 들어왔다"는 뜻이 아니라,
/// 건너편에서 건물을 훑어보던 사용자가 영문 모르고 실내 화면에 들어와 있었다.
/// 그래서 한동안 걷어냈다.
///
/// 지금은 **화면 중심이 그 건물 위일 때만** 들여보낸다
/// ([shouldEnterIndoorForZoom]과 호출부의 위치 판정). 건물을 화면 한가운데
/// 놓고 그만큼 확대했다면 그건 "저 건물을 열어 보고 있다"에 가깝고, 걷어냈던
/// 이유였던 "건너편에서 훑어보는" 경우는 중심이 건물 밖이라 걸리지 않는다.
/// 도면 탭과 GPS 진입([indoor_entry_gps.dart])은 그대로다.
///
/// 이탈은 zoom이 계속 맡는다. 실내에서 충분히 축소하는 것은 "이제 밖을 보겠다"는
/// 명확한 조작이고, GPS가 건물 안을 계속 가리키는 동안 사용자가 화면을 빠져나올
/// 수단이 하나는 있어야 한다.
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

/// 도면이 완전히 보이는(페이드가 끝나는) zoom.
///
/// 한때는 이 값이 곧 **진입 임계값**이었다. 지금은 진입 트리거가 아니라 카메라를
/// 맞출 때의 목표 zoom이다 — 층 chip을 눌렀거나 실내로 들어왔는데 도면이 화면에
/// 안 보이면 여기까지 확대해 준다([indoorFocusZoomFor]).
const indoorFocusZoom = indoorOverlayFadeInEndZoom;

/// 이 zoom 미만으로 축소하면 실내 오버레이를 접고 야외로 되돌아간다.
///
/// **도면이 다 보이는 zoom보다 확실히 낮아야 한다.** 두 값이 붙어 있으면
/// 사용자가 층 전체를 보려고 조금만 축소해도 즉시 야외로 튕겨 나간다. 더현대
/// 서울의 지하는 지상보다 훨씬 넓다 — 층 도면은 정북 기준 53도 돌아가 있어서,
/// 로컬 좌표로는 295 x 148 m인 B3·B4가 화면(정북 정렬) 기준으로는
/// **286 x 305 m**를 차지한다. 지상층(약 180 x 190 m)의 1.6배다.
///
/// 폭 360 px 화면에 이 286 m를 담으려면 z≈16.05까지 축소해야 하는데, 예전처럼
/// 17.5에서 바로 이탈 판정이 나면 "다 담기지도 않았는데 벗어나는" 증상이
/// 생긴다(17.5에서 보이는 폭은 121 m뿐이다).
///
/// 그래서 이탈은 fit zoom 16.05보다 확실히 아래인 15.6으로 내린다. 여기서
/// 보이는 폭이 450 m라 가장 넓은 지하층도 57% 여유를 두고 들어간다.
const indoorExitZoomThreshold = 15.6;

/// 하단 바에서 '홈'(야외)을 눌러 야외 지도로 돌아올 때 카메라를 맞출 zoom.
///
/// [indoorExitZoomThreshold]보다 **낮아야 한다.** 이 값이 이탈 임계값 위에
/// 있으면 오버레이를 닫아도 카메라는 "실내로 볼 수 있는 zoom"에 남는다. 그
/// 상태는 두 가지로 어긋난다 — 페이드 구간이 진입 램프로 되돌아가 도면이 반쯤
/// 보이고([indoorOverlayFadeExpr]), 다음 카메라 정지에서 다시 실내로 끌려
/// 들어갈 수 있다. 이탈 임계값 아래로 내리면 zoom 판정도 "야외"로 일치한다.
const outdoorReturnZoom = indoorExitZoomThreshold - 0.1;

/// 화면 폭 [viewportWidthPx]에서 카메라를 맞출 zoom.
///
/// [indoorFocusZoom]은 **절대 zoom**이라, 같은 값이라도 화면이 넓으면 더 넓은
/// 땅이 보인다. 더현대 서울(정북 정렬 폭 약 179 m, 위도 37.526) 기준으로:
///
/// | 화면 폭 | 건물이 화면에 담기는 zoom | z=17.5에서 보이는 폭 |
/// |---|---|---|
/// | 1400 px (데스크톱 Chrome) | 18.8 | 470 m — 건물이 여유롭게 담긴다 |
/// | 360 px (폰 세로) | 16.8 | 121 m — 건물의 68%만 보인다 |
///
/// 즉 폰에서 고정 17.5로 맞추면 건물이 화면 밖으로 넘치게 확대돼, 포커스를
/// 맞췄는데 오히려 건물이 안 보인다. 그래서 "건물이 화면 폭에 담기는 zoom"을
/// 상한으로 함께 쓴다 — 두 값 중 낮은 쪽(min)이 답이다.
///
/// 하한은 [indoorOverlayFadeOutEndZoom](16.0)이다. 진입 **후** 페이드 램프가 이
/// zoom에서 이미 100%라, 여기까지만 확대해도 도면이 흐린 채로 남는 일이 없다.
/// [indoorExitZoomThreshold](15.6)보다도 위라, 포커스를 맞춘 그 자리에서 곧바로
/// 이탈 판정이 나는 일도 없다.
///
/// [buildingWidthMeters]나 [viewportWidthPx]가 0 이하면(건물 미로드 등) 판정
/// 근거가 없으므로 보정 없이 기본값을 그대로 돌려준다.
double indoorFocusZoomFor({
  required double buildingWidthMeters,
  required double viewportWidthPx,
  required double latitude,
}) {
  if (buildingWidthMeters <= 0 || viewportWidthPx <= 0) {
    return indoorFocusZoom;
  }
  final fitZoom = zoomToFitWidth(
    widthMeters: buildingWidthMeters,
    availablePx: viewportWidthPx,
    latitude: latitude,
  );
  return math.max(
    math.min(indoorFocusZoom, fitZoom),
    indoorOverlayFadeOutEndZoom,
  );
}

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

/// [zoom]에서 실내 오버레이를 접어야 하는지.
///
/// **판정은 이탈 하나뿐이다.** 확대는 아무리 깊어도 실내로 들여보내지 않는다 —
/// 진입은 도면 탭과 GPS만 담당한다(파일 상단 주석). 그래서 이 함수는 "얼마나
/// 축소했는가"만 본다.
///
/// [indoorExitZoomThreshold] 이상에서는 false다. 실내에 들어와 층 전체를 보려고
/// 축소하는 구간이 여기이며, 도면은 그동안 계속 진하게 남아 있다
/// ([indoorOverlayFadeOutEndZoom]).
bool shouldExitIndoorForZoom(double zoom) => zoom < indoorExitZoomThreshold;

/// 확대만으로 실내 오버레이를 켤 zoom.
///
/// 도면이 완전히 진해지는 지점([indoorFocusZoom])과 같다. 그보다 낮으면 반쯤
/// 흐린 도면 위에서 실내로 들어가 있게 되고, 화면은 "들어온 것도 아니고 밖도
/// 아닌" 상태로 보인다.
///
/// **이탈 임계값(15.6)과 크게 벌려 둔 것이 핵심이다.** 두 값이 붙어 있으면 손가락
/// 한 번 움찔하는 것만으로 진입과 이탈이 번갈아 발화한다.
const indoorEntryZoomThreshold = indoorFocusZoom;

/// 확대만으로 실내에 들어갈 zoom인지.
///
/// **이 판정 하나로 들어가지 않는다.** 호출부가 "카메라 중심이 실제로 그 건물
/// 위인지"를 함께 본다. zoom만 보고 들여보내던 시절에 건너편에서 건물을 훑던
/// 사용자가 영문 모르고 실내 화면에 들어와 있었고(파일 상단 주석), 그래서 한 번
/// 걷어냈던 기능이다. 위치 조건을 붙여 되살린 것이라 zoom 단독으로는 부족하다.
bool shouldEnterIndoorForZoom(double zoom) => zoom >= indoorEntryZoomThreshold;

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
