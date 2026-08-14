import 'package:latlong2/latlong.dart';

import '../../models/route/transit_route.dart';

/// 출발지 → 도착지 대중교통(버스·지하철) 경로 안내.
///
/// 도보 경로([DirectionsRepository])와 계약을 나눈 이유는 결과의 모양이 다르기
/// 때문이다. 도보는 좌표열 하나면 되지만 대중교통은 "무엇을 타고 어디서
/// 갈아타는지"가 본문이고, 후보가 여러 개이며, 경로가 **없는 것이 정상인**
/// 상황(700m 이내)이 있다.
abstract class TransitRepository {
  /// TMAP 키가 주입돼 이 기능을 쓸 수 있는지.
  bool get isAvailable;

  /// [origin]에서 [destination]까지의 대중교통 경로 후보를 받는다.
  ///
  /// 실패해도 예외를 던지지 않고 [TransitRoutes.status]로 이유를 돌려준다 —
  /// 호출부가 "없음"과 "못 물어봄"을 구분해 다른 안내를 띄우기 위해서다.
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count,
  });
}

/// TMAP 키가 없을 때 쓰는 구현. 항상 [TransitRoutesStatus.unavailable]이다.
class UnavailableTransitRepository implements TransitRepository {
  const UnavailableTransitRepository();

  @override
  bool get isAvailable => false;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 0,
  }) async => const TransitRoutes.failure(TransitRoutesStatus.unavailable);
}
