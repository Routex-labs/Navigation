const apiBaseUrl = 'http://10.0.2.2:8001';

/// 데모 데이터셋의 유일한 건물 ID. 다건물 지원은 범위 밖(design.md 8번 항목).
const demoBuildingId = 'bldg-001';

/// TMAP(SK Open API) 보행자 경로 안내. https://openapi.sk.com 에서 앱 등록 후 발급.
/// 키가 비어있으면 TmapDirectionsRepository 호출이 실패하므로, 발급 전까지는
/// service_locator.dart에서 MockDirectionsRepository를 사용한다.
const tmapAppKey = '';
const tmapBaseUrl = 'https://apis.openapi.sk.com/tmap';
