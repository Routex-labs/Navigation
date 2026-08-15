/// 거리를 사람이 읽는 문자열로 적는 **단일 출처**.
///
/// 예전에는 검색 결과·야외 POI·턴바이턴이 각자 포매팅을 들고 있어서, 같은
/// 1.2 km가 화면마다 `1200m`·`1.2km`로 달리 보였다. 어느 쪽이 맞는지 사용자가
/// 알 방법이 없다.
///
/// 검증 기준은 `client/test/domain/geo/distance_format_test.dart`가 단일 출처다.
library;

/// 1 km 미만/이상을 가르는 경계(m).
const _kilometerThresholdMeters = 1000;

/// m → `"480m"` / `"1.2km"`.
///
/// 1000 m 미만이면 정수 m로, 이상이면 소수 한 자리 km로 적는다. **m으로 반올림한
/// 뒤에 경계를 본다** — 999.6 m를 먼저 비교하면 m 갈래로 들어가 `1000m`이 된다.
///
/// km는 반올림이 아니라 **버림**이라 1049 m는 `1.0km`다. 안내에서 거리를 부풀리면
/// 사용자가 이미 지나친 지점을 아직 남았다고 읽는다.
///
/// 음수·NaN·무한대는 빈 문자열이다. 화면에 `NaNm`이 뜨는 것보다 낫다.
String formatDistance(double meters) {
  if (!meters.isFinite || meters < 0) return '';
  final rounded = meters.round();
  if (rounded < _kilometerThresholdMeters) return '${rounded}m';
  // 정수 데시킬로미터로 내림한 뒤 나눈다. toStringAsFixed(1)은 반올림이라
  // 1049 m가 1.0km, 1051 m가 1.1km로 갈려 "덜 남았다"고 읽히는 쪽이 생긴다.
  final deciKm = rounded ~/ 100;
  return '${deciKm ~/ 10}.${deciKm % 10}km';
}
