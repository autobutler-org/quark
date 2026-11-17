import 'dart:async';
import 'dart:developer';

import 'package:quark/utils/app_log.dart';

/// Times the steps `main` takes before the app's first frame, so a slow
/// launch says where its time went (#2066).
///
/// Each [step] is a `Timeline` task named `startup: <name>`, which a DevTools
/// or Perfetto trace of a profile build shows on the UI thread. [finish]
/// writes one line to the [AppLog] once the first frame is up: how long after
/// `main` started it came, each step's time, and each [note] with when it
/// happened. Only Dart's share is counted; the engine's start before `main`
/// shows in `adb shell am start -W` instead.
class StartupTrace {
  /// [log] receives the summary and [elapsed] is the time since `main`
  /// started; tests pass fakes.
  StartupTrace({AppLog? log, Duration Function()? elapsed})
    : _log = log ?? AppLog.instance,
      _elapsed = elapsed ?? _since(Stopwatch()..start());

  static Duration Function() _since(Stopwatch watch) =>
      () => watch.elapsed;

  final AppLog _log;
  final Duration Function() _elapsed;

  /// The summary's parts, in the order they happened.
  final _parts = <String>[];

  /// Runs [body] as the step [name], timing it whether it returns or throws.
  /// [body]'s result or error comes back unchanged.
  Future<T> step<T>(String name, FutureOr<T> Function() body) async {
    final task = TimelineTask()..start('startup: $name');
    final began = _elapsed();
    try {
      return await body();
    } finally {
      task.finish();
      _parts.add('$name ${(_elapsed() - began).inMilliseconds}ms');
    }
  }

  /// Records that [event] happened now, such as the loader being shown.
  void note(String event) {
    Timeline.instantSync('startup: $event');
    _parts.add('$event at ${_elapsed().inMilliseconds}ms');
  }

  /// Writes the summary once [firstFrame] completes.
  Future<void> finish(Future<void> firstFrame) async {
    await firstFrame;
    _log.info(
      'Startup: first frame ${_elapsed().inMilliseconds}ms after main '
      '(${_parts.join(', ')})',
    );
  }
}
