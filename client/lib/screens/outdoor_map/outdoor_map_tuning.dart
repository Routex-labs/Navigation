/// 야외 지도의 **조정 값**. 거리 문턱, 줌 배율, 애니메이션 길이, 화면 여백.
///
/// 화면 파일 머리에 상수 서른 몇 개가 쌓여 있었다. 그 자체로는 잘못이 아니지만,
/// 값을 하나 만지려고 열 때마다 화면 코드 전체를 스크롤해야 했고 "이 숫자가
/// 어디에 쓰이나"를 찾으려면 같은 파일 2,200줄을 훑어야 했다.
///
/// **근거는 값 옆에 그대로 남긴다.** 여기 있는 숫자는 대부분 실기기에서
/// 재보고 정한 것이라, 주석이 없으면 다음 사람이 "적당해 보이는 값"으로
/// 바꾼다.
library;

import 'package:latlong2/latlong.dart' as ll;

import 'indoor_entry_zoom.dart' show indoorTilesMaxZoom;

// 위치 조회 실패 시 대체 좌표 (서울시청). 저장·전달은 latlong2 타입으로 하고
// MapLibre API에 넘길 때만 [_toGl]로 변환한다 — 이 파일 외부(Building.entrance,
// DirectionsRoute.points)가 latlong2를 쓰고 있어 그 타입을 저장 형식으로 유지한다.
const fallbackLocation = ll.LatLng(37.5665, 126.9780);

// 'GPS 신호 약함' 배지 임계값.
//
// 진입 판정이 쓰는 [decisiveAccuracyMeters](20 m)보다 느슨하다. 배지는 "이 좌표를
// 믿지 말라"는 경고이고 판정은 "이 좌표로 결론을 내도 되는가"라, 후자가 더
// 엄격한 것이 맞다 — 20~30 m 구간에서는 배지 없이 판정만 보류한다.
const lowAccuracyThresholdMeters = 30.0;

// 야외 완료선은 GPS가 이 거리 이상 경로에서 떨어진 틱을 채택하지 않는다.
// 정확도 원 안에 경로가 들어오지 않는 상태에서 억지로 투영하면, 건물 안쪽이나
// 평행한 도로를 걸은 흔적이 계획 경로 위에 회색으로 그려진다.
const outdoorRouteMaxProjectionOffsetM = 25.0;

// GPS가 조금 흔들릴 때 진행점이 앞뒤로 떨리는 것을 표시하지 않는다. 실제로
// 되돌아 걷는 경우에도 이미 지나온 선은 완료 이력으로 남아야 하므로, 야외
// 사용자 선은 단조 증가 정책을 쓴다.
const outdoorRouteRegressionToleranceM = 2.0;

// 실내 경로 ETA 분 계산에 쓰는 평균 걷기 속도. 실내 화면 상수와 일치시켜야
// 같은 목적지 라우팅에서 두 화면 사이 표시가 어긋나지 않는다.
const indoorWalkingSpeedMetersPerSecond = 1.2;

// 자동 진입 직후 입구를 기준으로 실내 위치(PDR 앵커)를 잡을 때, 입구 좌표에서
// 통행 그래프까지 허용하는 최대 거리(m).
//
// 사용자가 손으로 찍는 경우(maxPdrAnchorSnapDistanceM, 40 m)보다 좁게 잡는다.
// 그쪽은 "화면에서 건물이 작게 보여 탭이 빗나가는" 오차를 감싸야 하지만, 여기서
// 비교하는 두 좌표는 백엔드가 내려준 입구와 같은 백엔드가 내려준 통행 그래프라
// 둘이 크게 벌어졌다면 그건 손 떨림이 아니라 **데이터 정합이 깨진 상태**다.
// 그런 상태에서 억지로 스냅하면 건물 반대편 복도에 위치를 찍어 놓고 거기서부터
// 걸음을 쌓는다 — 위치가 없는 것보다 나쁘다.
// 자동차 안내를 시작할 때 현재 위치로 내려가며 맞추는 zoom. 다음 교차로가
// 화면에 들어오는 정도이고, 실내 진입 임계값 위라 건물 근처에서 눌러도 도면이
// 끼어들지 않는다.
const carGuidanceZoom = 17.5;

