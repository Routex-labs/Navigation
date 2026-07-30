import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_node_naming.dart';

void main() {
  group('EscalatorNodeName.tryParse', () {
    test('상행 탑승 노드에서 그룹·방향·목표 층을 읽는다', () {
      final parsed = EscalatorNodeName.tryParse('ES1-UP(TO3F)')!;
      expect(parsed.group, 'ES1');
      expect(parsed.direction, EscalatorDirection.up);
      expect(parsed.role, EscalatorNodeRole.boarding);
      expect(parsed.otherFloorLabel, '3F');
    });

    test('상행 도착 노드는 타고 온 층을 가리킨다', () {
      final parsed = EscalatorNodeName.tryParse('ES1-UP(FR1F)')!;
      expect(parsed.role, EscalatorNodeRole.arrival);
      expect(parsed.otherFloorLabel, '1F');
    });

    test('하이픈이 들어간 그룹(ES2-1)을 통째로 읽는다', () {
      final parsed = EscalatorNodeName.tryParse('ES2-1-DN(TO1F)')!;
      expect(parsed.group, 'ES2-1');
      expect(parsed.direction, EscalatorDirection.down);
      expect(parsed.role, EscalatorNodeRole.boarding);
      expect(parsed.otherFloorLabel, '1F');
    });

    test('그룹 라벨이 비어 있는 실측 이름도 파싱한다', () {
      // 5F 데이터에 실제로 있는 이름이다.
      final parsed = EscalatorNodeName.tryParse('ES-UP(TO6F)')!;
      expect(parsed.group, 'ES');
      expect(parsed.otherFloorLabel, '6F');
    });

    test('지하층 표기를 그대로 유지한다', () {
      expect(
        EscalatorNodeName.tryParse('ES3-UP(FRB1)')!.otherFloorLabel,
        'B1',
      );
    });

    test('DOWN 표기도 DN과 같게 다룬다', () {
      expect(
        EscalatorNodeName.tryParse('ES1-DOWN(TO2F)')!.direction,
        EscalatorDirection.down,
      );
    });

    test('규칙과 다른 이름·null은 null이다', () {
      expect(EscalatorNodeName.tryParse(null), isNull);
      expect(EscalatorNodeName.tryParse(''), isNull);
      expect(EscalatorNodeName.tryParse('엘리베이터'), isNull);
      expect(EscalatorNodeName.tryParse('ES1-UP'), isNull);
      expect(EscalatorNodeName.tryParse('ES1(TO3F)'), isNull);
    });

    test('isArrivalOf는 탑승 노드의 짝을 구조로 판정한다', () {
      // 2F의 ES1-UP(TO3F)를 탔다면, 3F에서 찾을 도착 노드는 ES1-UP(FR2F)다.
      final arrival = EscalatorNodeName.tryParse('ES1-UP(FR2F)')!;
      expect(
        arrival.isArrivalOf(
          group: 'ES1',
          direction: EscalatorDirection.up,
          fromFloorLabel: '2F',
        ),
        isTrue,
      );
      // 같은 랜딩에 붙어 있는 탑승 노드는 도착 노드가 아니다.
      final boarding = EscalatorNodeName.tryParse('ES1-UP(TO4F)')!;
      expect(
        boarding.isArrivalOf(
          group: 'ES1',
          direction: EscalatorDirection.up,
          fromFloorLabel: '2F',
        ),
        isFalse,
      );
      // 다른 그룹·다른 방향·다른 출발 층은 모두 거부한다.
      expect(
        arrival.isArrivalOf(
          group: 'ES2',
          direction: EscalatorDirection.up,
          fromFloorLabel: '2F',
        ),
        isFalse,
      );
      expect(
        arrival.isArrivalOf(
          group: 'ES1',
          direction: EscalatorDirection.down,
          fromFloorLabel: '2F',
        ),
        isFalse,
      );
      expect(
        arrival.isArrivalOf(
          group: 'ES1',
          direction: EscalatorDirection.up,
          fromFloorLabel: '1F',
        ),
        isFalse,
      );
    });
  });
}
