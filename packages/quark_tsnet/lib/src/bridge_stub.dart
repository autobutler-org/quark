/// Stand-in for platforms without `dart:ffi` (the web build), where a browser
/// cannot run a tailnet node.
library;

import 'status.dart';

/// The embedded tailnet node; unavailable on this platform.
abstract final class QuarkTsnet {
  /// Whether this platform has the native bridge.
  static const bool isSupported = false;

  /// Always throws: there is no native bridge here.
  static Future<int> start({
    required String stateDir,
    required String controlUrl,
    required String authKey,
    required String hostname,
    required String upstream,
  }) async => throw UnsupportedError('quark_tsnet needs dart:ffi');

  /// No-op.
  static Future<void> stop() async {}

  /// Always stopped.
  static TsnetStatus status() => const TsnetStatus(state: 'Stopped');
}
