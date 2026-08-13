/// 기압 변화로 **에스컬레이터 층 이동**을 판정한다.
///
/// 설계 원칙 세 개가 이 파일의 모든 임계값을 결정한다.
///
/// 1. **오탐 비용이 미탐 비용보다 훨씬 크다.** 층을 잘못 바꾸면 도면·경로·현재
///    위치가 통째로 엉뚱한 층으로 가고, 사용자는 복구 방법을 모른다. 놓치면
///    지금까지의 동작(수동 층 선택)과 같다. 그래서 애매하면 판정하지 않는다.
/// 2. **그래프 노드는 "허가"이고 기압이 "근거"다.** 에스컬레이터 노드 근처를
///    지나는 것만으로는 아무것도 확정하지 않는다. 반대로 노드 근처가 아니면
///    기압이 얼마나 변해도 층을 바꾸지 않는다(HVAC·자동문·기상 변화 방어).
/// 3. **절대 고도는 쓸 수 없다.** 해면기압이 시간당 1~2 hPa(8~16 m) 움직이므로,
///    직전 확정 층에서 다시 잡은 baseline과의 **차이**만 본다.
///
/// 올라갔는지 내려갔는지는 노드가 아니라 기압 부호가 정한다. 그 방향과 반대인
/// 탑승 노드는 후보에서 제외하고, 붙어 있는 레인은 활성 경로가 고른 정확한
/// 노드를 우선한다. 경로가 없으면 같은 방향 중 현재 위치에 가장 가까운 탑승
/// 노드를 쓴다. 도착 역할 노드는 탑승 허가에 사용하지 않는다.
///
/// HTTP·플러그인·UI를 알지 못하는 순수 로직이다. 합성 기압 시계열로 전부
/// 테스트된다: `client/test/features/indoor_navigation/escalator_transition_detector_test.dart`.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/floor_label.dart';
import '../../../models/floor_graph.dart';
import '../contract/altitude_sample.dart';
import '../contract/raw_motion_activity.dart';
import 'escalator_node_naming.dart';

/// 판정 임계값. 전부 **초안값**이며 실측 로그(schema v12의
/// `altimeter_samples`·`floor_transition_events`)를 보고 조정해야 한다.
class EscalatorDetectorConfig {
  const EscalatorDetectorConfig({
    this.armRadiusM = 6.0,
    this.routeApproachArmRadiusM = 16.0,
    this.armHoldMs = 60000,
    this.smoothingWindowMs = 3000,
    this.minSmoothingSamples = 3,
    this.maxSampleAgeMs = 15000,
    this.minDeltaM = 1.2,
    this.mapSwapDeltaM = 2.4,
    this.minConfirmDeltaM = 2.2,
    this.rampConsistencyWindowMs = 5000,
    this.minDirectionalRampStrides = 3,
    this.directionalStrideMs = 1000,
    this.minDirectionalSampleDeltaM = 0.04,
    this.minRampMs = 2500,
    this.settleWindowMs = 2500,
    this.minRampRiseM = 0.45,
    this.settleSlopeM = 0.25,
    this.fastAltitudeTauMs = 300,
    this.fastSlopeBaseMs = 700,
    this.fastExitSlopeMps = 0.12,
    this.fastExitWithStepSlopeMps = 0.18,
    this.fastExitQuietMs = 1000,
    this.candidateTimeoutMs = 90000,
    this.multiFloorRejectM = 10.0,
    this.baselineTrackAlpha = 0.02,
    this.boardingApproachRadiusM = 3.0,
    this.boardingApproachUpdates = 2,
    this.boardingPhaseTimeoutMs = 40000,
    this.minVerticalSpeedMps = 0.12,
    this.verticalMotionMinMs = 1000,
    this.visibleVerticalDeltaM = 1.2,
    this.minVisibleRiseM = 0.5,
    this.earlyVerticalQuietMs = 1000,
  });

  /// 에스컬레이터 노드에 이만큼 다가오면 판정을 "허가"한다. 랜딩 폭과 보정
  /// 위치 오차를 감안한 값이다.
  final double armRadiusM;

  /// 활성 다층 경로가 에스컬레이터 탑승 노드를 정확히 가리킬 때 허용하는 현재
  /// 위치 오차. 일반 근접 허가보다 넓지만 **경로 끝이 에스컬레이터인 경우에만**
  /// 사용하므로, 평소 복도에서 기압 변화만으로 층이 바뀌지는 않는다.
  ///
  /// 2026-07-30 하행 로그는 실제 -5.46m가 관측됐지만 map-matched 위치가 탑승
  /// 노드에서 약 12m 어긋나 `armed=false`로 끝났다. 16m는 그 실측 오차를
  /// 포함하면서 인접 에스컬레이터 뱅크까지 무제한 허가하지 않는 범위다.
  final double routeApproachArmRadiusM;

  /// 허가 유지 시간. 탑승 뒤에는 걸음이 멈춰 위치가 갱신되지 않으므로, 노드에서
  /// 멀어진 것으로 계산되는 동안에도 판정할 수 있어야 한다.
  final int armHoldMs;

  /// 중앙값 평활 창. 기압 단기 노이즈(±0.1~0.3 hPa ≈ ±1~2.5 m)를 눌러야
  /// 층 간격(4~6 m)과 구분된다.
  ///
  /// **이 창이 곧 판정 지연이다.** 중앙값은 창 길이의 절반쯤 뒤처지므로, 창이
  /// 4초면 실제로 오르기 시작한 시각보다 약 2초 늦게 delta가 따라온다. 층 전환
  /// 전체 지연(=여기 + [minDeltaM]에 도달할 때까지)에서 무시할 수 없는 몫이라
  /// 3초로 줄였다. iOS `CMAltimeter` 실측 간격 1069ms 기준 3개가 들어와 중앙값
  /// 3개짜리는 그대로 유지되고(단발 튐은 여전히 걸러진다), 지연은 약 1초로
  /// 줄어든다.
  ///
  /// 2000ms였을 때 iOS에서 판정이 **한 번도 돌지 않았다**. 2초 창에는 항상 2개만
  /// 들어와 [minSmoothingSamples]를 영원히 못 채웠기 때문이다(실측 로그의
  /// `smoothed_m`이 전 구간 null). 그 실패는 창 길이가 아니라 개수 보장이
  /// 없었던 탓이고, 지금은 아래 [minSmoothingSamples]가 창과 무관하게 최근 3개를
  /// 항상 남긴다 — 센서 간격이 더 벌어져도 판정은 계속 돈다.
  final int smoothingWindowMs;

  /// 평활에 쓸 최소 샘플 수. iOS ~0.93Hz, Android 5Hz로 간격이 5배 다르므로
  /// 시간 창만으로는 개수가 보장되지 않는다. 창보다 오래된 샘플이라도 최근
  /// 이 개수는 남겨 두어, 센서 주기가 어떻든 판정이 돌게 한다.
  final int minSmoothingSamples;

  /// 이보다 오래된 샘플은 평활에 쓰지 않는다.
  ///
  /// [minSmoothingSamples] 보장이 "오래된 샘플이라도 남긴다"는 뜻이라, 앱이
  /// background에 다녀오는 등 시계열이 끊긴 뒤에는 몇 분 전 고도가 중앙값에
  /// 섞일 수 있다. 그 구간은 판정하지 않고 창을 다시 채운다.
  final int maxSampleAgeMs;

  /// 후보를 열기 위한 최소 고도 변화(m). 건물마다 층고가 다르고 세션 시작
  /// 기압도 달라 절대 층고 대신, 사람이 한 번에 점프하기 어려운 변화량과
  /// 아래의 지속 방향 조건을 함께 쓴다.
  ///
  /// 이 값이 **지도가 바뀌는 시점**을 정한다. 1.8m였을 때 에스컬레이터 수직
  /// 속도(0.25~0.5 m/s) 기준 탑승 후 4~7초가 지나야 지도가 넘어갔고, 그 사이
  /// 사용자는 "이미 탔는데 아직 이전 층"인 화면을 봤다. 1.2m면 2~5초로 당겨진다.
  ///
  /// 더 낮출 수도 있지만 다음을 감수해야 한다. 후보가 열린 뒤 delta가
  /// `minDeltaM * 0.5` 아래로 돌아오면 취소로 보고 층·경로를 되돌리므로, 문턱이
  /// 낮을수록 그 되돌림 폭도 좁아져 평활 노이즈에 층이 깜빡일 수 있다. 1.2m는
  /// 중앙값 평활 뒤 잔여 노이즈(±0.3m 수준)의 4배이면서 반 층보다 낮은 값이다.
  ///
  /// **이 문턱 하나로 층이 바뀌지는 않는다.** 탑승 노드 근접 허가, 같은 방향으로
  /// 이어지는 램프([minDirectionalRampStrides]), 지금도 그 속도로 움직이는 중
  /// ([minRampRiseM])이 모두 함께 성립해야 한다. 기상 드리프트는 세 번째 조건에서
  /// 걸린다.
  ///
  /// 예전에는 이 문턱이 **지도가 바뀌는 시점**이기도 했다. 지금은 후보만 열고,
  /// 도면 교체는 [mapSwapDeltaM]에서 따로 한다.
  final double minDeltaM;

  /// 목적 층 도면으로 갈아 끼우는(조기 층 전환 신호를 내는) 누적 변화량.
  ///
  /// [minDeltaM]과 분리한 이유는 2026-08-13 더현대 실측 피드백이다. Δ1.2m에서
  /// 도면을 갈면 26초 탑승 중 21초를 도착 층 도면으로 보낸다 — 아직 출발 층
  /// 천장도 못 지났는데 화면은 도착 층이라, 사용자가 "층 전환이 너무 빨리
  /// 일어난다"고 느꼈다. 2.4m는 실측 층고(4.4~6.2m)의 반 층 부근이라, 도면이
  /// 바뀌는 순간과 몸이 두 층 사이 중간을 지나는 순간이 대략 겹친다.
  ///
  /// [minConfirmDeltaM](2.2)보다 크므로 낮은 층고에서는 확정이 이 문턱보다
  /// 먼저 올 수 있다. 그 경우 조기 신호 없이 `landed`에서 한 번에 전환된다 —
  /// 신호 순서가 꼬이는 것보다 늦은 전환이 낫다.
  final double mapSwapDeltaM;

  /// PDR 고정을 풀고 층 이동을 최종 확정할 최소 변화량. 고정된 한 층 높이를
  /// 맞히려 하지 않고, 같은 방향의 등속 변화와 하차 시 수직 속도 감소가 함께
  /// 확인될 때만 쓴다. 더현대 실측 한 층은 약 4.4~6.2m였지만 더 낮은 층고도
  /// 놓치지 않도록 이 문턱 자체는 낮게 둔다.
  final double minConfirmDeltaM;

  /// 후보 시작 전 상승·하강이 한 번의 압력 튐이 아니라 같은 방향으로 이어졌는지
  /// 확인하는 시간 창이다.
  final int rampConsistencyWindowMs;

