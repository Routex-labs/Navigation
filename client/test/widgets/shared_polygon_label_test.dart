import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/floor_plan.dart';
import 'package:navigation_client/core/map/store_label_anchor.dart';

/// **실제 서버 응답으로 재현한다.** 오설록·일상다완이 화면에서 하나로만 보이던
/// 문제를 좌표 몇 개로 흉내 낸 값이 아니라 `/buildings/thehyundai-seoul/floors/B1`이
/// 실제로 내려준 두 매장으로 확인한다 — 흉내 낸 값으로는 이미 통과하고 있었는데
/// 실기기에서는 안 됐다.
void main() {
  late FloorPlan floorPlan;

  setUpAll(() {
    final file = File('test/fixtures/osulloc_shared_polygon_b1.json');
    floorPlan = FloorPlan.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  });

  test('두 매장이 모두 파싱된다', () {
    expect(floorPlan.stores.map((s) => s.name), ['오설록', '일상다완']);
  });

  test('중심점은 같고 입구는 다르게 들어온다', () {
    final osulloc = floorPlan.stores.first;
    final ilsang = floorPlan.stores.last;

    expect(osulloc.centroid, ilsang.centroid);
    expect(osulloc.entrance, isNotNull);
    expect(ilsang.entrance, isNotNull);
    expect(osulloc.entrance, isNot(ilsang.entrance));
  });

  test('폴리곤도 둘 다 들어온다', () {
    expect(floorPlan.stores.every((s) => s.polygon.length >= 3), isTrue);
  });

  test('같은 자리로 묶여 공유 수가 2로 잡힌다', () {
    final shares = storeLabelShareCounts(floorPlan.stores);

    expect(shares.values, everyElement(2));
  });

  test('앵커가 서로 다른 점으로 갈라진다', () {
    final anchors = resolveStoreLabelAnchors(
      stores: floorPlan.stores,
      bearingDeg: 0,
    );

    final osulloc = anchors[floorPlan.stores.first.id]!;
    final ilsang = anchors[floorPlan.stores.last.id]!;
    expect(osulloc, isNot(ilsang));

    // 화면에서 얼마나 떨어지는지까지 확인한다. 폴리곤 세로의 절반이어야 한다.
    final gapM = ((osulloc.latitude - ilsang.latitude) * 111320.0).abs();
    expect(gapM, greaterThan(1.0));
  });
}
