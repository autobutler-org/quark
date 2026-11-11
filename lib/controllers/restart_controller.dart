import 'package:flutter/foundation.dart';
import 'package:quark/models/restart_status.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/restart_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// The restart Quark section of the settings page (#4019).
///
/// After the Quark accepts a restart it keeps serving for about two seconds
/// before it exits, so the controller waits out [exitPause] and then asks for
/// the installed version every [pollInterval] until the Quark answers, or
/// gives up after [timeout].
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes and short durations without a mocking
/// library.
class RestartController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  RestartController({
    Future<RestartStatus> Function() getStatus = RestartService.getStatus,
    Future<void> Function() restart = RestartService.restart,
    Future<Object?> Function() getInstalledVersion =
        FilesService.getInstalledVersion,
    this.exitPause = const Duration(seconds: 3),
    this.pollInterval = const Duration(seconds: 1),
    this.timeout = const Duration(seconds: 90),
  }) : _getStatus = getStatus,
       _restart = restart,
       _getInstalledVersion = getInstalledVersion;

  final Future<RestartStatus> Function() _getStatus;
  final Future<void> Function() _restart;
  final Future<Object?> Function() _getInstalledVersion;

  /// How long to wait after the request before asking whether the Quark is
  /// back: longer than the two seconds it keeps serving before it exits.
  final Duration exitPause;

  /// How often to ask whether the Quark is back.
  final Duration pollInterval;

  /// How long to keep asking before saying it did not come back.
  final Duration timeout;

  RestartStatus? _status;
  bool _isWorking = false;
  bool _isRestarting = false;
  bool _isBack = false;
  String? _error;

  /// The last status the Quark sent, or null before the first load.
  RestartStatus? get status => _status;

  /// Whether the Quark can restart itself here. False until it says so.
  bool get isAvailable => _status?.available ?? false;

  /// Whether the restart request is in flight.
  bool get isWorking => _isWorking;

  /// Whether the Quark accepted a restart and has not answered since.
  bool get isRestarting => _isRestarting;

  /// Whether the last restart finished and the Quark answered again.
  bool get isBack => _isBack;

  /// User-facing copy for the last failure, or null. Always from [Errors].
  String? get error => _error;

  /// Fetches the status. A failure leaves the section hidden: the Updates
  /// tab already says when the Quark can't be reached.
  Future<void> load() async {
    try {
      _status = await _getStatus();
    } catch (error) {
      debugPrint('[restart_controller.dart] Error: $error');
    }
    notifyListeners();
  }

  /// Asks the Quark to restart and waits for it to answer again.
  Future<void> restart() async {
    _isWorking = true;
    _isBack = false;
    _error = null;
    notifyListeners();
    try {
      await _restart();
    } catch (error) {
      _error = Errors.message(error, 'restart Quark');
    }
    _isWorking = false;
    _isRestarting = _error == null;
    notifyListeners();
    if (!_isRestarting) return;

    await Future<void>.delayed(exitPause);
    final back = await _waitUntilBack();
    if (isDisposed) return;
    _isRestarting = false;
    _isBack = back;
    _error = back ? null : Errors.restartDidNotFinish;
    notifyListeners();
  }

  Future<bool> _waitUntilBack() async {
    final intervalMs = pollInterval.inMilliseconds;
    final attempts = intervalMs <= 0
        ? 1
        : (timeout.inMilliseconds ~/ intervalMs).clamp(1, 1 << 30);
    for (var i = 0; i < attempts; i++) {
      if (isDisposed) return false;
      try {
        await _getInstalledVersion();
        return true;
      } catch (_) {
        // The Quark is down while it restarts. Keep asking.
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }
}
