/// `dart:ffi` binding to the Go bridge built by `hook/build.dart`.
///
/// The `@Native` functions resolve against the code asset the hook emits under
/// this library's own URI, so there is no `DynamicLibrary.open` and no path
/// handling per platform.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'status.dart';

@Native<
  Int Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>(symbol: 'quark_tsnet_start')
external int _start(
  Pointer<Utf8> stateDir,
  Pointer<Utf8> controlUrl,
  Pointer<Utf8> authKey,
  Pointer<Utf8> hostname,
  Pointer<Utf8> upstream,
);

@Native<Void Function()>(symbol: 'quark_tsnet_stop')
external void _stop();

@Native<Pointer<Utf8> Function()>(symbol: 'quark_tsnet_status')
external Pointer<Utf8> _status();

@Native<Void Function(Pointer<Utf8>)>(symbol: 'quark_tsnet_free')
external void _free(Pointer<Utf8> p);

/// The embedded tailnet node and its loopback proxy.
///
/// One per process. [start] and [stop] block in Go, so they run on a
/// background isolate and never stall the UI.
abstract final class QuarkTsnet {
  /// Whether this platform has the native bridge.
  static const bool isSupported = true;

  /// Joins the tailnet and starts the proxy; returns the loopback port.
  ///
  /// [upstream] is the Quark's tailnet address (`http://100.x.y.z`). Throws
  /// [TsnetException] with the bridge's reason on failure.
  static Future<int> start({
    required String stateDir,
    required String controlUrl,
    required String authKey,
    required String hostname,
    required String upstream,
  }) async {
    final port = await Isolate.run(
      () => using((arena) {
        Pointer<Utf8> s(String v) => v.toNativeUtf8(allocator: arena);
        return _start(
          s(stateDir),
          s(controlUrl),
          s(authKey),
          s(hostname),
          s(upstream),
        );
      }),
    );
    if (port < 0) throw TsnetException(status().error);
    return port;
  }

  /// Stops the proxy and the node.
  static Future<void> stop() => Isolate.run(_stop);

  /// The node's current state. Cheap enough to poll.
  static TsnetStatus status() {
    final p = _status();
    try {
      return TsnetStatus.fromJson(
        jsonDecode(p.toDartString()) as Map<String, dynamic>,
      );
    } finally {
      _free(p);
    }
  }
}
