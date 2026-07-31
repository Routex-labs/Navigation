import '../models/place_detail.dart';

/// 부가 상세 정보 조회. 실패는 예외가 아니라 null로 전달해 호출부의 길찾기·
/// 저장 같은 핵심 동작을 막지 않는다.
abstract class PlaceDetailRepository {
  Future<PlaceDetail?> getPlaceDetail(String buildingId, String placeId);
}
