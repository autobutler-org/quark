import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// A connection whose [mode] the test sets and whose [check] the test
/// settles, counting how many checks the pages asked for.
class _FakeConnection extends ConnectionController {
  _FakeConnection(this._fakeMode);

  ConnectionMode? _fakeMode;
  int checks = 0;
  Completer<void>? pending;

  @override
  ConnectionMode? get mode => _fakeMode;

  @override
  PhoneRemoteAccess get phoneRemoteAccess => PhoneRemoteAccess.ready;

  set fakeMode(ConnectionMode? value) {
    _fakeMode = value;
    notifyListeners();
  }

  @override
  Future<void> check() {
    checks++;
    pending = Completer<void>();
    return pending!.future;
  }

  /// Ends the check in flight on [mode].
  void settle(ConnectionMode mode) {
    _fakeMode = mode;
    notifyListeners();
    pending!.complete();
  }
}

/// A page whose load fails until [failing] turns false, counting its loads.
class _Page extends StatefulWidget {
  const _Page({required this.failing});

  final ValueNotifier<bool> failing;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int loads = 1;
  late bool failed = widget.failing.value;

  @override
  Widget build(BuildContext context) => failed
      ? QuarkDisconnectedView(
          hostAddress: 'http://quark.lan:8080',
          onRetry: () => setState(() {
            loads++;
            failed = widget.failing.value;
          }),
        )
      : const Text('photos');
}

/// #3881: over remote access one failed request flipped a page to "You're
/// not connected" while the app was connected. The page now asks the
/// connection to check once, says it is reconnecting meanwhile, and loads
/// again by itself when the check says the Quark answers.
void main() {
  Future<_FakeConnection> pump(
    WidgetTester tester,
    Size size, {
    required ConnectionMode? mode,
    required bool onDevice,
    required Widget body,
  }) async {
    setViewport(tester, size);
    final session = ValueNotifier<String?>(null);
    final jobs = JobsController(
      listJobs: ({required kinds}) async => const [],
      events: () => const Stream<FileEvent>.empty(),
      session: () => session,
    );
    final notifications = NotificationsController(
      listNotifications: () async => const [],
      readDisabled: () async => {},
      saveEnabled: (_, _) async => {},
      events: () => const Stream<FileEvent>.empty(),
      session: () => session,
    );
    final connection = _FakeConnection(mode);
    addTearDown(jobs.dispose);
    addTearDown(notifications.dispose);
    addTearDown(connection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        builder: (context, child) => AppBarTrailingHost(
          jobs: jobs,
          connection: connection,
          notifications: notifications,
          onNavigate: (_) {},
          runsOnDeviceNode: onDevice,
          child: child!,
        ),
        home: Scaffold(body: body),
      ),
    );
    await tester.pump();
    return connection;
  }

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('a failed load over remote access reconnects instead of '
        'going offline (${size.width})', (tester) async {
      final failing = ValueNotifier<bool>(true);
      final connection = await pump(
        tester,
        size,
        mode: ConnectionMode.remote,
        onDevice: true,
        body: Row(
          children: [
            Expanded(child: _Page(failing: failing)),
            Expanded(child: _Page(failing: failing)),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(quarkReconnectingHeadline), findsNWidgets(2));
      expect(find.text(quarkDisconnectedHeadline), findsNothing);
      expect(find.text(quarkTroubleshootingSteps.first), findsNothing);
      expect(find.text('http://quark.lan:8080'), findsNothing);
      expect(find.text('Using remote access'), findsNWidgets(2));
      expect(connection.checks, 1, reason: 'one check for both pages');

      failing.value = false;
      connection.settle(ConnectionMode.remote);
      await tester.pump();
      await tester.pump();

      expect(find.text('photos'), findsNWidgets(2));
      // Nothing is left on screen, so nothing checks again.
      await tester.pump(const Duration(minutes: 5));
      expect(connection.checks, 1);
    });
  }

  testWidgets('a check that finds the Quark gone shows the phone reason, '
      'never the home Wi-Fi checklist', (tester) async {
    final connection = await pump(
      tester,
      const Size(360, 640),
      mode: ConnectionMode.remote,
      onDevice: true,
      body: _Page(failing: ValueNotifier<bool>(true)),
    );

    connection.settle(ConnectionMode.offline);
    await tester.pump();

    expect(find.text(quarkReconnectingHeadline), findsNothing);
    expect(find.text("Your Quark isn't answering."), findsOneWidget);
    expect(find.text(quarkTroubleshootingSteps.first), findsNothing);
    expect(find.text('http://quark.lan:8080'), findsNothing);
    // Still on screen: it checks again later, backing off.
    await tester.pump(const Duration(seconds: 5));
    expect(connection.checks, 2);
    connection.settle(ConnectionMode.offline);
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('the Quark coming back retries a page that was offline', (
    tester,
  ) async {
    final failing = ValueNotifier<bool>(true);
    final connection = await pump(
      tester,
      const Size(1280, 800),
      mode: ConnectionMode.offline,
      onDevice: true,
      body: _Page(failing: failing),
    );
    connection.settle(ConnectionMode.offline);
    await tester.pump();
    expect(find.text("Your Quark isn't answering."), findsOneWidget);

    failing.value = false;
    connection.fakeMode = ConnectionMode.local;
    await tester.pump();
    await tester.pump();

    expect(find.text('photos'), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
  });
}
