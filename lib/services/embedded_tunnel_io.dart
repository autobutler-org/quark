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

/// The saved enrollment. The auth key is not here: it is single-use, and the
/// node state on disk is what a later start rejoins with.
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

Future<void> _tail = Future<void>.value();
var _running = false;
var _port = 0;
_TunnelConfig? _config;
void Function()? _onReconnected;
var _watching = false;
final _lifecycle = _TunnelLifecycle();

/// Runs [action] after whatever start, stop, or warm is already in flight.
Future<T> _serialized<T>(Future<T> Function() action) {
  final run = _tail.then((_) => action());
  _tail = run.then((_) {}, onError: (Object _, StackTrace _) {});
  return run;
}

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
  return _serialized(_statusNative);
}

Future<String?> tunnelProxyUrl(String upstream) {
  if (!_mobile) return Future<String?>.value();
  return _serialized(() async {
    final root = await _rootDir();
    if (!await _hasState(root)) return null;
    final cfg = await _load(root);
    if (upstream.isNotEmpty) {
      cfg.upstream = upstream;
      await _save(root, cfg);
    }
    if (!_running) {
      final (port, _) = await _startNative(
        stateDir: _statePath(root),
        controlUrl: cfg.controlUrl,
        authKey: '',
        hostname: cfg.hostname,
        upstream: cfg.upstream,
      );
      if (port < 0) return null;
    }
    return 'http://127.0.0.1:$_port';
  });
}

Future<void> tunnelWarm(String upstream) {
  if (!_mobile) return Future<void>.value();
  return _serialized(() async {
    try {
      if (upstream.isEmpty) {
        await _stopNative();
        return;
      }
      final root = await _rootDir();
      // The first key comes from tunnelEnroll. Until that has left state
      // on disk there is nothing here to rejoin.
      if (!await _hasState(root)) return;
      final cfg = await _load(root);
      cfg.upstream = upstream;
      await _save(root, cfg);
      if (!_running) {
        await _startNative(
          stateDir: _statePath(root),
          controlUrl: cfg.controlUrl,
          authKey: '',
          hostname: cfg.hostname,
          upstream: cfg.upstream,
        );
      }
    } catch (error, stack) {
      developer.log(
        'embedded tunnel did not start',
        name: 'quark.tunnel',
        error: error,
        stackTrace: stack,
      );
    }
  });
}

Future<void> tunnelEnroll({
  required String controlUrl,
  required String authKey,
  required String upstream,
}) {
  if (!_mobile) return Future<void>.value();
  return _serialized(() async {
    final root = await _rootDir();
    final cfg = await _load(root);
    cfg
      ..controlUrl = controlUrl
      ..upstream = upstream;
    await _save(root, cfg);
    await _startNative(
      stateDir: _statePath(root),
      controlUrl: controlUrl,
      authKey: authKey,
      hostname: cfg.hostname,
      upstream: upstream,
    );
  });
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
  await _serialized(() async {
    final cfg = _config;
    if (!_running || cfg == null) return;
    final root = await _rootDir();
    await _stopNative();
    await _startNative(
      stateDir: _statePath(root),
      controlUrl: cfg.controlUrl,
      authKey: '',
      hostname: cfg.hostname,
      upstream: cfg.upstream,
    );
  });
  _onReconnected?.call();
}

Future<(int, String)> _startNative({
  required String stateDir,
  required String controlUrl,
  required String authKey,
  required String hostname,
  required String upstream,
}) async {
  final (port, error, token) = await Isolate.run(
    () => _startBlocking(
      stateDir: stateDir,
      controlUrl: controlUrl,
      authKey: authKey,
      hostname: hostname,
      upstream: upstream,
    ),
  );
  if (port > 0) {
    _port = port;
    _running = true;
    tunnelProxyCredentials = (port: port, token: token);
    _config = _TunnelConfig(
      controlUrl: controlUrl,
      hostname: hostname,
      upstream: upstream,
    );
  }
  return (port, error);
}

Future<void> _stopNative() async {
  await Isolate.run(_stopBlocking);
  _running = false;
  _port = 0;
  tunnelProxyCredentials = null;
}

Future<Map<String, dynamic>> _statusNative() => Isolate.run(_statusBlocking);

/// Starts the bridge. Returns the proxy port, or -1, the error text, and the
/// token the proxy asks for.
(int, String, String) _startBlocking({
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
  if (port > 0) return (port, '', _readToken());
  // A second start leaves the node running and returns -1. The status port
  // is the one already listening; the error text is not always filled in.
  final status = _readStatus();
  final existing = status['port'];
  if (status['state'] == 'Running' && existing is int && existing > 0) {
    return (existing, '', _readToken());
  }
  return (port, status['error'] as String? ?? '', '');
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

String _statePath(Directory root) => '${root.path}/state';

Future<bool> _hasState(Directory root) async {
  final state = Directory(_statePath(root));
  if (!await state.exists()) return false;
  await for (final _ in state.list()) {
    return true;
  }
  return false;
}

Future<_TunnelConfig> _load(Directory root) async {
  final file = File('${root.path}/tunnel.json');
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

Future<void> _save(Directory root, _TunnelConfig cfg) async {
  final file = File('${root.path}/tunnel.json');
  await file.writeAsString(jsonEncode(cfg.toJson()));
  _config = cfg;
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
