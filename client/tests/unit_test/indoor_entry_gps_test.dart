import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/screens/outdoor_map/indoor_entry_gps.dart';

/// GPS 기반 실내 진입/이탈 판정에 대한 회귀 테스트.
///
/// 예전 판정("입구 20 m 안에서 신호가 무너짐")이 실기기에서 놓치던 경우를 여기에
/// 고정한다. 실내에서도 입구 부근에서는 오차가 작게 유지돼 "무너짐"이 성립하지
/// 않았고, 정작 사용자는 이미 건물 안이었다. 지금은 좌표를 직접 읽는다.
///
/// 위젯 테스트로는 재현하기 어려운 판정이라(실기기를 들고 건물을 드나들어야
/// 보인다) 정책을 순수 함수로 떼어냈고, 이 파일이 그 이유다.
void main() {
  // 한 변 100 m짜리 정사각형 건물. 서울 위도에서 위도 1도는 약 111,320 m,
  // 경도 1도는 약 88,240 m다.
  const south = 37.5665;
  const west = 126.9779;
  final north = south + 100 / 111320;
  final east = west + 100 / 88240;
  final footprint = [
    ll.LatLng(south, west),
    ll.LatLng(south, east),
    ll.LatLng(north, east),
    ll.LatLng(north, west),
  ];
  final center = ll.LatLng((south + north) / 2, (west + east) / 2);

  /// 남쪽 벽에서 [meters]만큼 **안쪽**(양수) 또는 **바깥쪽**(음수)인 좌표.
  /// 동서로는 건물 한가운데라, 다른 변까지의 거리가 판정에 끼어들지 않는다.
  ll.LatLng fromSouthWall(double meters) =>
      ll.LatLng(south + meters / 111320, center.longitude);

  GpsBuildingVerdict judge(ll.LatLng point, double accuracy) =>
      judgeBuildingFromGps(
        fix: GpsFix(point: point, accuracyMeters: accuracy),
        footprint: footprint,
      );

  group('건물 안', () {
    test('믿을 수 있는 좌표가 건물 안이면 들어온 것으로 본다', () {
      // 예전 판정은 여기서 "신호가 멀쩡하다"는 이유로 진입하지 않았다.
      expect(judge(center, 8), GpsBuildingVerdict.inside);
    });

    test('입구를 막 지난 지점도 진입으로 잡는다', () {
      // 문을 통과하면 곧바로 넘는 거리여야 한다 — 안 그러면 사용자는 건물
      // 한가운데까지 걸어 들어가야 지도가 반응한다.
      expect(judge(fromSouthWall(6), 10), GpsBuildingVerdict.inside);
    });

    test('오차가 크면 건물 안이어도 판단하지 않는다', () {
      // 오차 반경이 건물 폭에 육박하면 "안"이라는 판정 자체가 의미를 잃는다.
      expect(judge(center, 45), GpsBuildingVerdict.unclear);
    });

    test('벽 바로 안쪽은 판단하지 않는다', () {
      // 문 앞에 선 사람의 좌표는 벽을 넘나든다. 여기서 진입을 발화하면 화면이
      // 실내와 야외를 오간다.
      expect(judge(fromSouthWall(2), 8), GpsBuildingVerdict.unclear);
    });
  });

  group('건물 밖', () {
    test('벽에서 충분히 떨어지면 나온 것으로 본다', () {
      expect(judge(fromSouthWall(-30), 8), GpsBuildingVerdict.outside);
    });

    test('벽 바로 밖은 판단하지 않는다', () {
      // 실내에서 켜 둔 GPS는 좌표가 건물 밖으로 조금씩 튄다. 그 한 건으로 실내
      // 상태를 접으면 사용자는 건물 안에서 도면과 위치 아이콘을 잃는다.
      expect(judge(fromSouthWall(-10), 8), GpsBuildingVerdict.unclear);
    });

    test('오차가 크면 멀리 있어도 판단하지 않는다', () {
      expect(judge(fromSouthWall(-30), 45), GpsBuildingVerdict.unclear);
    });
  });

  group('히스테리시스', () {
    test('안팎 임계값 사이에 완충 구간이 있다', () {
      // 이 구간이 없으면 벽 근처에서 진입과 이탈이 번갈아 성립한다.
      expect(outdoorExitMarginMeters, greaterThan(indoorEnterInsetMeters));
      for (var m = -outdoorExitMarginMeters + 1;
          m < indoorEnterInsetMeters;
          m += 1) {
        expect(
          judge(fromSouthWall(m), 8),
          GpsBuildingVerdict.unclear,
          reason: '벽에서 ${m}m 지점은 완충 구간이어야 한다',
        );
      }
    });

    test('나가는 쪽이 더 엄격하다', () {
      // 잘못 들어가는 비용(밖인데 도면이 뜸)보다 잘못 나오는 비용(안인데 추적이
      // 끊김)이 크다.
      expect(outdoorExitMarginMeters, greaterThanOrEqualTo(20));
    });
  });

  group('근거가 없으면 판단하지 않는다', () {
    test('외곽선을 아직 못 받았으면 판단하지 않는다', () {
      expect(
        judgeBuildingFromGps(
          fix: GpsFix(point: center, accuracyMeters: 8),
          footprint: null,
        ),
        GpsBuildingVerdict.unclear,
      );
    });

    test('외곽선이 폴리곤이 아니면 판단하지 않는다', () {
      expect(
        judgeBuildingFromGps(
          fix: GpsFix(point: center, accuracyMeters: 8),
          footprint: [ll.LatLng(south, west), ll.LatLng(north, east)],
        ),
        GpsBuildingVerdict.unclear,
      );
    });
  });
}
