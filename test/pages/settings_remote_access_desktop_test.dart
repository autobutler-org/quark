import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark/widgets/settings/settings_network_tab.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/secure_storage.dart';
import '../support/tap_target_guidelines.dart' show setViewport;
import '../support/unreachable_quark.dart';

/// #3779: the desktop app has no node of its own, so it offers no switch or
/// pause for remote access on "this phone" and says why once, in Settings.
///
/// Tests run on the VM, where [EmbeddedTunnel.isSupported] is false and
/// `kIsWeb` is false, which is exactly the desktop app.
void main() {
  final settings = AppSettings.instance;

  setUpAll(mockSecureStorage);

  late HttpOverrides? priorOverrides;

  Future<void> reset() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.setSessionToken(null);
    settings.isAdmin.value = false;
  }

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await reset();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    await reset();
  });

  void testBothViewports(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    for (final size in const [Size(360, 640), Size(1280, 800)]) {
      testWidgets('$description (${size.width.toInt()})', (tester) async {
        setViewport(tester, size);
        await body(tester);
      });
    }
  }

  test('the test platform has no node, like the desktop app', () {
    expect(EmbeddedTunnel.isSupported, isFalse);
  });

  testBothViewports('Settings shows the note instead of the switch', (
    tester,
  ) async {
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path != '/api/v0/settings/remote-access') {
        return http.Response('', 404);
      }
      return http.Response(
        jsonEncode({
          'enabled': true,
          'connected': true,
          'remoteUrl': 'http://100.64.0.7:80',
        }),
        200,
      );
    });
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');

    // Settings overflows its own app bar at any viewport; ignore only that.
    final priorOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = priorOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      priorOnError?.call(details);
    };

    await tester.pumpWidget(
      const MaterialApp(home: SettingsPage(tab: SettingsTab.network)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.byKey(const ValueKey('remote_access_on_this_phone')),
      findsNothing,
    );
    expect(find.text('This phone'), findsNothing);
    final note = find.text(SettingsNetworkTab.desktopRemoteAccessNote);
    expect(note, findsOneWidget);
    await tester.ensureVisible(note);
  });

  testBothViewports('the connection sheet has no switch and no pause', (
    tester,
  ) async {
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
    final host = HostEntry(
      name: 'Home',
      hostAddress: 'https://quark.local',
      remoteAddress: 'http://100.64.0.7:80',
    );
    final connection = ConnectionController(
      activeHostChanges: ChangeNotifier(),
      activeHost: () => host,
      probe: (address) async => address == host.hostAddress,
      readRemoteAccess: () async => null,
      watchEmbeddedTunnel: (_) {},
      warmEmbeddedTunnel: (_) async {},
      // Paused once, before this device lost its node: still not shown.
      readPause: (_) async =>
          const StoredPause(choice: DevicePauseChoice.untilManual),
    );
    connection.start();

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        builder: (context, child) => AppBarTrailingHost(
          jobs: jobs,
          connection: connection,
          notifications: notifications,
          onNavigate: (_) {},
          child: child!,
        ),
        home: const QuarkPageScaffold(
          title: 'Files',
          icon: QuarkIcons.folder_outlined,
          body: SizedBox(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(connection.remoteAccessPaused, isFalse);
    expect(find.text('Paused'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('connection_indicator')));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Remote access on this phone'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    connection.dispose();
    notifications.dispose();
    jobs.dispose();
  });
}
