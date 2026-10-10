import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/services/app_settings.dart';

import '../../support/unreachable_quark.dart';

/// #2053: the app bar's theme toggle and the Theme radios in Settings show one
/// setting, so changing it from either moves the other.
void main() {
  final settings = AppSettings.instance;

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const toggle = ValueKey('theme_toggle');

  late HttpOverrides? priorOverrides;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await settings.setThemeMode(ThemeMode.system);
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    await settings.setThemeMode(ThemeMode.system);
  });

  Future<void> pumpSettings(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Settings overflows its own app bar at any viewport; ignore only that.
    final priorOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = priorOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      priorOnError?.call(details);
    };

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  ThemeMode? selectedRadio(WidgetTester tester) => tester
      .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>))
      .groupValue;

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: the app bar toggle moves the Theme radios', (
      tester,
    ) async {
      await pumpSettings(tester, size);
      expect(selectedRadio(tester), ThemeMode.system);

      await tester.tap(find.byKey(toggle));
      await tester.pump();

      expect(settings.themeMode.value, ThemeMode.light);
      expect(selectedRadio(tester), ThemeMode.light);

      await tester.tap(find.byKey(toggle));
      await tester.pump();

      expect(selectedRadio(tester), ThemeMode.dark);
    });

    testWidgets('$name: a Theme radio moves the app bar toggle', (
      tester,
    ) async {
      await pumpSettings(tester, size);

      await tester.ensureVisible(find.text('Dark'));
      await tester.pump();
      await tester.tap(find.text('Dark'));
      await tester.pump();

      expect(settings.themeMode.value, ThemeMode.dark);
      expect(selectedRadio(tester), ThemeMode.dark);
      expect(find.byTooltip('Switch to light mode'), findsOneWidget);

      await tester.ensureVisible(find.text('System'));
      await tester.pump();
      await tester.tap(find.text('System'));
      await tester.pump();

      expect(settings.themeMode.value, ThemeMode.system);
      expect(selectedRadio(tester), ThemeMode.system);
    });
  }
}
