import Flutter
import Network
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
    // Keeps the photo cache's folder out of iCloud backup (#4221).
    FlutterMethodChannel(
      name: "org.autobutler.quark/backup_exclusion",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      guard call.method == "exclude",
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        try BackupExclusion.exclude(path: path)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "exclude_failed", message: error.localizedDescription, details: nil))
      }
    }
    // Whether the current network may cost the user money, such as mobile
    // data or Low Data Mode, so a kept album waits for Wi-Fi unless they
    // allow otherwise (#4222).
    NetworkPath.start()
    FlutterMethodChannel(
      name: "org.autobutler.quark/network",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      if call.method == "isMetered" {
        result(NetworkPath.isMetered)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Watches the device's network path from launch, so asking whether it is
/// metered answers at once (#4222).
enum NetworkPath {
  private static let monitor: NWPathMonitor = {
    let monitor = NWPathMonitor()
    monitor.start(queue: DispatchQueue(label: "org.autobutler.quark.network"))
    return monitor
  }()

  /// Starts watching, so the path is known by the time anyone asks.
  static func start() {
    _ = monitor
  }

  /// Whether the path is expensive (cellular, a shared phone connection) or constrained (Low
  /// Data Mode). No network at all reads as metered.
  static var isMetered: Bool {
    let path = monitor.currentPath
    return path.status != .satisfied || path.isExpensive || path.isConstrained
  }
}

/// Marks a path with `isExcludedFromBackup`, so iCloud and device backups
/// skip it (#4221).
enum BackupExclusion {
  static func exclude(path: String) throws {
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
}
