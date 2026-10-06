import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/settings/settings_general_tab.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2740: the General tab offers every signed-in user an theme color of their own
/// and an admin the Quark's default.
void main() {
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
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

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  const userPicker = ValueKey('settings_theme_color');
  const quarkPicker = ValueKey('settings_quark_theme_color');

  Future<void> pumpTab(
    WidgetTester tester, {
    QuarkThemeColor themeColor = QuarkThemeColor.blue,
    bool followsQuarkThemeColor = true,
    QuarkThemeColor quarkThemeColor = QuarkThemeColor.blue,
    ValueChanged<String>? onThemeColorChanged,
    ValueChanged<String>? onQuarkThemeColorChanged,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SettingsGeneralTab(
            theme: ThemeMode.system,
            onThemeChanged: (_) {},
            themeColor: themeColor,
            followsQuarkThemeColor: followsQuarkThemeColor,
            quarkThemeColor: quarkThemeColor,
            onThemeColorChanged: onThemeColorChanged,
            onQuarkThemeColorChanged: onQuarkThemeColorChanged,
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

  Finder within(ValueKey<String> picker, String key) =>
      find.descendant(of: find.byKey(picker), matching: find.byKey(Key(key)));

  testWidgets('signed out, there is no theme color to pick', (tester) async {
    await pumpTab(tester);

    expect(find.byType(QuarkThemeColorPicker), findsNothing);
    expect(find.text('Theme color'), findsNothing);
  });

  testWidgets('a member gets their own picker and no Quark default', (
    tester,
  ) async {
    await pumpTab(tester, onThemeColorChanged: (_) {});

    expect(find.text('Theme color'), findsOneWidget);
    expect(find.byKey(userPicker), findsOneWidget);
    expect(find.text("This Quark's default"), findsNothing);
    expect(find.byKey(quarkPicker), findsNothing);
  });

  testWidgets('an admin gets both pickers', (tester) async {
    await pumpTab(
      tester,
      themeColor: QuarkThemeColor.violet,
      followsQuarkThemeColor: false,
      quarkThemeColor: QuarkThemeColor.lime,
      onThemeColorChanged: (_) {},
      onQuarkThemeColorChanged: (_) {},
    );

    expect(find.text("This Quark's default"), findsOneWidget);
    final user = tester.widget<QuarkThemeColorPicker>(find.byKey(userPicker));
    expect(user.value, QuarkThemeColor.violet);
    expect(user.usingDefault, isFalse);
    expect(user.onUseDefault, isNotNull);
    final quark = tester.widget<QuarkThemeColorPicker>(find.byKey(quarkPicker));
    expect(quark.value, QuarkThemeColor.lime);
    // The Quark's default has no default of its own to fall back to.
    expect(quark.onUseDefault, isNull);
    expect(within(quarkPicker, 'theme_color_use_default'), findsNothing);
  });

  testWidgets('each picker reports storage strings to its own callback', (
    tester,
  ) async {
    final mine = <String>[];
    final quarks = <String>[];
    await pumpTab(
      tester,
      onThemeColorChanged: mine.add,
      onQuarkThemeColorChanged: quarks.add,
    );

    await tester.tap(within(userPicker, 'theme_color_swatch_violet'));
    await tester.tap(within(userPicker, 'theme_color_use_default'));
    await tester.tap(within(quarkPicker, 'theme_color_swatch_lime'));
    await tester.tap(within(quarkPicker, 'theme_color_custom'));

    // Empty is "follow this Quark".
    expect(mine, ['violet', '']);
    expect(quarks.first, 'lime');
    expect(quarks.last, matches(RegExp(r'^#[0-9a-f]{6}$')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('following the Quark marks the default choice', (tester) async {
    await pumpTab(
      tester,
      themeColor: QuarkThemeColor.lime,
      quarkThemeColor: QuarkThemeColor.lime,
      onThemeColorChanged: (_) {},
    );

    final picker = tester.widget<QuarkThemeColorPicker>(find.byKey(userPicker));
    expect(picker.usingDefault, isTrue);
    expect(picker.value, QuarkThemeColor.lime);
  });
}
