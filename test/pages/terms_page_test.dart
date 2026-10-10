import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/terms/agree_button.dart';

/// #2064: saving a new Quark replaced the flow with the full terms and an
/// I Agree button, with nothing on the page tying them to the Quark that had
/// just been added. It read as a hijack rather than a step of adding a host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    // The session token lives in secure storage on native platforms, and
    // there's no plugin behind it in a unit test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  final settings = AppSettings.instance;
  final intro = find.byKey(const ValueKey('terms_host_intro'));

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(clearHosts);
  tearDown(clearHosts);

  Future<void> pumpTerms(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TermsPage()));
    await tester.pumpAndSettle();
  }

  for (final (label, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$label: says which Quark the terms are for and why', (
      tester,
    ) async {
      await settings.addHost(
        HostEntry(name: 'Attic', hostAddress: 'https://quark-2064.local'),
      );
      await pumpTerms(tester, size);

      expect(intro, findsOneWidget);
      expect(
        find.descendant(of: intro, matching: find.textContaining('Attic')),
        findsOneWidget,
      );
      // Above the terms, so it is read before the wall of text it explains.
      expect(
        tester.getTopLeft(intro).dy,
        lessThan(tester.getTopLeft(find.text('Terms and Conditions')).dy),
      );
      expect(find.byType(AgreeButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a Quark saved without a name is still explained', (
    tester,
  ) async {
    await settings.addHost(
      HostEntry(name: '', hostAddress: 'https://quark-2064.local'),
    );
    await pumpTerms(tester, const Size(360, 640));

    expect(
      find.descendant(of: intro, matching: find.textContaining('this Quark')),
      findsOneWidget,
    );
  });

  testWidgets('rereading accepted terms carries no intro', (tester) async {
    await settings.addHost(
      HostEntry(name: 'Attic', hostAddress: 'https://quark-2064.local'),
    );
    await settings.acceptTerms();
    await pumpTerms(tester, const Size(360, 640));

    expect(intro, findsNothing);
  });

  testWidgets('no Quark configured carries no intro', (tester) async {
    await pumpTerms(tester, const Size(360, 640));

    expect(intro, findsNothing);
  });
}