const maxEntranceAnchorSnapDistanceM = 25.0;

// 자동 진입 때 GPS 좌표를 통로에 붙일 수 있는 최대 거리(m).
//
// 문 폴백([maxEntranceAnchorSnapDistanceM])보다 조인다. 문은 "여기로 들어왔다"가
// 확실한 지점이지만 GPS 좌표는 오차 반경을 달고 오므로, 통로에서 멀면 매장
// 한가운데를 가리키고 있을 가능성이 크다. 그때는 억지로 붙이지 않고 문으로
// 떨어지는 편이 낫다.
const autoEntryGpsSnapDistanceM = 15.0;

// 자동 앵커를 확정하기 전에 센서 세션의 첫 보고를 기다리는 최대 시간.
// 근거는 [_awaitSensorWarmup] 주석 참고.
const sensorWarmupTimeout = Duration(seconds: 2);

// GPS course(진행 방향)를 신뢰할 수 있다고 보는 최소 속도(m/s). 이보다 느리면
// 플랫폼이 채워 넣는 0°를 "정북으로 걸어 들어왔다"로 오독하게 된다.
const entryCourseMinSpeedMps = 0.5;

// 검색 결과에서 고른 야외 장소로 옮길 때의 zoom. 건물 하나가 화면에 들어오는
// 정도이고, 실내 진입 임계보다 낮게 둬 위치만 확인하는 이동이 실내 진입으로
// 읽히지 않게 한다.
const poiFocusZoom = 17.0;

// TMAP POI 좌표가 이만큼 안에 있으면 그 건물의 가게로 본다.
//
// 엄격한 폴리곤 판정으로는 안 된다 — TMAP이 주는 좌표는 대표점이 아니라
// **도로에서 들어오는 접근점**(frontLat/frontLon)이라 백화점 입점 매장도
// 건물 벽 바깥 인도에 찍힌다. 여유가 남의 가게를 삼킬 여지는 좁다. 이 판정만으로
// 두 줄을 합치는 것이 아니라 브랜드 이름까지 맞아야 하기 때문이다.
const poiBuildingProximityMeters = 40.0;

// 건물 폴리곤의 기본/눌린 상태 fill opacity. 기본은 옅게 존재만 알리고,
// 사용자가 탭한 순간 잠깐 진하게 반짝여서 "인식됐다"는 시각 피드백을 준다.
const buildingFillOpacityDefault = 0.15;

const buildingFillOpacityPressed = 0.45;

// 탭 후 오버레이 페이드인이 완료되는 시간 감각. 시각 피드백이 잠깐 이어져야
// "인식됐다" 느낌을 준다.
const buildingPressedHoldMs = 220;

/// 건물을 탭해 실내로 들어갈 때 카메라가 확대되는 시간.
///
/// 너무 빠르면(≤400ms) 한 번에 갈아 낀 것과 구분이 안 되고, 너무 느리면
/// (≥1.5s) 탭에 대한 반응이 굼떠 두 번 누르게 된다. 900ms면 확대되는 과정이
/// 눈에 남으면서도 기다린다는 느낌은 들지 않는다.
///
/// 반짝임([buildingPressedHoldMs] 220ms)이 끝난 **뒤에** 시작하므로, 탭부터
/// 도면이 자리 잡기까지는 약 1.1초다.
const indoorZoomInDuration = Duration(milliseconds: 900);

/// 층을 갈아탈 때 카메라가 새 층 외곽선에 다시 맞춰지는 시간.
///
/// 진입([indoorZoomInDuration])보다 짧다. 진입은 "밖에서 안으로 들어간다"는
/// 큰 장면 전환이라 과정을 보여 줘야 하지만, 층 전환은 이미 같은 건물 안에서
/// 도면만 갈아 끼우는 것이라 같은 900ms를 쓰면 층을 훑을 때마다 지도가 느릿하게
/// 따라와 답답하다.
const floorSwitchZoomDuration = Duration(milliseconds: 500);

