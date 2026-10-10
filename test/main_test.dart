import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/main.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3071: turning on high contrast used to discard the theme color. All four
/// of the app's theme slots follow it now, so the Settings switch and the
/// platform's contrast setting give the same themed result.
void main() {
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final settings = AppSettings.instance;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    SharedPreferences.setMockInitialValues({});
    await settings.load();
  });

  tearDown(() {
    settings.themeColor.value = QuarkThemeColor.classic;
    settings.highContrast.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('high contrast follows the theme color ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      QuarkTokens tokens(ThemeData? theme) => theme!.extension<QuarkTokens>()!;
      QuarkTokens high(QuarkThemeColor themeColor, Brightness brightness) =>
          themeColor.tokensFor(brightness, highContrast: true);

      settings.themeColor.value = QuarkThemeColor.violet;
      await tester.pumpWidget(const QuarkApp());

      // Off: the everyday slots wear the color, and the pair the platform's
      // contrast setting selects already does too.
      const violet = QuarkThemeColor.violet;
      expect(tokens(app().theme), violet.tokensFor(Brightness.light));
      expect(tokens(app().darkTheme), violet.tokensFor(Brightness.dark));
      expect(tokens(app().highContrastTheme), high(violet, Brightness.light));
      expect(
        tokens(app().highContrastDarkTheme),
        high(violet, Brightness.dark),
      );

      // The Settings switch puts the same themed pair in the everyday slots.
      settings.highContrast.value = true;
      await tester.pump();
      expect(tokens(app().theme), high(violet, Brightness.light));
      expect(tokens(app().darkTheme), high(violet, Brightness.dark));
      expect(
        tokens(app().theme).primary,
        isNot(QuarkTokens.highContrastLight.primary),
      );

      // Changing the color with high contrast on changes the app.
      const pink = QuarkThemeColor.pink;
      settings.themeColor.value = pink;
      await tester.pump();
      for (final theme in [app().theme, app().highContrastTheme]) {
        expect(tokens(theme), high(pink, Brightness.light));
      }
      for (final theme in [app().darkTheme, app().highContrastDarkTheme]) {
        expect(tokens(theme), high(pink, Brightness.dark));
      }

      // And the color survives turning high contrast back off.
      settings.highContrast.value = false;
      await tester.pump();
      expect(tokens(app().theme), pink.tokensFor(Brightness.light));
      expect(tokens(app().darkTheme), pink.tokensFor(Brightness.dark));
    });
  }
}
