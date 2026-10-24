import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Storage tab's protection card: the level the Quark reported, and a
/// reload when a backup completes or fails.
///
/// Service calls arrive as function parameters defaulting to
/// [DataProtectionService.fetch], so a test passes a fake without a mocking
/// library. [level] is that response's level. A drive list that disagrees
/// with it is still shown as sent; this controller does not count copies.
class DataProtectionController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller. [events] defaults to the app's event stream.
  /// `backup_completed`, `backup_failed`, and `resync` load again.
  DataProtectionController({
    Future<DataProtectionStatus> Function() fetch = DataProtectionService.fetch,
    Stream<FileEvent>? events,
  }) : _fetch = fetch {
    _events = (events ?? EventsService.instance.events).listen(_onEvent);
  }

  final Future<DataProtectionStatus> Function() _fetch;
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
  DataProtectionLevel? get level => switch (_status?.level) {
    'unprotected' => DataProtectionLevel.unprotected,
    'basic' => DataProtectionLevel.basic,
    'protected' => DataProtectionLevel.protected,
    _ => null,
  };

  /// [status]'s drives, mapped for the card. The order is the response's.
  List<DataProtectionDrive> get drives {
    final drives = _status?.drives;
    if (drives == null) return const [];
    return [
      for (var i = 0; i < drives.length; i++)
        DataProtectionDrive(
          id: drives[i].serial.isNotEmpty ? drives[i].serial : 'drive_$i',
          name: drives[i].name.isNotEmpty
              ? drives[i].name
              : (drives[i].serial.isNotEmpty
                    ? drives[i].serial
                    : 'Backup drive'),
          lastBackedUp: drives[i].lastBackedUp,
          reason: drives[i].reason,
        ),
    ];
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