  /// 그 창 안에서 같은 방향으로 움직인 것을 확인할 **구간(stride) 수**.
  ///
  /// 예전에는 "샘플 수"였는데, 그러면 같은 5초가 iOS에서는 4~5개, Android에서는
  /// 27개로 세어진다. 개수 문턱 3은 iOS에서 3초어치를 요구하지만 Android에서는
  /// 0.5초어치로 줄어, 노이즈 몇 개가 곧 "같은 방향으로 이어졌다"가 된다.
  final int minDirectionalRampStrides;

  /// 한 구간의 최소 길이. 이보다 짧은 간격의 샘플 쌍은 한 구간으로 세지 않는다.
  ///
  /// 이 값이 곧 [minDirectionalSampleDeltaM]의 의미를 정한다. 1초 동안 4cm는
  /// 에스컬레이터(0.25 m/s = 25cm)에 한참 못 미치는 하한이지만, 0.18초 동안
  /// 4cm는 0.22 m/s여서 실제 탑승과 노이즈를 못 가른다.
  final int directionalStrideMs;

  final double minDirectionalSampleDeltaM;

  /// 후보가 최소 이만큼 유지돼야 확정 판단으로 넘어간다.
  ///
  /// 중앙값 평활은 상승이 하강으로 꺾이는 지점에서 **평평한 구간**을 만든다.
  /// 그래서 짧게 올라갔다 바로 내려오면 꼭대기에서 "안정됨" 조건이 만족돼
  /// 확정될 수 있다. 다만 후보가 반 층(Δ 2.5m)에서 이미 열리고 빠른 확정은
  /// 별도로 수직 속도 감소까지 요구하므로, 오래 기다리면 하차 뒤에도 마커가
  /// 얼어 있었다. 되돌림 방어는 유지하면서 2.5초만 둔다.
  final int minRampMs;

  /// 상승/하강이 멈췄는지 보는 창. "움직이는 중"인지도 같은 창으로 본다.
  final int settleWindowMs;

  /// 후보를 열려면 [settleWindowMs] 동안 이만큼은 실제로 움직이고 있어야 한다.
  ///
  /// **누적 변화량만으로는 부족하다.** 기상 변화로 5분에 3m가 흐르면 누적
  /// [minDeltaM]을 넘고, 순간 기울기는 0에 가까워 "안정됨" 조건까지 통과해
  /// 층이 바뀐다(실제로 이 테스트에서 오탐이 났다). 에스컬레이터의 수직 속도는
  /// 0.2~0.3 m/s(≈0.5~0.75 m / 2.5초)이고 기상 드리프트는 0.01 m/s 수준이라,
  /// 속도 조건 하나로 두 경우가 10배 이상 벌어진다.
  ///
  /// [minDeltaM]을 1.8→1.2로 낮추면서 0.35→0.45로 올렸다. 누적 변화량 문턱이
  /// 내려간 만큼 "지금 실제로 그 속도로 움직이는 중"이라는 근거를 더 받는
  /// 것이다. 0.45m/2.5초 = 0.18 m/s로 에스컬레이터(0.2~0.3 m/s)보다 낮아 실제
  /// 탑승은 그대로 통과하고, 드리프트(0.01 m/s)보다는 18배 높다.
  final double minRampRiseM;

  /// 이 창 동안 고도 변화가 이 값 이하면 "멈췄다"로 본다. 확정 시점을 하차
  /// 순간에 맞추려면 임계값 통과가 아니라 **정지**를 기다려야 한다. 임계값
  /// 통과에서 바로 확정하면 아직 탑승 중인데 지도가 바뀐다.
  final double settleSlopeM;

  /// 하차 직후를 빠르게 잡기 위한 저지연 EMA의 **시정수**(ms). 기존 중앙값
  /// 평활은 오탐 방어에는 좋지만 iOS 1Hz 샘플에서 3~4초 늦는다. 후보가 이미
  /// 열린 뒤에는 이 빠른 필터를 "움직임이 잦아들었는지" 확인하는 보조 근거로만
  /// 쓴다.
  ///
  /// 예전에는 샘플당 고정 계수(α 0.65)였다. 같은 α가 iOS 1069ms에서는 시정수
  /// 약 1초짜리 필터지만 Android 180ms에서는 0.2초짜리가 되어, 기압 원시값을
  /// 거의 그대로 통과시킨다. 시정수로 적으면 두 기기가 같은 필터가 된다 —
  /// 계수는 매 샘플 `1 - exp(-dt/tau)`로 만든다.
  ///
  /// 300ms는 짧아 보이지만, **평활의 몫이 [fastSlopeBaseMs]로 넘어갔기 때문이다.**
  /// 이 EMA가 맡는 일은 빠른 센서의 샘플 잡음을 눌러 주는 것뿐이고(Android
  /// 180ms에서 α 0.45 = 두세 샘플 평균), 노이즈 대 신호를 실제로 가르는 것은
  /// 700ms 밑변이다. iOS는 α 0.97로 사실상 원시값이 지나가는데, 샘플 간격
  /// 자체가 이미 1초짜리 밑변이라 여기서 더 누르면 지연만 는다.
  ///
  /// 1000ms(기존 α 0.65와 같은 값)로 두면 그 지연이 실제로 보였다 — 문턱
  /// 근처의 느린 램프에서 수직 속도가 한 샘플씩 늦게 잡혀, 연속 환승에서
  /// 마커를 세우는 시점이 1초 밀렸다.
  final int fastAltitudeTauMs;

  /// 수직 속도를 잴 **최소 시간 밑변**(ms).
  ///
  /// 속도를 직전 샘플과의 차이로 재면 밑변이 곧 센서 주기다. Android 180ms
  /// 밑변에서 에스컬레이터는 한 샘플에 5cm 움직이는데, 기압 센서 분해능은 흔히
  /// 0.01 hPa(약 8cm)라 **진짜 변화가 격자보다 작다.** 그러면 연속 샘플이 같은
  /// 값으로 나오고 속도는 정확히 0으로 읽힌다 — 타고 있는 중에 "멈췄다"가 된다.
  ///
  /// 700ms 이상 떨어진 샘플과 비교하면 그 사이 실제 변화가 17cm를 넘어 격자
  /// 위로 올라온다. iOS는 직전 샘플이 이미 1069ms 뒤라 지금과 동일하게 동작한다.
  final int fastSlopeBaseMs;

  /// 빠른 EMA의 수직 속도가 이 값 이하로 유지되면 하차로 본다.
  final double fastExitSlopeMps;

  /// 새 걸음이 함께 관측된 경우의 완화된 속도 상한. 사용자가 에스컬레이터에서
  /// 걷더라도 수직 속도가 계속 크면 통과하지 않고, 하차 뒤 첫 걸음과 수직 속도
  /// 감소가 겹치면 곧바로 재개한다.
  final double fastExitWithStepSlopeMps;

  /// 걸음 근거가 없을 때 저속이 **유지돼야 하는 시간**.
  ///
  /// 예전에는 "연속 저속 샘플 2개"였다. 그 2개가 iOS에서는 약 2.1초지만
  /// Android에서는 0.36초라, 노이즈 한 번이 하차로 읽혔다. 그 결과가 탑승
  /// 중간의 확정 → 남은 반 층의 재판정, 즉 **한 층을 내려가는데 층이 두 번
  /// 바뀌는** 증상이다(Android에서만 재현됐다).
  ///
  /// 1000ms는 iOS의 두 번째 저속 샘플이 도착하는 시각(1069ms)과 같다 — 지금
  /// 통과 중인 iOS 타이밍을 그대로 두고 Android만 맞춘다.
  final int fastExitQuietMs;

  /// 후보가 이 시간 안에 안정되지 않으면 기상 변화·센서 드리프트로 보고 버린다.
  final int candidateTimeoutMs;

  /// 이만큼 큰 변화는 에스컬레이터 한 층으로 설명되지 않는다(엘리베이터이거나
  /// 연속 에스컬레이터를 쉬지 않고 탄 경우). v1은 ±1층만 지원하므로 확정하지
  /// 않고 거부하되, 얼마나 자주 생기는지 로그로 남긴다.
  ///
  /// 더현대 실측에서 한 층(B2→B1) 상승이 **6.2m**였다. 처음 잡은 8.0m는 한 층
  /// 이동의 1.3배밖에 안 돼 정상 이동을 거부할 위험이 있어 10.0m로 올렸다.
  /// 두 층(약 12m)과는 여전히 구분된다.
  final double multiFloorRejectM;

  /// 허가/후보가 없는 동안 baseline을 천천히 따라가는 비율. 기상 드리프트를
  /// 흡수한다. 허가 중에는 추적하지 않는다 — 상승분을 같이 먹어버린다.
  final double baselineTrackAlpha;

  /// 활성 경로의 탑승점에 이만큼 다가오면 **배너만** 띄운다.
  ///
  /// 배너는 되돌리기 비용이 거의 없다(문구가 사라질 뿐이다). 그래서 층 지도를
  /// 바꾸는 [minDeltaM]보다 훨씬 이른 근거로 띄워도 된다. 반대로 기압이
  /// [minDeltaM]만큼 움직일 때까지 기다리면 이미 반 층을 올라간 뒤에 배너가 뜬다.
  final double boardingApproachRadiusM;

  /// 탑승점까지 남은 거리가 줄어드는 것을 확인할 **서로 다른 걸음 갱신** 횟수.
  ///
  /// 한 프레임의 근접만으로 띄우면 탑승점 옆을 스쳐 지나가는 사람에게도 뜬다.
  final int boardingApproachUpdates;

  /// 배너를 띄운 뒤 수직 이동 근거 없이 기다리는 최대 시간. 넘으면 취소한다.
  final int boardingPhaseTimeoutMs;

  /// "지금 실제로 오르내리는 중"으로 보는 최소 수직 속도(m/s).
  ///
  /// 에스컬레이터는 0.2~0.3 m/s, 기상 드리프트는 0.01 m/s 수준이다. 이 값은
  /// 누적 고도 [minDeltaM]에 닿기 **전에** 걸음 누적을 멈추기 위한 근거이며,
  /// 층 지도를 바꾸는 근거로는 쓰지 않는다.
  final double minVerticalSpeedMps;

  /// 단일 기압 튐을 배제하기 위해 같은 방향이 이어져야 하는 시간.
  ///
  /// iOS 연속 2샘플(1069ms)과 같은 길이다. 개수로 적으면 Android에서 0.36초가
  /// 되어, 걷는 동안의 기압 노이즈로도 마커가 멈춘다.
  final int verticalMotionMinMs;

