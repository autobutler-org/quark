// cspell:words ffi

/// `dart:ffi` binding to the Go bridge built by `hook/build.dart`, and the
/// foreground lifecycle around it (#1881).
///
/// The `@Native` functions resolve against the code asset the hook emits for
/// this library, so there is no `DynamicLibrary.open` and no path per
/// platform. Starting and stopping the node run in a helper isolate: joining
/// the tailnet blocks, and the UI isolate must not.
///
/// iOS and Android call into the bridge. Every other `dart:io` host, including
/// the Linux desktop build and the test runner, reports the tunnel
/// unavailable and never looks the symbols up. The node runs in the foreground
/// only. Coming back to the app restarts it. There is no background mode.
///
/// The bridge runs one node per process, but a phone can pair with several
/// Quarks, each in its own household. Each Quark keeps its own state directory
/// and saved setup, keyed by its tailnet address, and the node only ever runs
/// for one of them: the active Quark's. Asking for another Quark stops it and
/// starts it again from that Quark's state (#3784).
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quark/services/tunnel_token_client.dart';

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>(
  symbol: 'quark_tsnet_start',
  assetId: 'package:quark/services/embedded_tunnel_io.dart',
)
external int _start(
  Pointer<Utf8> stateDir,
  Pointer<Utf8> controlUrl,
  Pointer<Utf8> authKey,
  Pointer<Utf8> hostname,
  Pointer<Utf8> upstream,
);

@Native<Pointer<Utf8> Function()>(
  symbol: 'quark_tsnet_token',
  assetId: 'package:quark/services/embedded_tunnel_io.dart',
)
external Pointer<Utf8> _token();

@Native<Void Function()>(
  symbol: 'quark_tsnet_stop',
  assetId: 'package:quark/services/embedded_tunnel_io.dart',
)
external void _stop();

@Native<Pointer<Utf8> Function()>(
  symbol: 'quark_tsnet_status',
  assetId: 'package:quark/services/embedded_tunnel_io.dart',
)
external Pointer<Utf8> _status();

@Native<Void Function(Pointer<Utf8>)>(
  symbol: 'quark_tsnet_free',
  assetId: 'package:quark/services/embedded_tunnel_io.dart',
)
external void _free(Pointer<Utf8> p);

/// The saved enrollment for one Quark. The auth key is not here: it is
/// single-use, and the node state on disk is what a later start rejoins with.
class _TunnelConfig {
  _TunnelConfig({
    required this.controlUrl,
    required this.hostname,
    required this.upstream,
  });

  String controlUrl;
  String hostname;
  String upstream;

  Map<String, String> toJson() => {
    'controlUrl': controlUrl,
    'hostname': hostname,
    'upstream': upstream,
  };
}

/// What one start of the bridge reported.
///
/// [alreadyRunning] means the bridge refused because a node was already up.
/// [port] is then -1: that node may be another Quark's, so nothing adopts it.
@visibleForTesting
typedef TunnelStart = ({
  int port,
  String error,
  String token,
  bool alreadyRunning,
});

/// The calls [TunnelNode] makes into the Go bridge. Tests pass a fake.
@visibleForTesting
abstract interface class TunnelBridge {
  /// Starts the node from [stateDir], logging in with [authKey] when the
  /// state holds no login yet.
  Future<TunnelStart> start({
    required String stateDir,
    required String controlUrl,
    required String authKey,
    required String hostname,
    required String upstream,
  });

  /// Stops the node, if one runs.
  Future<void> stop();

  /// The bridge's status JSON.
  Future<Map<String, dynamic>> status();
}

/// The node's lifecycle: which Quark it runs for, and when it stops, resets,
/// and starts again.
///
/// Every call runs after whatever start, stop, or warm is already in flight.
/// The node runs for at most one Quark at a time, and only from that Quark's
/// own state under [rootDir]'s `quarks/` directory (#3784).
@visibleForTesting
class TunnelNode {
  /// Creates a lifecycle over [bridge], keeping its state under [rootDir].
  TunnelNode({
    required TunnelBridge bridge,
    required Future<Directory> Function() rootDir,
  }) : _bridge = bridge,
       _rootDir = rootDir;

