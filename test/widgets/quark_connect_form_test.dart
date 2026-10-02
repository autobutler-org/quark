import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/quark_connect_form.dart';

/// #2518: a router that appends `.lan` answers for `quark.lan` while the
/// user types the `quark.local` the form suggests. The form tries the other
/// local names before it gives up, and saves the one that answered.
void main() {
  final settings = AppSettings.instance;
  late List<String> probed;
  late bool connected;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    await clearHosts();
    probed = [];
    connected = false;
  });

  tearDown(() async {
    await clearHosts();
    hostReachabilityProbe = AuthService.isReachable;
  });

  Future<void> connect(WidgetTester tester, String typed) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuarkConnectForm(
              onConnected: () => connected = true,
              autofocus: false,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), typed);
    await tester.tap(find.text('Connect'));
    // A connected form keeps its loader spinning for the caller to replace,
    // so it never settles; pump until the probes and the save are through.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a .local that does not answer saves the .lan that does', (
    tester,
  ) async {
    hostReachabilityProbe = (address) async {
      probed.add(address);
      return address == 'https://quark.lan';
    };

    await connect(tester, 'quark.local');

    expect(probed.first, 'https://quark.local');
    expect(settings.activeHostEntry?.hostAddress, 'https://quark.lan');
    expect(connected, isTrue);
  });

  testWidgets('no name answering keeps the user on the form', (tester) async {
    hostReachabilityProbe = (address) async => false;

    await connect(tester, 'quark.local');

    expect(settings.hosts, isEmpty);
    expect(connected, isFalse);
    expect(find.text(Errors.couldNotConnect), findsOneWidget);
  });
}
