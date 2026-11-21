import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/phone_backup_background.dart';
import 'package:quark/utils/phone_backup_background_config.dart';

/// An in-memory stand-in for the native lock, shared by a "foreground" and a
/// "background" run in the same test.
class _FakeLock implements PhoneBackupRunLock {
  bool held = false;
  int releases = 0;

  @override
  Future<bool> tryAcquire() async {
    if (held) return false;
    held = true;
    return true;
  }

  @override
  Future<void> release() async {
    held = false;
    releases++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLock lock;
  late int runs;
  late List<(int, int)> progress;
  late PhoneBackupConditions? conditions;

  PhoneBackupBackgroundWake wake({
    PhoneBackupRun? run,
    Future<void> Function(int done, int total)? reportProgress,
  }) => PhoneBackupBackgroundWake(
    run:
        run ??
        (onProgress) async {
          runs++;
        },
    lock: lock,
    loadConditions: () async => conditions,
    reportProgress:
        reportProgress ?? (done, total) async => progress.add((done, total)),
  );

  setUp(() {
    lock = _FakeLock();
    runs = 0;
    progress = [];
    conditions = const PhoneBackupConditions(
      wifiOnly: false,
      chargingOnly: false,
    );
  });

  test('a background wake calls the backup run', () async {
    expect(await wake().handle(), PhoneBackupWakeOutcome.ran);
    expect(runs, 1);
    expect(lock.held, isFalse);
  });

  test('a wake with backup off does not run', () async {
    conditions = null;
    expect(await wake().handle(), PhoneBackupWakeOutcome.backupOff);
    expect(runs, 0);
  });

  test('a wake never overlaps a foreground run holding the lock', () async {
    final foregroundDone = Completer<void>();
    final foreground = lock.runExclusively(() => foregroundDone.future);
    await Future<void>.delayed(Duration.zero);

    expect(await wake().handle(), PhoneBackupWakeOutcome.alreadyRunning);
    expect(runs, 0);

    foregroundDone.complete();
    expect(await foreground, isTrue);
    expect(await wake().handle(), PhoneBackupWakeOutcome.ran);
    expect(runs, 1);
  });

  test('two wakes at once run the backup only once', () async {
    final release = Completer<void>();
    var started = 0;
    Future<void> slowRun(PhoneBackupProgress _) async {
      started++;
      await release.future;
    }

    final first = wake(run: slowRun).handle();
    await Future<void>.delayed(Duration.zero);
    final second = await wake(run: slowRun).handle();
    release.complete();

    expect(second, PhoneBackupWakeOutcome.alreadyRunning);
    expect(await first, PhoneBackupWakeOutcome.ran);
    expect(started, 1);
  });

  test('a run that throws fails the wake and frees the lock', () async {
    final outcome = await wake(
      run: (_) => Future.error(StateError('boom')),
    ).handle();
    expect(outcome, PhoneBackupWakeOutcome.failed);
    expect(lock.held, isFalse);
    expect(lock.releases, 1);
  });

  test('progress reaches the notification only for a long run', () async {
    const threshold = PhoneBackupBackgroundConfig.foregroundThreshold;
    await wake(
      run: (onProgress) async {
        onProgress(1, threshold);
        onProgress(1, threshold + 1);
        onProgress(2, threshold + 1);
      },
    ).handle();
    expect(progress, [(1, threshold + 1), (2, threshold + 1)]);
  });

  test('a progress report that fails does not stop the run', () async {
    const total = PhoneBackupBackgroundConfig.foregroundThreshold + 1;
    var reached = 0;
    final outcome = await wake(
      run: (onProgress) async {
        onProgress(1, total);
        await Future<void>.delayed(Duration.zero);
        reached++;
      },
      reportProgress: (done, total) =>
          Future.error(PlatformException(code: 'boom')),
    ).handle();
    expect(outcome, PhoneBackupWakeOutcome.ran);
    expect(reached, 1);
  });

  group('the Android channel', () {
    const channel = MethodChannel(PhoneBackupBackgroundConfig.channelName);
    late List<MethodCall> calls;
    late List<bool> lockAnswers;

    setUp(() {
      calls = [];
      lockAnswers = [true];
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'conditions' => {'wifiOnly': true, 'chargingOnly': false},
              'tryAcquireRunLock' => lockAnswers.removeAt(0),
              _ => null,
            };
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('schedule passes the conditions, cancel cancels', () async {
      await PhoneBackupBackgroundScheduler.schedule(
        const PhoneBackupConditions(wifiOnly: true, chargingOnly: true),
      );
      await PhoneBackupBackgroundScheduler.cancel();
      expect(calls.map((c) => c.method), ['schedule', 'cancel']);
      expect(calls.first.arguments, {'wifiOnly': true, 'chargingOnly': true});
    });

    test('a wired wake reads conditions and holds the native lock', () async {
      final outcome = await PhoneBackupBackgroundWake.android(
        run: (onProgress) async => onProgress(1, 100),
      ).handle();
      expect(outcome, PhoneBackupWakeOutcome.ran);
      expect(calls.map((c) => c.method), [
        'conditions',
        'tryAcquireRunLock',
        'progress',
        'releaseRunLock',
      ]);
    });

    test('a second run from the same engine is refused while the first '
        'holds the lock', () async {
      // The native lock answers false to a second take from any owner,
      // the app's own engine included.
      lockAnswers = [true, false];
      const lock = ChannelPhoneBackupRunLock();
      final release = Completer<void>();
      var started = 0;
      final first = lock.runExclusively(() async {
        started++;
        await release.future;
      });
      await Future<void>.delayed(Duration.zero);
      final second = await lock.runExclusively(() async => started++);
      release.complete();

      expect(second, isFalse);
      expect(await first, isTrue);
      expect(started, 1);
    });

    test('a wake that throws still tells the worker it finished', () async {
      await reportPhoneBackupWake(() => throw StateError('no plugins'));
      expect(calls.single.method, 'finished');
      expect(calls.single.arguments, PhoneBackupWakeOutcome.failed.name);
    });

    test('a wake tells the worker how it went', () async {
      await reportPhoneBackupWake(() => PhoneBackupWakeOutcome.backupOff);
      expect(calls.single.arguments, PhoneBackupWakeOutcome.backupOff.name);
    });

    test('off Android the scheduler does nothing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await PhoneBackupBackgroundScheduler.schedule(
        const PhoneBackupConditions(wifiOnly: false, chargingOnly: false),
      );
      expect(await PhoneBackupBackgroundScheduler.scheduledConditions(), null);
      expect(calls, isEmpty);
    });
  });
}
