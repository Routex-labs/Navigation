import '../../features/indoor_navigation/contract/pdr_anchor.dart';

/// 지도를 다시 돌리기까지 참아 주는 최소 방향 변화(도).
///
/// 실내 heading은 자기 왜곡 때문에 가만히 서 있어도 몇 도씩 흔들린다. 그걸
/// 그대로 카메라에 걸면 화면이 쉬지 않고 떨리면서 매장 라벨이 계속 재배치된다.
/// 12°는 "몸을 돌렸다"와 "센서가 떨린다"를 가르는 값으로 잡았다 — 사람이
/// 의도적으로 방향을 바꾸면 대개 한 번에 이보다 크게 돈다.
const kBearingFollowDeadbandDeg = 12.0;

/// 카메라에 새로 적용할 bearing을 돌려준다. 지금 각도를 유지해야 하면 null이다.
///
/// [heading]은 사용자가 바라보는 방향(북쪽 기준 시계방향), [cameraBearing]은
/// 지금 카메라가 향한 각도다.
///
/// **실패 조건 세 가지를 여기서 흡수한다.**
///  - heading을 아직 모르면(PDR 미시작, 자기 왜곡으로 미수렴) null — 모르는
///    방향으로 지도를 돌리는 것보다 안 돌리는 게 낫다.
///  - 카메라 각도를 모르면 heading을 그대로 적용한다. 비교 대상이 없으니
///    데드밴드를 걸 수가 없고, 이 경우는 첫 정렬이라 돌리는 게 맞다.
///  - 359°와 1°는 2° 차이지 358° 차이가 아니다. 최단 회전각으로 재야 북쪽을
///    지날 때마다 지도가 한 바퀴 도는 일이 없다.
///
/// [force]가 참이면 데드밴드를 건너뛴다. "위치 보정"처럼 사용자가 명시적으로
/// 정렬을 요청한 경우다 — 그때는 3° 어긋난 것도 맞춰 줘야 누른 보람이 있다.
double? bearingToFollow({
  required double? heading,
  required double? cameraBearing,
  bool force = false,
  double deadbandDeg = kBearingFollowDeadbandDeg,
}) {
  if (heading == null || !heading.isFinite) return null;
  final normalized = normalizePdrBearing(heading);
  if (cameraBearing == null || !cameraBearing.isFinite) return normalized;
  if (force) return normalized;
  final turn = normalizePdrRotation(normalized - cameraBearing).abs();
  if (turn < deadbandDeg) return null;
  return normalized;
}
