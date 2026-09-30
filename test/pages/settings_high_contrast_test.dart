import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/services/app_settings.dart';

import '../support/unreachable_quark.dart';

/// #2601: the High contrast switch sits under Theme on Settings, needs no
/// Quark to be configured, and writes straight to [AppSettings].
void main() {
  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  late HttpOverrides? priorOverrides;

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await clearHosts();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await settings.setHighContrast(false);
    await clearHosts();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

  Finder highContrastSwitch() =>
      find.widgetWithText(SwitchListTile, 'High contrast');

  testWidgets('is offered even with no Quark configured', (tester) async {
    await pumpSettings(tester);

    expect(highContrastSwitch(), findsOneWidget);
    expect(tester.widget<SwitchListTile>(highContrastSwitch()).value, isFalse);
  });

  testWidgets('reflects a flag that is already on', (tester) async {
    await settings.setHighContrast(true);

    await pumpSettings(tester);

    expect(tester.widget<SwitchListTile>(highContrastSwitch()).value, isTrue);
  });

  testWidgets('flipping it updates the app setting both ways', (tester) async {
    await pumpSettings(tester);

    await tester.tap(highContrastSwitch());
    await tester.pump();

    expect(settings.highContrast.value, isTrue);
    expect(tester.widget<SwitchListTile>(highContrastSwitch()).value, isTrue);

    await tester.tap(highContrastSwitch());
    await tester.pump();

    expect(settings.highContrast.value, isFalse);
    expect(tester.widget<SwitchListTile>(highContrastSwitch()).value, isFalse);
  });
}