  /// 노드 근접 없이 **사용자에게 보이는 단계**로 올리기 위한 누적 고도 변화(m).
  ///
  /// 층 판정은 두 겹이다. 1차(수직 속도가 잡힘)는 화면에 아무것도 알리지 않고
  /// 걸음도 그대로 흘린다. 2차에서만 걸음을 멈추고 마커를 세우고 화면을 덮는다 —
  /// 이 둘을 나눈 이유는, 근거가 옅은 시점에 마커를 세우면 **아직 통로를 걷고
  /// 있는 사용자의 점이 먼저 멈춰 버려** 화면이 고장 난 것처럼 보이기 때문이다.
  ///
  /// 2차로 올라가는 길은 둘이다. 하나는 탑승점에 [boardingApproachRadiusM](3m)
  /// 안으로 붙는 것이고, 다른 하나가 이 값이다. 1.2m은 평활 뒤 잔여 노이즈
  /// (±0.3m)의 네 배이면서 반 층에는 한참 못 미친다 — 계단 몇 칸이나 기상
  /// 드리프트로는 안 나오고, 하차 전에 충분히 잡힌다. 랜딩에서 보정 위치가
  /// 12m까지 어긋나 노드 허가가 안 걸리던 실측 사례를 이 갈래가 받는다.
  ///
  /// 지도 전환 문턱([minDeltaM])과 같은 값이지만 **하는 일이 다르다.** 이쪽은
  /// 걸음을 멈추고 마커를 세우는 데까지고, 도면 교체는 그 위에 노드 허가와 램프
  /// 일관성을 더 요구한다 — 되돌릴 수 없는 쪽은 근거를 그대로 둔다. 화면을 덮는
  /// 시점은 또 따로다(도면이 실제로 갈리는 순간). 걸음을 멈추는 것은 그 구간의
  /// 발판 진동이 위치에 쌓이는 것을 막는 일이라 이르게 해도 손해가 없지만,
  /// 화면을 덮는 것은 이르면 지도를 못 보는 시간만 길어진다.
  final double visibleVerticalDeltaM;

  /// 탑승점이 정해져 있어도 2차로 올리기 전에 요구하는 최소 수직 변화(m).
  ///
  /// 수직 **속도**만 보면 기압 노이즈 한 번에 단계가 올라간다. 평활 뒤 잔여
  /// 노이즈가 ±0.3m쯤이고 빠른 EMA(α 0.65)는 그 튐을 0.6 m/s로 읽으므로, 두
  /// 샘플 연속은 복도를 걷는 동안에도 성립한다. 실제로 **얼마나** 움직였는지를
  /// 함께 봐야 걸을 때 마커가 탑승 노드로 끌려갔다 돌아오는 일이 없다(실기기에서
  /// "걸을 때 위치가 계속 뒤로 순간이동한다"로 나타났다).
  ///
  /// 0.5m은 잔여 노이즈의 1.5배가 넘으면서 에스컬레이터 속도(0.25 m/s)로 2초면
  /// 넘는 값이다 — 오탐은 막고 판정은 안 늦춘다.
  final double minVisibleRiseM;

  /// 노드를 못 고른 채 열린 2차 단계를 접기까지 "수직 속도 없음"이 이어져야
  /// 하는 시간.
  ///
  /// 노드가 없으면 하차를 확정할 수단도 없어서, 그대로 두면 화면이 덮인 채
  /// [boardingPhaseTimeoutMs](40초)를 기다린다. 수직 이동이 멎으면 내린 것으로
  /// 보고 바로 걷는다 — 어차피 이 단계가 한 일은 걸음 정지뿐이라 되돌리는 비용이
  /// 없다.
  final int earlyVerticalQuietMs;
}

/// 층 이동의 공개 진행 단계.
///
/// 배너·걸음 pause·층 지도 전환·하차 재개가 **서로 다른 근거와 시점**을 쓰도록
/// 나눈 것이다. 예전에는 넷이 모두 `|delta| >= 1.8m` 한 지점에서 동시에
/// 일어나서, 배너는 반 층 뒤에 뜨고 지도는 아직 타는 중에 바뀌었다.
enum EscalatorPhase {
  idle,

  /// 활성 경로의 탑승점에 접근했다. 배너만 띄운다.
  boardingDetected,

  /// 실제로 오르내리는 중이다. 위치에 반영하는 걸음만 멈춘다.
  verticalMotionDetected,

  /// 반 층을 지났다. 이 단계에서만 목적 층 지도를 연다.
  midpointReached,

  /// 하차했다. 새 anchor를 잡고 걸음 적용을 재개한다.
  landed,

  cancelled,
  failed,
}

/// 단계 전이 한 건. UI는 이 값만 보고 문구·pause·층 전환을 결정한다.
class EscalatorPhaseChange {
  const EscalatorPhaseChange({
    required this.phase,
    required this.atMs,
    required this.fromFloorLabel,
    required this.reason,
    this.toFloorLabel,
    this.group,
    this.direction,
    this.boardingNodeId,
    this.expectedArrivalNodeId,
    this.deltaM = 0,
    this.transition,
  });

  final EscalatorPhase phase;
  final int atMs;
  final String fromFloorLabel;
  final String reason;
  final String? toFloorLabel;
  final String? group;
  final EscalatorDirection? direction;
  final String? boardingNodeId;
  final String? expectedArrivalNodeId;
  final double deltaM;

  /// `midpointReached`·`landed`·`cancelled`에서만 채워진다.
  final EscalatorTransition? transition;

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'at_ms': atMs,
    'reason': reason,
    'from_floor': fromFloorLabel,
    'to_floor': toFloorLabel,
    'group': group,
    'direction': direction?.name,
    'boarding_node_id': boardingNodeId,
    'expected_arrival_node_id': expectedArrivalNodeId,
    'delta_m': deltaM,
  };
}

/// 확정된 층 이동.
class EscalatorTransition {
  const EscalatorTransition({
    required this.group,
    required this.direction,
    required this.fromFloorLabel,
    required this.toFloorLabel,
    required this.deltaM,
    required this.durationMs,
    required this.stepsDuring,
    required this.boardingNodeId,
    required this.boardingNodeName,
    required this.boardingDistanceM,
    required this.boardingEvidence,
    this.expectedArrivalNodeId,
  });

  /// 에스컬레이터 뱅크 식별자(`ES1`…). 도착 노드를 새 층에서 찾을 때 쓴다.
  final String group;

  final EscalatorDirection direction;
  final String fromFloorLabel;
  final String toFloorLabel;

  /// baseline 대비 고도 변화(m). 상행이면 양수.
  final double deltaM;

  /// 후보가 열린 시점부터 확정까지 걸린 시간.
  final int durationMs;

  /// 그 사이 늘어난 걸음 수. 에스컬레이터는 거의 0, 계단은 크다 — 사후 분석에서
  /// 두 경우를 가르는 값이다.
  final int stepsDuring;

  final String boardingNodeId;
  final String? boardingNodeName;

  /// 허가 시점에 관측한 탑승 노드까지의 거리(m).
  final double boardingDistanceM;

  /// `observed`(위치로 단일 후보), `routeAndObserved`(예정 노드도 근접 관측),
  /// `routeExpected`(위치 오차 때문에 활성 경로의 예정 노드만 사용).
  final String boardingEvidence;

  /// 활성 경로가 선택한 정확한 도착 노드. 붙어 있는 레인은 센서로 억지
  /// 재구분하지 않고 길찾기가 고른 전이를 따라 새 층 앵커를 복원한다.
  final String? expectedArrivalNodeId;
}

/// 판정 과정 진단 이벤트. 확정뿐 아니라 **거부도 남긴다** — 임계값 튜닝은
/// 거부 이유가 있어야 가능하다.
class EscalatorDetectionEvent {
  const EscalatorDetectionEvent({
    required this.atMs,
    required this.kind,
    required this.reason,
    required this.deltaM,
    required this.fromFloorLabel,
    this.toFloorLabel,
    this.group,
    this.durationMs,
    this.stepsDuring,
    this.boardingEvidence,
  });

  final int atMs;

  /// `armed` · `candidate` · `confirmed` · `rejected`.
  final String kind;

  /// 거부 이유(`reverted`·`noSettle`·`multiFloorUnsupported`·`noBoardingNode`·
  /// `unknownTargetFloor`) 또는 진행 사유.
  final String reason;

  final double deltaM;
  final String fromFloorLabel;
  final String? toFloorLabel;
  final String? group;
  final int? durationMs;
  final int? stepsDuring;
  final String? boardingEvidence;

  Map<String, Object?> toJson() => {
    'at_ms': atMs,
    'kind': kind,
    'reason': reason,
    'delta_m': deltaM,
    'from_floor': fromFloorLabel,
    'to_floor': toFloorLabel,
    'group': group,
    'duration_ms': durationMs,
    'steps_during': stepsDuring,
    'boarding_evidence': boardingEvidence,
  };
}

/// 기압 시계열 + 에스컬레이터 노드 근접으로 층 이동을 판정하는 상태기.
///
/// 입력은 두 갈래다. [updateContext]·[onPosition]이 "지금 어느 층의 어느
/// 에스컬레이터 근처인가"를 알려주고, [onAltitude]가 기압을 넣으며 판정한다.
class EscalatorTransitionDetector {
  EscalatorTransitionDetector({
    this.config = const EscalatorDetectorConfig(),
    this.maxEvents = 200,
  });

  final EscalatorDetectorConfig config;

  /// 진단 이벤트 보관 상한. 넘으면 오래된 쪽을 버린다.
  final int maxEvents;

  // 컨텍스트.
  String? _floorLabel;
  FloorGraph? _graph;
  List<String> _floorLabels = const [];
  List<_EscalatorNode> _escalatorNodes = const [];

  // 기압 상태.
  final List<AltitudeSample> _window = [];
  final List<_Smoothed> _smoothedHistory = [];
  double? _baselineM;
  double? _lastSmoothedM;

  // 허가 상태. 도착 노드나 같은 그룹의 다른 레인이 대신 허가하지 못하도록
  // 탑승 노드 id별로 보관한다.
  final Map<String, _ArmedNode> _armedNodes = {};
  final Map<String, double> _observedBoardingDistances = {};
  String? _expectedBoardingNodeId;
  String? _expectedArrivalNodeId;
  String _boardingEvidence = 'observed';
  int? _armedUntilMs;
  int _lastSteps = 0;

  /// 방금 확정한 이동의 목적 층. 화면이 그 층을 알려 올 때 "설명되는 층 변경"
  /// 임을 알아보고 baseline·기압 창을 지키기 위한 표식이다. 한 번 쓰면 비운다.
  String? _confirmedToFloorLabel;

  // 후보 상태.
  int? _candidateStartMs;
  int _candidateSign = 0;
  int _candidateStartSteps = 0;
  _EscalatorNode? _candidateBoarding;
  String? _candidateToFloor;

  // 중앙값 평활보다 빠른 하차 판정 상태.
  double? _fastAltitudeM;
  int? _lastFastAltitudeAtMs;

  /// 빠른 EMA의 최근 이력. 수직 속도를 [EscalatorDetectorConfig.fastSlopeBaseMs]
  /// 이상 떨어진 값과 비교해 재기 위해 들고 있다.
  final List<_Smoothed> _fastHistory = [];

  /// 저속이 이어지기 시작한 시각. 저속이 끊기면 null.
  int? _fastExitQuietSinceMs;
  int _lastAltitudeSteps = 0;

  /// 위치 적용과 무관한 원시 움직임 누적. 걸음 pause 중에도 늘어난다.
  int _rawMotionCount = 0;
  int _lastAltitudeRawMotionCount = 0;

