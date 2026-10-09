import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/services/app_settings.dart';

/// #2053: the header button is the one place the theme changes. Settings shows
/// the mode it set, follows it as it changes, and offers no second control.
void main() {
  final settings = AppSettings.instance;

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  tearDown(() => settings.setThemeMode(ThemeMode.system));

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();
  }

  const row = ValueKey('settings_theme_mode');
  const toggle = ValueKey('theme_toggle');

  Finder inRow(String text) =>
      find.descendant(of: find.byKey(row), matching: find.text(text));

  testWidgets('Settings follows every tap of the header button', (
    tester,
  ) async {
    await settings.setThemeMode(ThemeMode.system);
    await pumpSettings(tester);

    expect(inRow('Matches your device'), findsOneWidget);

    await tester.tap(find.byKey(toggle));
    await tester.pump();
    expect(settings.themeMode.value, ThemeMode.light);
    expect(inRow('Light'), findsOneWidget);

    await tester.tap(find.byKey(toggle));
    await tester.pump();
    expect(settings.themeMode.value, ThemeMode.dark);
    expect(inRow('Dark'), findsOneWidget);

    await tester.tap(find.byKey(toggle));
    await tester.pump();
    expect(settings.themeMode.value, ThemeMode.system);
    expect(inRow('Matches your device'), findsOneWidget);
  });

  testWidgets('Settings has no second theme control', (tester) async {
    await pumpSettings(tester);

    expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
    expect(find.byKey(toggle), findsOneWidget);
  });
}
