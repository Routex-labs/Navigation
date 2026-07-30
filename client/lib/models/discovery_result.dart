import 'package:latlong2/latlong.dart';

import 'poi_search_result.dart';

/// 탐색(Discovery) 질의 응답의 mode. 백엔드 dto/query.py의
/// DiscoveryResponse.mode(문자열)와 1:1 대응한다.
///
/// 설계: docs/backend/native/conversational-discovery.md 8-3절.
enum DiscoveryMode {
  /// 명확한 목적지 한 건 — matches 1건, 질문 없음.
  direct,

  /// 후보가 넓어 한 번 더 선택이 필요 — question + options + 초기 후보.
  clarify,

  /// 선택이 충분히 좁혀졌거나 되물을 축이 없음 — 다양성 보정된 후보 목록.
  results,

  /// 검증된 후보가 없음.
  noMatch,

  /// 의미 검색 기능 자체를 못 쓰는 상태(모델·인덱스 미가용). 경량/태그 결과가
  /// 있으면 matches에 함께 담겨 온다.
  degraded,

  /// 서버가 이 클라이언트가 모르는 값을 보낸 경우의 방어용 폴백. 백엔드가
  /// mode를 늘려도 파서가 죽지 않고, 화면은 noMatch와 같이 안전하게 처리한다.
  unknown;

  static DiscoveryMode fromWire(String value) => switch (value) {
    'direct' => DiscoveryMode.direct,
    'clarify' => DiscoveryMode.clarify,
    'results' => DiscoveryMode.results,
    'no_match' => DiscoveryMode.noMatch,
    'degraded' => DiscoveryMode.degraded,
    _ => DiscoveryMode.unknown,
  };
}

/// clarify 질문의 선택지 하나. 백엔드 DiscoveryOption(dto/query.py)과 1:1.
/// 실제 후보가 있는 값만 오므로(빈 chip 금지, 설계 문서 4-3절) 클라이언트는
/// count==0을 별도로 걸러낼 필요가 없다.
class DiscoveryOption {
  const DiscoveryOption({
    required this.facet,
    required this.value,
    required this.label,
    required this.count,
  });

  /// 축 이름(styles·cuisines·...). 사용자가 이 값을 고르면
  /// selected_facets 키로 되돌려 보낸다.
  final String facet;

  /// 축의 값(vocabulary에 선언된 값). 되돌려 보낼 실제 값.
  final String value;

  /// 화면 표시용 라벨. 현재는 value와 같지만 계약을 분리해 둔다.
  final String label;

  /// 이 값을 가진 현재 후보 수.
  final int count;

  factory DiscoveryOption.fromJson(Map<String, dynamic> json) =>
      DiscoveryOption(
        facet: json['facet'] as String,
        value: json['value'] as String,
        label: json['label'] as String,
        count: json['count'] as int,
      );
}

/// 추천 매장 1건. 백엔드 DiscoveryMatch(dto/query.py) — QueryMatch(목적지
/// 계약) 필드에 추천 근거(matchedFacets·reason)를 덧붙인 모양이다.
///
/// [PoiSearchResult]와 필드가 겹치지만 별도 클래스로 둔다: storeId·floorId처럼
/// 지금 화면이 아직 쓰지 않는 필드도 그대로 보존해야 Wave 11(질문 chip·후보
/// 목록 UI)이 값을 새로 파싱하지 않고 쓸 수 있고, matchedFacets·reason은
/// destination 계약([PoiSearchResult])에는 없는 개념이라 거기 끼워 넣으면
/// "목적지 결과인데 추천 이유가 있다"는 모순된 모양이 된다.
class DiscoveryMatch {
  const DiscoveryMatch({
    required this.storeId,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.floorId,
    required this.floorName,
    required this.entranceNodeId,
    required this.point,
    required this.matchedFacets,
    required this.reason,
  });

  final String storeId;
  final String name;
  final String? category;
  final String? subcategory;
  final String floorId;
  final String floorName;

  /// 온디바이스 다익스트라의 도착 노드. null이면 아직 입구가 스냅되지 않은
  /// 매장이라 실제 경로 계산은 불가능하다(destination 계약과 동일한 규약).
  final String? entranceNodeId;

  /// 지도 표시용 실좌표. 파서가 이미 centroid_wgs84 null인 매장을 걸러낸
  /// 뒤에만 이 타입이 만들어지므로 여기서는 non-null이다.
  final LatLng point;

  /// 이번 질문/선택과 실제로 일치한 검증 태그. 축 이름 → 값 목록. 원본
  /// facet 전체가 아니라 이번에 실제로 맞은 것만 담겨 온다(설계 문서 8-3절).
  final Map<String, List<String>> matchedFacets;

  /// matchedFacets에서만 템플릿으로 조립된 추천 이유. 근거 태그가 없으면 null.
  final String? reason;

  /// 기존 화면(PoiSearchResult 리스트 기반)에 그대로 얹기 위한 변환.
  /// storeId·floorId·matchedFacets·reason은 Wave 11 전까지 화면에서 쓰이지
  /// 않으므로 여기서는 버려진다 — 그 화면이 필요해지면 이 변환을 걷어내고
  /// DiscoveryMatch를 직접 그리면 된다.
  PoiSearchResult toPoiSearchResult() => PoiSearchResult(
    name: name,
    floor: floorName,
    point: point,
    nodeId: entranceNodeId,
    category: category,
    subcategory: subcategory,
  );
}

/// 탐색(Discovery) 질의 응답. mode가 화면 분기의 유일한 근거다. 백엔드
/// dto/query.py의 DiscoveryResponse와 1:1 대응.
class DiscoveryResult {
  const DiscoveryResult({
    required this.mode,
    required this.query,
    this.question,
    this.options = const [],
    this.matches = const [],
  });

  final DiscoveryMode mode;

  /// 사용자가 보낸 원문. 화면에 되비추는 용도.
  final String query;

  /// clarify일 때만 값이 있다. 7-3절 템플릿에서 고른 질문 문장.
  final String? question;

  /// clarify일 때만 채워진다.
  final List<DiscoveryOption> options;

  /// mode에 따라 1건(direct)·여러 건(clarify 초기 후보·results)·0건(no_match)
  /// 이 온다. degraded는 가능한 결과가 있으면 함께 담아 온다.
  final List<DiscoveryMatch> matches;
}
