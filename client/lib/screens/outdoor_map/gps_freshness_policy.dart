/// 야외 위치가 낡았을 때 **직접 한 건 요청할지**를 정하는 정책.
///
/// ## 왜 필요한가 — 스트림이 약속을 안 지킨다
///
/// `core/service_locator.dart`의 `positionStreamSettings()`는 안드로이드에
/// `distanceFilter: 0`, `intervalDuration: 1초`를 준다. 그런데 실기기(더현대
/// 앞 야외, 2026-08-13)에서 진단 칩이 찍은 좌표 사이 간격은 다음과 같았다:
///
///   +15.5s · +23.3s · +36.2s · +36.4s
///
/// 1초를 요청했는데 15~36초에 한 건이 왔다. 같은 순간 화면의 "위치 갱신"
/// 버튼(`Geolocator.getCurrentPosition`)은 누를 때마다 즉시 새 좌표를 돌려줬다.
/// 즉 **기기가 좌표를 못 만드는 것이 아니라, 스트림 스케줄이 우리 요청대로
/// 돌지 않는 것**이다. 스트림 설정으로 더 열 여지는 남아 있지 않다.
///
/// 그래서 스트림을 믿되, 조용한 구간만 일회성 조회로 메운다. 사용자가 손으로
/// 눌러 되던 일을 앱이 대신 하는 것이고, 그 경로는 이미 동작이 확인돼 있다.
///
/// ## 어디서 깨지는가
///
/// - **요청이 겹치면 안 된다.** 일회성 조회는 응답까지 수 초 걸릴 수 있어,
///   간격만 보고 계속 쏘면 요청이 쌓이고 배터리만 태운다. [requestInFlight]로 막는다.
/// - **스트림이 정상인 기기에서는 한 번도 발화하면 안 된다.** [maxAge]가 스트림
///   주기(1초)보다 넉넉해야 하는 이유다. 3초면 1초 스트림에서는 절대 안 걸리고,
///   위 실측처럼 15초 넘게 비는 구간에서는 반드시 걸린다.
/// - **실내에서는 아예 돌면 안 된다.** 실내 위치의 주인은 PDR이고, 여기서 좌표를
///   더 부지런히 가져와 봐야 건물 밖 점만 자주 찍힌다. 그 판단은 호출자가 한다.
library;

/// 마지막 좌표가 이보다 오래되면 직접 한 건 요청한다.
///
/// 스트림이 약속대로 1초에 한 번 주는 기기에서는 이 값에 절대 닿지 않는다 —
/// 그런 기기에서 추가 요청이 나가면 배터리만 쓰고 얻는 것이 없다.
const gpsFixMaxAge = Duration(seconds: 3);

/// 지금 일회성 위치 조회를 보내야 하는지.
///
/// [lastFixReceivedAt]은 좌표를 **받은** 시각이다(기기가 찍은 시각이 아니다).
/// 낡음의 기준은 "화면이 얼마나 오래 옛 위치를 보여주고 있는가"이므로, 고정된
/// 좌표를 반복해서 받는 경우까지 신선하다고 보면 안 된다.
///
/// 아직 한 건도 못 받았으면([lastFixReceivedAt]이 null) 즉시 요청한다 — 스트림
/// 첫 좌표가 늦는 기기에서 지도가 한참 빈 채로 열리는 것을 막는다.
bool shouldRequestFreshFix({
  required DateTime? lastFixReceivedAt,
  required DateTime now,
  required bool requestInFlight,
  Duration maxAge = gpsFixMaxAge,
}) {
  if (requestInFlight) return false;
  if (lastFixReceivedAt == null) return true;
  return now.difference(lastFixReceivedAt) >= maxAge;
}
