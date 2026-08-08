import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/dijkstra.dart';
import 'package:navigation_client/widgets/directions_sheet.dart';

/// 길찾기 후보 목록이 상단 검색 결과와 **같은 판단 재료**를 갖는지.
///
/// 같은 앱에서 같은 매장을 고르는데 한쪽에만 거리가 있으면 사용자는 두 화면이
/// 다른 것을 뜻한다고 읽는다. 설계는 `docs/client/map-ui-redesign-plan.md`의
/// 「7+E 합동 설계」 2단계가 단일 출처다.

DirectionsCandidate _candidate({
  required String title,
  String? nodeId,
  String floor = '3F',
}) => DirectionsCandidate(
  title: title,
  subtitle: floor,
  point: const LatLng(37.5, 127.0),
  nodeId: nodeId,
  floor: floor,
);

Widget _subject({
  required List<DirectionsCandidate> results,
  Map<String, NodeReach>? reachByNodeId,
}) => MaterialApp(
  home: Scaffold(
    body: DirectionsSheet(
      originLabel: '현재 위치',
      search: (_) async => results,
      reachByNodeId: reachByNodeId,
    ),
  ),
);

/// 디바운스(300ms)를 지나 가짜 응답이 프레임에 반영될 때까지 흘려보낸다.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  group('길찾기 후보의 거리 줄', () {
    testWidgets('위치를 잡았으면 거리와 도보 시간을 함께 보여준다', (tester) async {
      await tester.pumpWidget(
        _subject(
          results: [_candidate(title: '나이키 라이즈', nodeId: 'N1')],
          reachByNodeId: const {
            'N1': NodeReach(distanceM: 124.4, costM: 124.4),
          },
        ),
      );
      await _search(tester, '나이키');

      // 124.4m / 1.2m·s⁻¹ ≈ 104초 → 올림해서 2분. 상단 검색 결과와 같은 함수다.
      expect(find.text('124m · 도보 2분'), findsOneWidget);
    });

    // 위치를 아직 안 잡은 상태가 정상 경로다. 줄마다 "거리 알 수 없음"을
    // 반복하면 목록이 읽히지 않는다 — 상단 검색 결과와 같은 규칙.
    testWidgets('위치가 없으면 거리 줄을 아예 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        _subject(
          results: [_candidate(title: '나이키 라이즈', nodeId: 'N1')],
        ),
      );
      await _search(tester, '나이키');

      expect(find.textContaining('도보'), findsNothing);
      expect(find.text('나이키 라이즈'), findsOneWidget);
    });

    // 그래프가 끊겨 있으면 그 노드는 맵에 키가 없다(reachableFrom 계약).
    testWidgets('도달할 수 없는 후보는 거리 줄이 없다', (tester) async {
      await tester.pumpWidget(
        _subject(
          results: [_candidate(title: '나이키 라이즈', nodeId: 'N1')],
          reachByNodeId: const {'다른-노드': NodeReach(distanceM: 10, costM: 10)},
        ),
      );
      await _search(tester, '나이키');

      expect(find.textContaining('도보'), findsNothing);
    });

    // 입구 노드가 없는 매장은 애초에 경로를 못 그린다. 그 사실은 기존
    // `경로 안내 불가` 문구가 이미 말하므로 거리 줄과 겹치지 않아야 한다.
    testWidgets('경로 안내 불가 후보는 문구가 그대로 남고 거리 줄이 없다', (tester) async {
      await tester.pumpWidget(
        _subject(
          results: [_candidate(title: '나이키 라이즈')],
          reachByNodeId: const {'N1': NodeReach(distanceM: 10, costM: 10)},
        ),
      );
      await _search(tester, '나이키');

      expect(find.textContaining('경로 안내 불가'), findsOneWidget);
      expect(find.textContaining('도보'), findsNothing);
    });
  });
}