  /// 원시 움직임 중 **네이티브 걸음만** 센 것. 발판 진동(accel peak)은 여기
  /// 안 들어간다 — 진동은 "기기가 움직이는 중"의 근거는 되지만 "하차 후 첫
  /// 걸음"의 근거는 못 된다. 2026-08-13 Samsung 실측에서 진동이 걸음으로
  /// 인정돼 탑승 중간(층고의 65%)에 하차가 확정됐다.
  int _rawStepCount = 0;
  int _lastAltitudeRawStepCount = 0;

  /// 확정 직후 수직 이동이 실제로 멎을 때까지 새 후보를 열지 않는 잠금.
  ///
  /// 확정이 하차보다 이르면 baseline이 탑승 중간 높이로 잡히고, 남은 이동분이
  /// **유령 후보**로 다시 열린다(2026-08-13 실측: 확정 10초 뒤 잔여 2.1m가
  /// Δ2.14 후보로 열려 확정 문턱 2.2m에 6cm 차이로만 살아남았다 — 이전
  /// 이중 층 전환의 정체). 저속이 [EscalatorDetectorConfig.earlyVerticalQuietMs]
  /// 만큼 이어지면 그 시점 고도로 baseline을 다시 잡아 잔여분을 흡수한다.
  bool _awaitingPostConfirmQuiet = false;
  int? _postConfirmQuietSinceMs;

  // UI가 "층은 먼저 바꾸고 마커는 고정"하는 두 단계 전환을 적용할 수 있도록
  // 후보 시작/취소 신호를 한 번씩 보관한다. 최종 확정은 onAltitude 반환값이다.
  EscalatorTransition? _startedTransition;
  EscalatorTransition? _cancelledTransition;
  EscalatorTransition? _pendingTransition;

  // 공개 단계 상태.
  EscalatorPhase _phase = EscalatorPhase.idle;
  int? _phaseEnteredAtMs;
  final List<EscalatorPhaseChange> _phaseChanges = [];

  // 탑승점 접근 상태(배너 근거). 위치 갱신에서만 갱신한다.
  double? _lastApproachDistanceM;
  int _approachDecreaseUpdates = 0;
  int? _lastApproachSteps;
  _EscalatorNode? _approachBoarding;

  /// 내리자마자 바로 다음 에스컬레이터를 타는 구간인지. 안내가 알려 준다.
  ///
  /// 이 경우 사용자는 이미 발판 앞에 서 있고, 다음 행동은 타는 것 하나뿐이다.
  /// "얼마나 올랐는지"를 기다릴 이유가 없고(어차피 걸을 거리가 없어 오탐 여지도
  /// 없다), 기다리면 연속 환승마다 마커가 먼저 몇 걸음 흘러간다.
  bool _immediateTransfer = false;

  // 수직 이동 상태(걸음 pause 근거). 시각으로 들고 있다 — 개수로 세면 같은
  // 조건이 기기 주기에 따라 5배 다른 시간을 뜻하게 된다.
  int? _verticalMotionSinceMs;
  int _verticalMotionSign = 0;

  /// 지금 걸음을 멈춘 단계가 **노드 허가 없이** 열린 것인지. 하차를 확정할
  /// 수단이 없으므로, 수직 이동이 멎는 즉시 접어야 한다.
  bool _earlyVerticalMotion = false;
  int? _verticalMotionQuietSinceMs;

  /// 1차 감지 — 수직 속도가 잡혔다. **화면에는 알리지 않는다.** 디버그 칩이
  /// "왜 아직 탑승으로 안 넘어가는가"를 볼 수 있게만 내놓는다.
  bool _verticalMotionObserved = false;

  /// 같은 방향으로 이어지는 동안 빠른 EMA 속도를 시간으로 적분한 변위(m).
  ///
  /// 중앙값 평활 delta와 **같은 것을 재지만 훨씬 덜 늦다.** 중앙값은 창 길이의
  /// 절반쯤(iOS 1069ms 간격에 3샘플이면 약 1.1초) 뒤처지므로, 그 값으로 걸음
  /// 정지를 걸면 실제로 오르내리기 시작한 시각보다 1초 넘게 늦게 멈춘다. 그
  /// 1초가 곧 발판 진동이 위치에 쌓이는 시간이다.
  ///
  /// 방향이 바뀌거나 수직 속도가 문턱 아래로 떨어지면 0으로 되돌린다 — 누적이
  /// 살아 있으면 오르내림을 반복하는 동안 값만 커진다.
  ///
  /// **층을 바꾸는 판정에는 쓰지 않는다.** 그쪽은 되돌릴 수 없으므로 노이즈에
  /// 강한 중앙값을 그대로 쓴다.
  double _fastDisplacementM = 0;

  final List<EscalatorDetectionEvent> _events = [];

  /// 디버그 오버레이·로그용 현재 관측값.
  double? get baselineM => _baselineM;
  double? get smoothedAltitudeM => _lastSmoothedM;
  double? get deltaM => (_baselineM == null || _lastSmoothedM == null)
      ? null
      : _lastSmoothedM! - _baselineM!;
  bool get isArmed => _armedNodes.isNotEmpty;

  /// 1차 감지가 서 있는지 — 수직 속도는 잡혔지만 아직 사용자에게 알리지 않은
  /// 상태. 진단용이다(왜 아직 탑승 단계로 안 넘어가는지 읽는다).
  bool get isVerticalMotionObserved => _verticalMotionObserved;
  bool get hasCandidate => _candidateStartMs != null;
  EscalatorTransition? get pendingTransition => _pendingTransition;

  EscalatorTransition? takeStartedTransition() {
    final transition = _startedTransition;
    _startedTransition = null;
    return transition;
  }

  EscalatorTransition? takeCancelledTransition() {
    final transition = _cancelledTransition;
    _cancelledTransition = null;
    return transition;
  }

  /// 지금 공개 단계.
  EscalatorPhase get phase => _phase;

  /// 기록된 단계 전이를 비우며 가져간다. UI는 이 순서대로 적용한다.
  List<EscalatorPhaseChange> takePhaseChanges() {
    final drained = List<EscalatorPhaseChange>.unmodifiable(_phaseChanges);
    _phaseChanges.clear();
    return drained;
  }

  /// 기록된 진단 이벤트를 비우며 가져간다.
  List<EscalatorDetectionEvent> takeEvents() {
    final drained = List<EscalatorDetectionEvent>.unmodifiable(_events);
    _events.clear();
    return drained;
  }

  /// 층·그래프·층 목록을 갱신한다.
  ///
  /// **설명되지 않는** 층 변경이면 baseline과 허가·후보를 전부 버린다. 사용자가
  /// 층 선택기로 다른 층을 고르거나 계단·엘리베이터로 옮긴 경우가 그렇다. 그런
  /// 이동은 고도 관계를 알 수 없으므로 이전 층 baseline을 들고 가면 다음 판정이
  /// 이미 기울어진 값에서 시작한다.
  ///
  /// 반대로 **이 판정기가 방금 확정한 이동**이면 아무것도 버리지 않는다.
  /// [_confirm]이 하차 시점 고도로 baseline을 이미 새로 잡았고, 기압 창은 층
  /// 라벨과 무관한 실제 관측 이력이라 버릴 이유가 없다. 예전에는 여기서
  /// 창까지 비워서 하차 직후 최소 [minSmoothingSamples]개를 다시 채울 때까지
  /// (iOS 약 3초) 판정이 아예 돌지 않았다 — 내리자마자 다음 에스컬레이터를 타는
  /// 연속 환승에서 두 번째 층이 그만큼 늦게 잡혔다.
  ///
  /// 탑승 중(`pendingTransition != null`)에는 호출자가 아예 이 함수를 부르지
  /// 않는다. 화면은 반 층에서 목적 층으로 먼저 넘어가지만 판정기는 탑승 층
  /// 기준을 하차까지 유지해야 하기 때문이다. 그 규칙이 깨지면 긴 에스컬레이터
  /// 중간에 baseline이 다시 잡혀 남은 반 층이 **또 하나의 층 이동**으로 보인다.
  void updateContext({
    required String? floorLabel,
    required FloorGraph? graph,
    required List<String> floorLabels,
  }) {
    _floorLabels = floorLabels;
    final floorChanged = floorLabel != _floorLabel;
    final graphChanged = !identical(graph, _graph);
    _floorLabel = floorLabel;
    if (graphChanged) {
      _graph = graph;
      _escalatorNodes = _parseEscalatorNodes(graph);
    }
    if (!floorChanged) return;
    if (floorLabel != null && floorLabel == _confirmedToFloorLabel) {
      _confirmedToFloorLabel = null;
      return;
    }
    _resetForNewFloor();
  }

  /// 보정된 현재 위치를 넣어 허가 상태를 갱신한다.
  ///
  /// [positionM]은 층 `local_m` 좌표(복도 보정 결과)여야 한다. 원시 PDR 좌표를
  /// 넣으면 노드 근접 판정이 앵커 오차만큼 어긋난다.
  void onPosition({
    required PdrLocalPoint positionM,
    required int steps,
    required int timestampMs,
  }) {
    _lastSteps = steps;
    if (_escalatorNodes.isEmpty) return;

    var armedNow = false;
    for (final node in _escalatorNodes) {
      if (node.name.role != EscalatorNodeRole.boarding) continue;
      final distance = math.sqrt(
        math.pow(positionM.eastM - node.xM, 2) +
            math.pow(positionM.northM - node.yM, 2),
      );
      if (distance > config.armRadiusM) continue;
      armedNow = true;
      final existing = _armedNodes[node.id];
      if (existing == null || distance < existing.distanceM) {
        _armedNodes[node.id] = _ArmedNode(
          nodeId: node.id,
          distanceM: distance,
          atMs: timestampMs,
        );
      }
      final observedDistance = _observedBoardingDistances[node.id];
      if (observedDistance == null || distance < observedDistance) {
        _observedBoardingDistances[node.id] = distance;
      }
    }
    if (armedNow) {
      final wasArmed = _armedUntilMs != null && timestampMs <= _armedUntilMs!;
      _armedUntilMs = timestampMs + config.armHoldMs;
      if (!wasArmed) {
        _pushEvent(
          atMs: timestampMs,
          kind: 'armed',
          reason: _armedNodes.keys.join(','),
        );
      }
    }
  }

