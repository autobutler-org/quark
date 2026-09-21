// Conditional entry for Flutter Probe.
//
// IO platforms get [maybeStartProbeAgent] that can start ProbeAgent; web
// gets a no-op stub so `dart:io` from flutter_probe_agent never enters the
// web compile.
/// Starts the Flutter Probe agent on platforms with `dart:io`, and is a no-op on web, so the probe package never
/// enters the web build.
library;

export 'probe_bootstrap_stub.dart'
    if (dart.library.io) 'probe_bootstrap_io.dart';
