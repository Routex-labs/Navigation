/// 야외 지도의 "GPS 기반 실내 진입/이탈" 판정 정책.
///
/// zoom 정책([indoor_entry_zoom.dart])·카메라 근접 정책
/// ([indoor_entry_proximity.dart])과 짝을 이룬다. 화면 코드에서 분리한 이유도
/// 같다 — 이 판정은 위치 스트림과 시간에 얽혀 있어서, 화면 안에 묻어 두면
/// 실기기를 들고 입구를 드나들어야만 검증할 수 있다.
///
/// ## 무엇을 판정하는가
///
/// 실내에 들어갔는지를 직접 알 방법은 없다. 앱이 볼 수 있는 건 플랫폼이 주는
/// `accuracy`(내 위치가 이 반경 안에 있을 것이라는 추정, m) 하나뿐이고, 위성
/// 개수나 신호 세기는 얻을 수 없다. 그래서 **"신호가 멀쩡했을 때 입구 근처에
/// 있었는데, 지금 신호가 무너졌다"** 는 정황으로 판정한다.
///
/// ## 왜 "직전 값 대비 몇 배"가 아닌가
///
/// 예전 판정은 `현재 > 직전 × 1.3`이었다. 이 형태는 **샘플 간격에 결합된다.**
/// 위치는 5 m 움직일 때마다 오므로 간격이 걷는 속도에 따라 달라지는데, 촘촘히
/// 들어올수록 한 스텝의 변화가 작아져 같은 저하도 못 잡는다.
///
///   10 → 60                  : 6.0배 → 잡힘
///   10 → 15 → 22 → 33 → 50   : 각 1.5배 → 잡힘
///   10 → 12 → 14 → … → 50    : 각 1.2배 → **끝까지 못 잡음** (실제로는 5배)
///
/// 게다가 직전 값을 판정 성공 여부와 무관하게 덮어써서, 저하 순간에 좌표가 튀어
/// 거리 조건이 깨지면 그 한 번으로 기회가 사라졌다(다음 비교 기준이 이미 나쁜
/// 값이 되어 버린다). 이것이 실제 미탐의 주된 원인이었다.
///
/// 그래서 비율을 버리고 **절대값 두 개 + 되짚는 창**으로 바꿨다. 창 안에서
/// 조건을 다시 읽으므로 한 번 놓쳐도 다음 위치에서 다시 판정되고, 몇 번에 나눠
/// 나빠지든 결과가 같다. 요구하는 대비는 오히려 1.3배에서 2배
/// ([trustedAccuracyMeters] → [degradedAccuracyMeters])로 **엄격해진다.**
library;

import 'package:latlong2/latlong.dart' as ll;

/// 이 오차 이하면 좌표를 믿는다(m).
///
/// 두 가지 일을 한다 — (1) "신호가 멀쩡했다"의 증거, (2) 입구까지 거리를 잴 때
/// 쓸 좌표의 자격. 더 조이면(예: 10 m) 큰 건물 벽 옆에서는 거의 성립하지 않아
/// 진입이 통째로 죽고, 풀면 거리 판정이 헐거워진다.
const trustedAccuracyMeters = 15.0;

/// 이 오차를 넘으면 신호가 무너졌다고 본다(m).
///
/// 화면의 'GPS 신호 약함' 배지와 **같은 값을 쓴다.** 배지가 뜬 상태에서 진입이
/// 판정되므로 사용자가 보는 것과 코드의 판단이 어긋나지 않는다.
const degradedAccuracyMeters = 30.0;

/// 입구에서 이 거리 안이면 "입구에 있었다"고 본다(m).
///
/// [indoor_entry_proximity.dart]의 `indoorEntryProximityMeters`(80 m)와 다른
/// 값이다. 그쪽은 **카메라**가 건물 근처인지, 이쪽은 **사용자**가 입구 앞인지다.
const entranceNearMeters = 20.0;

/// 자동 진입을 다시 켜려면 입구에서 이만큼 떨어진 곳에서 신뢰 좌표가 잡혀야
/// 한다(m).
///
/// [entranceNearMeters]와 같은 값을 쓰면 경계에서 켜졌다 꺼졌다 한다. 신뢰
/// 좌표라도 오차가 [trustedAccuracyMeters]까지 있으므로, 40 m면 오차를 빼도
/// 진입 반경 밖이 보장된다. zoom 정책이 진입 17.5 / 이탈 15.6으로 벌려 둔 것과
/// 같은 이유다.
const entranceFarMeters = 40.0;

/// 진입 판정이 과거를 되짚는 창.
///
/// 이 길이가 곧 **"급격함"의 정의**다. 짧으면 확 나빠진 경우만, 길면 완만한
/// 저하까지 잡는다. 10초를 고른 근거는 양쪽 압력이다.
///   - 더 짧으면: 위치는 5 m 이동마다 오므로 보통 걸음에서 4초에 한 건꼴이다.
///     10초에 2~3건이 들어가는데 이보다 짧으면 창이 비거나 한 건뿐이라 판정이
///     불안정해진다. 정확도 수치 자체도 문을 통과한 뒤 몇 초에 걸쳐 올라간다.
///   - 더 길면: 걸어서 10초는 약 13 m다. 30초로 잡으면 "40 m 전에 입구 근처였다"
///     가 되어, 입구를 지나쳐 간 사람까지 진입으로 읽는다.
///
/// 실기기 로그로 가장 먼저 조정할 값이다.
const entryLookbackWindow = Duration(seconds: 10);

