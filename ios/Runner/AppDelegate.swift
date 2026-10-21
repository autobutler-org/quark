import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The device's IANA zone, which the app sends with each calendar event so
    // the Quark steps its occurrences in it (#3732).
    FlutterMethodChannel(
      name: "org.autobutler.quark/time_zone",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      if call.method == "localTimeZone" {
        result(TimeZone.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    // The vault key behind Face ID or Touch ID (#3595).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VaultKeychain") {
      VaultKeychain.register(with: registrar.messenger())
    }
    // Quark logins in the QuickType bar, opt-in (#3599).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QuickTypeIdentities") {
      QuickTypeIdentities.register(with: registrar.messenger())
    }
  }
}
