import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/photo_index_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/photo_location.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo library index status shown with duplicate results (#3556):
/// what the background pass has covered, pausing and resuming it, and the
/// files it could not read.
///
/// The status is admin-only on the Quark. Nothing is fetched until [start],
/// which the caller makes only for an admin; a 403 anyway (the account was
/// demoted) sets [isHidden] instead of an error, since there is nothing a
/// non-admin can be shown. `photo_index_changed` and `resync` events load
/// again; a slow answer cannot overwrite a newer one.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class PhotoIndexController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller. [events] defaults to the app's event stream.
  PhotoIndexController({
    Future<PhotoIndexStatus> Function() fetch = PhotoIndexService.fetchStatus,
    Future<PhotoIndexStatus> Function() pause = PhotoIndexService.pause,
    Future<PhotoIndexStatus> Function() resume = PhotoIndexService.resume,
    Future<List<StorageDevice>> Function() listDevices =
        StorageService.listDevices,
    Stream<FileEvent>? events,
  }) : _fetch = fetch,
       _pause = pause,
       _resume = resume,
       _listDevices = listDevices,
       _eventStream = events;

  final Future<PhotoIndexStatus> Function() _fetch;
  final Future<PhotoIndexStatus> Function() _pause;
  final Future<PhotoIndexStatus> Function() _resume;
  final Future<List<StorageDevice>> Function() _listDevices;
  final Stream<FileEvent>? _eventStream;
  StreamSubscription<FileEvent>? _events;

  PhotoIndexStatus? _status;
  List<PhotoIndexFailureItem> _failures = const [];
  Map<String, String>? _devices;
  Object? _error;
  String _errorAction = '';
  bool _isLoading = false;
  bool _isChanging = false;
  bool _isHidden = false;
  bool _showFailures = false;
  int _generation = 0;

  /// The last status, or null before the first success.
  PhotoIndexStatus? get status => _status;

  /// [status]'s failures, worded for the list.
  List<PhotoIndexFailureItem> get failures => _failures;

  /// Why the last load, pause or resume failed, or null. A later success
  /// clears it. The page words it with [errorAction].
  Object? get error => _error;

  /// What failed, as a verb phrase for [Errors.message].
  String get errorAction => _errorAction;

  /// Whether the first load is in flight.
  bool get isLoading => _isLoading;

  /// Whether a pause or resume is in flight.
  bool get isChanging => _isChanging;

  /// Whether the Quark refused the status, so nothing should be shown.
  bool get isHidden => _isHidden;

  /// Whether the failed files are listed.
  bool get showFailures => _showFailures;

  /// Follows index events and loads. Calling it again only loads.
  Future<void> start() {
    _events ??= (_eventStream ?? EventsService.instance.events).listen(
      _onEvent,
    );
    return load();
  }

  /// Fetches the status.
  Future<void> load() async {
    final generation = ++_generation;
    if (_status == null) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final status = await _fetch();
      if (!_current(generation)) return;
      await _take(status);
    } catch (error) {
      if (!_current(generation)) return;
      _fail(error, 'load the photo index status');
    } finally {
      if (_current(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Holds the pass before its next photo.
  Future<void> pause() => _change(_pause, 'pause indexing');

  /// Lets a paused pass carry on.
  Future<void> resume() => _change(_resume, 'resume indexing');

  /// Shows or hides the failed files.
  void toggleFailures() {
    _showFailures = !_showFailures;
    notifyListeners();
  }

  Future<void> _change(
    Future<PhotoIndexStatus> Function() call,
    String action,
  ) async {
    if (_isChanging) return;
    _isChanging = true;
    notifyListeners();
    // A load already in flight answered before this change; drop it.
    final generation = ++_generation;
    try {
      final status = await call();
      if (_current(generation)) await _take(status);
    } catch (error) {
      if (_current(generation)) _fail(error, action);
    } finally {
      _isChanging = false;
      notifyListeners();
    }
  }

  Future<void> _take(PhotoIndexStatus status) async {
    final devices = await _deviceNames(status.failures);
    _status = status;
    _error = null;
    _isHidden = false;
    _failures = [
      for (final f in status.failures)
        PhotoIndexFailureItem(
          id: '${f.serial}:${f.relPath}',
          name: f.relPath.substring(f.relPath.lastIndexOf('/') + 1),
          location: photoLocation(
            f.relPath,
            deviceName: f.serial.isEmpty ? null : devices[f.serial] ?? f.serial,
          ),
          reason: Errors.photoIndexFailure(f.reason),
        ),
    ];
  }

  void _fail(Object error, String action) {
    if (error is ApiException && error.statusCode == 403) {
      _isHidden = true;
      return;
    }
    _error = error;
    _errorAction = action;
  }

  /// Device names by serial, fetched once, and only when a failure is on a
  /// drive other than the internal one. A failure falls back to the serial.
  Future<Map<String, String>> _deviceNames(
    List<PhotoIndexFailure> failures,
  ) async {
    final known = _devices;
    if (known != null) return known;
    if (!failures.any((f) => f.serial.isNotEmpty)) return const {};
    try {
      return _devices = {
        for (final d in await _listDevices())
          if (d.serial.isNotEmpty) d.serial: d.name,
      };
    } catch (_) {
      return const {};
    }
  }

  void _onEvent(FileEvent event) {
    if (event.kind == 'photo_index_changed' || event.kind == 'resync') load();
  }

  bool _current(int generation) => !isDisposed && generation == _generation;

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
