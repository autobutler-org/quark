import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/app_bar_trailing_host.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark/widgets/layout/remote_access_pause_banner.dart';
import 'package:quark/widgets/settings/settings_network_tab.dart';
import 'package:quark/widgets/settings/this_phone_card.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #3779: with no on-device node, and not on web, the Network tab and the
/// connection sheet hide the phone's remote-access switch and pause banner
/// and say why, once.
void main() {
  setUp(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient(
      (request) async =>
          http.Response(jsonEncode({'enabled': true, 'connected': true}), 200),
    );
  });
  tearDown(resetSharedHttpClient);

  test('names the section for the device and says why desktop has none', () {
    expect(
      desktopRemoteAccessUnavailable,
      "Remote access isn't available in the desktop app yet. "
      'At home, Quark works as usual.',
    );
    expect(thisDeviceRemoteAccessHeading(TargetPlatform.android), 'This phone');
    expect(thisDeviceRemoteAccessHeading(TargetPlatform.iOS), 'This phone');
    expect(
      thisDeviceRemoteAccessHeading(TargetPlatform.linux),
      'This computer',
    );
    expect(
      thisDeviceRemoteAccessHeading(TargetPlatform.macOS),
      'This computer',
    );
    expect(
      thisDeviceRemoteAccessHeading(TargetPlatform.windows),
      'This computer',
    );
    expect(
      remoteAccessOnThisDevice(TargetPlatform.android),
      remoteAccessOnThisPhone,
    );
    expect(
      remoteAccessOnThisDevice(TargetPlatform.linux),
      remoteAccessOnThisComputer,
    );
  });

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('hides phone remote access at ${size.width}x${size.height}', (
      tester,
    ) async {
      expect(EmbeddedTunnel.isSupported, isFalse);
      expect(kIsWeb, isFalse);
      setViewport(tester, size);

      final hostChanges = ChangeNotifier();
      addTearDown(hostChanges.dispose);
      final connection = ConnectionController(
        activeHostChanges: hostChanges,
        activeHost: () => HostEntry(
          name: 'Home',
          hostAddress: 'https://quark.local',
          remoteAddress: 'http://100.64.0.7:80',
        ),
        probe: (_) async => false,
        embeddedProxy: (_) async => null,
        hasOnDeviceNode: false,
        warmEmbeddedTunnel: (_) async {},
        watchEmbeddedTunnel: (_) {},
        readPause: (_) async => null,
        savePause: (_, _) async {},
        clearPause: (_) async {},
        readPairing: (_) async => null,
        savePairing: (_, _) async {},
        clearPairing: (_) async {},
      );
      // A stored pause is what used to draw the banner and the Paused chip
      // for a node this build does not run.
      await connection.pause(DevicePauseChoice.untilManual);
      await connection.check();

      final session = ValueNotifier<String?>('token');
      addTearDown(session.dispose);
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
      addTearDown(jobs.dispose);
      addTearDown(notifications.dispose);

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
            title: 'Settings',
            icon: QuarkIcons.settings_outlined,
            body: SettingsNetworkTab(
              hasHost: true,
              isAdmin: false,
              remoteAccess: Text('remote access card'),
              connectedDevices: Text('connected devices card'),
              // What the page used to pass on every build that was not web.
              thisPhone: ThisPhoneCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsNetworkTab), findsOneWidget);
      expect(find.byType(ConnectionSheetButton), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remote_access_on_this_phone')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('remote_access_pause_banner')),
        findsNothing,
      );
      expect(find.text('Paused'), findsNothing);
      expect(find.text('This phone'), findsNothing);
      expect(find.text(desktopRemoteAccessUnavailable), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('connection_indicator')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('remote_access_on_this_phone')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('remote_access_pause_banner')),
        findsNothing,
      );
      expect(find.text(desktopRemoteAccessUnavailable), findsOneWidget);
      // check() arms the next look. Dispose before the test ends so that
      // timer is not still pending.
      connection.dispose();
    });
  }
}
