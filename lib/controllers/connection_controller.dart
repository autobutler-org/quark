import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/models/this_phone_setup.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/app_log.dart';
import 'package:quark/utils/connection_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/remote_access_config.dart';
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
/// On iOS and Android the remote address is the on-device proxy in front of
/// the Quark's tailnet URL (#1881). [embeddedProxy] returns that proxy, or
/// null where the app does not embed a node, and the tailnet URL is used as
/// it stands. While a home check succeeds and this phone has no saved
/// pairing, it asks the Quark for a key, stores it, and [enroll] starts the
/// node so the proxy is up before the phone leaves home (#2876). Coming back
/// to the foreground restarts the node and checks again; the proxy port can
/// change.
///
/// Pausing remote access on this phone stops only this phone's node. It is
/// remembered across a restart, and it never calls the Quark.
///
/// Where the platform has no node of its own ([hasDeviceNode] false, the
/// desktop app today), the Quark's private remote address is out of reach:
/// away from home only a proxy [embeddedProxy] hands back is probed, the
/// device never pairs, and a pause saved earlier is ignored (#3779).
///
/// [setup] says where this phone's own remote access stands, in words with
/// the next step, and each step of pairing goes to the app log so a support
/// report can show it (#3776, #3613).
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
    Future<String?> Function(String upstream) embeddedProxy =
        EmbeddedTunnel.proxyUrl,
    Future<void> Function(String upstream) warmEmbeddedTunnel =
        EmbeddedTunnel.warm,
    void Function(void Function() onReconnected) watchEmbeddedTunnel =
        EmbeddedTunnel.watchLifecycle,
    Future<PairedDevice> Function() pairDevice = RemoteAccessService.pairDevice,
    Future<StoredPairing?> Function(String host) readPairing =
        DevicePairingStore.readPairing,
    Future<void> Function(String host, StoredPairing pairing) savePairing =
        DevicePairingStore.savePairing,
    Future<void> Function(String host) clearPairing =
        DevicePairingStore.clearPairing,
    Future<StoredPause?> Function(String host) readPause =
        DevicePairingStore.readPause,
    Future<void> Function(String host, StoredPause pause) savePause =
        DevicePairingStore.savePause,
    Future<void> Function(String host) clearPause =
        DevicePairingStore.clearPause,
    Future<void> Function({
          required String controlUrl,
          required String authKey,
          required String upstream,
        })
        enroll =
        EmbeddedTunnel.enroll,
    Future<bool> Function() nodeRejected = _appNodeRejected,
    bool Function() hasDeviceNode = _appHasDeviceNode,
    DateTime Function() now = DateTime.now,
    void Function(String message) log = _appLog,
  }) : _probe = probe,
       _readRemoteAccess = readRemoteAccess,
       _activeHost = activeHost,
       _saveRemoteAddress = saveRemoteAddress,
       _embeddedProxy = embeddedProxy,
       _warmEmbeddedTunnel = warmEmbeddedTunnel,
       _watchEmbeddedTunnel = watchEmbeddedTunnel,
       _pairDevice = pairDevice,
       _readPairing = readPairing,
       _savePairing = savePairing,
       _clearPairing = clearPairing,
       _readPause = readPause,
       _savePause = savePause,
       _clearPause = clearPause,
       _enroll = enroll,
       _nodeRejected = nodeRejected,
       _hasDeviceNode = hasDeviceNode,
       _now = now,
       _log = log,
       _activeHostChanges =
           activeHostChanges ?? AppSettings.instance.activeHostNotifier;

  /// The app's one controller.
  static final ConnectionController instance = ConnectionController();

  final Future<bool> Function(String address) _probe;
  final Future<RemoteAccessStatus?> Function() _readRemoteAccess;
  final HostEntry? Function() _activeHost;
  final Future<void> Function(String hostAddress, String? remoteAddress)
  _saveRemoteAddress;

  /// Replaces a tailnet URL with the on-device proxy in front of it.
  final Future<String?> Function(String upstream) _embeddedProxy;

  /// Starts the on-device node, or stops it when the upstream is empty.
  final Future<void> Function(String upstream) _warmEmbeddedTunnel;

  /// Registers the foreground restart. Called once from [start].
  final void Function(void Function() onReconnected) _watchEmbeddedTunnel;

  final Future<PairedDevice> Function() _pairDevice;
  final Future<StoredPairing?> Function(String host) _readPairing;
  final Future<void> Function(String host, StoredPairing pairing) _savePairing;
  final Future<void> Function(String host) _clearPairing;
  final Future<StoredPause?> Function(String host) _readPause;
  final Future<void> Function(String host, StoredPause pause) _savePause;
  final Future<void> Function(String host) _clearPause;
  final Future<void> Function({
    required String controlUrl,
    required String authKey,
    required String upstream,
  })
  _enroll;
  final Future<bool> Function() _nodeRejected;
  final bool Function() _hasDeviceNode;
  final DateTime Function() _now;

  /// Records a pairing step. Never passed a key or an address.
  final void Function(String message) _log;

  /// Fires when the active Quark changes; [AppSettings.activeHostNotifier]
  /// unless a test passes its own.
  final Listenable _activeHostChanges;

  ConnectionMode? _mode;
  String? _remoteHost;
  String? _remoteUrl;
  Timer? _timer;
  Timer? _pauseTimer;
  StoredPause? _pause;
  ThisPhoneSetup _setup = _notSetUp;

  /// Set after a rejected node drops its key, so this visit home does not
  /// immediately ask for another one. Cleared once the phone leaves home.
  bool _repairHeld = false;

  /// Whether a home probe has failed since the current pause. "Until I'm
  /// back" waits for that, then clears on the next probe that succeeds.
  /// Clearing on a probe that is already succeeding would end the pause
  /// before the phone has left.
  bool _awaySincePause = false;
  int _generation = 0;
  Duration _backoff = ConnectionConfig.offlineBackoffInitial;
  bool _started = false;

  /// What the app was doing when automatic pairing failed, for [Errors].
  static const _pairAction = 'set up remote access on this phone';

  /// How long "For 1 hour" lasts.
  static const _hour = Duration(hours: 1);

  static const _notSetUp = ThisPhoneSetup(ThisPhoneSetupState.notSetUp);

  // What [setup] says. Written for the user to read; they move into
  // `Errors` with the rest of the app's copy as a follow-up.

  /// Away from home with no pairing: only a visit home can pair.
  static const finishSetupAtHome =
      'Open Quark once on your home Wi-Fi to finish setting up remote access.';

  /// Pairing is refused with a 503, or the Quark's remote access has not
  /// connected yet.
  static const quarkStillConnecting =
      "Your Quark isn't connected to remote access yet. We'll keep trying.";

  /// Pairing is refused with a 409: the Quark has no household to add this
  /// phone to, uses a network of its own, or has remote access off.
  static const quarkCannotAddPhone =
      "Your Quark can't add this phone to remote access. Check the remote "
      "access settings on your Quark.";

  /// Remote access is off for the Quark itself.
  static const remoteAccessOffForQuark = 'Remote access is off for your Quark.';

  /// The key was refused, replaced, and the replacement refused too.
  static const keyRefusedAgain =
      "Remote access stopped working on this phone. We'll set it up again "
      "the next time you're home.";

  /// A fresh key was saved but the node did not start with it.
  static const nodeDidNotStart =
      "Remote access couldn't start on this phone. We'll try again shortly.";

  /// Shown while pairing is under way.
  static const settingUpNow = 'Setting up remote access on this phone…';

  /// Shown once this phone is paired and its node started.
  static const readyAway = 'Ready to use away from home.';

  /// How the active Quark is reached, or null before the first check and
  /// when no Quark is configured.
  ConnectionMode? get mode => _mode;

  /// Whether this device runs its own tailnet node, so remote access and
  /// its pause apply to it. False on web and on desktop.
  bool get hasDeviceNode => _hasDeviceNode();

  /// Whether remote access is paused on this phone only.
  bool get remoteAccessPaused => _pause != null;

  /// Which pause is in effect, or null when this phone is not paused.
  DevicePauseChoice? get pauseChoice => _pause?.choice;

  /// Where remote access stands on this phone for the active Quark.
  ThisPhoneSetup get setup => _setup;

  /// Why this phone cannot use remote access: setup failed, or it is away
  /// from home with no pairing yet. Null otherwise.
  String? get pairingError =>
      _setup.state == ThisPhoneSetupState.notWorking ||
          _setup.message == finishSetupAtHome
      ? _setup.message
      : null;

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
    _watchEmbeddedTunnel(() {
      unawaited(check());
    });
    _activeHostChanges.addListener(_onHostChanged);
    unawaited(_restorePause().then((_) => check()));
  }

  void _onHostChanged() {
    _backoff = ConnectionConfig.offlineBackoffInitial;
    _pauseTimer?.cancel();
    _pause = null;
    _repairHeld = false;
    _awaySincePause = false;
    _setSetup(_notSetUp);
    unawaited(_restorePause().then((_) => check()));
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
    // Only an hour that has already run out is cleared here. Awaiting when
    // there is nothing to clear would let a later check steal the first
    // probe from one that is still starting.
    if (_timedPauseElapsed()) {
      await _forgetPause(host.hostAddress);
      if (!isCurrent()) return;
    }

    if (await _reaches(host.hostAddress, ConnectionConfig.lanProbeTimeout)) {
      if (!isCurrent()) return;
      _set(ConnectionMode.local);
      if (_pause?.choice == DevicePauseChoice.untilHome && _awaySincePause) {
        await _forgetPause(host.hostAddress);
      }
      if (!isCurrent()) return;
      _settled(generation);
      await _learnRemoteAddress(host, generation, isCurrent);
      return;
    }
    if (!isCurrent()) return;

    // Away from home with this phone paused: the node stays stopped, and the
    // remote address is not probed. Leaving home is what allows the next
    // visit to pair again after a rejected key.
    _repairHeld = false;
    if (_pause?.choice == DevicePauseChoice.untilHome) _awaySincePause = true;
    if (_pause != null) {
      _set(ConnectionMode.offline);
      _settled(generation);
      return;
    }
    final stored = host.remoteAddress;
    if (stored != null) {
      final proxy = await _embeddedProxy(stored);
      if (!isCurrent()) return;
      // Without a node of its own, this device cannot reach the tailnet
      // address, so only a proxy is worth probing.
      final remote = (proxy != null && proxy.isNotEmpty)
          ? proxy
          : _hasDeviceNode()
          ? stored
          : null;
      if (remote != null &&
          await _reaches(remote, ConnectionConfig.remoteProbeTimeout)) {
        if (!isCurrent()) return;
        _set(ConnectionMode.remote, host: host.hostAddress, url: remote);
        _settled(generation);
        return;
      }
    }
    if (!isCurrent()) return;

    // Only a visit home can pair, so a phone that has never paired says so
    // rather than leaving the generic can't-reach message to explain it.
    if (!kIsWeb &&
        _hasDeviceNode() &&
        _setup.state != ThisPhoneSetupState.notWorking) {
      final pairing = await _readPairing(host.hostAddress);
      if (!isCurrent()) return;
      if (pairing == null) {
        _setSetup(
          const ThisPhoneSetup(ThisPhoneSetupState.notSetUp, finishSetupAtHome),
        );
      }
    }

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
    _timer?.cancel();
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
    int generation,
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
    if (!isCurrent()) return;
    await _ensureDeviceNode(host, remote, status, generation, isCurrent);
  }

  /// Stops this phone's node while it is paused or remote access is off, and
  /// otherwise pairs when needed and starts the node.
  ///
  /// A key the coordination server no longer accepts, whether the node
  /// dropped to NeedsLogin while running or failed to log in as this check
  /// started it (#3783), is dropped and replaced in the same check, once per
  /// visit home. A second rejection waits for the next visit.
  Future<void> _ensureDeviceNode(
    HostEntry host,
    String? remote,
    RemoteAccessStatus? status,
    int generation,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    if (_pause != null || remote == null || remote.isEmpty) {
      if (_pause == null && status != null) {
        _setSetup(
          status.enabled
              ? const ThisPhoneSetup(
                  ThisPhoneSetupState.settingUp,
                  quarkStillConnecting,
                )
              : const ThisPhoneSetup(
                  ThisPhoneSetupState.notSetUp,
                  remoteAccessOffForQuark,
                ),
        );
      }
      await _warmEmbeddedTunnel('');
      return;
    }
    if (kIsWeb || !_hasDeviceNode()) {
      await _warmEmbeddedTunnel(remote);
      return;
    }
    var pairing = await _readPairing(host.hostAddress);
    if (!isCurrent()) return;
    var rejected = pairing != null && await _nodeRejected();
    while (true) {
      if (!isCurrent()) return;
      if (rejected) {
        _note('Remote access key refused; dropping it');
        await _clearPairing(host.hostAddress);
        await _warmEmbeddedTunnel('');
        pairing = null;
        if (!isCurrent()) return;
        if (_repairHeld) {
          _note('Refused again this visit; waiting for the next visit home');
          _setSetup(
            const ThisPhoneSetup(
              ThisPhoneSetupState.notWorking,
              keyRefusedAgain,
            ),
          );
          return;
        }
        _repairHeld = true;
      }
      if (pairing == null) {
        if (_repairHeld && !rejected) {
          await _warmEmbeddedTunnel(remote);
          return;
        }
        if (status == null || !status.enabled || !status.connected) {
          _note('Quark remote access not connected yet; not pairing');
          _setSetup(
            const ThisPhoneSetup(
              ThisPhoneSetupState.settingUp,
              quarkStillConnecting,
            ),
          );
          await _warmEmbeddedTunnel(remote);
          return;
        }
        pairing = await _pair(host.hostAddress, generation, isCurrent);
        if (!isCurrent()) return;
        if (pairing == null) {
          await _warmEmbeddedTunnel(remote);
          return;
        }
      }
      await _warmEmbeddedTunnel(remote);
      if (!isCurrent()) return;
      rejected = await _nodeRejected();
      if (!isCurrent()) return;
      if (!rejected) break;
    }
    _note('Remote access on this phone is ready');
    _setSetup(const ThisPhoneSetup(ThisPhoneSetupState.ready, readyAway));
  }

  /// Asks the Quark for a key and starts the node. Null means it did not
  /// pair or the node did not start: a 409 waits for the next check, a 503
  /// waits [RemoteAccessConfig.statusPollInterval], and [setup] says which.
  Future<StoredPairing?> _pair(
    String host,
    int generation,
    bool Function() isCurrent,
  ) async {
    _note('Asking the Quark to pair this phone');
    _setSetup(
      const ThisPhoneSetup(ThisPhoneSetupState.settingUp, settingUpNow),
    );
    try {
      final paired = await _pairDevice();
      if (!isCurrent()) return null;
      final stored = StoredPairing(
        authKey: paired.authKey,
        controlUrl: paired.controlUrl,
        quarkAddress: paired.quarkAddress,
      );
      await _savePairing(host, stored);
      if (!isCurrent()) return null;
      _note('Paired; starting the node');
      try {
        await _enroll(
          controlUrl: stored.controlUrl,
          authKey: stored.authKey,
          upstream: stored.quarkAddress,
        );
      } catch (error, stack) {
        _note('Node did not start: $error');
        debugPrint('$stack');
        if (isCurrent()) {
          _setSetup(
            const ThisPhoneSetup(
              ThisPhoneSetupState.notWorking,
              nodeDidNotStart,
            ),
          );
        }
        return null;
      }
      if (!isCurrent()) return null;
      return stored;
    } on ApiException catch (error) {
      if (!isCurrent()) return null;
      _note('Pairing refused with ${error.statusCode}');
      if (error.statusCode == 409) {
        _setSetup(
          const ThisPhoneSetup(
            ThisPhoneSetupState.notWorking,
            quarkCannotAddPhone,
          ),
        );
        return null;
      }
      if (error.statusCode == 503) {
        _setSetup(
          const ThisPhoneSetup(
            ThisPhoneSetupState.settingUp,
            quarkStillConnecting,
          ),
        );
        _schedule(generation, RemoteAccessConfig.statusPollInterval);
        return null;
      }
      _setSetup(
        ThisPhoneSetup(
          ThisPhoneSetupState.notWorking,
          Errors.message(error, _pairAction),
        ),
      );
      return null;
    } catch (error, stack) {
      if (!isCurrent()) return null;
      _note('Pairing failed: $error');
      debugPrint('$stack');
      _setSetup(
        ThisPhoneSetup(
          ThisPhoneSetupState.notWorking,
          Errors.message(error, _pairAction),
        ),
      );
      return null;
    }
  }

  /// Pauses remote access on this phone only. Nothing is sent to the Quark.
  Future<void> pause(DevicePauseChoice choice) async {
    _timer?.cancel();
    _generation++;
    _awaySincePause = false;
    final until = choice == DevicePauseChoice.hour ? _now().add(_hour) : null;
    _pause = StoredPause(choice: choice, until: until);
    final host = _activeHost()?.hostAddress;
    if (host != null) await _savePause(host, _pause!);
    _armPauseTimer();
    if (_mode == ConnectionMode.remote) _set(ConnectionMode.offline);
    notifyListeners();
    await _warmEmbeddedTunnel('');
    _schedule(_generation, ConnectionConfig.recheckInterval);
  }

  /// Ends this phone's pause and starts its node again.
  Future<void> resumeRemoteAccess() async {
    final host = _activeHost()?.hostAddress;
    await _forgetPause(host);
    final remote = _activeHost()?.remoteAddress;
    if (remote != null && remote.isNotEmpty) {
      await _warmEmbeddedTunnel(remote);
    }
    await check();
  }

  Future<void> _restorePause() async {
    final host = _activeHost()?.hostAddress;
    if (host == null || !_hasDeviceNode()) return;
    final stored = await _readPause(host);
    if (stored == null) return;
    final until = stored.until;
    if (stored.choice == DevicePauseChoice.hour &&
        (until == null || !until.isAfter(_now()))) {
      await _clearPause(host);
      return;
    }
    _pause = stored;
    _armPauseTimer();
    notifyListeners();
  }

  /// Whether an hour-long pause has reached its time.
  bool _timedPauseElapsed() {
    final pause = _pause;
    final until = pause?.until;
    if (pause?.choice != DevicePauseChoice.hour || until == null) return false;
    return !until.isAfter(_now());
  }

  Future<void> _forgetPause(String? host) async {
    _pauseTimer?.cancel();
    _pause = null;
    _awaySincePause = false;
    if (host != null) await _clearPause(host);
    notifyListeners();
  }

  void _armPauseTimer() {
    _pauseTimer?.cancel();
    final until = _pause?.until;
    if (until == null) return;
    final remaining = until.difference(_now());
    if (remaining <= Duration.zero) {
      final host = _activeHost()?.hostAddress;
      if (host != null) unawaited(_forgetPause(host));
      return;
    }
    _pauseTimer = Timer(remaining, () {
      unawaited(resumeRemoteAccess());
    });
  }

  void _setSetup(ThisPhoneSetup setup) {
    if (setup == _setup) return;
    _setup = setup;
    notifyListeners();
  }

  /// Logs a pairing step to the console and the app log.
  void _note(String message) {
    debugPrint('[connection_controller.dart] $message');
    _log(message);
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
    _pauseTimer?.cancel();
    if (_started) {
      _activeHostChanges.removeListener(_onHostChanged);
    }
    super.dispose();
  }

  static bool _appHasDeviceNode() => EmbeddedTunnel.isSupported;

  static void _appLog(String message) =>
      AppLog.instance.info('Remote access: $message');

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

  static Future<bool> _appNodeRejected() async {
    if (!EmbeddedTunnel.isSupported) return false;
    return isRejected(await EmbeddedTunnel.status());
  }

  /// `NeedsLogin` is the bridge's report that the key expired, the node was
  /// removed, or the last start could not log in. Anything else keeps the
  /// saved pairing.
  @visibleForTesting
  static bool isRejected(TunnelStatus status) => status.state == 'NeedsLogin';
}
