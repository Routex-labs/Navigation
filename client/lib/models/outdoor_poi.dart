import 'package:latlong2/latlong.dart';

/// TMAP POI 통합검색(`GET /tmap/pois`)이 돌려주는 **건물 밖 장소** 한 건.
///
/// 우리 백엔드가 아는 장소는 더현대 서울 안의 매장뿐이다. 사용자가 검색창에
/// "스타벅스"를 쳤을 때 건물 안에 없으면 지금까지는 "찾지 못했어요"로 끝났는데,
/// 그 말은 사실이 아니다 — 건물 밖 200m 지점에 있을 수 있다. 이 모델이 그
/// 바깥 후보를 담는다.
///
/// [PoiSearchResult]와 합치지 않는 이유는 **경로 계산 방식이 다르기 때문**이다.
/// 실내 매장은 노드 ID로 그래프를 타지만, 여기에는 노드가 없고 위경도만 있다.
/// 한 타입에 억지로 담으면 `nodeId == null`인 값이 실내 라우팅으로 흘러들어가
/// "출발지는 잡혔는데 경로만 안 나오는" 상태가 된다.
class OutdoorPoi {
  const OutdoorPoi({
    required this.id,
    required this.name,
    required this.point,
    this.category,
    this.address,
    this.telNo,
    this.distanceMeters,
  });

  /// TMAP 응답 한 건(`searchPoiInfo.pois.poi[]`)을 파싱한다. 좌표를 못 읽으면
  /// null을 돌려준다 — 좌표 없는 POI는 지도에 찍을 수도, 경로를 낼 수도 없어
  /// 목록에 남겨 두면 눌러도 아무 일이 없는 줄이 된다.
  ///
  /// **위경도가 숫자가 아니라 문자열로 온다.** `"frontLat": "37.5665"` 형태라
  /// `as num`으로 읽으면 그 자리에서 던진다. 실제 응답을 그대로 캡처한 픽스처로
  /// 회귀를 막아 둔다(`tests/unit_test/tmap_poi_repository_test.dart`).
  static OutdoorPoi? fromTmapJson(Map<String, dynamic> json) {
    final point = _pickPoint(json);
    if (point == null) return null;
    final name = _text(json['name']);
    if (name == null) return null;
    return OutdoorPoi(
      id: _text(json['id']) ?? '${point.latitude},${point.longitude}',
      name: name,
      point: point,
      category: _category(json),
      address: _address(json),
      telNo: _text(json['telNo']),
      distanceMeters: _distanceMeters(json),
    );
  }

  final String id;
  final String name;

  /// 지도에 찍고 경로의 끝점으로 쓸 좌표.
  ///
  /// TMAP은 좌표를 두 벌 준다 — `frontLat/frontLon`(건물 **입구** 쪽)과
  /// `noorLat/noorLon`(대표점, 대개 건물 중심). 길안내 목적이라 입구 쪽을
  /// 우선한다. 중심 좌표로 안내하면 도보 경로가 건물 안쪽을 향하고, TMAP
  /// 보행자 API가 가장 가까운 도로로 스냅하면서 실제 출입구와 다른 면으로
  /// 데려다 놓는다.
  final LatLng point;

  /// 업종(예: 커피전문점). 없으면 null이고, 그 경우 화면은 업종 줄을 그리지 않는다.
  final String? category;

  /// 지번 주소 한 줄. 사용자가 같은 이름의 지점을 구별하는 유일한 단서다.
  final String? address;

  final String? telNo;

  /// 검색 기준점(현재 위치)에서의 거리. TMAP이 km 단위 문자열(`radius`)로 주는
  /// 값을 m로 바꿔 담는다. 기준점 없이 검색하면 null이다.
  final double? distanceMeters;

  /// 좌표는 front(입구) → noor(대표점) 순으로 고른다. 둘 다 없거나 0이면 null.
  static LatLng? _pickPoint(Map<String, dynamic> json) {
    final front = _latLng(json['frontLat'], json['frontLon']);
    if (front != null) return front;
    return _latLng(json['noorLat'], json['noorLon']);
  }

  static LatLng? _latLng(Object? lat, Object? lon) {
    final latitude = _number(lat);
    final longitude = _number(lon);
    if (latitude == null || longitude == null) return null;
    // TMAP은 값이 없을 때 빈 문자열 대신 "0"을 채워 넣는 필드가 있다. 적도·
    // 본초자오선은 한국 서비스 범위 밖이므로 좌표 없음으로 본다.
    if (latitude == 0 || longitude == 0) return null;
    return LatLng(latitude, longitude);
  }

  /// 숫자로도 문자열로도 올 수 있는 필드를 한 곳에서 받는다.
  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 업종은 세 단계(대/중/소)로 오는데 **좁은 것부터** 고른다. "음식점"보다
  /// "커피전문점"이 사용자가 찾던 것과 맞는지 판단하는 데 도움이 된다.
  static String? _category(Map<String, dynamic> json) {
    return _text(json['lowerBizName']) ??
        _text(json['middleBizName']) ??
        _text(json['upperBizName']) ??
        _text(json['bizName']);
  }

  /// 지번 주소를 조립한다. 도로명 주소(`newAddressList`)가 있으면 그쪽을 쓴다 —
  /// 요즘 사용자가 읽고 바로 알아보는 형식이다.
  static String? _address(Map<String, dynamic> json) {
    final road = _roadAddress(json);
    if (road != null) return road;

    final parts = [
      _text(json['upperAddrName']),
      _text(json['middleAddrName']),
      _text(json['lowerAddrName']),
      _text(json['detailAddrName']) ?? _text(json['detailAddrname']),
    ].whereType<String>().toList();
    final lotNumber = _lotNumber(json);
    if (lotNumber != null) parts.add(lotNumber);
    return parts.isEmpty ? null : parts.join(' ');
  }

  static String? _roadAddress(Map<String, dynamic> json) {
    final list = json['newAddressList'];
    if (list is! Map<String, dynamic>) return null;
    final addresses = list['newAddress'];
    if (addresses is! List || addresses.isEmpty) return null;
    final first = addresses.first;
    if (first is! Map<String, dynamic>) return null;
    return _text(first['fullAddressRoad']);
  }

  /// 번지. `secondNo`는 값이 없을 때 "0"으로 오므로 그때는 붙이지 않는다.
  static String? _lotNumber(Map<String, dynamic> json) {
    final first = _text(json['firstNo']);
    if (first == null || first == '0') return null;
    final second = _text(json['secondNo']);
    if (second == null || second == '0') return first;
    return '$first-$second';
  }

  /// `radius`는 km 단위 문자열이다(예: "0.25" = 250m).
  static double? _distanceMeters(Map<String, dynamic> json) {
    final km = _number(json['radius']);
    if (km == null || km <= 0) return null;
    return km * 1000;
  }
}
