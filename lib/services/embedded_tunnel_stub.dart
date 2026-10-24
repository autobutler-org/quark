/// Stand-in for platforms without a native tailnet node, including the web
/// build. A browser cannot join the tailnet.
library;

/// Whether this platform loads the native bridge. Always false here.
const bool tunnelIsSupported = false;

/// Always stopped.
Future<Map<String, dynamic>> tunnelStatusJson() async => const {
  'state': 'Stopped',
  'tailnetIPs': <String>[],
  'port': 0,
  'error': '',
};

/// No proxy on this platform.
Future<String?> tunnelProxyUrl(String upstream) async => null;

/// Does nothing.
Future<void> tunnelWarm(String upstream) async {}

/// Does nothing.
Future<void> tunnelEnroll({
  required String controlUrl,
  required String authKey,
  required String upstream,
}) async {}

/// Does nothing.
void tunnelWatch(void Function() onReconnected) {}
