// Conditional entry for Flutter Probe.
//
// IO platforms get [maybeStartProbeAgent] that can start ProbeAgent; web
// gets a no-op stub so `dart:io` from flutter_probe_agent never enters the
// web compile.
export 'probe_bootstrap_stub.dart'
    if (dart.library.io) 'probe_bootstrap_io.dart';
