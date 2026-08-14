/// 실내 벡터 타일(MVT) 소스 URL. 실내 화면과 야외 오버레이가 **같은 규칙**으로
/// 만들어야 타일이 두 주소로 캐시되지 않는다.
library;

import 'api_config.dart';

/// [tileRevision]을 `?v=`로 붙이면 서버가 `immutable`을 줘 **재검증조차 하지
/// 않는다**(콜드 재시작 한 번에 304가 22건 나가던 왕복이 사라진다). 내용이 바뀌면
/// revision이 바뀌므로 낡은 타일을 쥘 위험도 없다. null이면(구버전 백엔드) 짧은
/// 캐시 + 재검증으로 동작한다.
String indoorTileUrl({
  required String buildingId,
  required String floorName,
  String? tileRevision,
}) {
  final base =
      '$apiBaseUrl/buildings/$buildingId/floors/$floorName'
      '/tiles/{z}/{x}/{y}.mvt';
  if (tileRevision == null || tileRevision.isEmpty) return base;
  return '$base?v=${Uri.encodeQueryComponent(tileRevision)}';
}
