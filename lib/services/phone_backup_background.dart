import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quark/utils/phone_backup_background_config.dart';

/// Phone backup's Android background triggers (#4165): a `WorkManager` job
/// about every hour, a `MediaStore` trigger soon after a new photo or video,
/// and the one lock that keeps a background run from overlapping a foreground
/// one.
///
/// The native half lives in `android/app/src/main/kotlin/org/autobutler/backup/`.
/// [PhoneBackupBackgroundScheduler.schedule] hands it the backup's conditions,
/// which become the jobs' constraints. When a job fires, the worker starts a
/// headless Flutter engine at [phoneBackupBackgroundMain], which runs a
/// [PhoneBackupBackgroundWake] and reports back how it went.
///
/// The jobs' constraints carry **Wi-Fi only**, and the worker checks **Only
/// while charging** before it starts an engine, so a wake does not check
/// either again.
const _channel = MethodChannel(PhoneBackupBackgroundConfig.channelName);

/// The settings that limit when a backup run may start.
@immutable
class PhoneBackupConditions {
  /// Creates the conditions a run must meet.
  const PhoneBackupConditions({
    required this.wifiOnly,
    required this.chargingOnly,
  });

  /// Reads the map the platform channel carries.
  factory PhoneBackupConditions.fromMap(Map<Object?, Object?> map) =>
      PhoneBackupConditions(
        wifiOnly: map['wifiOnly'] == true,
        chargingOnly: map['chargingOnly'] == true,
      );

  /// **Wi-Fi only**: run only on an unmetered network.
  final bool wifiOnly;

  /// **Only while charging**: run only while the phone is plugged in.
  final bool chargingOnly;

  /// The map the platform channel carries.
  Map<String, bool> toMap() => {
    'wifiOnly': wifiOnly,
    'chargingOnly': chargingOnly,
  };
}

/// What a background wake did.
enum PhoneBackupWakeOutcome {
  /// The backup run started and finished.
  ran,

  /// Backup is off, so there was nothing to do.
  backupOff,

  /// Another run, in the foreground or the background, holds the lock.
  alreadyRunning,

  /// The run threw; the next wake tries again.
  failed,
}

/// Reports a run's progress: [done] of [total] files handled so far.
typedef PhoneBackupProgress = void Function(int done, int total);

/// The backup run itself, the same one the foreground starts (#4162).
typedef PhoneBackupRun = Future<void> Function(PhoneBackupProgress onProgress);

/// The one lock every backup run takes, so two never run at once.
///
/// On Android the lock lives in the native process, so a run in the app's
/// engine and one in the background worker's engine see the same lock.
abstract interface class PhoneBackupRunLock {
  /// Takes the lock, or answers false when another run holds it.
  Future<bool> tryAcquire();

  /// Gives the lock back.
  Future<void> release();
}

/// Runs a backup under a [PhoneBackupRunLock].
extension PhoneBackupRunExclusively on PhoneBackupRunLock {
  /// Runs [body] while holding the lock and answers true, or answers false
  /// without running it when another run holds the lock. The lock is released
  /// even when [body] throws.
  Future<bool> runExclusively(Future<void> Function() body) async {
    if (!await tryAcquire()) return false;
    try {
      await body();
    } finally {
      await release();
    }
    return true;
  }
}

/// The process-wide lock the Android side holds for every Flutter engine.
class ChannelPhoneBackupRunLock implements PhoneBackupRunLock {
  /// Creates a lock that asks the native side.
  const ChannelPhoneBackupRunLock();

  @override
  Future<bool> tryAcquire() async =>
      await _channel.invokeMethod<bool>('tryAcquireRunLock') ?? false;

  @override
  Future<void> release() => _channel.invokeMethod<void>('releaseRunLock');
}

/// One background wake: checks the conditions, takes the lock, and calls the
/// same run the foreground does.
///
/// Every platform call is injected, so a test drives a wake with fakes.
class PhoneBackupBackgroundWake {
  /// Creates a wake. [loadConditions] answers null when backup is off.
  PhoneBackupBackgroundWake({
    required this.run,
    required this.lock,
    required this.loadConditions,
    required this.reportProgress,
  });

