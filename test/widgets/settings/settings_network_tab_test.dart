import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/settings/hostname_section.dart';
import 'package:quark/widgets/settings/settings_network_tab.dart';
import 'package:quark/widgets/settings/ssh_access_section.dart';

/// #2344: the device name is an admin's to change, so the Network tab asks
/// the Quark about it for an admin only, above SSH access.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  setUp(() {
    // A Quark with neither endpoint: both admin sections ask and get a 404.
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient(
      (request) async => http.Response(jsonEncode({'error': ''}), 404),
    );
  });
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> pumpTab(
    WidgetTester tester,
    Size size, {
    required bool isAdmin,
    bool hasHost = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsNetworkTab(
            hasHost: hasHost,
            isAdmin: isAdmin,
            remoteAccess: const Text('remote access card'),
            connectedDevices: const Text('connected devices card'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('a member is not offered the device name at $size', (
      tester,
    ) async {
      await pumpTab(tester, size, isAdmin: false);

      expect(tester.takeException(), isNull);
      expect(find.byType(HostnameSection), findsNothing);
      expect(find.byType(SshAccessSection), findsNothing);
    });

    testWidgets('an admin gets it above SSH access at $size', (tester) async {
      await pumpTab(tester, size, isAdmin: true);

      expect(tester.takeException(), isNull);
      expect(find.byType(HostnameSection), findsOneWidget);
      // This Quark has no hostname endpoint, so the section takes no room.
      expect(find.byKey(const ValueKey('hostname_section')), findsNothing);
      expect(find.text('Device name'), findsNothing);
      expect(tester.getSize(find.byType(HostnameSection)).height, 0);
      expect(
        tester.getTopLeft(find.byType(HostnameSection)).dy,
        lessThan(tester.getTopLeft(find.byType(SshAccessSection)).dy),
      );
    });

    testWidgets('nobody gets it with no Quark set at $size', (tester) async {
      await pumpTab(tester, size, isAdmin: true, hasHost: false);

      expect(tester.takeException(), isNull);
      expect(find.byType(HostnameSection), findsNothing);
    });
  }
}