  /// 활성 다층 경로의 마지막 점이 에스컬레이터 탑승점일 때 쓰는 보조 허가.
  ///
  /// [routeEndM] 자체가 실제 그래프 경로에서 나온 탑승점이라는 강한 근거가
  /// 있으므로, 현재 위치 보정이 조금 늦어도 사용자가 그 지점에 접근했다면
  /// 해당 뱅크를 허가한다. 경로가 없는 수동 이동에는 호출하지 않는다.
  void onEscalatorRouteApproach({
    required PdrLocalPoint positionM,
    required PdrLocalPoint routeEndM,
    required String expectedBoardingNodeId,
    String? expectedArrivalNodeId,
    required int steps,
    required int timestampMs,
    bool immediateTransfer = false,
  }) {
    final approachDistance = (positionM - routeEndM).distance;
    if (approachDistance > config.routeApproachArmRadiusM) {
      _resetApproach();
      return;
    }
    _lastSteps = steps;
    final expected = _escalatorNodes
        .where(
          (node) =>
              node.id == expectedBoardingNodeId &&
              node.name.role == EscalatorNodeRole.boarding,
        )
        .firstOrNull;
    if (expected == null) return;
    _expectedBoardingNodeId = expectedBoardingNodeId;
    _expectedArrivalNodeId = expectedArrivalNodeId;
    _approachBoarding = expected;
    _immediateTransfer = immediateTransfer;
    _armedNodes[expected.id] = _ArmedNode(
      nodeId: expected.id,
      distanceM: approachDistance,
      atMs: timestampMs,
    );
    _armedUntilMs = timestampMs + config.armHoldMs;
    _updateBoardingApproach(
      approachDistanceM: approachDistance,
      steps: steps,
      timestampMs: timestampMs,
      expectedArrivalNodeId: expectedArrivalNodeId,
      boarding: expected,
    );
  }

  /// 탑승점까지 남은 거리가 실제로 줄고 있을 때만 배너 단계로 올린다.
  ///
  /// 거리 하나로 판정하면 탑승점 옆을 지나가는 사람에게도 뜬다. 서로 다른
  /// 걸음 갱신에서 연속으로 줄어드는지를 함께 본다 — 그게 "탑승점 방향으로
  /// 가고 있다"는 근거다.
  void _updateBoardingApproach({
    required double approachDistanceM,
    required int steps,
    required int timestampMs,
    required String? expectedArrivalNodeId,
    required _EscalatorNode boarding,
  }) {
    if (_phase != EscalatorPhase.idle &&
        _phase != EscalatorPhase.boardingDetected) {
      return;
    }
    if (_lastApproachSteps != steps) {
      final previous = _lastApproachDistanceM;
      if (previous != null && approachDistanceM < previous - 0.2) {
        _approachDecreaseUpdates++;
      } else if (previous != null && approachDistanceM > previous + 0.5) {
        // 다시 멀어졌다. 근거를 처음부터 다시 모은다.
        _approachDecreaseUpdates = 0;
        if (_phase == EscalatorPhase.boardingDetected) {
          _setPhase(
            EscalatorPhase.cancelled,
            atMs: timestampMs,
            reason: 'movedAwayFromBoarding',
          );
        }
      }
      _lastApproachDistanceM = approachDistanceM;
      _lastApproachSteps = steps;
    }
    if (_phase == EscalatorPhase.boardingDetected) return;
    if (approachDistanceM > config.boardingApproachRadiusM) return;
    if (_approachDecreaseUpdates < config.boardingApproachUpdates) return;
    final toFloor = boarding.name.otherFloorLabel;
    if (_floorLabels.isNotEmpty && !_floorLabels.contains(toFloor)) return;
    _setPhase(
      EscalatorPhase.boardingDetected,
      atMs: timestampMs,
      reason: 'routeApproach',
      toFloorLabel: toFloor,
      group: boarding.name.group,
      direction: boarding.name.direction,
      boardingNodeId: boarding.id,
      expectedArrivalNodeId: expectedArrivalNodeId,
    );
  }

  void _resetApproach() {
    _lastApproachDistanceM = null;
    _lastApproachSteps = null;
    _approachDecreaseUpdates = 0;
    _approachBoarding = null;
    _immediateTransfer = false;
  }

  void _setPhase(
    EscalatorPhase phase, {
    required int atMs,
    required String reason,
    String? toFloorLabel,
    String? group,
    EscalatorDirection? direction,
    String? boardingNodeId,
    String? expectedArrivalNodeId,
    double deltaM = 0,
    EscalatorTransition? transition,
  }) {
    if (_phase == phase) return;
    _phase = phase;
    _phaseEnteredAtMs = atMs;
    if (phase == EscalatorPhase.cancelled ||
        phase == EscalatorPhase.failed ||
        phase == EscalatorPhase.landed) {
      _resetApproach();
      _verticalMotionSinceMs = null;
      _verticalMotionSign = 0;
      _verticalMotionObserved = false;
      _fastDisplacementM = 0;
      _earlyVerticalMotion = false;
      _verticalMotionQuietSinceMs = null;
      _phase = EscalatorPhase.idle;
    }
    _phaseChanges.add(
      EscalatorPhaseChange(
        phase: phase,
        atMs: atMs,
        fromFloorLabel: _floorLabel ?? '',
        reason: reason,
        toFloorLabel: toFloorLabel,
        group: group,
        direction: direction,
        boardingNodeId: boardingNodeId,
        expectedArrivalNodeId: expectedArrivalNodeId,
        deltaM: deltaM,
        transition: transition,
      ),
    );
  }

  /// 위치에 반영되지 않은 원시 움직임을 넣는다.
  ///
  /// 탑승 중 걸음 적용을 멈추면 [onPosition]의 `steps`가 늘지 않아 하차 빠른
  /// 확정 경로가 동작하지 않는다. 이 신호는 pause와 무관하게 흐르므로 "하차
  /// 뒤 첫 걸음"을 한 샘플 만에 잡을 수 있다. **수직 속도가 충분히 낮을 때만**
  /// 보조 근거로 쓰이므로 에스컬레이터 진동 peak로는 재개되지 않는다.
  void onRawMotion(RawMotionActivity activity) {
    if (!activity.hasMotion) return;
    _rawMotionCount +=
        activity.accelPeakDelta + (activity.nativeStepDelta ?? 0);
    _rawStepCount += activity.nativeStepDelta ?? 0;
  }

