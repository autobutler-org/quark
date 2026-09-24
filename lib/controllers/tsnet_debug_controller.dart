import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_tsnet/quark_tsnet.dart';

/// Drives the debug-only embedded tailnet screen (#1881 spike): gets a key,
/// starts and stops the in-app tsnet node, polls its status, and times a
/// request through its loopback proxy.
///
/// Service calls are injectable so a test can pass fakes.
class TsnetDebugController extends ChangeNotifier {
  /// Creates the controller. The defaults are the real calls.
  TsnetDebugController({
    Future<DevicePairing> Function()? pairDevice,
    Future<String> Function()? stateDir,
  }) : _pairDevice = pairDevice ?? RemoteAccessService.pairDevice,
       _stateDir = stateDir ?? _defaultStateDir;

  final Future<DevicePairing> Function() _pairDevice;
  final Future<String> Function() _stateDir;

  /// Headscale coordination server; defaults to the live control plane.
  final controlUrl = TextEditingController(
    text: 'https://quark.ts.autobutler.org',
  );

  /// Single-use pre-auth key.
  final authKey = TextEditingController();

  /// The Quark's tailnet address, `http://100.x.y.z`.
  final upstream = TextEditingController();

  /// The bridge's last reported status.
  TsnetStatus status = QuarkTsnet.isSupported
      ? QuarkTsnet.status()
      : const TsnetStatus(state: 'Stopped');

  /// Whether a pair, start, stop or fetch is in flight.
  bool busy = false;

  /// User-facing copy for the last failure, from [Errors].
  String? error;

  /// The last `/api/v0/version` result through the proxy.
  String? versionResult;

  /// How long [start] took, from call to Running.
  Duration? startTook;

  Timer? _poll;

  static Future<String> _defaultStateDir() async =>
      '${(await getApplicationSupportDirectory()).path}/tsnet';

  /// Starts polling the bridge once a second.
  void attach() {
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  void _refresh() {
    if (!QuarkTsnet.isSupported) return;
    status = QuarkTsnet.status();
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() body, String action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      debugPrint('tsnet debug: $action failed: $e');
      error = action == 'pair'
          ? Errors.pairDevice(e)
          : Errors.message(e, action);
    } finally {
      busy = false;
      _refresh();
      notifyListeners();
    }
  }

  /// Asks the Quark on the home network for a key and fills in the fields.
  Future<void> pair() => _run(() async {
    final p = await _pairDevice();
    controlUrl.text = p.controlUrl;
    authKey.text = p.authKey;
    upstream.text = p.quarkAddress;
  }, 'pair');

  /// Joins the tailnet and starts the loopback proxy.
  Future<void> start() => _run(() async {
    final sw = Stopwatch()..start();
    await QuarkTsnet.start(
      stateDir: await _stateDir(),
      controlUrl: controlUrl.text.trim(),
      authKey: authKey.text.trim(),
      hostname: 'quark-app-${defaultTargetPlatform.name.toLowerCase()}',
      upstream: upstream.text.trim(),
    );
    startTook = sw.elapsed;
  }, 'join the tailnet');

  /// Stops the proxy and the node.
  Future<void> stop() => _run(QuarkTsnet.stop, 'stop the tailnet node');

  /// Fetches `/api/v0/version` through the proxy and records the latency.
  Future<void> fetchVersion() => _run(() async {
    final base = status.loopbackUrl;
    if (base == null) {
      throw const MessageException('Start the node first.');
    }
    final sw = Stopwatch()..start();
    final r = await http
        .get(base.resolve('/api/v0/version'))
        .timeout(const Duration(seconds: 30));
    versionResult =
        'HTTP ${r.statusCode} in ${sw.elapsedMilliseconds} ms\n${r.body}';
  }, 'reach the Quark through the tailnet');

  @override
  void dispose() {
    _poll?.cancel();
    controlUrl.dispose();
    authKey.dispose();
    upstream.dispose();
    super.dispose();
  }
}
