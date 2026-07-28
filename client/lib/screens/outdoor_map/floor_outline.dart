/// 야외 지도 위에 그리는 "지금 보고 있는 층의 외곽선" 규칙.
///
/// 화면 코드에서 분리한 이유는 [indoor_entry_zoom.dart]와 같다 — 규칙을 함수로
/// 고정하고 테스트로 지킨다. 여기서 지키는 규칙은 셋이다.
///
/// 1. **실내에 들어가 있지 않으면 선을 그리지 않는다.** 야외 지도를 훑는 동안
///    건물 테두리가 계속 떠 있으면 지도만 시끄러워진다. "이 건물은 탭할 수
///    있다"는 힌트는 옅은 fill이 이미 준다.
/// 2. **지상층(1F 이상)은 건물 외곽선을 따른다.** 층 도면보다 건물 외곽선이
///    사용자가 밖에서 보던 모양과 일치한다.
/// 3. **지하층은 그 층 도면의 외곽선을 따른다.** 더현대 서울처럼 지하가 지상보다
///    훨씬 넓은 건물에서는 두 모양이 아예 다르다([indoor_entry_zoom.dart]의
///    이탈 임계값 주석 참고 — B3·B4는 화면 기준 286 x 305 m로 지상층의 1.6배다).
///    이때 건물 외곽선을 그대로 쓰면 선이 도면 한가운데를 가로지르거나 도면과
///    상관없는 곳에 떠 있게 된다.
///
/// 지하층인데 그 층 도면이 아직 없으면(로딩 중이거나 로드 실패) **아무것도 그리지
/// 않는다.** 건물 외곽선으로 폴백하면 잠깐이라도 틀린 모양을 보여주게 되는데,
/// 그건 선이 잠깐 없는 것보다 나쁘다 — 사용자는 그 선을 층 경계로 믿는다.
library;

import 'package:latlong2/latlong.dart';

/// 층 라벨이 지하인지. 백엔드가 내려주는 라벨 규약은 `B<n>`(지하) / `<n>F`(지상)
/// 이며, 정렬용 level 계산([`category_stores_sheet.dart`]의 `_floorLevel`)과 같은
/// 형식을 본다. 알 수 없는 형식은 **지상으로 취급**한다 — 판단이 애매할 때
/// 건물 외곽선을 쓰는 쪽이 안전하다(지금까지의 동작과 같다).
bool isBasementFloor(String? floor) {
  if (floor == null) return false;
  return RegExp(r'^B\d+$').hasMatch(floor.toUpperCase());
}

/// 지금 그려야 하는 외곽선 링. 그리지 않아야 하면 null.
///
/// 링으로 쓸 수 있는 최소 조건은 점 3개다. 그보다 적으면 폴리곤이 되지 않으므로
/// 없는 것으로 본다.
List<LatLng>? floorOutlineRing({
  required bool indoorEntered,
  required String? floor,
  required List<LatLng>? buildingFootprint,
  required List<LatLng>? floorFootprint,
}) {
  if (!indoorEntered) return null;
  final ring = isBasementFloor(floor) ? floorFootprint : buildingFootprint;
  if (ring == null || ring.length < 3) return null;
  return ring;
}