  final TunnelBridge _bridge;
  final Future<Directory> Function() _rootDir;
  Future<void> _tail = Future<void>.value();
  var _migrated = false;

  /// The Quark the running node serves, or null when it is stopped.
  ({Directory dir, _TunnelConfig config, int port})? _serving;

  /// The proxy port, 0 when the node is stopped.
  int get port => _serving?.port ?? 0;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }

  /// The bridge's status JSON.
  Future<Map<String, dynamic>> status() => _serialized(_bridge.status);

  /// The proxy URL for [upstream]'s Quark, starting its node first, or null
  /// when this phone has not enrolled with that Quark.
  Future<String?> proxyUrl(String upstream) {
    if (upstream.isEmpty) return Future<String?>.value();
    return _serialized(() async {
      final port = await _ensure(upstream);
      return port == null ? null : 'http://127.0.0.1:$port';
    });
  }

  /// Runs the node for [upstream]'s Quark, or stops it when [upstream] is
  /// empty. A failed start is logged, not thrown.
  Future<void> warm(String upstream) => _serialized(() async {
    try {
      if (upstream.isEmpty) {
        await _stopNode();
        return;
      }
      await _ensure(upstream);
    } catch (error, stack) {
      developer.log(
        'embedded tunnel did not start',
        name: 'quark.tunnel',
        error: error,
        stackTrace: stack,
      );
    }
  });

  /// Joins [upstream]'s Quark's household with a fresh [authKey].
  ///
  /// Whatever node runs now stops, and this Quark's old state goes, so the
  /// node logs in with the new key rather than rejoining as before. Throws
  /// when the node does not start.
  Future<void> enroll({
    required String controlUrl,
    required String authKey,
    required String upstream,
  }) {
    if (upstream.isEmpty) {
      throw ArgumentError.value(upstream, 'upstream', 'names no Quark');
    }
    return _serialized(() async {
      final dir = await _quarkDir(upstream);
      await _stopNode();
      final state = Directory(_statePath(dir));
      if (await state.exists()) await state.delete(recursive: true);
      final cfg = await _load(dir)
        ..controlUrl = controlUrl
        ..upstream = upstream;
      await _save(dir, cfg);
      final error = await _startNode(dir, cfg, authKey);
      if (error != null) {
        throw Exception('the tailnet node did not start: $error');
      }
    });
  }

  /// Restarts the running node for the Quark it already serves.
  Future<void> resume() => _serialized(() async {
    final serving = _serving;
    if (serving == null) return;
    await _stopNode();
    await _startNode(serving.dir, serving.config, '');
  });

  /// The port of the node serving [upstream]'s Quark, started from that
  /// Quark's own state, or null when there is no state or it did not start.
  Future<int?> _ensure(String upstream) async {
    final dir = await _quarkDir(upstream);
    final serving = _serving;
    if (serving != null && serving.dir.path == dir.path) return serving.port;
    // Another Quark's node must not keep answering for this one.
    if (serving != null) await _stopNode();
    // The first key comes from enroll. Until that has left state on disk
    // there is nothing here to rejoin.
    if (!await _hasState(dir)) return null;
    final error = await _startNode(dir, await _load(dir), '');
    return error == null ? _serving?.port : null;
  }

  /// Starts the node for [dir]'s Quark. Null on success, else why not.
  Future<String?> _startNode(
    Directory dir,
    _TunnelConfig cfg,
    String authKey,
  ) async {
    Future<TunnelStart> attempt() => _bridge.start(
      stateDir: _statePath(dir),
      controlUrl: cfg.controlUrl,
      authKey: authKey,
      hostname: cfg.hostname,
      upstream: cfg.upstream,
    );
    var result = await attempt();
    if (result.alreadyRunning) {
      // Every start here follows a stop of whatever this node ran, so a node
      // still up is one this start did not ask for, possibly another
      // Quark's. Stop it and try once more rather than serve it.
      await _bridge.stop();
      result = await attempt();
    }
    if (result.alreadyRunning) return 'another node is still running';
    if (result.port <= 0) {
      return result.error.isEmpty ? 'the bridge refused' : result.error;
    }
    _serving = (dir: dir, config: cfg, port: result.port);
    tunnelProxyCredentials = (port: result.port, token: result.token);
    return null;
  }

  Future<void> _stopNode() async {
    await _bridge.stop();
    _serving = null;
    tunnelProxyCredentials = null;
  }

  /// [upstream]'s Quark's own directory, created if missing.
  Future<Directory> _quarkDir(String upstream) async {
    final root = await _rootDir();
    if (!_migrated) {
      await _migrateShared(root);
      _migrated = true;
    }
    final dir = _dirFor(root, upstream);
    await dir.create(recursive: true);
    return dir;
  }

  /// Moves the one state directory and setup earlier builds kept for every
  /// Quark into the directory of the Quark it last ran for.
  Future<void> _migrateShared(Directory root) async {
    final setup = File('${root.path}/tunnel.json');
    final state = Directory(_statePath(root));
    if (await setup.exists()) {
      final upstream = (await _load(root)).upstream;
      if (upstream.isNotEmpty) {
        final dir = _dirFor(root, upstream);
        await dir.create(recursive: true);
        final movedState = Directory(_statePath(dir));
        if (await state.exists() && !await movedState.exists()) {
          await state.rename(movedState.path);
        }
        final movedSetup = File('${dir.path}/tunnel.json');
        if (!await movedSetup.exists()) await setup.rename(movedSetup.path);
      }
    }
    if (await state.exists()) await state.delete(recursive: true);
    if (await setup.exists()) await setup.delete();
  }
}

