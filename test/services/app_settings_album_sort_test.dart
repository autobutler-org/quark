import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2510: the Photos sidebar's album order is a client-side preference, so it
/// has to survive a restart and default to A-Z, the order the sidebar always
/// showed before a sort control existed.
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

  test('defaults to A-Z until changed', () async {
    await loadWith({});

    expect(settings.albumSort.value, AlbumSort.nameAsc);
  });

  test('reads a persisted order on load', () async {
    await loadWith({'albumSort': 'oldest'});

    expect(settings.albumSort.value, AlbumSort.oldest);
  });

  test('an unrecognized persisted value falls back to the default', () async {
    await loadWith({'albumSort': 'garbage'});

    expect(settings.albumSort.value, AlbumSort.nameAsc);
  });

  test('setAlbumSort publishes and persists the order', () async {
    await loadWith({});

    await settings.setAlbumSort(AlbumSort.newest);

    expect(settings.albumSort.value, AlbumSort.newest);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('albumSort'), 'newest');
  });
}
