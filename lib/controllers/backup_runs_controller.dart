import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// The backups on each backup drive the Storage tab shows (#4044): listing
/// them, deleting one, and listing again when a backup is deleted, pruned or
/// completed anywhere.
///
/// Service calls arrive as function parameters defaulting to
/// [StorageService.listBackupRuns] and [StorageService.deleteBackupRun], so a
/// test passes fakes without a mocking library.
class BackupRunsController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller. [events] defaults to the app's event stream.
  /// `backup_deleted`, `backup_completed`, and `resync` list every drive
  /// again.
  BackupRunsController({
    Future<List<BackupRun>> Function(String deviceSerial) list =
        StorageService.listBackupRuns,
    Future<void> Function({required String deviceSerial, required String run})
        delete =
        StorageService.deleteBackupRun,
    Stream<FileEvent>? events,
  }) : _list = list,
       _delete = delete {
    _events = (events ?? EventsService.instance.events).listen(_onEvent);
  }

  final Future<List<BackupRun>> Function(String deviceSerial) _list;
  final Future<void> Function({
    required String deviceSerial,
    required String run,
  })
  _delete;
  late final StreamSubscription<FileEvent> _events;

  Set<String> _serials = const {};
  final Map<String, List<BackupRun>> _runs = {};
  final Map<String, Object> _errors = {};

  /// The runs on [serial], newest first, or null before its first listing
  /// and after a failed one.
  List<BackupRun>? runsFor(String serial) => _runs[serial];

  /// The thrown object from [serial]'s last failed listing. A later success
  /// clears it.
  Object? errorFor(String serial) => _errors[serial];

  /// Lists the runs on each of [serials]. A drive not among them is
  /// forgotten.
  Future<void> load(Iterable<String> serials) async {
    _serials = serials.toSet();
    _runs.removeWhere((serial, _) => !_serials.contains(serial));
    _errors.removeWhere((serial, _) => !_serials.contains(serial));
    await Future.wait(_serials.map(_loadOne));
  }

  Future<void> _loadOne(String serial) async {
    try {
      final runs = await _list(serial);
      if (!_serials.contains(serial)) return;
      _runs[serial] = runs;
      _errors.remove(serial);
    } catch (error) {
      if (!_serials.contains(serial)) return;
      _runs.remove(serial);
      _errors[serial] = error;
    }
    notifyListeners();
  }

  /// Deletes [run] from [serial] for good, then lists that drive again.
  /// Returns the thrown object when the Quark refused, or null.
  Future<Object?> delete(String serial, String run) async {
    try {
      await _delete(deviceSerial: serial, run: run);
    } catch (error) {
      return error;
    }
    await _loadOne(serial);
    return null;
  }

  void _onEvent(FileEvent event) {
    if (event.kind != 'backup_deleted' &&
        event.kind != 'backup_completed' &&
        event.kind != 'resync') {
      return;
    }
    load(_serials);
  }

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
