/// What a return to the foreground does to the on-device node (#3882).
///
/// iOS sends `resumed` after every `inactive`: Control Center, Notification
/// Center, Face ID, the share sheet, the photo picker, a permission dialog.
/// Restarting the node on each of those took the proxy down, moved it to a
/// new port, and made every screen fail with "You're not connected" until
/// the node rejoined. [TunnelLifecycleObserver] reports only a return from
/// the background, and [resumeTunnelNode] keeps a node that still works.
///
/// Pure Dart with no FFI, so tests drive it with fakes.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// How long the probe through the existing proxy gets on a return to the
/// foreground before the node is restarted. Matches the app's remote probe.
const tunnelResumeProbeTimeout = Duration(seconds: 5);

/// Calls [onReturn] when the app comes back from the background.
///
/// A `resumed` counts only after `hidden` or `paused`: the app really left
/// the screen. A `resumed` that follows `inactive` alone, an overlay or a
/// system prompt, does nothing.
class TunnelLifecycleObserver with WidgetsBindingObserver {
  /// Called on a return from the background, after the binding has
  /// delivered the state change.
  void Function()? onReturn;

  /// Logs each state change, for the timeline in #3882.
  void Function(String message)? log;

  bool _leftScreen = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log?.call('lifecycle ${state.name}');
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _leftScreen = true;
      case AppLifecycleState.resumed:
        if (!_leftScreen) return;
        _leftScreen = false;
        onReturn?.call();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }
}

/// Keeps a healthy node and restarts one that is not. Returns whether it
/// restarted.
///
/// Healthy means [status] reports `Running` on [port] and [probe] answers
/// through the proxy at `http://127.0.0.1:<port>` within [probeTimeout]. A
/// probe that throws or runs out of time counts as a failure. [restart]
/// stops the node and starts it again.
Future<bool> resumeTunnelNode({
  required int port,
  required Future<Map<String, dynamic>> Function() status,
  required Future<bool> Function(String proxyUrl)? probe,
  required Future<void> Function() restart,
  Duration probeTimeout = tunnelResumeProbeTimeout,
  void Function(String message)? log,
}) async {
  final current = await status();
  final running = current['state'] == 'Running' && current['port'] == port;
  var healthy = false;
  if (running && port > 0) {
    if (probe == null) {
      healthy = true;
    } else {
      try {
        healthy = await probe('http://127.0.0.1:$port').timeout(probeTimeout);
      } catch (_) {
        healthy = false;
      }
    }
  }
  log?.call(
    'resume: node ${current['state']} on ${current['port']}, '
    '${healthy ? 'kept' : 'restarting'}',
  );
  if (healthy) return false;
  await restart();
  return true;
}