/// 안내를 시작할 때 경로 전체를 담으러 물러서는 시간.
///
/// 진입(900ms)보다 짧고 층 전환(500ms)보다 길다. 진입만큼 큰 장면 전환은
/// 아니지만 "지금부터 이 길로 간다"를 읽을 시간은 줘야 한다.
const routeOverviewDuration = Duration(milliseconds: 700);

/// 개요 연출을 하지 않는 경로 길이(m).
///
/// 바로 옆 매장이면 담을 것이 없다. 물러섰다 돌아오는 동작만 남아 화면이
/// 까닭 없이 출렁인다. 걷기 경로 쪽 [_fitCameraToRoute]의 5m 가드와 같은 취지다.
const routeOverviewMinDistanceM = 5.0;

/// 경로 상자의 변 길이 하한(m).
///
/// **없으면 zoom이 발산한다.** 곧게 뻗은 복도 경로는 최소 넓이 상자의 짧은 변이
/// 0에 수렴하는데, [zoomToFitWidth]는 `log(가용폭 / 폭)`이라 폭이 0이면 무한대를
/// 돌려준다. 12m는 복도 폭 남짓이라, 곧은 경로도 양옆이 조금 보이는 배율에서
/// 멈춘다.
const routeFitMinSideM = 12.0;

/// 경로 개요가 확대해 들어가는 상한.
///
/// 하한([routeFitMinSideM])만으로는 짧은 세그먼트에서 배율이 지나치게
/// 올라간다 — 층 전환 직후 15m짜리 B1 세그먼트가 복도 하나만 꽉 채운 화면이
/// 됐다. 경로가 화면에 다 들어와도 **주변 매장 몇 개는 함께 보여야** 여기가
/// 어디인지 읽힌다. 타일이 더 세밀해지지 않는 상한(18)보다 반 단계 아래로
/// 잡아 짧은 경로에서도 맥락이 남게 한다.
const routeFitMaxZoom = 17.5;

/// "내 위치로" 버튼이 되돌아가는 배율의 하한.
///
/// 개요 연출이 물러선 자리에서 누르면 이만큼 다시 당겨 온다. 실내 타일이 더
/// 세밀해지지 않는 상한([indoorTilesMaxZoom])을 그대로 쓴다 — 그 위로 확대해도
/// 도면은 같은 그림을 늘린 것뿐이다.
///
/// 이미 이보다 확대해 둔 사용자에게는 **적용하지 않는다.** 무언가를 들여다보려
/// 당겨 둔 배율을 버튼 한 번에 되돌리면, 위치로 돌아가는 대신 방금 보던 것을
/// 잃는다.
const walkingViewZoom = indoorTilesMaxZoom;

/// "내 위치로" 카메라 이동 시간. 층 전환 재정렬(500ms)보다 짧다 — 사용자가 직접
/// 누른 조작이라 과정을 보여 줄 이유가 없고, 즉시 반응하는 편이 낫다.
const recenterDuration = Duration(milliseconds: 300);

/// 도면을 맞출 때 화면 위·아래에서 비워 두는 chrome 높이(논리 px).
///
/// 이걸 빼지 않으면 도면 한가운데가 화면 한가운데에 오는데, 위쪽은 검색창과
/// 카테고리 줄이 덮고 있어서 **도면 윗부분 매장이 칩에 가린다.** 아래 chrome이
/// 위보다 얇으므로, 가려지지 않는 띠의 한가운데로 도면을 내려 놓아야 한다.
const floorFitTopChromePx = placingHintTopPx;

const floorFitBottomChromePx = mapShellBottomChromePx;

