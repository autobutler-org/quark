import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/connection_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Picks the address the app reaches the active Quark on: its home address,
/// its remote-access address, or neither (#1880).
///
/// A check probes the home address first and the remote-access address
/// second, with the timeouts in [ConnectionConfig]. While either works it
/// checks again every [ConnectionConfig.recheckInterval], so a phone on the
/// remote address moves back home once the home address answers again, and
/// one at home notices having left. While neither answers it retries with a
/// doubling backoff.
///
/// Each successful home check also re-reads `GET /settings/remote-access` and
/// records the Quark's remote address on its [HostEntry], or clears it once
/// remote access is off. That is how an address saved before remote access
/// existed learns one.
///
/// [baseUrl] is what `apiBaseUrl` reads, so every request the app makes
/// follows the switch. [mode] feeds the app bar's [ConnectionIndicator].
///
/// Service calls arrive as function parameters defaulting to the real ones,
/// so a test passes fakes and never touches the network.
class ConnectionController extends ChangeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  ConnectionController({
    Future<bool> Function(String address) probe = AuthService.isReachable,
    Future<RemoteAccessStatus?> Function() readRemoteAccess = _appRemoteAccess,
    HostEntry? Function() activeHost = _appActiveHost,
    Future<void> Function(String hostAddress, String? remoteAddress)
        saveRemoteAddress =
        _appSaveRemoteAddress,
    Listenable? activeHostChanges,
  }) : _probe = probe,
       _readRemoteAccess = readRemoteAccess,
       _activeHost = activeHost,
       _saveRemoteAddress = saveRemoteAddress,
       _activeHostChanges =
           activeHostChanges ?? AppSettings.instance.activeHostNotifier;

  /// The app's one controller.
  static final ConnectionController instance = ConnectionController();

  final Future<bool> Function(String address) _probe;
  final Future<RemoteAccessStatus?> Function() _readRemoteAccess;
  final HostEntry? Function() _activeHost;
  final Future<void> Function(String hostAddress, String? remoteAddress)
  _saveRemoteAddress;

  /// Fires when the active Quark changes; [AppSettings.activeHostNotifier]
  /// unless a test passes its own.
  final Listenable _activeHostChanges;

  ConnectionMode? _mode;
  String? _remoteHost;
  String? _remoteUrl;
  Timer? _timer;
  int _generation = 0;
  Duration _backoff = ConnectionConfig.offlineBackoffInitial;
  bool _started = false;

  /// How the active Quark is reached, or null before the first check and
  /// when no Quark is configured.
  ConnectionMode? get mode => _mode;

  /// The remote-access address requests go to instead of the active host's
  /// own, or null to use the active host's.
  ///
  /// Tied to the host it was chosen for, so a switch of Quark never sends a
  /// request to the previous one's remote address, even before the next
  /// check has run.
  String? get baseUrl {
    if (_mode != ConnectionMode.remote) return null;
    final host = _activeHost()?.hostAddress;
    return host != null && host == _remoteHost ? _remoteUrl : null;
  }

  /// Checks now, and again whenever the active Quark changes.
  ///
  /// Does nothing on web: the Quark serves the web app itself, so the page is
  /// already on whichever address the browser used and there is nothing to
  /// switch.
  void start() {
    if (kIsWeb || _started) return;
    _started = true;
    _activeHostChanges.addListener(_onHostChanged);
    unawaited(check());
  }

  void _onHostChanged() {
    _backoff = ConnectionConfig.offlineBackoffInitial;
    unawaited(check());
  }

  /// Probes the active Quark's addresses and settles [mode] and [baseUrl].
  ///
  /// A check started later wins: one still waiting on a probe when the host
  /// changes or another check starts drops its answer.
  Future<void> check() async {
    _timer?.cancel();
    final generation = ++_generation;
    bool isCurrent() => generation == _generation;

    final host = _activeHost();
    if (host == null) {
      _set(null);
      return;
    }

    if (await _reaches(host.hostAddress, ConnectionConfig.lanProbeTimeout)) {
      if (!isCurrent()) return;
      _set(ConnectionMode.local);
      _settled(generation);
      await _learnRemoteAddress(host, isCurrent);
      return;
    }
    if (!isCurrent()) return;

    final remote = host.remoteAddress;
    if (remote != null &&
        await _reaches(remote, ConnectionConfig.remoteProbeTimeout)) {
      if (!isCurrent()) return;
      _set(ConnectionMode.remote, host: host.hostAddress, url: remote);
      _settled(generation);
      return;
    }
    if (!isCurrent()) return;

    _set(ConnectionMode.offline);
    _schedule(generation, _backoff);
    final doubled = _backoff * 2;
    _backoff = doubled > ConnectionConfig.offlineBackoffMax
        ? ConnectionConfig.offlineBackoffMax
        : doubled;
  }

  /// Resets the offline backoff and schedules the next routine check.
  void _settled(int generation) {
    _backoff = ConnectionConfig.offlineBackoffInitial;
    _schedule(generation, ConnectionConfig.recheckInterval);
  }

  void _schedule(int generation, Duration after) {
    _timer = Timer(after, () {
      if (generation == _generation) unawaited(check());
    });
  }

  Future<bool> _reaches(String address, Duration timeout) async {
    try {
      return await _probe(address).timeout(timeout);
    } catch (_) {
      // A timeout and a refusal both mean the address is not answering.
      return false;
    }
  }

  /// Records the Quark's current remote-access address on [host].
  ///
  /// Runs only right after a home check succeeds, so the request goes to the
  /// home address and the answer is about this Quark. A Quark that is enabled
  /// but not connected yet keeps whatever address it had; one with remote
  /// access off loses it.
  Future<void> _learnRemoteAddress(
    HostEntry host,
    bool Function() isCurrent,
  ) async {
    final RemoteAccessStatus? status;
    try {
      status = await _readRemoteAccess();
    } catch (_) {
      return;
    }
    if (status == null || !isCurrent()) return;
    final url = status.remoteUrl;
    final remote = !status.enabled
        ? null
        : status.connected && url != null && url.isNotEmpty
        ? url
        : host.remoteAddress;
    if (remote != host.remoteAddress) {
      await _saveRemoteAddress(host.hostAddress, remote);
    }
  }

  void _set(ConnectionMode? mode, {String? host, String? url}) {
    if (mode == _mode && host == _remoteHost && url == _remoteUrl) return;
    _mode = mode;
    _remoteHost = host;
    _remoteUrl = url;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    if (_started) {
      _activeHostChanges.removeListener(_onHostChanged);
    }
    super.dispose();
  }

  static HostEntry? _appActiveHost() => AppSettings.instance.activeHostEntry;

  /// The status only a signed-in user can read; null without a session, so
  /// the check sends nothing the Quark would refuse.
  static Future<RemoteAccessStatus?> _appRemoteAccess() async =>
      AppSettings.instance.sessionToken == null
      ? null
      : RemoteAccessService.getStatus();

  static Future<void> _appSaveRemoteAddress(
    String hostAddress,
    String? remoteAddress,
  ) => AppSettings.instance.setRemoteAddress(hostAddress, remoteAddress);
}
