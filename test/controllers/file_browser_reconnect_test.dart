import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_events_controller.dart';

import '../support/reconnecting_events.dart';

/// #3094: the Files page listened to both `reconnects` and `resync`, so one
/// reconnect refreshed it twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a reconnect refreshes the Files page exactly once', (
    tester,
  ) async {
    final events = ReconnectingEvents();
    await events.start();
    var refreshes = 0;
    final controller = FileBrowserEventsController(
      currentFolder: () => '/',
      isBusy: () => false,
      onRefresh: () => refreshes++,
    );
    await tester.pump();
    expect(refreshes, 0, reason: 'the first connect is not a reconnect');

    await events.reconnect(tester);
    await tester.pump();

    expect(refreshes, 1);
    controller.dispose();
    await events.stop();
  });
}