/// 안내 중에 화면 위·아래에서 비워 두는 chrome 높이(논리 px).
///
/// **층 도면용 값([floorFitTopChromePx])을 그대로 쓰면 안 된다.** 그 132는
/// 검색창 + 카테고리 칩 줄 기준인데, 안내가 시작되면 칩 줄은 통째로 접히고
/// (map_shell_screen의 `_guidanceActive` 분기) 상단 바도 도착지 한 줄로 줄어든다.
/// 없는 줄만큼 위를 비우면 경로가 필요 이상으로 화면 아래에 눌려 놓인다.
/// 132에서 칩 줄(높이 ≈32 + 간격 8)을 뺀 값이다.
///
/// 아래도 마찬가지다. 하단 바는 안내 중 아예 그려지지 않고([_guidanceActive])
/// ETA 카드만 화면 맨 아래에 도킹하므로, 카드 높이만 비우면 된다.
const guidanceFitTopChromePx = 92.0;

const guidanceFitBottomChromePx = bottomBarLiftPx;

// PDR 앵커 배치 시 탭 위치에서 통로 그래프까지 허용하는 최대 거리(m).
// 야외 지도에서는 건물이 화면 안에서 상대적으로 작게 보이고 탭 정밀도가 떨어져
// 실내 SVG(12m)보다 크게 잡는다 — 사용자가 매장 폴리곤 안쪽을 탭해도 인근
// 복도 노드까지 20~25m 벌어지는 경우가 흔하다. 그 이상이면 사실상 건물 밖을
// 잘못 탭한 것으로 보고 다시 유도한다.
const maxPdrAnchorSnapDistanceM = 40.0;

// 층 선택기와 하단 바 사이 baseline 계산에 쓰이는 MapBottomBar 내부 여백
// (map_bottom_bar.dart의 outer padding).
const bottomBarInnerBottomPaddingPx = 14.0;

// pill 하단을 하단 바의 맨 아래 줄(홈/실내 세그먼트)과 같은 baseline에 앉힌다.
// 세그먼트는 우측, pill은 좌측이라 같은 줄에 내려도 겹치지 않는다. 실내 화면과
// 동일한 계산이어야 두 화면 사이 pill 위치가 어긋나지 않는다.
const floorSelectorBottomOffset = bottomBarInnerBottomPaddingPx;

// 경로 ETA 카드가 화면에 뜨면 하단 바(=층 선택기 기준선)가 이만큼 위로 올라간다.
// map_shell_screen.dart의 _etaBarLiftHeight와 동일해야 한다.
const bottomBarLiftPx = 92.0;

// 홈/실내 세그먼트의 왼쪽에 8px 간격으로 PDR 제어를 붙이는 right inset.
// indoor_map_screen.dart의 동명 상수와 같은 값이어야 실내 탭과 야외 실내 진입
// 오버레이에서 PDR 버튼이 같은 자리에 놓인다.
const pdrControlRightInsetPx = 184.0;

// PDR 안내 토스트를 하단 바(+ETA 카드) 위로 띄우기 위한 오프셋. 실내 화면의
// mapShellBottomChromePx/etaCardHeightPx와 같은 값을 쓴다.
const mapShellBottomChromePx = 112.0;

const etaCardHeightPx = 130.0;

// 위치 지정 안내를 상단 chrome 아래에 놓기 위한 오프셋. MapShellScreen의
// 검색창(top 0)과 그 아래 카테고리 chip 열(top 78, 높이 ≈32) 밑으로 내려야
// 안내가 chip에 가려지지 않는다. 이 오버레이는 chip 열과 **다른 Stack**에
// 있으므로 Positioned만으로는 겹침을 피할 수 없다 — SafeArea로 감싸 노치
// 기기에서 chip 열이 상태바만큼 내려앉는 것까지 같이 따라가야 한다.
// 실내 화면의 동명 상수(184)와 **일부러 다르다.** 홈에서는 카테고리 칩을 아예
// 노출하지 않기로 해서 여기 상단 오버레이는 장소 pill 한 줄뿐인 반면, 실내는
// 대분류·소분류·개수 안내까지 3단이라 그만큼 더 내려야 한다.
const placingHintTopPx = 132.0;
