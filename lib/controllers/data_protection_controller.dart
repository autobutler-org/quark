import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Storage tab's protection status: the level the Quark reported, each
/// drive's copies, **Back up now**, and a reload when a backup completes,
/// fails, or is deleted.
///
/// Service calls arrive as function parameters defaulting to
/// [DataProtectionService.fetch] and [StorageService.startSnapshotBackup], so
/// a test passes fakes without a mocking library. [level] is that
/// response's level; this controller does not count copies.
class DataProtectionController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller. [events] defaults to the app's event stream.
  /// `backup_completed`, `backup_failed`, `backup_deleted`, and `resync`
  /// load again.
  DataProtectionController({
    Future<DataProtectionStatus> Function() fetch = DataProtectionService.fetch,
    Future<String> Function({
          required String targetDeviceSerial,
          bool acknowledgeHealth,
        })
        startBackup =
        StorageService.startSnapshotBackup,
    Stream<FileEvent>? events,
  }) : _fetch = fetch,
       _startBackup = startBackup {
    _events = (events ?? EventsService.instance.events).listen(_onEvent);
  }

  final Future<DataProtectionStatus> Function() _fetch;
  final Future<String> Function({
    required String targetDeviceSerial,
    bool acknowledgeHealth,
  })
  _startBackup;
  late final StreamSubscription<FileEvent> _events;

  DataProtectionStatus? _status;
  Object? _error;
  bool _isLoading = false;
  int _generation = 0;

  /// The last status, or null before the first success.
  DataProtectionStatus? get status => _status;

  /// The thrown object from the last failed load. The page turns it into
  /// copy. A later success clears it. A failure keeps [status].
  Object? get error => _error;

  /// Whether the first load is in flight. A refresh that already has a
  /// [status] leaves this false so the card stays up.
  bool get isLoading => _isLoading;

  /// [status]'s level, or null when there is no status or the word is not one
  /// the card knows.
  DataProtectionLevel? get level => levelOf(_status?.level);

  /// The card's level for the Quark's word [raw], or null for one it does
  /// not know.
  static DataProtectionLevel? levelOf(String? raw) => switch (raw) {
    'unprotected' => DataProtectionLevel.unprotected,
    'basic' => DataProtectionLevel.basic,
    'protected' => DataProtectionLevel.protected,
    _ => null,
  };

  /// The backup drives **Back up now** starts onto: every one that is
  /// plugged in and not already receiving. A retired drive is left out: its
  /// copies would not count, and starting onto it needs the health
  /// acknowledgment its own card asks for.
  List<DataProtectionBackupDrive> get backUpNowTargets => [
    for (final drive in _status?.backupDrives ?? const [])
      if (drive.state != DataProtectionBackupState.away &&
          drive.state != DataProtectionBackupState.receiving &&
          drive.state != DataProtectionBackupState.retired)
        drive,
  ];

  /// Starts one backup onto each of [backUpNowTargets]. Returns the error of
  /// the first start that failed, or null when every one started. The others
  /// still start: one refusal does not stop the rest.
  Future<Object?> backUpNow() async {
    Object? firstError;
    for (final drive in backUpNowTargets) {
      try {
        await _startBackup(targetDeviceSerial: drive.serial);
      } catch (error) {
        firstError ??= error;
      }
    }
    return firstError;
  }

  /// Fetches the status. A slow answer cannot overwrite a newer load.
  Future<void> load() async {
    final generation = ++_generation;
    if (_status == null) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final status = await _fetch();
      if (!_current(generation)) return;
      _status = status;
      _error = null;
    } catch (error) {
      if (!_current(generation)) return;
      _error = error;
    } finally {
      if (_current(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _onEvent(FileEvent event) {
    if (event.kind != 'backup_completed' &&
        event.kind != 'backup_failed' &&
        event.kind != 'backup_deleted' &&
        event.kind != 'resync') {
      return;
    }
    load();
  }

  bool _current(int generation) => !isDisposed && generation == _generation;

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
