import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/utils/app_log_config.dart';
import 'package:quark/utils/app_log_sink.dart';

/// The app's own log, kept on the client's disk so it survives a crash and
/// does not depend on the Quark being reachable (#1822).
///
/// [guard] records every uncaught error; [info] and [error] are for the app
/// to call. Nothing here throws. Never pass a secret: a session token, a
/// password, a vault entry or a chat key does not belong in a log.
/// [redactLogText] runs over every entry as a backstop, not as permission.
class AppLog {
  /// [sink] is where entries go and [now] stamps them; tests pass fakes.
  AppLog({AppLogSink? sink, DateTime Function()? now})
    : _sink = sink ?? appLogSinkPlatform,
      _now = now ?? DateTime.now;

  /// The log every part of the app writes to.
  static final AppLog instance = AppLog();

  final AppLogSink _sink;
  final DateTime Function() _now;

  /// Whether this platform keeps the log. False on the web.
  bool get persists => _sink.persists;

  /// Records something that happened, for the timeline around an error.
  void info(String message) => _write('INFO', message);

  /// Records a failure, with the thrown [error] and its [stack] when known.
  void error(String message, [Object? error, StackTrace? stack]) =>
      _write('ERROR', message, error, stack);

  /// Everything kept, oldest first.
  Future<String> read() => _sink.read();

  /// Runs [body] with every uncaught error recorded: what Flutter reports
  /// through [FlutterError.onError], and what escapes an async gap, which
  /// is routed there too. Each error still reaches the handler that was
  /// installed before, so the console shows what it always did.
  ///
  /// Call it once, around everything `main` does: the binding has to be
  /// initialized inside [body] for its callbacks to run in the guarded zone.
  void guard(Future<void> Function() body) {
    final present = FlutterError.onError;
    FlutterError.onError = (details) {
      error(
        'Uncaught error in ${details.library ?? 'the app'}',
        details.exception,
        details.stack,
      );
      present?.call(details);
    };
    runZonedGuarded(
      body,
      (e, stack) => FlutterError.reportError(
        FlutterErrorDetails(exception: e, stack: stack, library: 'quark'),
      ),
    );
  }

  void _write(
    String level,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    try {
      final text = [message, ?error, ?stack].join('\n').trimRight();
      // Cut before redacting, so the patterns only ever run over a bounded
      // entry.
      final capped = text.length > AppLogConfig.maxEntryChars
          ? '${text.substring(0, AppLogConfig.maxEntryChars)}…'
          : text;
      _sink.write(
        '${_now().toUtc().toIso8601String()} $level ${redactLogText(capped)}\n',
      );
    } catch (_) {
      // An error whose toString throws must not take the handler down.
    }
  }
}

final _credentialPattern = RegExp(
  '((?:token|password|passwd|secret|authorization|cookie|api[_-]?key|auth[_-]?key)'
  r'''[\w-]*["']?\s*[=:]\s*)'''
  r'''(?:"[^"]*"|'[^']*'|(?:(?:Bearer|Basic)\s+)?[^\s"'&,;}]+)''',
  caseSensitive: false,
);
final _bearerPattern = RegExp(r'\b(Bearer)\s+[^\s"]+', caseSensitive: false);
final _userInfoPattern = RegExp(r'://[^/\s@]+@');

/// [text] with anything shaped like a credential replaced by `[redacted]`:
/// a `token=…`, `password: …` or `Authorization: …` pair, a bare
/// `Bearer …`, and the `user:pass@` of a URL.
///
/// Errors carry request URIs and response bodies, so this keeps an
/// accidental credential off the disk. It matches shapes, not secrets: it
/// cannot recognize one that arrives with no label.
String redactLogText(String text) => text
    .replaceAllMapped(_credentialPattern, (m) => '${m[1]}[redacted]')
    .replaceAllMapped(_bearerPattern, (m) => '${m[1]} [redacted]')
    .replaceAll(_userInfoPattern, '://[redacted]@');
