import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2601: the high-contrast switch survives a restart and defaults off, so
/// the platform's own high-contrast setting decides until the user does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  final settings = AppSettings.instance;

  Future<void> loadWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await settings.load();
  }

  test('is off until switched on', () async {
    await loadWith({});

    expect(settings.highContrast.value, isFalse);
  });

  test('reads the persisted flag on load', () async {
    await loadWith({'highContrast': true});

    expect(settings.highContrast.value, isTrue);
  });

  test('switching it publishes and persists both ways', () async {
    await loadWith({});
    final prefs = await SharedPreferences.getInstance();

    await settings.setHighContrast(true);
    expect(settings.highContrast.value, isTrue);
    expect(prefs.getBool('highContrast'), isTrue);

    await settings.setHighContrast(false);
    expect(settings.highContrast.value, isFalse);
    expect(prefs.getBool('highContrast'), isFalse);
  });
}