  /// 기압 샘플을 넣고 판정한다. 층 이동이 확정된 순간에만 non-null.
  EscalatorTransition? onAltitude(AltitudeSample sample) {
    final previousFastAltitude = _fastAltitudeM;
    final previousFastAtMs = _lastFastAltitudeAtMs;
    // "하차 후 첫 걸음"은 위치에 적용된 걸음 **또는 네이티브 걸음**만 인정한다.
    // 발판 진동(accel peak)은 여기서 빠진다 — 에스컬레이터 위에서는 진동이
    // 항상 흐르므로, 진동을 걸음으로 치면 순간 저속 한 번(센서 격자·EMA 눌림)에
    // 유지 시간 없이 그 자리에서 확정된다. 실제로 그렇게 탑승 중간에 확정이
    // 났다(2026-08-13 Samsung 실측: 확정 Δ3.83m vs 실제 층고 5.9m).
    final hadNewSteps =
        _lastSteps > _lastAltitudeSteps ||
        _rawStepCount > _lastAltitudeRawStepCount;
    // 진동까지 포함한 "기기가 실제로 움직이는 중" 근거. 걸음 pause 갈래에서만
    // 쓴다 — 그쪽은 책상 위 기압 드리프트를 거르는 용도라 진동도 근거가 된다.
    final hadMotionEvidence =
        hadNewSteps || _rawMotionCount > _lastAltitudeRawMotionCount;
    _lastAltitudeSteps = _lastSteps;
    _lastAltitudeRawMotionCount = _rawMotionCount;
    _lastAltitudeRawStepCount = _rawStepCount;

    // 1) 시계열이 끊겼으면(background 복귀 등) 이전 관측을 통째로 버린다.
    //    공백 동안 층이 바뀌었을 수 있어 baseline과 후보도 함께 무효다.
    final previous = _window.isEmpty ? null : _window.last;
    final timelineGap =
        previous != null &&
        sample.timestampMs - previous.timestampMs > config.maxSampleAgeMs;
    if (timelineGap) {
      _window.clear();
      _smoothedHistory.clear();
      _baselineM = null;
      _lastSmoothedM = null;
      _candidateStartMs = null;
      _candidateSign = 0;
      _candidateBoarding = null;
      _candidateToFloor = null;
      _pendingTransition = null;
      _fastAltitudeM = null;
      _lastFastAltitudeAtMs = null;
      _fastHistory.clear();
      _fastExitQuietSinceMs = null;
      _awaitingPostConfirmQuiet = false;
      _postConfirmQuietSinceMs = null;
    }

    final rawAltitude = sample.altitudeM;
    // EMA 계수를 **경과 시간에서 만든다.** 샘플당 고정 계수를 쓰면 같은 숫자가
    // iOS(1069ms)에서는 시정수 1초, Android(180ms)에서는 0.2초짜리 필터가 된다.
    final fastDeltaSeconds = timelineGap || previousFastAtMs == null
        ? null
        : (sample.timestampMs - previousFastAtMs) / 1000.0;
    final alpha = fastDeltaSeconds == null || fastDeltaSeconds <= 0
        ? 1.0
        : 1 - math.exp(-fastDeltaSeconds * 1000 / config.fastAltitudeTauMs);
    _fastAltitudeM = _fastAltitudeM == null
        ? rawAltitude
        : _fastAltitudeM! + alpha * (rawAltitude - _fastAltitudeM!);
    _lastFastAltitudeAtMs = sample.timestampMs;
    // 이 샘플에서 실제로 움직인 양. 적분(_fastDisplacementM)은 이 값을 그대로
    // 더해 망원합이 되므로, 아래 속도가 어떤 밑변으로 재지든 영향받지 않는다.
    final fastStepM = previousFastAltitude == null || fastDeltaSeconds == null
        ? 0.0
        : _fastAltitudeM! - previousFastAltitude;
    _fastHistory.add(_Smoothed(sample.timestampMs, _fastAltitudeM!));
    final fastSpeedMps = _fastSpeedOver(sample.timestampMs);

    _window.add(sample);
    // 2) 시간 창으로 자르되 최근 minSmoothingSamples개는 항상 남긴다. 센서
    //    주기가 창 대비 크면(iOS 1069ms) 창만으로는 개수를 못 채운다.
    final windowStart = sample.timestampMs - config.smoothingWindowMs;
    while (_window.length > config.minSmoothingSamples &&
        _window.first.timestampMs < windowStart) {
      _window.removeAt(0);
    }
    if (_window.length < config.minSmoothingSamples) {
      // 아직 평활할 근거가 없다. 디버그 표시가 지난 값을 "지금 관측"으로
      // 보이지 않도록 비워 둔다.
      _lastSmoothedM = null;
      return null;
    }

    final smoothed = _median(
      _window.map((item) => item.altitudeM).toList(growable: false),
    );
    _lastSmoothedM = smoothed;
    _smoothedHistory.add(_Smoothed(sample.timestampMs, smoothed));
    // 안정 판단은 settleWindow만 보면 되지만, 타임아웃 구간까지 넉넉히 남긴다.
    final historyStart =
        sample.timestampMs - config.candidateTimeoutMs - config.settleWindowMs;
    _smoothedHistory.removeWhere((item) => item.atMs < historyStart);

    _baselineM ??= smoothed;
    final armed = _armedUntilMs != null && sample.timestampMs <= _armedUntilMs!;
    if (!armed) {
      _armedNodes.clear();
      _observedBoardingDistances.clear();
    }
    final delta = smoothed - _baselineM!;

    if (_candidateStartMs == null && _awaitingPostConfirmQuiet) {
      // 확정 직후 잠금 구간 — 하차가 실제로 끝났는지부터 본다. 확정이 하차보다
      // 일렀다면 지금도 오르내리는 중이고, 그 잔여 이동분으로 후보를 열면 한
      // 층이 두 층이 된다. 저속이 이어져 "멎었다"가 확인되는 순간, 그 자리
      // 고도로 0점을 다시 잡아 잔여분을 통째로 흡수한다.
      final quietNow =
          fastSpeedMps != null &&
          fastSpeedMps.abs() < config.minVerticalSpeedMps;
      if (quietNow) {
        final since = _postConfirmQuietSinceMs ??= sample.timestampMs;
        if (sample.timestampMs - since >= config.earlyVerticalQuietMs) {
          _baselineM = smoothed;
          _awaitingPostConfirmQuiet = false;
          _postConfirmQuietSinceMs = null;
        }
      } else {
        _postConfirmQuietSinceMs = null;
      }
      return null;
    }

    if (_candidateStartMs == null) {
      // 허가도 후보도 없는 구간에서만 baseline이 기상 드리프트를 따라간다.
      if (!armed) {
        // **지금 실제로 오르내리는 중이면 따라가지 않는다.** 허가는 보정 위치가
        // 탑승 노드에 닿아야 걸리는데, 그 위치가 늦게 수렴하면(하행 랜딩에서
        // 실측 12m 오차가 있었다) 허가 전 구간의 고도 변화가 baseline에 그대로
        // 흡수된다. 그러면 허가가 걸린 순간 Δ가 0으로 초기화된 것과 같아, 이미
        // 반쯤 내려온 사용자가 처음부터 다시 [minDeltaM]을 채워야 한다.
        // 정지 상태의 기상 드리프트는 이 조건에 걸리지 않으므로(0.01 m/s)
        // 흡수는 그대로 유지된다.
        final movingVertically =
            fastSpeedMps != null &&
            fastSpeedMps.abs() >= config.minVerticalSpeedMps;
        if (!movingVertically) {
          _baselineM = _baselineM! + config.baselineTrackAlpha * delta;
        }
        // **허가가 없어도 걸음은 멈춘다.** 노드 근접이 안 잡히는 랜딩이 실측에서
        // 흔했고, 그때 사용자는 이미 에스컬레이터 위인데 마커만 계속 걸어갔다.
        _updateVerticalMotion(
          sample.timestampMs,
          fastSpeedMps,
          fastStepM: fastStepM,
          deltaM: delta,
          hasMotionEvidence: hadMotionEvidence,
        );
        _expireStalledPhase(sample.timestampMs, reason: 'armExpired');
        return null;
      }
      // 누적 고도가 아직 문턱에 못 미쳐도, **지금 오르내리는 중**이라는 근거는
      // 이미 있다. 걸음 pause는 여기서 시작한다 — 에스컬레이터 진동이 위치에
      // 쌓이는 것을 막는 데 반 층을 기다릴 이유가 없다.
      _updateVerticalMotion(
        sample.timestampMs,
        fastSpeedMps,
        fastStepM: fastStepM,
        deltaM: delta,
        hasMotionEvidence: hadMotionEvidence,
      );
      _expireStalledPhase(sample.timestampMs, reason: 'noVerticalMotion');
      if (delta.abs() < config.minDeltaM) return null;
      // 누적 변화량 + 지금도 그 방향으로 움직이는 중일 때만 후보를 연다.
      final rise = _riseOver(sample.timestampMs, smoothed);
      if (rise == null) return null;
      final sign = delta > 0 ? 1 : -1;
      if (rise * sign < config.minRampRiseM) return null;
      if (!_hasConsistentRamp(sample.timestampMs, sign)) return null;
      _candidateStartMs = sample.timestampMs;
      _candidateSign = sign;
      _candidateStartSteps = _lastSteps;
      _fastExitQuietSinceMs = null;
      _pushEvent(
        atMs: sample.timestampMs,
        kind: 'candidate',
        reason: _candidateSign > 0 ? 'rising' : 'falling',
        deltaM: delta,
      );

      final direction = sign > 0
          ? EscalatorDirection.up
          : EscalatorDirection.down;
      final boarding = _pickBoardingNode(direction);
      final fromFloor = _floorLabel;
      if (fromFloor == null || boarding == null) {
        _closeCandidate(
          atMs: sample.timestampMs,
          reason: 'noBoardingNode',
          deltaM: delta,
          elapsedMs: 0,
        );
        return null;
      }
      final toFloor = boarding.name.otherFloorLabel;
      if (_floorLabels.isNotEmpty && !_floorLabels.contains(toFloor)) {
        _closeCandidate(
          atMs: sample.timestampMs,
          reason: 'unknownTargetFloor',
          deltaM: delta,
          elapsedMs: 0,
          toFloorLabel: toFloor,
          group: boarding.name.group,
        );
        return null;
      }
      _candidateBoarding = boarding;
      _candidateToFloor = toFloor;
      // 후보는 여기서 열리지만 조기 층 전환(도면 교체) 신호는 아직 내지 않는다.
      // 그 신호는 아래 후보 유지 구간에서 [mapSwapDeltaM]에 닿을 때 나간다.
      return null;
    }

    final candidateStartMs = _candidateStartMs!;
    final elapsedMs = sample.timestampMs - candidateStartMs;

    // 부호가 뒤집혔거나 baseline 근처로 돌아왔다 = 층을 옮긴 게 아니다.
    if (delta * _candidateSign < config.minDeltaM * 0.5) {
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'reverted',
        deltaM: delta,
        elapsedMs: elapsedMs,
      );
      return null;
    }

