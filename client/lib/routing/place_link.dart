/// 장소 공유 링크를 만들고 읽는다. 순수 함수만 둔다 — 지도도 저장소도 모른다.
library;

/// 공유 링크가 가리키는 장소. 이름·층·좌표는 **담지 않는다.**
///
/// 링크의 글자를 신뢰 가능한 값으로 쓰지 않는다는 뜻이다. 이름을 실어 보내면 그
/// 매장이 이름을 바꾼 날부터 링크가 거짓말을 하고, 층·좌표는 사람이 손으로 고칠 수
/// 있다. 받은 쪽은 두 id만 믿고 나머지를 서버에서 다시 구한다.
class PlaceLink {
  const PlaceLink({required this.buildingId, required this.placeId});

  final String buildingId;
  final String placeId;

  @override
  bool operator ==(Object other) =>
      other is PlaceLink &&
      other.buildingId == buildingId &&
      other.placeId == placeId;

  @override
  int get hashCode => Object.hash(buildingId, placeId);

  @override
  String toString() => 'PlaceLink($buildingId, $placeId)';
}

/// 공유 링크를 받는 origin. `https://호스트`까지다.
///
/// **컴파일 타임에 박는다.** 이 값이 비면 공유 버튼을 띄우지 않는다 — 앱이 링크를
/// 만들 수 있어도 그 주소가 증명 파일(`assetlinks.json`,
/// `apple-app-site-association`)을 내지 못하면 받은 사람에게는 브라우저로 새는
/// 링크일 뿐이다.
const placeLinkOrigin = String.fromEnvironment('PLACE_LINK_ORIGIN');

/// 링크를 만들 수 있는 상태인가. origin이 정해져야 성립한다.
bool placeLinkEnabled([String origin = placeLinkOrigin]) =>
    _originOf(origin) != null;

/// 문자열 origin에서 host가 있는 URI만 꺼낸다. 나머지는 전부 null이다.
Uri? _originOf(String origin) {
  final trimmed = origin.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  // http는 받지 않는다. 두 OS 모두 https로만 링크 소유를 검증한다.
  if (uri.scheme != 'https') return null;
  return uri;
}

const _placeSegment = 'place';

/// 두 id로 공유 URL을 만든다. 만들 수 없으면 null이다.
///
/// id는 percent-encode한다 — 한글·공백이 든 id가 들어와도 링크가 중간에서 끊기지
/// 않게. 빈 값은 만들지 않는다: `/place//x` 같은 주소는 받는 쪽에서 건물 없는
/// 장소로 읽히고, 그건 잘못된 링크가 아니라 **다른 장소**를 가리키는 링크다.
Uri? buildPlaceLink({
  required String buildingId,
  required String placeId,
  String origin = placeLinkOrigin,
}) {
  final base = _originOf(origin);
  final building = buildingId.trim();
  final place = placeId.trim();
  if (base == null || building.isEmpty || place.isEmpty) return null;
  return base.replace(pathSegments: [_placeSegment, building, place]);
}

/// 받은 URI에서 장소를 읽는다. 우리 링크가 아니면 null이다.
///
/// **모르면 연다가 아니라 모르면 만다.** 여분 segment나 다른 host를 너그럽게 받으면
/// 엉뚱한 링크가 임의의 매장을 여는 길이 된다. scheme·host·segment 수를 모두 본다.
PlaceLink? parsePlaceLink(Uri uri, {String origin = placeLinkOrigin}) {
  final base = _originOf(origin);
  if (base == null) return null;
  if (uri.scheme != base.scheme || uri.host != base.host) return null;

  final segments = uri.pathSegments;
  if (segments.length != 3 || segments.first != _placeSegment) return null;

  // pathSegments가 이미 percent-decode한 값을 준다. 디코딩 뒤 빈 값은 `%20`처럼
  // 공백만 있던 경우다.
  final building = segments[1].trim();
  final place = segments[2].trim();
  if (building.isEmpty || place.isEmpty) return null;

  return PlaceLink(buildingId: building, placeId: place);
}
