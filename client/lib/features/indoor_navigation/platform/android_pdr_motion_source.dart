import 'dart:async';

import 'package:flutter/services.dart';

import 'native_pdr_event.dart';
import 'pdr_motion_source.dart';

/// Android SensorManager bridge adapter.
///
/// Native code owns the sensor registrations and emits the same tagged
/// EventChannel contract as iOS. This class deliberately only converts the
/// raw payload at the platform boundary; PDR count/heading policy stays in
/// the typed core.
class AndroidPdrMotionSource implements PdrMotionSource {
  AndroidPdrMotionSource({
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
    if (_rawSub != null) return;
    final controller = _controller ??=
        StreamController<NativePdrEvent>.broadcast();
    _rawSub = _eventChannel.receiveBroadcastStream().listen(
      (raw) {
        final parsed = NativePdrEvent.tryParse(raw);
        if (parsed != null && !controller.isClosed) {
          controller.add(parsed);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
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