  /// A wake wired to the native side, running [run].
  factory PhoneBackupBackgroundWake.android({required PhoneBackupRun run}) =>
      PhoneBackupBackgroundWake(
        run: run,
        lock: const ChannelPhoneBackupRunLock(),
        loadConditions: PhoneBackupBackgroundScheduler.scheduledConditions,
        reportProgress: (done, total) => _channel.invokeMethod<void>(
          'progress',
          {'done': done, 'total': total},
        ),
      );

  /// The backup run.
  final PhoneBackupRun run;

  /// The lock shared with the foreground run.
  final PhoneBackupRunLock lock;

  /// The conditions backup was scheduled with, or null when it is off.
  final Future<PhoneBackupConditions?> Function() loadConditions;

  /// Shows progress in the foreground service's notification. Called only for
  /// a run with more than [PhoneBackupBackgroundConfig.foregroundThreshold]
  /// files, which is what promotes the run to a foreground service. A report
  /// that fails is logged and the run carries on.
  final Future<void> Function(int done, int total) reportProgress;

  /// Handles one wake and says what it did.
  Future<PhoneBackupWakeOutcome> handle() async {
    try {
      final conditions = await loadConditions();
      if (conditions == null) return PhoneBackupWakeOutcome.backupOff;
      final ran = await lock.runExclusively(
        () => run((done, total) {
          if (total > PhoneBackupBackgroundConfig.foregroundThreshold) {
            unawaited(_report(done, total));
          }
        }),
      );
      return ran
          ? PhoneBackupWakeOutcome.ran
          : PhoneBackupWakeOutcome.alreadyRunning;
    } on Object catch (error) {
      debugPrint('phone backup: background run failed: $error');
      return PhoneBackupWakeOutcome.failed;
    }
  }

  // Nothing awaits a progress report, so its failure is caught here; left
  // uncaught it would end the isolate before it says `finished`.
  Future<void> _report(int done, int total) async {
    try {
      await reportProgress(done, total);
    } on Object catch (error) {
      debugPrint('phone backup: progress report failed: $error');
    }
  }
}

/// Turns the Android background jobs on and off.
///
/// Only Android has them; on every other platform each call does nothing.
abstract final class PhoneBackupBackgroundScheduler {
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Schedules the hourly job and the new-photo trigger under [conditions],
  /// replacing any earlier schedule. Call it whenever backup is turned on or
  /// its **Wi-Fi only** or **Only while charging** setting changes.
  static Future<void> schedule(PhoneBackupConditions conditions) async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('schedule', conditions.toMap());
  }

  /// Cancels both jobs. Call it when backup is turned off.
  static Future<void> cancel() async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('cancel');
  }

  /// The conditions last scheduled, or null when backup is off.
  static Future<PhoneBackupConditions?> scheduledConditions() async {
    if (!_supported) return null;
    final map = await _channel.invokeMapMethod<Object?, Object?>('conditions');
    return map == null ? null : PhoneBackupConditions.fromMap(map);
  }
}

/// The backup run a background wake calls. It is the foreground run from
/// #4162, which has not landed yet; until then nothing schedules a wake, and a
/// wake that fires anyway reports [PhoneBackupWakeOutcome.failed].
Future<void> _phoneBackupRun(PhoneBackupProgress onProgress) =>
    Future.error(UnsupportedError('phone backup run is not available yet'));

/// Where the Android worker's headless engine starts (`PhoneBackupWorker`):
/// handles one wake and tells the worker it is finished.
@pragma('vm:entry-point')
Future<void> phoneBackupBackgroundMain() => reportPhoneBackupWake(() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return PhoneBackupBackgroundWake.android(run: _phoneBackupRun).handle();
});

/// Runs [wake] and always tells the worker it is `finished`, with
/// [PhoneBackupWakeOutcome.failed] when [wake] throws, so the worker never
/// waits on a wake that ended without saying so.
@visibleForTesting
Future<void> reportPhoneBackupWake(
  FutureOr<PhoneBackupWakeOutcome> Function() wake,
) async {
  var outcome = PhoneBackupWakeOutcome.failed;
  try {
    outcome = await wake();
  } on Object catch (error) {
    debugPrint('phone backup: background wake failed: $error');
  } finally {
    await _channel.invokeMethod<void>('finished', outcome.name);
  }
}
