# 이동 대장 — 야외 지도 화면 해체

`outdoor_map_screen.dart`에서 무엇이 어디로 갔는지의 **단일 출처**다.
[해체 계획](outdoor-map-decomposition.md)의 규칙 3이 요구하는 문서다.

rebase 충돌은 대부분 "이 함수 어디 갔지"를 찾는 데 시간이 든다. `main` 쪽 변경이 여기
적힌 옛 심볼을 건드렸다면, 새 위치에 같은 변경을 적용하면 끝난다.

읽는 법: **옛 이름은 옮기기 전 `OutdoorMapBodyState`의 멤버**다. 새 이름이 옛 이름과 다르면
Dart의 파일 단위 프라이버시(`_`) 때문에 공개로 바꾼 것이고, 그 외 본문은 글자 그대로다.

| 옛 심볼 | 새 위치 | 커밋 |
|---|---|---|
| `emptyGeoJsonCollection` `geoJsonCollection` `geoJsonLineFeature` (private) | `core/map_geojson.dart` (동명 공개) | 53a962b |
| `_registerDebugPdrLayers` | `screens/outdoor_map/pdr_debug_map_layers.dart:registerPdrDebugLayers` | 6082e6f |
| `_syncDebugPdrLayers`의 지도 쓰기 부분 | 〃 `syncPdrDebugLayers` | 6082e6f |
| `_setTrail` | 〃 `_setTrail`(파일 private) | 6082e6f |
| `_renderPdrLocationIcon` | `widgets/location_marker_icon.dart:renderLocationMarkerIcon` | a3d8b6d |
| `_pdrLocationIconPixelRatio` `_pdrLocationCoreRadius` `_pdrLocationRimRadius` | 〃 `kLocationMarkerIcon*` | a3d8b6d |
| `FloorPlanViewState._renderCurrentLocationIcon` | 〃 (같은 함수로 통합) | a3d8b6d |
| 대중교통 소스·레이어 등록 (`_onStyleLoaded` 안) | `screens/outdoor_map/transit_map_layers.dart:registerTransitLayers` | 7683ba0 |
| `_syncTransitLayer`의 feature 변환·쓰기 | 〃 `syncTransitLayer` | 7683ba0 |
| `_badgeImageFor` | 〃 `_badgeImageFor`(파일 private) | 7683ba0 |
| 경로선 소스·레이어 등록 (`_onStyleLoaded` 안) | `screens/outdoor_map/route_map_layers.dart:registerRouteLayers` / `registerTransferRouteLayer` | 2a327cd |
| `_routeSourceId` `_walkedRouteSourceId` `_transferRouteSourceId` `_routeCasingLayerId` | 〃 `kOutdoorRoute*` / `kOutdoorRouteCasingLayerId` | 2a327cd |
| `_searchDirectionsCandidates` (map_shell) | `screens/map_shell/directions_candidates.dart:searchDirectionsCandidates` | 0f71a80 |
| `_semanticDirectionsCandidates` `_mergeOutdoorResults` `_storeCandidate` `_outdoorRowCandidate` `_buildingDestinationPoint` (map_shell) | 〃 | 0f71a80 |

## 아직 옮기지 않은 것

- **에스컬레이터·층 전환 전부** — 알고리즘 재작성 예정이라 손대지 않는다.
- 공개 API 19개 — 해체가 끝나도 같은 자리에 남는다([계획서](outdoor-map-decomposition.md)).
