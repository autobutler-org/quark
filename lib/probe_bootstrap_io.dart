import 'package:flutter_probe_agent/flutter_probe_agent.dart';

/// Starts Flutter Probe when built with `--dart-define=PROBE_AGENT=true`.
///
/// Matches the flutter_probe_agent recommended gate so the agent is inactive
/// (and tree-shaken from release builds) unless explicitly enabled.
Future<void> maybeStartProbeAgent() async {
  const enabled = bool.fromEnvironment('PROBE_AGENT', defaultValue: false);
  if (!enabled) {
    return;
  }
  await ProbeAgent.start();
}