/// The bridge itself. Each call runs in a helper isolate: joining the tailnet
/// blocks, and the UI isolate must not.
class _NativeBridge implements TunnelBridge {
  const _NativeBridge();

  @override
  Future<TunnelStart> start({
    required String stateDir,
    required String controlUrl,
    required String authKey,
    required String hostname,
    required String upstream,
  }) => Isolate.run(
    () => _startBlocking(
      stateDir: stateDir,
      controlUrl: controlUrl,
      authKey: authKey,
      hostname: hostname,
      upstream: upstream,
    ),
  );

  @override
  Future<void> stop() => Isolate.run(_stopBlocking);

  @override
  Future<Map<String, dynamic>> status() => Isolate.run(_statusBlocking);
}

void Function()? _onReconnected;
var _watching = false;
final _lifecycle = _TunnelLifecycle();
final _node = TunnelNode(bridge: const _NativeBridge(), rootDir: _rootDir);

bool get _mobile => Platform.isAndroid || Platform.isIOS;

/// Whether this platform joins the tailnet. False on desktop and in tests.
bool get tunnelIsSupported => _mobile;

Future<Map<String, dynamic>> tunnelStatusJson() async {
  if (!_mobile) {
    return const {
      'state': 'Stopped',
      'tailnetIPs': <String>[],
      'port': 0,
      'error': '',
    };
  }
  return _node.status();
}

Future<String?> tunnelProxyUrl(String upstream) {
  if (!_mobile) return Future<String?>.value();
  return _node.proxyUrl(upstream);
}

Future<void> tunnelWarm(String upstream) {
  if (!_mobile) return Future<void>.value();
  return _node.warm(upstream);
}

