import 'package:latlong2/latlong.dart';

import '../models/outdoor_poi.dart';

/// 건물 밖 장소 검색. 우리 백엔드는 더현대 서울 안의 매장만 알고 있어서,
/// 바깥 후보는 외부 지도 데이터(TMAP)에서 받아 온다.
abstract class OutdoorPoiRepository {
  /// 이 기능을 지금 쓸 수 있는지. TMAP 키가 주입되지 않으면 false이고, 화면은
  /// "주변 장소" 섹션 자체를 그리지 않는다 — 늘 비어 있는 섹션을 띄워 놓고
  /// 사용자가 검색어를 바꿔 가며 헛수고하게 두지 않기 위해서다.
  bool get isAvailable;

  /// [keyword]로 [center] 주변 [radiusMeters] 안의 장소를 찾는다.
  ///
  /// 실패하거나 결과가 없으면 **빈 목록**이다. null이 아니라 빈 목록인 이유는,
  /// 이 검색이 실내 검색에 곁들이는 보조라 실패해도 화면 흐름을 막지 않아야
  /// 하기 때문이다(실내 결과는 그대로 뜬다).
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters,
    int limit,
  });
}

/// TMAP 키가 없을 때 쓰는 구현. 아무것도 찾지 않는다.
///
/// 가짜 장소를 지어내지 않는 것이 중요하다 — 실내 Mock과 달리 이 데이터는
/// 사용자를 실제로 그 좌표까지 걸어가게 만든다.
class UnavailableOutdoorPoiRepository implements OutdoorPoiRepository {
  const UnavailableOutdoorPoiRepository();

  @override
  bool get isAvailable => false;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 0,
    int limit = 0,
  }) async => const [];
}
