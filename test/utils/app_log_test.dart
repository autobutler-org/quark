import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/app_log.dart';
import 'package:quark/utils/app_log_config.dart';
import 'package:quark/utils/app_log_sink.dart';

class _MemorySink implements AppLogSink {
  final entries = <String>[];

  @override
  bool get persists => true;

  @override
  void write(String entry) => entries.add(entry);

  @override
  Future<String> read() async => entries.join();
}

class _Unprintable {
  @override
  String toString() => throw StateError('no');
}

void main() {
  late _MemorySink sink;
  late AppLog log;

  setUp(() {
    sink = _MemorySink();
    log = AppLog(sink: sink, now: () => DateTime.utc(2026, 10, 9, 12, 30));
  });

  test('an entry is one stamped line with its level', () {
    log.info('App started');

    expect(sink.entries, ['2026-10-09T12:30:00.000Z INFO App started\n']);
  });

  test('an error entry carries the error and its stack', () {
    log.error(
      'Upload failed',
      StateError('boom'),
      StackTrace.fromString('#0 main (file.dart:1)\n'),
    );

    expect(
      sink.entries.single,
      '2026-10-09T12:30:00.000Z ERROR Upload failed\n'
      'Bad state: boom\n'
      '#0 main (file.dart:1)\n',
    );
  });

  test('an entry longer than the cap is cut', () {
    log.info('x' * (AppLogConfig.maxEntryChars * 2));

    expect(
      sink.entries.single.length,
      lessThan(AppLogConfig.maxEntryChars + 64),
    );
    expect(sink.entries.single, endsWith('…\n'));
  });

  test('an error that cannot be printed is dropped, not thrown', () {
    expect(() => log.error('Failed', _Unprintable()), returnsNormally);
    expect(sink.entries, isEmpty);
  });

  test('credentials never reach the sink', () {
    log.error(
      'Request failed',
      Exception(
        'GET https://ada:hunter2@quark.local/api/v0/files?token=abc123&path=/a '
        'Authorization: Bearer eyJhbGciOi.payload.sig '
        '{"password": "correct horse", "refresh_token":"r3fr3sh"} '
        'Cookie: session=deadbeef',
      ),
    );

    final entry = sink.entries.single;
    for (final secret in [
      'hunter2',
      'abc123',
      'eyJhbGciOi',
      'correct horse',
      'r3fr3sh',
      'deadbeef',
    ]) {
      expect(entry, isNot(contains(secret)), reason: secret);
    }
    // What makes the entry worth reading is still there.
    expect(
      entry,
      contains('quark.local/api/v0/files?token=[redacted]&path=/a'),
    );
  });

  test('redaction leaves ordinary text alone', () {
    const text = 'Couldn\'t load /Photos/2026: 404 after 3 tries';
    expect(redactLogText(text), text);
  });

  group('guard', () {
    late List<FlutterErrorDetails> presented;

    setUp(() {
      final original = FlutterError.onError;
      addTearDown(() => FlutterError.onError = original);
      presented = [];
      FlutterError.onError = presented.add;
    });

    test('records an error Flutter reports and still presents it', () {
      log.guard(() async {});

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('bad build'),
          library: 'widgets library',
        ),
      );

      expect(
        sink.entries.single,
        contains(
          'ERROR Uncaught error in widgets library\nBad state: bad build',
        ),
      );
      expect(presented.single.exception, isStateError);
    });

    test('records an error that escapes an async gap', () async {
      log.guard(() async {
        await Future<void>.delayed(Duration.zero);
        throw StateError('late');
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sink.entries.single, contains('Bad state: late'));
      expect(presented.single.exception, isStateError);
    });
  });
}