Future<void> tunnelEnroll({
  required String controlUrl,
  required String authKey,
  required String upstream,
}) {
  if (!_mobile) return Future<void>.value();
  return _node.enroll(
    controlUrl: controlUrl,
    authKey: authKey,
    upstream: upstream,
  );
}

void tunnelWatch(void Function() onReconnected) {
  if (!_mobile) return;
  _onReconnected = onReconnected;
  _lifecycle.onResume = () {
    _resume();
  };
  if (_watching) return;
  _watching = true;
  WidgetsBinding.instance.addObserver(_lifecycle);
}

Future<void> _resume() async {
  await _node.resume();
  _onReconnected?.call();
}

/// Starts the bridge and reports the proxy port and the token the proxy asks
/// for, or -1 and the error text.
TunnelStart _startBlocking({
  required String stateDir,
  required String controlUrl,
  required String authKey,
  required String hostname,
  required String upstream,
}) {
  final port = using((arena) {
    Pointer<Utf8> native(String value) => value.toNativeUtf8(allocator: arena);
    return _start(
      native(stateDir),
      native(controlUrl),
      native(authKey),
      native(hostname),
      native(upstream),
    );
  });
  if (port > 0) {
    return (port: port, error: '', token: _readToken(), alreadyRunning: false);
  }
  // A second start leaves the node running and returns -1; the error text is
  // not always filled in, so the status says which case this is.
  final status = _readStatus();
  final existing = status['port'];
  return (
    port: port,
    error: status['error'] as String? ?? '',
    token: '',
    alreadyRunning:
        status['state'] == 'Running' && existing is int && existing > 0,
  );
}

String _readToken() {
  final pointer = _token();
  try {
    return pointer.toDartString();
  } finally {
    _free(pointer);
  }
}

void _stopBlocking() => _stop();

Map<String, dynamic> _statusBlocking() => _readStatus();

Map<String, dynamic> _readStatus() {
  final pointer = _status();
  try {
    final decoded = jsonDecode(pointer.toDartString());
    if (decoded is Map<String, dynamic>) return decoded;
    return const {'state': 'Stopped', 'error': 'status was not an object'};
  } finally {
    _free(pointer);
  }
}

Future<Directory> _rootDir() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/tsnet');
  await dir.create(recursive: true);
  return dir;
}

String _statePath(Directory dir) => '${dir.path}/state';

Directory _dirFor(Directory root, String upstream) {
  final token = base64Url.encode(utf8.encode(upstream)).replaceAll('=', '');
  return Directory('${root.path}/quarks/$token');
}

Future<bool> _hasState(Directory dir) async {
  final state = Directory(_statePath(dir));
  if (!await state.exists()) return false;
  await for (final _ in state.list()) {
    return true;
  }
  return false;
}

Future<_TunnelConfig> _load(Directory dir) async {
  final file = File('${dir.path}/tunnel.json');
  if (!await file.exists()) {
    return _TunnelConfig(controlUrl: '', hostname: _hostname(), upstream: '');
  }
  final json = jsonDecode(await file.readAsString());
  if (json is! Map) {
    return _TunnelConfig(controlUrl: '', hostname: _hostname(), upstream: '');
  }
  final hostname = json['hostname'] as String? ?? '';
  return _TunnelConfig(
    controlUrl: json['controlUrl'] as String? ?? '',
    hostname: hostname.isEmpty ? _hostname() : hostname,
    upstream: json['upstream'] as String? ?? '',
  );
}

Future<void> _save(Directory dir, _TunnelConfig cfg) async {
  final file = File('${dir.path}/tunnel.json');
  await file.writeAsString(jsonEncode(cfg.toJson()));
}

String _hostname() {
  final rand = Random.secure();
  final hex = List.generate(
    4,
    (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'phone-$hex';
}

/// Restarts the node when the app is foregrounded again.
class _TunnelLifecycle with WidgetsBindingObserver {
  /// Called on resume, after the binding has delivered the state change.
  void Function()? onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume?.call();
  }
}
