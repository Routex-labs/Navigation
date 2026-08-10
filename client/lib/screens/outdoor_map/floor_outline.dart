/// 야외 지도 위에 그리는 "지금 보고 있는 층의 외곽선" 규칙.
///
/// 화면 코드에서 분리한 이유는 [indoor_entry_zoom.dart]와 같다 — 규칙을 함수로
/// 고정하고 테스트로 지킨다. 여기서 지키는 규칙은 둘이다.
///
/// 1. **실내에 들어가 있지 않으면 선을 그리지 않는다.** 야외 지도를 훑는 동안
///    건물 테두리가 계속 떠 있으면 지도만 시끄러워진다. "이 건물은 탭할 수
///    있다"는 힌트는 옅은 fill이 이미 준다.
/// 2. **어느 층이든 그 층 도면의 외곽선을 따른다.** 건물 외곽선(`Building.
///    footprintWgs84`)은 쓰지 않는다 — 층이 아직 없으면 아무것도 그리지 않는다.
///
/// ## 왜 지상층도 건물 외곽선을 버렸나 (예전 규칙과의 차이)
///
/// 예전에는 지하층만 층 도면을 따르고 **지상층은 전부 건물 외곽선**을 썼다.
/// 그런데 야외 오버레이의 층 바닥(fill)은 MVT 타일의 `footprint` 소스 레이어이고,
/// 백엔드는 그 지오메트리를 **그 층의 footprint**로 만든다
/// (`app/geo/tiling.py`: `floor.footprint_local_m or building.footprint_local_m`).
/// 즉 선과 fill이 서로 다른 데이터에서 나오고 있었다.
///
/// 데모 데이터(더현대 서울)에서 이게 실제로 어긋난다. 시드가 층을 넣을 때 건물
/// 행은 **1F를 처음 넣는 순간에만** 채워지므로(`scripts/seed/seed_navigation.py`)
/// `Building.footprint_local_m`은 곧 **1F의 외곽선**이다. 반면 각 층은 자기
/// footprint를 따로 갖고 있고 점 개수부터 다르다 — 1F 20점, 2F 8점, 3F 8점,
/// B1 13점, B3 30점. 그래서
///
/// - **항목 31(외곽 크기가 미세하게 안 맞음)**: 2F 이상에서 fill은 그 층 모양,
///   선은 1F 모양이라 모서리마다 조금씩 어긋났다. 1F에서만 우연히 맞았다.
/// - **항목 39(2층부터 외곽선이 달라야 함)**: 1F·2F·3F가 전부 같은 링(=1F)을
///   써서 애초에 다르게 그릴 수가 없었다.
///
/// 두 문제의 원인이 하나라서 고침도 하나다 — **선도 층 footprint를 본다.**
///
/// ## 왜 타일에 LineLayer를 얹지 않았나
///
/// "같은 MVT 소스에 line 레이어를 추가"하면 픽셀 단위로 정합이 보장되지만, 그
/// 링은 **Dart 쪽에서 좌표로 읽을 수 없다.** dim scrim의 hole과 건물 안 탭
/// 판정은 GeoJSON 폴리곤이 필요해서 결국 다른 출처를 다시 쓰게 되고, 지금 지키고
/// 있는 "선·scrim·탭이 같은 링을 본다"는 불변식이 깨진다.
///
/// 대신 `/buildings/{id}/floors/{floor}` 응답의 `footprint_wgs84`
/// ([`FloorPlan.footprint`])를 쓴다. 백엔드에서 이 값은 타일과 **같은 선택 규칙
/// (층 우선, 없으면 건물)과 같은 아핀 변환**을 지나 나온다
/// (`app/repositories/building_queries.py`의 `_floor_footprint`). 남는 차이는
/// 타일 인코딩의 quantize 오차뿐인데, extent 4096 기준 z17에서 6cm 남짓이라
/// 어떤 확대 배율에서도 sub-pixel이다.
///
/// ## 도면이 아직 없으면 아무것도 그리지 않는다
///
/// 로딩 중이거나 로드 실패로 층 도면이 없으면 **건물 외곽선으로 폴백하지
/// 않는다.** 폴백하면 잠깐이라도 틀린 모양을 보여주게 되는데, 그건 선이 잠깐
/// 없는 것보다 나쁘다 — 사용자는 그 선을 층 경계로 믿는다. 층을 바꾼 직후에도
/// 마찬가지로 이전 층 선을 지운 채 새 도면을 기다린다.
library;

import 'package:latlong2/latlong.dart';

/// 지금 그려야 하는 외곽선 링. 그리지 않아야 하면 null.
///
/// 링으로 쓸 수 있는 최소 조건은 점 3개다. 그보다 적으면 폴리곤이 되지 않으므로
/// 없는 것으로 본다.
///
/// [floorFootprint]는 지금 보고 있는 층 도면의 외곽선이다(`FloorPlan.footprint`).
/// 건물 외곽선은 **일부러 받지 않는다** — 받을 수 있으면 언젠가 폴백에 쓰게 된다.
List<LatLng>? floorOutlineRing({
  required bool indoorEntered,
  required List<LatLng>? floorFootprint,
}) {
  if (!indoorEntered) return null;
  if (floorFootprint == null || floorFootprint.length < 3) return null;
  return floorFootprint;
}
