import 'api_config.dart';

/// 실내 벡터 타일(MVT) 소스 URL을 만든다.
///
/// 실내 화면과 야외 오버레이가 **같은 규칙**으로 만들어야 한다. 한쪽만 버전을
/// 붙이면 같은 타일이 두 주소로 캐시돼 디스크에 두 벌이 쌓이고, 한쪽만 재검증
/// 왕복을 계속 문다.
///
/// [tileRevision]이 있으면 `?v=`로 붙인다. 그러면 서버가 `immutable`을 줘서
/// 클라이언트가 만료 전에는 **재검증조차 하지 않는다** — 실측에서 콜드 재시작
/// 한 번에 304가 22건 나가던 것이 그 왕복이다. 내용이 바뀌면 revision이 바뀌어
/// 주소가 달라지므로 낡은 타일을 쥐고 있을 위험도 없다.
///
/// null이면(구버전 백엔드) 버전 없이 만들어 지금까지와 같은 짧은 캐시 +
/// 재검증으로 동작한다.
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
