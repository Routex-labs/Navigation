import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pdrMotionHandler: PdrMotionStreamHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let handler = PdrMotionStreamHandler()
    let messenger = engineBridge.applicationRegistrar.messenger()

    // EventChannel: 연속 센서 스트림 (native -> Dart).
    let eventChannel = FlutterEventChannel(
      name: "navigation_client/pdr_motion",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(handler)

    // MethodChannel: 단발 명령 (Dart -> native).
    let commandChannel = FlutterMethodChannel(
      name: "navigation_client/pdr_motion_cmd",
      binaryMessenger: messenger
    )
    commandChannel.setMethodCallHandler { [weak handler] call, result in
      guard let handler else {
        result(FlutterError(code: "PDR_SENSOR", message: "Bridge not ready", details: nil))
        return
      }
      switch call.method {
      case "resetPedometer":
        result(handler.resetPedometerBaseline())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    pdrMotionHandler = handler
  }
}