    if (delta.abs() >= config.multiFloorRejectM) {
      // 여러 층을 한 번에 이동했다. 몇 층인지 추정하려면 층고 가정이 필요하고,
      // 그 가정이 틀리면 2층 어긋난 위치를 조용히 보여준다. 거부가 안전하다.
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'multiFloorUnsupported',
        deltaM: delta,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
      );
      return null;
    }

    if (elapsedMs > config.candidateTimeoutMs) {
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'noSettle',
        deltaM: delta,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
      );
      return null;
    }

    // 반 층 부근에서 조기 층 전환 신호(도면 교체)를 낸다. 후보 열림과 분리한
    // 근거는 [EscalatorDetectorConfig.mapSwapDeltaM]에 적었다.
    if (_pendingTransition == null &&
        delta.abs() >= config.mapSwapDeltaM &&
        delta * _candidateSign > 0) {
      final boarding = _candidateBoarding;
      final fromFloor = _floorLabel;
      final toFloor = _candidateToFloor;
      if (boarding != null && fromFloor != null && toFloor != null) {
        final direction = _candidateSign > 0
            ? EscalatorDirection.up
            : EscalatorDirection.down;
        final started = _buildTransition(
          boarding: boarding,
          direction: direction,
          fromFloor: fromFloor,
          toFloor: toFloor,
          deltaM: delta,
          elapsedMs: elapsedMs,
        );
        _pendingTransition = started;
        _startedTransition = started;
        _setPhase(
          EscalatorPhase.midpointReached,
          atMs: sample.timestampMs,
          reason: _candidateSign > 0 ? 'rising' : 'falling',
          toFloorLabel: toFloor,
          group: boarding.name.group,
          direction: direction,
          boardingNodeId: boarding.id,
          expectedArrivalNodeId: started.expectedArrivalNodeId,
          deltaM: delta,
          transition: started,
        );
      }
    }

    if (elapsedMs < config.minRampMs) return null;
    if (delta.abs() < config.minConfirmDeltaM) return null;

    // 중앙값 settle 창보다 먼저, 저지연 EMA의 수직 속도가 잦아드는 순간을
    // 잡는다. 하차 뒤 첫 걸음이 함께 들어오면 그 즉시, 걸음이 없으면
    // [fastExitQuietMs] 동안 저속이 유지될 때 확정한다. 에스컬레이터 위에서
    // 걷는 동안에는 수직 속도가 계속 커서 걸음만으로 확정되지 않는다.
    //
    // **속도 자체가 이미 시간 밑변 위에서 재진 값이다**([_fastSpeedOver]).
    // 그래서 이 아래의 유지 시간과 밑변이 함께 "얼마나 오래 잠잠했는가"를
    // 정한다 — 어느 쪽도 센서 주기에 기대지 않는다.
    if (fastSpeedMps != null) {
      final slopeLimit = hadNewSteps
          ? config.fastExitWithStepSlopeMps
          : config.fastExitSlopeMps;
      if (fastSpeedMps.abs() <= slopeLimit) {
        _fastExitQuietSinceMs ??= sample.timestampMs;
      } else {
        _fastExitQuietSinceMs = null;
      }
      final quietSince = _fastExitQuietSinceMs;
      final fastSettled =
          quietSince != null &&
          (hadNewSteps ||
              sample.timestampMs - quietSince >= config.fastExitQuietMs);
      if (fastSettled) {
        return _confirm(
          atMs: sample.timestampMs,
          smoothed: smoothed,
          deltaM: delta,
          elapsedMs: elapsedMs,
        );
      }
    }

    // fast EMA가 준비된 뒤에는 중앙값 창의 꼭대기를 정지로 오인하지 않는다.
    // 실제 하차는 저속 샘플이 연속되지만, 올라갔다 바로 내려오는 삼각형
    // 움직임은 방향 전환 지점의 한 샘플만 평평해질 수 있다.
    if (fastSpeedMps == null && _hasSettled(sample.timestampMs, smoothed)) {
      return _confirm(
        atMs: sample.timestampMs,
        smoothed: smoothed,
        deltaM: delta,
        elapsedMs: elapsedMs,
      );
    }
    return null;
  }

  // ── 내부 ──

  EscalatorTransition? _confirm({
    required int atMs,
    required double smoothed,
    required double deltaM,
    required int elapsedMs,
  }) {
    final direction = _candidateSign > 0
        ? EscalatorDirection.up
        : EscalatorDirection.down;
    final fromFloor = _floorLabel;
    final boarding = _candidateBoarding;

    if (fromFloor == null || boarding == null || _candidateToFloor == null) {
      // 기압은 층 이동이라 말하는데 그 방향의 탑승 노드가 허가된 그룹에 없다.
      // 반대 방향 에스컬레이터 옆을 지나간 경우이거나 이름 규칙이 없는 데이터다.
      _closeCandidate(
        atMs: atMs,
        reason: 'noBoardingNode',
        deltaM: deltaM,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
      );
      return null;
    }

    final toFloor = _candidateToFloor!;
    if (_floorLabels.isNotEmpty && !_floorLabels.contains(toFloor)) {
      // 이름이 가리키는 층이 건물 층 목록에 없다 = 데이터가 어긋났다.
      _closeCandidate(
        atMs: atMs,
        reason: 'unknownTargetFloor',
        deltaM: deltaM,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
        toFloorLabel: toFloor,
        group: boarding.name.group,
      );
      return null;
    }

    final stepsDuring = _lastSteps - _candidateStartSteps;
    _pushEvent(
      atMs: atMs,
      kind: 'confirmed',
      reason: direction == EscalatorDirection.up ? 'up' : 'down',
      deltaM: deltaM,
      toFloorLabel: toFloor,
      group: boarding.name.group,
      durationMs: elapsedMs,
      stepsDuring: stepsDuring,
      boardingEvidence: _boardingEvidence,
    );

    final transition = _buildTransition(
      boarding: boarding,
      direction: direction,
      fromFloor: fromFloor,
      toFloor: toFloor,
      deltaM: deltaM,
      elapsedMs: elapsedMs,
      stepsDuring: stepsDuring,
    );

    // 확정했으면 새 층 기준으로 처음부터 다시 본다. **상대 고도 0점을 다시
    // 잡는 곳은 여기 하나뿐이다** — 하차가 확정된 순간이고, 그 값은 지금
    // 서 있는 층의 고도다. 이후 호출자가 updateContext로 이 층을 알려 와도
    // 초기화가 한 번 더 돌지 않도록 목적 층을 표식으로 남긴다.
    _confirmedToFloorLabel = toFloor;
    _candidateStartMs = null;
    _candidateSign = 0;
    _candidateBoarding = null;
    _candidateToFloor = null;
    _pendingTransition = null;
    _fastExitQuietSinceMs = null;
    _baselineM = smoothed;
    // 확정이 하차보다 일렀을 수 있다. 수직 이동이 실제로 멎을 때까지 새 후보를
    // 잠그고, 멎는 순간 잔여 이동분을 baseline에 흡수한다(필드 근거는 선언부).
    _awaitingPostConfirmQuiet = true;
    _postConfirmQuietSinceMs = null;
    _armedNodes.clear();
    _observedBoardingDistances.clear();
    _armedUntilMs = null;
    _setPhase(
      EscalatorPhase.landed,
      atMs: atMs,
      reason: direction == EscalatorDirection.up ? 'up' : 'down',
      toFloorLabel: toFloor,
      group: boarding.name.group,
      direction: direction,
      boardingNodeId: boarding.id,
      expectedArrivalNodeId: transition.expectedArrivalNodeId,
      deltaM: deltaM,
      transition: transition,
    );
    return transition;
  }

  /// 지금 실제로 오르내리는 중인지 갱신한다. **두 겹**이다.
  ///
  /// 1차는 조용하다 — 수직 속도가 같은 부호로 이어지면 [isVerticalMotionObserved]
  /// 만 세우고 끝난다(단일 기압 튐 배제를 위해 연속 관측을 요구한다). 화면도
  /// 걸음도 그대로다.
  ///
  /// 2차에서 비로소 `verticalMotionDetected`를 낸다 — 걸음이 멈추고, 마커가
  /// 서고, 화면이 덮인다. 올라가는 길은 탑승점 3m 근접이거나, 누적 고도
  /// [EscalatorDetectorConfig.visibleVerticalDeltaM] 초과다. 어느 쪽이든 층은
  /// 바꾸지 않는다.
  void _updateVerticalMotion(
    int atMs,
    double? fastSpeedMps, {
    required double fastStepM,
    required double deltaM,
    required bool hasMotionEvidence,
  }) {
    if (fastSpeedMps == null ||
        fastSpeedMps.abs() < config.minVerticalSpeedMps) {
      _verticalMotionSinceMs = null;
      _verticalMotionSign = 0;
      _verticalMotionObserved = false;
      _fastDisplacementM = 0;
      _expireEarlyVerticalMotion(atMs);
      return;
    }
    _verticalMotionQuietSinceMs = null;
    final sign = fastSpeedMps > 0 ? 1 : -1;
    if (sign != _verticalMotionSign) {
      _verticalMotionSign = sign;
      _verticalMotionSinceMs = atMs;
      _fastDisplacementM = fastStepM;
    } else {
      _fastDisplacementM += fastStepM;
    }
    final since = _verticalMotionSinceMs;
    if (since == null || atMs - since < config.verticalMotionMinMs) {
      return;
    }
    final direction = sign > 0
        ? EscalatorDirection.up
        : EscalatorDirection.down;
    // 여기까지가 **1차 감지**다. 화면에는 아무것도 알리지 않고, 걸음도 그대로
    // 흐른다. 아래 두 갈래 중 하나가 성립해야 2차로 올라간다.
    _verticalMotionObserved = true;
    // 중앙값 delta와 빠른 EMA 적분 중 **먼저 문턱을 넘는 쪽**을 쓴다. 둘은 같은
    // 것을 재지만 중앙값이 1초 넘게 늦고, 그 1초가 곧 발판 진동이 위치에 쌓이는
    // 시간이다.
    final risenM = math.max(deltaM.abs(), _fastDisplacementM.abs());

    final boarding = _approachBoarding ?? _pickBoardingNode(direction);
    if (boarding != null && boarding.name.direction == direction) {
      // 갈래 1 — **탑승점이 정해져 있다.** 안내가 이 에스컬레이터를 타라고
      // 지목했거나([_approachBoarding], 경로 접근 16m 안) 실제로 발판에
      // 올라섰다고 볼 거리([boardingApproachRadiusM], 3m)까지 붙었을 때다.
      //
      // 그래도 **속도만으로는 올리지 않는다** — 얼마나 움직였는지를 함께 본다
      // ([minVisibleRiseM], 그 상수에 근거가 있다).
      final distanceM =
          _observedBoardingDistances[boarding.id] ??
          _armedNodes[boarding.id]?.distanceM;
      final atBoardingPoint =
          _approachBoarding != null ||
          (distanceM != null && distanceM <= config.boardingApproachRadiusM);
      // 연속 환승(내리자마자 바로 다음 에스컬레이터)에서는 최소 변화를 요구하지
      // 않는다. 걸어갈 거리가 없어 오탐 여지도 없고, 기다리면 환승마다 마커가
      // 먼저 몇 걸음 흘러간다.
      final requiredRiseM = _immediateTransfer && _approachBoarding != null
          ? 0.0
          : config.minVisibleRiseM;
      if (atBoardingPoint && risenM >= requiredRiseM) {
        _earlyVerticalMotion = false;
        _setPhase(
          EscalatorPhase.verticalMotionDetected,
          atMs: atMs,
          reason: sign > 0 ? 'rising' : 'falling',
          toFloorLabel: boarding.name.otherFloorLabel,
          group: boarding.name.group,
          direction: direction,
          boardingNodeId: boarding.id,
          expectedArrivalNodeId: boarding.id == _expectedBoardingNodeId
              ? _expectedArrivalNodeId
              : null,
        );
        return;
      }
    }

    // 갈래 2 — **이미 사람이 오를 수 없는 만큼 올라왔다.** 노드가 없거나 아직
    // 멀어도, 누적 고도가 [visibleVerticalDeltaM]을 넘었으면 에스컬레이터 위인
    // 것이 분명하다(층고의 3분의 1쯤이라 계단 몇 칸으로는 안 나온다). 이 갈래가
    // 없으면 랜딩에서 보정 위치가 어긋난 실측 사례에서 마커가 끝까지 걸어간다.
    //
    // 기기가 실제로 움직이는 중이라는 신호를 함께 요구한다. 없으면 책상 위에 둔
    // 폰의 기압 드리프트로도 화면이 덮인다.
    if (risenM < config.visibleVerticalDeltaM) return;
    if (!hasMotionEvidence) return;
    final toFloor = (boarding != null && boarding.name.direction == direction)
        ? boarding.name.otherFloorLabel
        : _adjacentFloorLabel(direction);
    if (toFloor == null) return;
    // 노드를 못 고른 경우에는 하차를 확정할 수단이 없다 — 수직 이동이 멎으면
    // 스스로 접어야 한다([_expireEarlyVerticalMotion]).
    _earlyVerticalMotion = boarding == null;
    _verticalMotionQuietSinceMs = null;
    _setPhase(
      EscalatorPhase.verticalMotionDetected,
      atMs: atMs,
      reason: sign > 0 ? 'risingByAltitude' : 'fallingByAltitude',
      toFloorLabel: toFloor,
      group: boarding?.name.group,
      direction: direction,
      boardingNodeId: boarding?.id,
      deltaM: deltaM,
    );
  }

  /// 노드 없이 열린 단계를 수직 이동이 멎으면 접는다.
  ///
  /// 이 단계는 하차를 확정할 수단이 없다(도착 노드를 모른다). 그대로 두면
  /// [boardingPhaseTimeoutMs] 40초 동안 걸음이 멈춘 채 화면이 덮여 있다 —
  /// 내려서 걷기 시작한 사용자에게 그 40초는 앱이 죽은 것과 같다.
  void _expireEarlyVerticalMotion(int atMs) {
    if (!_earlyVerticalMotion) return;
    if (_phase != EscalatorPhase.verticalMotionDetected) return;
    final quietSince = _verticalMotionQuietSinceMs ??= atMs;
    if (atMs - quietSince < config.earlyVerticalQuietMs) return;
    _earlyVerticalMotion = false;
    _verticalMotionQuietSinceMs = null;
    _setPhase(
      EscalatorPhase.cancelled,
      atMs: atMs,
      reason: 'verticalMotionEnded',
    );
  }

  /// [direction] 쪽으로 한 칸 붙어 있는 층 라벨. 알 수 없으면 null.
  ///
  /// 노드를 못 골랐을 때 화면에 적을 도착 층을 여기서 만든다. 층 목록의 나열
  /// 순서에 기대지 않고 라벨 자체를 순위로 읽는다 — 서버 응답 순서는 위아래를
  /// 약속하지 않는다.
  String? _adjacentFloorLabel(EscalatorDirection direction) {
    final from = _floorLabel;
    if (from == null || _floorLabels.isEmpty) return null;
    final fromRank = floorLabelRank(from);
    if (fromRank == 0) return null;
    final step = direction == EscalatorDirection.up ? 1 : -1;
    // 지상 1층과 지하 1층 사이에는 0층이 없다.
    final targetRank = fromRank + step == 0
        ? fromRank + step * 2
        : fromRank + step;
    for (final label in _floorLabels) {
      if (floorLabelRank(label) == targetRank) return label;
    }
    return null;
  }

  /// 배너·pause 단계가 근거 없이 오래 머물면 되돌린다.
  ///
  /// 이 경로가 없으면 탑승점에 다가갔다가 그냥 지나친 사용자에게 배너가 영영
  /// 남고, `verticalMotionDetected`로 멈춘 걸음이 다시 켜지지 않는다.
  void _expireStalledPhase(int atMs, {required String reason}) {
    if (_phase != EscalatorPhase.boardingDetected &&
        _phase != EscalatorPhase.verticalMotionDetected) {
      return;
    }
    final since = _phaseEnteredAtMs;
    if (since == null || atMs - since < config.boardingPhaseTimeoutMs) return;
    _setPhase(EscalatorPhase.cancelled, atMs: atMs, reason: reason);
  }

  EscalatorTransition _buildTransition({
    required _EscalatorNode boarding,
    required EscalatorDirection direction,
    required String fromFloor,
    required String toFloor,
    required double deltaM,
    required int elapsedMs,
    int stepsDuring = 0,
  }) => EscalatorTransition(
    group: boarding.name.group,
    direction: direction,
    fromFloorLabel: fromFloor,
    toFloorLabel: toFloor,
    deltaM: deltaM,
    durationMs: elapsedMs,
    stepsDuring: stepsDuring,
    boardingNodeId: boarding.id,
    boardingNodeName: boarding.rawName,
    boardingDistanceM: _armedNodes[boarding.id]?.distanceM ?? double.nan,
    boardingEvidence: _boardingEvidence,
    expectedArrivalNodeId: boarding.id == _expectedBoardingNodeId
        ? _expectedArrivalNodeId
        : null,
  );

  /// 허가된 탑승 노드 중 방향이 맞는 가장 가까운 노드를 고른다. 활성 경로의
  /// 정확한 id가 있으면 그것을 우선한다. 경로가 없으면 같은 방향 후보 중
  /// 가장 가까운 것을 쓴다. 기압 방향으로 상·하행을 먼저 거르므로 붙어 있는
  /// 반대 방향 레인을 선택하지 않는다.
  _EscalatorNode? _pickBoardingNode(EscalatorDirection direction) {
    _boardingEvidence = 'observed';
    final candidates = <(_EscalatorNode, double)>[];
    for (final armed in _armedNodes.values) {
      final node = _escalatorNodes
          .where((candidate) => candidate.id == armed.nodeId)
          .firstOrNull;
      if (node == null || node.name.direction != direction) continue;
      candidates.add((node, armed.distanceM));
    }
    final expected = candidates
        .where((candidate) => candidate.$1.id == _expectedBoardingNodeId)
        .firstOrNull;
    if (expected != null) {
      _boardingEvidence = _observedBoardingDistances.containsKey(expected.$1.id)
          ? 'routeAndObserved'
          : 'routeExpected';
      return expected.$1;
    }

    final observedCandidates = candidates
        .where(
          (candidate) =>
              _observedBoardingDistances.containsKey(candidate.$1.id),
        )
        .map(
          (candidate) =>
              (candidate.$1, _observedBoardingDistances[candidate.$1.id]!),
        )
        .toList();
    observedCandidates.sort((a, b) => a.$2.compareTo(b.$2));
    if (observedCandidates.isNotEmpty) return observedCandidates.first.$1;
    return null;
  }

  /// 빠른 EMA의 수직 속도(m/s).
  ///
  /// 직전 샘플이 아니라 [EscalatorDetectorConfig.fastSlopeBaseMs] **이상 떨어진**
  /// 가장 최근 값과 비교한다. 밑변을 시간으로 고정해야 같은 움직임이 기기마다
  /// 같은 속도로 읽힌다. 그만큼의 이력이 아직 없으면 null — "안 움직였다"와
  /// "아직 못 잰다"를 섞으면 세션 시작 직후가 곧바로 하차로 읽힌다.
  double? _fastSpeedOver(int atMs) {
    if (_fastHistory.length < 2) return null;
    final baseLimit = atMs - config.fastSlopeBaseMs;
    // 밑변보다 오래된 값은 하나만 남기면 된다(그 하나가 기준점이다).
    while (_fastHistory.length > 2 && _fastHistory[1].atMs <= baseLimit) {
      _fastHistory.removeAt(0);
    }
    final reference = _fastHistory.first;
    if (reference.atMs > baseLimit) return null;
    final seconds = (atMs - reference.atMs) / 1000.0;
    if (seconds <= 0) return null;
    return (_fastHistory.last.value - reference.value) / seconds;
  }

  bool _hasSettled(int atMs, double smoothed) {
    final rise = _riseOver(atMs, smoothed);
    if (rise == null) return false;
    return rise.abs() <= config.settleSlopeM;
  }

  /// 최근 [EscalatorDetectorConfig.settleWindowMs] 동안의 평활 고도 변화량.
  ///
  /// 창을 채울 이력이 없으면 null — "안 움직였다"와 "아직 모른다"를 섞으면
  /// 세션 시작 직후 첫 샘플들이 곧바로 확정으로 넘어간다.
  double? _riseOver(int atMs, double smoothed) {
    final windowStart = atMs - config.settleWindowMs;
    _Smoothed? reference;
    for (final item in _smoothedHistory) {
      if (item.atMs <= windowStart) {
        reference = item;
      } else {
        break;
      }
    }
    if (reference == null) return null;
    return smoothed - reference.value;
  }

  /// 창 안의 평활 이력을 [EscalatorDetectorConfig.directionalStrideMs] 이상
  /// 떨어진 구간으로 잘라, 같은 방향 구간이 충분히 이어졌는지 본다.
  ///
  /// 샘플 쌍이 아니라 구간으로 세는 이유는 [minDirectionalSampleDeltaM]에 적었다 —
  /// 밑변이 센서 주기면 같은 4cm가 기기마다 다른 속도를 뜻하게 된다.
  bool _hasConsistentRamp(int atMs, int sign) {
    final windowStart = atMs - config.rampConsistencyWindowMs;
    _Smoothed? strideStart;
    var directionalStrides = 0;
    var opposingStrides = 0;
    int? firstAtMs;
    int? lastAtMs;
    for (final item in _smoothedHistory) {
      if (item.atMs < windowStart) continue;
      firstAtMs ??= item.atMs;
      lastAtMs = item.atMs;
      final before = strideStart;
      if (before == null) {
        strideStart = item;
        continue;
      }
      if (item.atMs - before.atMs < config.directionalStrideMs) continue;
      strideStart = item;
      final directionalDelta = (item.value - before.value) * sign;
      if (directionalDelta >= config.minDirectionalSampleDeltaM) {
        directionalStrides++;
      } else if (directionalDelta <= -config.minDirectionalSampleDeltaM) {
        opposingStrides++;
      }
    }
    final durationMs = firstAtMs == null || lastAtMs == null
        ? 0
        : lastAtMs - firstAtMs;
    return durationMs >= config.settleWindowMs &&
        directionalStrides >= config.minDirectionalRampStrides &&
        opposingStrides == 0;
  }

  void _closeCandidate({
    required int atMs,
    required String reason,
    required double deltaM,
    required int elapsedMs,
    double? rebaselineTo,
    String? toFloorLabel,
    String? group,
  }) {
    if (_pendingTransition != null) {
      _cancelledTransition = _pendingTransition;
    }
    _setPhase(
      EscalatorPhase.cancelled,
      atMs: atMs,
      reason: reason,
      toFloorLabel: toFloorLabel,
      group: group,
      deltaM: deltaM,
      transition: _pendingTransition,
    );
    _candidateStartMs = null;
    _candidateSign = 0;
    _candidateBoarding = null;
    _candidateToFloor = null;
    _pendingTransition = null;
    _fastExitQuietSinceMs = null;
    if (rebaselineTo != null) {
      _baselineM = rebaselineTo;
    }
    _pushEvent(
      atMs: atMs,
      kind: 'rejected',
      reason: reason,
      deltaM: deltaM,
      toFloorLabel: toFloorLabel,
      group: group,
      durationMs: elapsedMs,
      stepsDuring: _lastSteps - _candidateStartSteps,
    );
  }

  void _resetForNewFloor() {
    _confirmedToFloorLabel = null;
    _window.clear();
    _smoothedHistory.clear();
    _baselineM = null;
    _lastSmoothedM = null;
    _armedNodes.clear();
    _observedBoardingDistances.clear();
    _expectedBoardingNodeId = null;
    _expectedArrivalNodeId = null;
    _armedUntilMs = null;
    _candidateStartMs = null;
    _candidateSign = 0;
    _candidateBoarding = null;
    _candidateToFloor = null;
    _pendingTransition = null;
    _startedTransition = null;
    _cancelledTransition = null;
    _fastAltitudeM = null;
    _lastFastAltitudeAtMs = null;
    _fastExitQuietSinceMs = null;
    _lastAltitudeSteps = _lastSteps;
    _lastAltitudeRawMotionCount = _rawMotionCount;
    _lastAltitudeRawStepCount = _rawStepCount;
    _awaitingPostConfirmQuiet = false;
    _postConfirmQuietSinceMs = null;
    // 층이 바뀌었으면 진행 중인 단계도 끝난 것이다. 남겨 두면 새 층에서 옛
    // 배너와 pause가 그대로 이어진다.
    if (_phase == EscalatorPhase.boardingDetected ||
        _phase == EscalatorPhase.verticalMotionDetected ||
        _phase == EscalatorPhase.midpointReached) {
      _setPhase(
        EscalatorPhase.cancelled,
        atMs: _phaseEnteredAtMs ?? 0,
        reason: 'floorChanged',
      );
    }
    _phase = EscalatorPhase.idle;
    _phaseEnteredAtMs = null;
    _resetApproach();
    _verticalMotionSinceMs = null;
    _verticalMotionSign = 0;
    _verticalMotionObserved = false;
    _fastDisplacementM = 0;
    _earlyVerticalMotion = false;
    _verticalMotionQuietSinceMs = null;
  }

  void _pushEvent({
    required int atMs,
    required String kind,
    required String reason,
    double deltaM = 0,
    String? toFloorLabel,
    String? group,
    int? durationMs,
    int? stepsDuring,
    String? boardingEvidence,
  }) {
    if (_events.length >= maxEvents) {
      _events.removeAt(0);
    }
    _events.add(
      EscalatorDetectionEvent(
        atMs: atMs,
        kind: kind,
        reason: reason,
        deltaM: deltaM,
        fromFloorLabel: _floorLabel ?? '',
        toFloorLabel: toFloorLabel,
        group: group,
        durationMs: durationMs,
        stepsDuring: stepsDuring,
        boardingEvidence: boardingEvidence,
      ),
    );
  }

  static List<_EscalatorNode> _parseEscalatorNodes(FloorGraph? graph) {
    if (graph == null) return const [];
    final nodes = <_EscalatorNode>[];
    for (final node in graph.nodes) {
      if (node.type != 'escalator') continue;
      final parsed = EscalatorNodeName.tryParse(node.name);
      // 이름 규칙이 없는 노드는 방향·목표 층을 알 수 없어 판정에 쓸 수 없다.
      if (parsed == null) continue;
      nodes.add(
        _EscalatorNode(
          id: node.id,
          rawName: node.name,
          name: parsed,
          xM: node.xM,
          yM: node.yM,
        ),
      );
    }
    return List.unmodifiable(nodes);
  }

  static double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class _EscalatorNode {
  const _EscalatorNode({
    required this.id,
    required this.rawName,
    required this.name,
    required this.xM,
    required this.yM,
  });

  final String id;
  final String? rawName;
  final EscalatorNodeName name;
  final double xM;
  final double yM;
}

class _ArmedNode {
  const _ArmedNode({
    required this.nodeId,
    required this.distanceM,
    required this.atMs,
  });

  final String nodeId;
  final double distanceM;
  final int atMs;
}

class _Smoothed {
  const _Smoothed(this.atMs, this.value);

  final int atMs;
  final double value;
}
