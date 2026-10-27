import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/connection_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/device_pairing_store.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/this_phone_card.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _lan = 'https://quark.local';
const _remote = 'http://100.64.0.7:80';

/// #3776: the switch showed on for a phone that never paired, and a refused
/// pairing said nothing. The card now shows where setup really stands.
void main() {
  late bool home;
  late Object? pairFailure;
  late Map<String, StoredPairing> pairings;

  setUp(() {
    home = true;
    pairFailure = null;
    pairings = {};
  });

  ConnectionController controller() => ConnectionController(
    activeHostChanges: ChangeNotifier(),
    probe: (address) async => home && address == _lan,
    readRemoteAccess: () async => const RemoteAccessStatus(
      enabled: true,
      connected: true,
      remoteUrl: _remote,
    ),
    activeHost: () => HostEntry(name: 'Home', hostAddress: _lan),
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
    nodeRejected: () async => false,
    hasDeviceNode: () => true,
    log: (_) {},
  );

  Future<ConnectionController> pump(WidgetTester tester) async {
    final c = controller();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(body: ThisPhoneCard(controller: c)),
      ),
    );
    return c;
  }

  bool switchValue(WidgetTester tester) => tester
      .widget<SwitchListTile>(
        find.byKey(const ValueKey('remote_access_on_this_phone')),
      )
      .value;

  testWidgets('is off and says so before this phone has paired', (
    tester,
  ) async {
    await pump(tester);
    expect(switchValue(tester), isFalse);
    expect(find.text('Not set up yet.'), findsOneWidget);
  });

  testWidgets('is on and ready once paired at home', (tester) async {
    final c = await pump(tester);
    await tester.runAsync(c.check);
    await tester.pump();
    expect(switchValue(tester), isTrue);
    expect(find.text(ConnectionController.readyAway), findsOneWidget);
  });

  testWidgets('says how to finish setup when away and never paired', (
    tester,
  ) async {
    home = false;
    final c = await pump(tester);
    await tester.runAsync(c.check);
    await tester.pump();
    expect(switchValue(tester), isFalse);
    expect(find.text(ConnectionController.finishSetupAtHome), findsOneWidget);
  });

  testWidgets('says why when the Quark cannot add this phone', (tester) async {
    pairFailure = const ApiException(409, 'no household');
    final c = await pump(tester);
    await tester.runAsync(c.check);
    await tester.pump();
    expect(find.text(ConnectionController.quarkCannotAddPhone), findsOneWidget);
  });

  testWidgets('says the Quark is still connecting on a 503', (tester) async {
    pairFailure = const ApiException(503, 'connecting');
    final c = await pump(tester);
    await tester.runAsync(c.check);
    await tester.pump();
    expect(
      find.text(ConnectionController.quarkStillConnecting),
      findsOneWidget,
    );
  });
}
