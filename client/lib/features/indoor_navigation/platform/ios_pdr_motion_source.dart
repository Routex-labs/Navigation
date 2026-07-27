import 'dart:async';

import 'package:flutter/services.dart';

import 'native_pdr_event.dart';
import 'pdr_motion_source.dart';

/// iOS CoreMotion/CMPedometer 브릿지 어댑터.
///
/// native `PdrMotionBridge.swift`가 EventChannel로 raw 센서 map을 흘리고,
/// MethodChannel로 reset 명령을 받는다. 여기서 raw map을 [NativePdrEvent]로 파싱한다.
class IosPdrMotionSource implements PdrMotionSource {
  IosPdrMotionSource({
    EventChannel? eventChannel,
    MethodChannel? commandChannel,
  }) : _eventChannel =
           eventChannel ?? const EventChannel('navigation_client/pdr_motion'),
       _commandChannel =
           commandChannel ??
           const MethodChannel('navigation_client/pdr_motion_cmd');

  final EventChannel _eventChannel;
  final MethodChannel _commandChannel;

  StreamController<NativePdrEvent>? _controller;
  StreamSubscription<dynamic>? _rawSub;

  @override
  Stream<NativePdrEvent> get events =>
      (_controller ??= StreamController<NativePdrEvent>.broadcast()).stream;

  @override
  Future<void> start() async {
    if (_rawSub != null) {
      return;
    }
    final controller = _controller ??=
        StreamController<NativePdrEvent>.broadcast();
    _rawSub = _eventChannel.receiveBroadcastStream().listen(
      (raw) {
        final parsed = NativePdrEvent.tryParse(raw);
        if (parsed != null && !controller.isClosed) {
          controller.add(parsed);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) {
          controller.addError(error, stack);
        }
      },
    );
  }

  @override
  Future<void> stop() async {
    await _rawSub?.cancel();
    _rawSub = null;
  }

  @override
  Future<int?> resetPedometer() async {
    final result = await _commandChannel.invokeMethod<Object?>(
      'resetPedometer',
    );
    return (result as num?)?.toInt();
  }

  @override
  Future<Map<String, Object?>?> finalizePedometer() async {
    final result = await _commandChannel.invokeMethod<Object?>(
      'finalizePedometer',
    );
    return result is Map ? Map<String, Object?>.from(result) : null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller?.close();
    _controller = null;
  }
}
