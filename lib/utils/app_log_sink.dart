import 'package:quark/utils/app_log_sink_io.dart'
    if (dart.library.js_interop) 'package:quark/utils/app_log_sink_web.dart'
    as platform;

/// Where `AppLog` entries go: a bounded file on the client's own disk on
/// native, nowhere on the web.
abstract interface class AppLogSink {
  /// Whether entries are kept at all. False on the web, where there is
  /// nothing to show or copy.
  bool get persists;

  /// Appends [entry], a finished line or block ending in a newline. Returns
  /// at once and never throws: the write is queued.
  void write(String entry);

  /// Everything kept, oldest first. Empty when nothing has been written.
  Future<String> read();
}

/// The sink this platform keeps the app log in.
final AppLogSink appLogSinkPlatform = platform.appLogSinkPlatform;
