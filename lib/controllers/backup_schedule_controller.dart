import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// The schedule of each backup drive the Storage tab shows (#3984): reading
/// them, saving one, and reading them again when a schedule changes
/// anywhere.
///
/// Service calls arrive as function parameters defaulting to
/// [StorageService.getBackupSchedule] and [StorageService.setBackupSchedule],
/// so a test passes fakes without a mocking library.
class BackupScheduleController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller. [events] defaults to the app's event stream.
  /// `backup_schedule_changed` and `resync` read every drive again.
  BackupScheduleController({
    Future<BackupSchedule> Function(String deviceSerial) get =
        StorageService.getBackupSchedule,
    Future<BackupSchedule> Function({
          required String deviceSerial,
          required BackupCadence cadence,
          required List<String> sourceSerials,
        })
        set =
        StorageService.setBackupSchedule,
    Stream<FileEvent>? events,
  }) : _get = get,
       _set = set {
    _events = (events ?? EventsService.instance.events).listen(_onEvent);
  }

  final Future<BackupSchedule> Function(String deviceSerial) _get;
  final Future<BackupSchedule> Function({
    required String deviceSerial,
    required BackupCadence cadence,
    required List<String> sourceSerials,
  })
  _set;
  late final StreamSubscription<FileEvent> _events;

  Set<String> _serials = const {};
  final Map<String, BackupSchedule> _schedules = {};

  /// The schedule of [serial], or null before it is read and after a failed
  /// read.
  BackupSchedule? scheduleFor(String serial) => _schedules[serial];

  /// Reads the schedule of each of [serials]. A drive not among them is
  /// forgotten.
  Future<void> load(Iterable<String> serials) async {
    _serials = serials.toSet();
    _schedules.removeWhere((serial, _) => !_serials.contains(serial));
    await Future.wait(_serials.map(_loadOne));
  }

  Future<void> _loadOne(String serial) async {
    try {
      final schedule = await _get(serial);
      if (!_serials.contains(serial)) return;
      _schedules[serial] = schedule;
    } catch (error) {
      // The card leaves out what it cannot read; saving still works.
      debugPrint('[backup_schedule_controller.dart] $serial: $error');
      _schedules.remove(serial);
    }
    notifyListeners();
  }

  /// Saves the schedule of [deviceSerial] and returns the Quark's answer,
  /// whose [BackupSchedule.jobId] is a backup it started. Throws when the
  /// Quark refused.
  Future<BackupSchedule> save({
    required String deviceSerial,
    required BackupCadence cadence,
    required List<String> sourceSerials,
  }) async {
    final saved = await _set(
      deviceSerial: deviceSerial,
      cadence: cadence,
      sourceSerials: sourceSerials,
    );
    if (_serials.contains(deviceSerial)) {
      _schedules[deviceSerial] = saved;
      notifyListeners();
    }
    return saved;
  }

  void _onEvent(FileEvent event) {
    if (event.kind != 'backup_schedule_changed' && event.kind != 'resync') {
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
