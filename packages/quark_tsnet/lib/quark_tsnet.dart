/// An embedded tsnet node for the Quark app (#1881): joins the tailnet in
/// userspace and serves a plain-HTTP reverse proxy on 127.0.0.1 that reaches
/// one Quark over it.
///
/// `QuarkTsnet.isSupported` is false on the web, where the stub stands in.
library;

export 'src/bridge_stub.dart' if (dart.library.ffi) 'src/bridge_ffi.dart';
export 'src/status.dart';
