import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/login/active_host_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2069: opening Change host showed the active Quark on the summary card
/// and again as the selected radio, so the address appeared twice. While
/// the list is open the card is only the heading and the Done button.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  const name = 'Cabin';
  const address = 'http://10.0.2.2:8080';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': name, 'hostAddress': address},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
  });

  Future<void> pumpCard(
    WidgetTester tester,
    Size size, {
    required bool managingHosts,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveHostCard(
            managingHosts: managingHosts,
            onToggleManagingHosts: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (label, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$label: collapsed shows the host address once', (
      tester,
    ) async {
      await pumpCard(tester, size, managingHosts: false);

      expect(find.text(address), findsOneWidget);
      expect(find.text(name), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Choose a Quark'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: expanded does not repeat the address', (tester) async {
      await pumpCard(tester, size, managingHosts: true);

      expect(find.text('Choose a Quark'), findsOneWidget);
      expect(find.text(address), findsNothing);
      expect(find.text(name), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
