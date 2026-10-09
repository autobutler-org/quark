import 'package:quark/utils/app_log_sink.dart';

/// Keeps nothing: the web build has no disk of its own to write to, and the
/// browser console already holds what was printed.
class NoAppLogSink implements AppLogSink {
  /// A sink that drops every entry.
  const NoAppLogSink();

  @override
  bool get persists => false;

  @override
  void write(String entry) {}

  @override
  Future<String> read() async => '';
}

/// The web build's sink.
const AppLogSink appLogSinkPlatform = NoAppLogSink();
