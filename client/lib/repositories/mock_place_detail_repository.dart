import '../models/place_detail.dart';
import 'place_detail_repository.dart';

/// Mock 지도 모드에는 서버 상세 데이터가 없으므로 코어 시트만 남기도록 null을
/// 반환한다. 실제 API와 달리 합성된 place id를 상세 조회 키로 쓰지 않는다.
class MockPlaceDetailRepository implements PlaceDetailRepository {
  @override
  Future<PlaceDetail?> getPlaceDetail(
    String buildingId,
    String placeId,
  ) async => null;
}
