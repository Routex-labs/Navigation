/// 실행 설정. 값은 전부 `--dart-define`으로 주입한다.
///
/// 키 발급 절차·무료 쿼터·안 켜면 401 나는 설정 같은 운영 사정은
/// `docs/guide/local-development-guide.md`가 단일 출처다.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// 백엔드 주소. dart-define이 최우선이고, 없으면 플랫폼별 기본값이다 —
/// 안드로이드 에뮬레이터는 호스트 localhost를 `10.0.2.2`로 가리켜야 붙는다.
String get apiBaseUrl {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8001';
  }
  return 'http://localhost:8001';
}

/// Studio 1F만 적재하는 기본 개발 DB와 맞춘 데모 건물 ID.
const demoBuildingId = 'thehyundai-seoul';

/// TMAP 보행자 경로·POI 통합검색. 비면 `MockDirectionsRepository`로 떨어진다.
const tmapAppKey = String.fromEnvironment('TMAP_APP_KEY');
const tmapBaseUrl = 'https://apis.openapi.sk.com/tmap';

/// 대중교통만 base path가 `/transit`이다(`/tmap/routes/transit`은 404).
///
/// **지금은 쓰지 않는다** — 무료 제공량이 하루 10건이라 카카오로 옮겼다.
/// `TmapTransitRepository`는 되돌릴 여지로 남겨 둔다.
const tmapTransitBaseUrl = 'https://apis.openapi.sk.com/transit';

/// 카카오맵 대중교통. **REST API 키**다(JavaScript 키가 아니다). 비면 기능이
/// 꺼진 `UnavailableTransitRepository`를 쓴다.
const kakaoRestApiKey = String.fromEnvironment('KAKAO_REST_KEY');
const kakaoTransitBaseUrl = 'https://dapi.kakao.com/v2/routing';

/// VWorld 배경지도 타일. 비면 OSM 타일로 대체한다.
const vworldApiKey = String.fromEnvironment('VWORLD_API_KEY');
