import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/app_log.dart';
import 'package:quark/utils/app_log_sink.dart';
import 'package:quark/utils/startup_trace.dart';

class _MemorySink implements AppLogSink {
  final entries = <String>[];

  @override
  bool get persists => true;

  @override
  void write(String entry) => entries.add(entry);

  @override
  Future<String> read() async => entries.join();
}

/// #2066: a launch that took minutes on Android left nothing saying where
/// the time went, so the stall could not be traced back to a step.
void main() {
  late _MemorySink sink;
  late Duration now;
  late StartupTrace trace;

  setUp(() {
    sink = _MemorySink();
    now = Duration.zero;
    trace = StartupTrace(
      log: AppLog(sink: sink, now: () => DateTime.utc(2026, 11, 16)),
      elapsed: () => now,
    );
  });

  test(
    'logs each step and when the first frame went up, once it does',
    () async {
      await trace.step('settings', () async {
        now += const Duration(milliseconds: 1200);
      });
      trace.note('loader shown');
      await trace.step('services', () {
        now += const Duration(milliseconds: 30);
      });

      final firstFrame = Completer<void>();
      final finished = trace.finish(firstFrame.future);
      await Future<void>.delayed(Duration.zero);
      expect(sink.entries, isEmpty);

      now = const Duration(milliseconds: 1500);
      firstFrame.complete();
      await finished;

      expect(sink.entries, hasLength(1));
      expect(
        sink.entries.single,
        contains(
          'Startup: first frame 1500ms after main '
          '(settings 1200ms, loader shown at 1200ms, services 30ms)',
        ),
      );
    },
  );

  test('a step that throws is still timed, and its error comes back', () async {
    await expectLater(
      trace.step<void>('settings', () async {
        now += const Duration(milliseconds: 40);
        throw StateError('storage');
      }),
      throwsStateError,
    );
    await trace.finish(Future.value());

    expect(sink.entries.single, contains('(settings 40ms)'));
  });

  test('a synchronous step returns its value', () async {
    expect(await trace.step('probe agent', () => 7), 7);
  });
}
