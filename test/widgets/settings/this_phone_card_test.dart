import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/embedded_tunnel.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/this_phone_card.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _lan = 'https://quark.local';
const _remote = 'http://100.64.0.7:80';

/// #3776: the switch for remote access on this phone shows the real state —
/// off until the phone pairs, with a line saying where setup stands.
void main() {
  late Map<String, StoredPairing> pairings;
  late Object? pairFailure;
  late Set<String> answering;

  ConnectionController build() {
    final c = ConnectionController(
      activeHostChanges: ChangeNotifier(),
      probe: (address) async => answering.contains(address),
      readRemoteAccess: () async => const RemoteAccessStatus(
        enabled: true,
        connected: true,
        remoteUrl: _remote,
      ),
      activeHost: () =>
          HostEntry(name: 'Home', hostAddress: _lan, remoteAddress: _remote),
      saveRemoteAddress: (_, _) async {},
      embeddedProxy: (_) async => null,
      warmEmbeddedTunnel: (_) async {},
      watchEmbeddedTunnel: (_) {},
      pairDevice: () async {
        final failure = pairFailure;
        if (failure != null) throw failure;
        return const PairedDevice(
          authKey: 'key',
          controlUrl: 'https://control.example',
          quarkAddress: _remote,
        );
      },
      readPairing: (h) async => pairings[h],
      savePairing: (h, p) async => pairings[h] = p,
      clearPairing: (h) async => pairings.remove(h),
      readPause: (_) async => null,
      savePause: (_, _) async {},
      clearPause: (_) async {},
      enroll:
          ({
            required String controlUrl,
            required String authKey,
            required String upstream,
          }) async {},
      nodeStatus: () async => const TunnelStatus(state: 'Running'),
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    pairings = {};
    pairFailure = null;
    answering = {};
  });

  Future<void> pump(WidgetTester tester, ConnectionController c) =>
      tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
          home: Scaffold(body: ThisPhoneCard(connection: c)),
        ),
      );

  bool switchValue(WidgetTester tester) => tester
      .widget<SwitchListTile>(
        find.byKey(const ValueKey('remote_access_on_this_phone')),
      )
      .value;

  testWidgets('reads off away from home before the phone paired', (
    tester,
  ) async {
    final c = build();
    await tester.runAsync(c.check);
    await pump(tester, c);

    expect(switchValue(tester), isFalse);
    expect(find.text(Errors.finishRemoteAccessAtHome), findsOneWidget);
  });

  testWidgets('reads on once the phone paired at home', (tester) async {
    answering = {_lan};
    final c = build();
    await tester.runAsync(c.check);
    await pump(tester, c);

    expect(switchValue(tester), isTrue);
    expect(find.text(Errors.finishRemoteAccessAtHome), findsNothing);
  });

  testWidgets('says why the Quark refused this phone', (tester) async {
    answering = {_lan};
    pairFailure = const ApiException(409, 'no household');
    final c = build();
    await tester.runAsync(c.check);
    await pump(tester, c);

    expect(find.text(Errors.quarkRefusedThisPhone), findsOneWidget);
  });
}
