import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/services/remote_access_service.dart';
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
/// the Quark's tailnet URL (#1881). [embeddedProxy] returns that proxy.
/// Where this build has no on-device node, the Quark's private tailnet
/// address is not probed: a desktop cannot reach it (#3779). A proxy the
/// node returns is still probed, which is how a future desktop node (#2877)
/// says it can reach the Quark. While a home check succeeds and this phone
/// has no saved pairing, it asks the Quark for a key, [enroll] starts the
/// node, and only then is the pairing stored, so the proxy is up before the
/// phone leaves home (#2876). Coming back to the foreground restarts the
/// node and checks again; the proxy port can change.
///
/// Setting up heals itself (#3776). A stored pairing whose node does not run,
/// or whose key the Quark no longer accepts, is dropped on the next check at
/// home and the phone pairs again in that same check. [phoneRemoteAccess] and
/// [phoneRemoteAccessDetail] say where that stands in words a user reads,
/// including the Quark's own refusals, and [setupLog] keeps each step for
/// diagnostics.
///
/// Pausing remote access on this phone stops only this phone's node. It is
/// remembered across a restart, and it never calls the Quark.
///
/// Signing out calls [forgetDevice], which stops the node and drops this
/// phone's pairing, so the next account to sign in pairs afresh (#3785).
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
    bool? hasOnDeviceNode,
    Future<void> Function(String upstream) warmEmbeddedTunnel =
        EmbeddedTunnel.warm,
    Future<void> Function() forgetEmbeddedTunnel = EmbeddedTunnel.forget,
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
    Future<TunnelStatus?> Function() nodeStatus = _appNodeStatus,
    DateTime Function() now = DateTime.now,
  }) : _probe = probe,
       _readRemoteAccess = readRemoteAccess,
       _activeHost = activeHost,
       _saveRemoteAddress = saveRemoteAddress,
       _embeddedProxy = embeddedProxy,
       _hasOnDeviceNode = hasOnDeviceNode ?? EmbeddedTunnel.isSupported,
       _warmEmbeddedTunnel = warmEmbeddedTunnel,
       _forgetEmbeddedTunnel = forgetEmbeddedTunnel,
       _watchEmbeddedTunnel = watchEmbeddedTunnel,
       _pairDevice = pairDevice,
       _readPairing = readPairing,
       _savePairing = savePairing,
       _clearPairing = clearPairing,
       _readPause = readPause,
       _savePause = savePause,
       _clearPause = clearPause,
       _enroll = enroll,
       _nodeStatus = nodeStatus,
       _now = now,
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

  /// Whether this platform runs an on-device node. False on desktop, web,
  /// and in tests unless one opts into the phone. A proxy from
  /// [_embeddedProxy] is probed either way (#3779).
  final bool _hasOnDeviceNode;

  /// Starts the on-device node, or stops it when the upstream is empty.
  final Future<void> Function(String upstream) _warmEmbeddedTunnel;

  /// Stops the on-device node and deletes its state.
  final Future<void> Function() _forgetEmbeddedTunnel;

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

  /// This phone's node, or null where the app does not embed one.
  final Future<TunnelStatus?> Function() _nodeStatus;
  final DateTime Function() _now;

  /// Fires when the active Quark changes; [AppSettings.activeHostNotifier]
  /// unless a test passes its own.
  final Listenable _activeHostChanges;

  ConnectionMode? _mode;
  String? _remoteHost;
  String? _remoteUrl;
  Timer? _timer;
  Timer? _pauseTimer;
  StoredPause? _pause;
  PhoneRemoteAccess _phone = PhoneRemoteAccess.notSetUp;
  String? _phoneDetail;
  final List<String> _setupLog = [];

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

  /// How many steps [setupLog] keeps.
  static const _setupLogLength = 50;

  /// How the active Quark is reached, or null before the first check and
  /// when no Quark is configured.
  ConnectionMode? get mode => _mode;

  /// Whether remote access is paused on this phone only.
  bool get remoteAccessPaused => _pause != null;

  /// Whether this phone's remote access switch reads on: not paused, and
  /// paired or on the way to it. A phone that never paired reads off.
  bool get remoteAccessOnThisPhone =>
      _pause == null && _phone != PhoneRemoteAccess.notSetUp;

  /// Which pause is in effect, or null when this phone is not paused.
  DevicePauseChoice? get pauseChoice => _pause?.choice;

  /// Where remote access on this phone stands.
  PhoneRemoteAccess get phoneRemoteAccess => _phone;

  /// [phoneRemoteAccess] in a sentence for the user, or null while paused
  /// and when the state says it all. Away from home with no pairing this is
  /// [Errors.finishRemoteAccessAtHome].
  String? get phoneRemoteAccessDetail => _pause != null
      ? null
      : _phoneDetail ?? (_mode == ConnectionMode.local ? null : _finishAtHome);

  /// Why this phone's remote access is not working, in [Errors]' words, or
  /// null while it is not [PhoneRemoteAccess.notWorking].
  String? get pairingError =>
      _phone == PhoneRemoteAccess.notWorking ? _phoneDetail : null;

  /// What to tell a user the Quark is out of reach for when it is because
  /// this phone never paired, or null. Only set while offline.
  String? get offlineReason =>
      _mode == ConnectionMode.offline ? _finishAtHome : null;

  /// The latest setup steps, oldest first, each stamped with its time. For
  /// the diagnostics a user can send (#3613); never shown as status.
  List<String> get setupLog => List.unmodifiable(_setupLog);

  String? get _finishAtHome =>
      _phone == PhoneRemoteAccess.notSetUp && _pause == null
      ? Errors.finishRemoteAccessAtHome
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
    unawaited(_restore().then((_) => check()));
  }

  void _onHostChanged() {
    _backoff = ConnectionConfig.offlineBackoffInitial;
    _pauseTimer?.cancel();
    _pause = null;
    _awaySincePause = false;
    unawaited(_restore().then((_) => check()));
  }

  /// Reads the active Quark's pause and whether this phone paired with it.
  Future<void> _restore() async {
    await _restorePause();
    final host = _activeHost()?.hostAddress;
    final stored = host == null ? null : await _readPairing(host);
    _setPhone(
      stored == null ? PhoneRemoteAccess.notSetUp : PhoneRemoteAccess.ready,
    );
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
    // remote address is not probed.
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
      // No on-device node means this device cannot reach the Quark's private
      // tailnet address. Probe only a proxy the node hands back, which is
      // how a future desktop node (#2877) says it can reach the Quark.
      final remote = (proxy != null && proxy.isNotEmpty)
          ? proxy
          : _hasOnDeviceNode
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

  /// Stops this phone's node while it is paused or has nothing to reach,
  /// keeps a working pairing running, and otherwise pairs and starts the
  /// node.
  ///
  /// A stored pairing whose node is not running, or whose key the Quark no
  /// longer accepts, is dropped and replaced in this same check: the phone
  /// is home, which is the one place it can pair.
  Future<void> _ensureDeviceNode(
    HostEntry host,
    String? remote,
    RemoteAccessStatus status,
    int generation,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    if (_pause != null || remote == null || remote.isEmpty) {
      await _warmEmbeddedTunnel('');
      if (_pause != null || !isCurrent()) return;
      if (!status.enabled) {
        _setPhone(PhoneRemoteAccess.notSetUp, Errors.quarkRemoteAccessOff);
      } else {
        _setPhone(
          PhoneRemoteAccess.settingUp,
          Errors.quarkRemoteAccessNotConnected,
        );
      }
      return;
    }
    if (kIsWeb) {
      await _warmEmbeddedTunnel(remote);
      return;
    }
    final stored = await _readPairing(host.hostAddress);
    if (!isCurrent()) return;
    if (stored != null) {
      await _warmEmbeddedTunnel(remote);
      if (!isCurrent()) return;
      final node = await _nodeStatus();
      if (!isCurrent()) return;
      final state = node?.state;
      final rejected = state == 'NeedsLogin' || state == 'NeedsMachineAuth';
      final running = node == null || state == 'Running' || state == 'Starting';
      if (!rejected && running) {
        _setPhone(PhoneRemoteAccess.ready);
        return;
      }
      _log(
        rejected
            ? 'the Quark rejected this phone\'s key; dropping the pairing'
            : 'the node is $state with a stored pairing '
                  '(${node?.error}); dropping the pairing',
      );
      await _clearPairing(host.hostAddress);
      await _warmEmbeddedTunnel('');
      if (!isCurrent()) return;
      _setPhone(
        PhoneRemoteAccess.notWorking,
        rejected
            ? Errors.phoneRemoteAccessRejected
            : Errors.phoneRemoteAccessDidNotStart,
      );
    }
    if (!status.connected) {
      _setPhone(
        PhoneRemoteAccess.settingUp,
        Errors.quarkRemoteAccessNotConnected,
      );
      return;
    }
    if (await _pair(host.hostAddress, generation, isCurrent)) {
      await _warmEmbeddedTunnel(remote);
    }
  }

  /// Asks the Quark for a key, starts the node, and stores the pairing once
  /// the node runs. False means it did not pair, with the reason on
  /// [phoneRemoteAccessDetail]: a 409 and a node that did not start wait for
  /// the next check, and a 503 waits [RemoteAccessConfig.statusPollInterval].
  Future<bool> _pair(
    String host,
    int generation,
    bool Function() isCurrent,
  ) async {
    _setPhone(PhoneRemoteAccess.settingUp);
    _log('asking the Quark for a key');
    final PairedDevice paired;
    try {
      paired = await _pairDevice();
    } catch (error) {
      if (!isCurrent()) return false;
      _log('the Quark did not pair this phone: $error');
      switch (error) {
        case ApiException(statusCode: 409):
          _setPhone(PhoneRemoteAccess.notWorking, Errors.quarkRefusedThisPhone);
        case ApiException(statusCode: 503):
          _setPhone(
            PhoneRemoteAccess.settingUp,
            Errors.quarkRemoteAccessNotConnected,
          );
          _schedule(generation, RemoteAccessConfig.statusPollInterval);
        default:
          _setPhone(
            PhoneRemoteAccess.notWorking,
            Errors.message(error, _pairAction),
          );
      }
      return false;
    }
    if (!isCurrent()) return false;
    _log('starting this phone\'s node');
    try {
      await _enroll(
        controlUrl: paired.controlUrl,
        authKey: paired.authKey,
        upstream: paired.quarkAddress,
      );
    } catch (error) {
      if (!isCurrent()) return false;
      // Nothing was stored, so the next check at home pairs again.
      _log('the node did not start: $error');
      await _warmEmbeddedTunnel('');
      _setPhone(
        PhoneRemoteAccess.notWorking,
        Errors.phoneRemoteAccessDidNotStart,
      );
      return false;
    }
    if (!isCurrent()) return false;
    await _savePairing(
      host,
      StoredPairing(
        authKey: paired.authKey,
        controlUrl: paired.controlUrl,
        quarkAddress: paired.quarkAddress,
      ),
    );
    if (!isCurrent()) return false;
    _setPhone(PhoneRemoteAccess.ready);
    return true;
  }

  /// Stops this phone's node, deletes its state, and drops the pairing saved
  /// for the active Quark (#3785).
  ///
  /// Signing out and deleting the account call it, so a phone that changes
  /// hands keeps no way onto the household's tailnet, and the next account to
  /// sign in pairs for itself the next time it is home. A check already in
  /// flight is dropped, so it cannot start the node again; a started
  /// controller checks again after [ConnectionConfig.recheckInterval].
  Future<void> forgetDevice() async {
    _timer?.cancel();
    _generation++;
    _setPhone(PhoneRemoteAccess.notSetUp);
    if (_mode == ConnectionMode.remote) _set(ConnectionMode.offline);
    await _forgetEmbeddedTunnel();
    final host = _activeHost()?.hostAddress;
    if (host != null) await _clearPairing(host);
    if (_started) _schedule(_generation, ConnectionConfig.recheckInterval);
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
    if (host == null) return;
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

  /// Moves this phone to [state], logging the change.
  void _setPhone(PhoneRemoteAccess state, [String? detail]) {
    if (state == _phone && detail == _phoneDetail) return;
    _phone = state;
    _phoneDetail = detail;
    _log('this phone is ${state.name}${detail == null ? '' : ': $detail'}');
    notifyListeners();
  }

  /// Records one setup step for [setupLog] and the platform log.
  void _log(String step) {
    developer.log(step, name: 'quark.remote_access');
    _setupLog.add('${_now().toUtc().toIso8601String()} $step');
    if (_setupLog.length > _setupLogLength) _setupLog.removeAt(0);
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

  /// The embedded node's status, or null where the app does not embed one,
  /// so a desktop build never drops its pairing over a node it has not got.
  static Future<TunnelStatus?> _appNodeStatus() async =>
      EmbeddedTunnel.isSupported ? EmbeddedTunnel.status() : null;
}

/// Where remote access on this phone stands (#3776), as the switch and its
/// card show it. A pause is separate: [ConnectionController.remoteAccessPaused].
enum PhoneRemoteAccess {
  /// This phone has not paired with the Quark.
  notSetUp,

  /// Pairing is under way, or waiting on the Quark.
  settingUp,

  /// Paired, with the node running.
  ready,

  /// Pairing or the node failed; the detail says why and what happens next.
  notWorking,
}
