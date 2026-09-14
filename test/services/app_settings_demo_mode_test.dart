import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1746: demo mode is a client-side switch. It has to survive a restart, so
/// a demo set up the night before is still on in the morning, and it has to
/// default off so nobody sees sample content they never asked for.
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

    expect(settings.demoMode.value, isFalse);
  });

  test('reads the persisted flag on load', () async {
    await loadWith({'demoMode': true});

    expect(settings.demoMode.value, isTrue);
  });

  test('switching it on publishes and persists', () async {
    await loadWith({});

    await settings.setDemoMode(true);

    expect(settings.demoMode.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('demoMode'), isTrue);
  });

  test('switching it off again clears the persisted flag', () async {
    await loadWith({'demoMode': true});

    await settings.setDemoMode(false);

    expect(settings.demoMode.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('demoMode'), isFalse);
  });
}
