import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'package:navigation_client/features/indoor_navigation/debug/pdr_device_harness.dart';
import 'package:navigation_client/features/indoor_navigation/platform/native_pdr_event.dart';
import 'package:navigation_client/features/indoor_navigation/platform/pdr_motion_source.dart';

class FakeHarnessMotionSource implements PdrMotionSource {
  final _events = StreamController<NativePdrEvent>.broadcast();

  @override
  Stream<NativePdrEvent> get events => _events.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<int?> resetPedometer() async => 1;

  @override
  Future<Map<String, Object?>?> finalizePedometer() async => null;

  @override
  Future<void> dispose() async => _events.close();

  void emit(Map<String, Object?> raw) {
    final event = NativePdrEvent.tryParse(raw);
    if (event != null) _events.add(event);
  }
}

void main() {
  testWidgets('걸음 snapshot과 stop 확인 뒤 PASS를 표시한다', (tester) async {
    final source = FakeHarnessMotionSource();
    final driver = IndoorNavigationDriver(source: source, nowMs: () => 0);
    final receipts = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PdrDeviceHarness(
          source: source,
          driver: driver,
          walkingTimeout: const Duration(seconds: 5),
          stopObservation: Duration.zero,
          writeReceipt: (value) async => receipts.add(value),
        ),
      ),
    );
    await tester.pump();

    source.emit({
      'source': 'ios_core_motion',
      'kind': 'motion',
      'stepSessionId': 1,
      'fusedHeadingDeg': 0.0,
      'headingStable': true,
      'headingSource': 'device_motion/xMagneticNorthZVertical',
      'motionTimestamp': 1000.0,
    });
    source.emit({
      'source': 'ios_core_motion',
      'kind': 'pedometer',
      'stepSessionId': 1,
      'steps': 4,
      'pedometerSessionStartMs': 900,
      'pedometerTimestamp': 2000.0,
      'pedometerDistance': 2.8,
      'pedometerDistanceAvailable': true,
      'stepPeakTimes': [1200.0, 1600.0],
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(find.text('PASS'), findsOneWidget);
    expect(find.textContaining('4걸음'), findsOneWidget);
    expect(receipts.first, contains('"result":"RUNNING"'));
    expect(receipts.last, contains('"result":"PASS"'));
  });
}
