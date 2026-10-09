import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/settings/settings_general_tab.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2601: the General tab's high-contrast switch, for a platform with no
/// contrast setting of its own, and the setting it saves.
void main() {
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const toggle = ValueKey('settings_high_contrast');

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    // The tab's host manager reads the saved hosts.
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
    });
    await AppSettings.instance.load();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    required Size size,
    bool highContrast = false,
    ValueChanged<bool>? onHighContrastChanged,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SettingsGeneralTab(
            theme: ThemeMode.system,
            onThemeChanged: (_) {},
            highContrast: highContrast,
            onHighContrastChanged: onHighContrastChanged,
            themeColor: QuarkThemeColor.classic,
            followsQuarkThemeColor: true,
            quarkThemeColor: QuarkThemeColor.classic,
            refreshIntervalSeconds: 15,
            onRefreshIntervalChanged: (_) {},
            demoMode: false,
            onDemoModeChanged: (_) {},
            onHostsChanged: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: flipping the switch reports the new value', (
      tester,
    ) async {
      bool? reported;
      await pumpTab(
        tester,
        size: size,
        onHighContrastChanged: (v) => reported = v,
      );

      expect(find.text('High contrast'), findsOneWidget);
      await tester.ensureVisible(find.byKey(toggle));
      await tester.tap(find.byKey(toggle));
      expect(reported, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: the switch shows the saved value', (tester) async {
      await pumpTab(
        tester,
        size: size,
        highContrast: true,
        onHighContrastChanged: (_) {},
      );

      final tile = tester.widget<SwitchListTile>(find.byKey(toggle));
      expect(tile.value, isTrue);
    });
  }

  testWidgets('without a handler there is no switch', (tester) async {
    await pumpTab(tester, size: const Size(1280, 800));

    expect(find.byKey(toggle), findsNothing);
  });

  test('the setting is off by default and survives a reload', () async {
    expect(AppSettings.instance.highContrast.value, isFalse);

    await AppSettings.instance.setHighContrast(true);
    AppSettings.instance.highContrast.value = false;
    await AppSettings.instance.load();

    expect(AppSettings.instance.highContrast.value, isTrue);
  });
}
