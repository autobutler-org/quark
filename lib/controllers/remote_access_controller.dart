import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/remote_access_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Remote access on the Settings Network tab (#2857): the Quark's status,
/// turning it on and off, and the stage the setup sheet is at.
///
/// While remote access is on but the Quark has not joined its private
/// network, the controller re-reads the status every
/// [RemoteAccessConfig.statusPollInterval], so Connecting… turns into On (or
/// Couldn't connect) without a reload. The poll stops once it settles.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class RemoteAccessController extends ChangeNotifier {
  /// Creates a controller talking to the real [RemoteAccessService] unless
  /// overridden.
  RemoteAccessController({
    Future<RemoteAccessStatus> Function() getStatus =
        RemoteAccessService.getStatus,
    Future<RemoteAccessStatus> Function() enable = RemoteAccessService.enable,
    Future<RemoteAccessStatus> Function() disable = RemoteAccessService.disable,
    Duration pollInterval = RemoteAccessConfig.statusPollInterval,
  }) : _getStatus = getStatus,
       _enable = enable,
       _disable = disable,
       _pollInterval = pollInterval;

  final Future<RemoteAccessStatus> Function() _getStatus;
  final Future<RemoteAccessStatus> Function() _enable;
  final Future<RemoteAccessStatus> Function() _disable;
  final Duration _pollInterval;

  RemoteAccessStatus? _status;
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  Object? _loadFailure;
  Timer? _poll;
  bool _disposed = false;

  /// The last status the Quark sent, or null before the first load.
  RemoteAccessStatus? get status => _status;

  /// What remote access is doing, as the panel shows it.
  RemoteAccessState get state => stateOf(_status);

  /// Whether the status is being read for the first time.
  bool get isLoading => _isLoading;

  /// Whether turning remote access on or off is in flight.
  bool get isWorking => _isWorking;

  /// Why the status could not be read, from [Errors], or null.
  String? get error => _error;

  /// What the last [load] threw, or null when it succeeded, so the page can
  /// tell an unreachable Quark from any other failure.
  Object? get loadFailure => _loadFailure;

  /// Where the setup sheet is: turning on, then connecting, then done. A
  /// failure sends the sheet away, so it never needs a stage of its own.
  RemoteAccessSetupStage get setupStage {
    if (_isWorking) return RemoteAccessSetupStage.preparing;
    return switch (state) {
      RemoteAccessState.connecting => RemoteAccessSetupStage.connecting,
      RemoteAccessState.on => RemoteAccessSetupStage.done,
      RemoteAccessState.off ||
      RemoteAccessState.failing => RemoteAccessSetupStage.intro,
    };
  }

  /// [status] as a [RemoteAccessState]. Switched on is the Quark's setting;
  /// connected is a separate fact that can lag it or never arrive (#1815).
  static RemoteAccessState stateOf(RemoteAccessStatus? status) {
    if (status == null || !status.enabled) return RemoteAccessState.off;
    if (status.error != null) return RemoteAccessState.failing;
    if (!status.connected) return RemoteAccessState.connecting;
    return RemoteAccessState.on;
  }

  /// Reads the status.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _notify();
    try {
      _set(await _getStatus());
      _loadFailure = null;
    } catch (error) {
      debugPrint('[remote_access_controller.dart] Load failed: $error');
      _loadFailure = error;
      _error = Errors.message(error, 'load remote access');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Forgets the status, for when no Quark is set.
  void clear() {
    _status = null;
    _error = null;
    _loadFailure = null;
    _isLoading = false;
    _syncPoll();
    _notify();
  }

  /// Turns remote access on. Null on success, else what to tell the user.
  Future<String?> enable() => _change(_enable, 'turn on remote access');

  /// Turns remote access off for everyone. Null on success, else what to
  /// tell the user.
  Future<String?> disable() => _change(_disable, 'turn off remote access');

  Future<String?> _change(
    Future<RemoteAccessStatus> Function() call,
    String action,
  ) async {
    _isWorking = true;
    _notify();
    try {
      _set(await call());
      return null;
    } catch (error) {
      debugPrint('[remote_access_controller.dart] $action failed: $error');
      return Errors.message(error, action);
    } finally {
      _isWorking = false;
      _notify();
    }
  }

  void _set(RemoteAccessStatus status) {
    if (status.error != null) {
      // A diagnostic from the network layer: for the log, never the screen.
      debugPrint('[remote_access_controller.dart] Failing: ${status.error}');
    }
    _status = status;
    _error = null;
    _syncPoll();
  }

  /// Polls while remote access is on and not yet connected, and stops
  /// otherwise.
  void _syncPoll() {
    final status = _status;
    if (_disposed || status == null || !status.enabled || status.connected) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  /// One quiet read: no loader, and a failure keeps the last status on
  /// screen for the next tick to replace.
  Future<void> _pollOnce() async {
    try {
      final status = await _getStatus();
      if (_disposed) return;
      _set(status);
      _notify();
    } catch (error) {
      debugPrint('[remote_access_controller.dart] Poll failed: $error');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