/// 창에 쌓아 두는 위치 표본 수의 상한.
///
/// 창은 표본의 **자체 timestamp**로 자르는데, 기기 시계가 멈추거나 플랫폼이 같은
/// 시각을 반복해 주면 아무것도 잘려 나가지 않는다. 그 경우에도 메모리가 무한정
/// 늘지 않도록 개수로도 막는다.
const _maxWindowSamples = 64;

/// 판정에 쓰는 위치 한 건.
class GpsFix {
  const GpsFix({
    required this.at,
    required this.point,
    required this.accuracyMeters,
  });

  /// 플랫폼이 준 관측 시각. 창을 자르는 기준이며, `DateTime.now()`가 아니라
  /// 표본 자신의 시각을 쓴다 — 테스트에서 시계를 흉내 낼 필요가 없고, 위치가
  /// 늦게 배달돼도 창 길이가 왜곡되지 않는다.
  final DateTime at;
  final ll.LatLng point;

  /// 오차 반경(m). **작을수록 정확하다.**
  final double accuracyMeters;
}

/// 위치 한 건이 요구하는 상태 변화.
enum IndoorEntryGpsDecision {
  /// 실내 진입 — 창 안에 입구 근처의 신뢰 좌표가 있었고 지금은 신호가 무너졌다.
  enter,

  /// 자동 진입 재활성화 — 신뢰 좌표가 입구에서 충분히 떨어진 곳에서 잡혔다.
  /// 오차 [trustedAccuracyMeters] 이하는 실내에서 거의 나오지 않으므로, 이
  /// 조건 자체가 사실상 "밖에 있다"의 증거다.
  rearm,

  /// 근거 없음 — 상태를 그대로 둔다.
  none,
}

/// 최근 위치를 창으로 들고 있으면서 [IndoorEntryGpsDecision]을 판정한다.
///
/// 순수 로직이다(Flutter·플랫폼 의존 없음). 화면은 위치가 올 때마다 [record]
/// 하고 [decide]가 시키는 대로만 하면 된다.
class IndoorEntryGpsTracker {
  final List<GpsFix> _window = <GpsFix>[];

  /// 테스트·진단용. 지금 창에 남아 있는 표본 수.
  int get sampleCount => _window.length;

  void record(GpsFix fix) {
    _window.add(fix);
    final cutoff = fix.at.subtract(entryLookbackWindow);
    // 방금 넣은 표본은 자기 자신보다 이르지 않으므로 항상 살아남는다.
    _window.removeWhere((sample) => sample.at.isBefore(cutoff));
    if (_window.length > _maxWindowSamples) {
      _window.removeRange(0, _window.length - _maxWindowSamples);
    }
  }

  /// 창을 비운다. 실내에 들어가 GPS 구독을 끊을 때처럼, 이전 표본이 더 이상
  /// 지금 상황을 대표하지 않을 때 호출한다.
  void clear() => _window.clear();

  /// [entrance]는 건물 입구 좌표, [armed]는 자동 진입이 지금 켜져 있는지다.
  ///
  /// 두 판정은 배타적이다 — 켜져 있으면 진입만, 꺼져 있으면 재활성화만 본다.
  /// 입구를 아직 모르거나([entrance]가 null) 표본이 하나도 없으면 판정하지
  /// 않는다. **근거가 없으면 판단하지 않는다**는 것이 이 파일 전체의 규칙이다.
  IndoorEntryGpsDecision decide({
    required ll.LatLng? entrance,
    required bool armed,
  }) {
    if (entrance == null || _window.isEmpty) {
      return IndoorEntryGpsDecision.none;
    }
    final latest = _window.last;

    if (!armed) {
      final trusted = latest.accuracyMeters <= trustedAccuracyMeters;
      final away = _metersBetween(latest.point, entrance) > entranceFarMeters;
      return trusted && away
          ? IndoorEntryGpsDecision.rearm
          : IndoorEntryGpsDecision.none;
    }

    // 지금 신호가 무너졌는가.
    if (latest.accuracyMeters <= degradedAccuracyMeters) {
      return IndoorEntryGpsDecision.none;
    }
    // 창 안 어딘가에 "믿을 수 있으면서 입구 앞이었던" 순간이 있었는가.
    //
    // any로 창 전체를 다시 읽는 것이 핵심이다. 이 덕분에 저하 순간에 좌표가 튀어
    // 놓치더라도, 창이 살아 있는 동안 들어오는 다음 위치에서 그대로 다시 성립한다.
    final approached = _window.any(
      (sample) =>
          sample.accuracyMeters <= trustedAccuracyMeters &&
          _metersBetween(sample.point, entrance) <= entranceNearMeters,
    );
    return approached
        ? IndoorEntryGpsDecision.enter
        : IndoorEntryGpsDecision.none;
  }
}

double _metersBetween(ll.LatLng a, ll.LatLng b) =>
    const ll.Distance().as(ll.LengthUnit.Meter, a, b);
