import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2509: the photo grid's sort field and order are a client-side preference,
/// so it has to survive a restart and default to added/desc — the order the
/// grid always showed before a sort control existed.
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

  test('defaults to added/desc until changed', () async {
    await loadWith({});

    expect(settings.photoSortField.value, PhotoSortField.added);
    expect(settings.photoSortOrder.value, PhotoSortOrder.desc);
  });

  test('reads a persisted sort on load', () async {
    await loadWith({'photoSortField': 'name', 'photoSortOrder': 'asc'});

    expect(settings.photoSortField.value, PhotoSortField.name);
    expect(settings.photoSortOrder.value, PhotoSortOrder.asc);
  });

  test('an unrecognized persisted value falls back to the default', () async {
    await loadWith({'photoSortField': 'garbage', 'photoSortOrder': 'garbage'});

    expect(settings.photoSortField.value, PhotoSortField.added);
    expect(settings.photoSortOrder.value, PhotoSortOrder.desc);
  });

  test('setPhotoSort publishes and persists both values', () async {
    await loadWith({});

    await settings.setPhotoSort(PhotoSortField.name, PhotoSortOrder.asc);

    expect(settings.photoSortField.value, PhotoSortField.name);
    expect(settings.photoSortOrder.value, PhotoSortOrder.asc);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('photoSortField'), 'name');
    expect(prefs.getString('photoSortOrder'), 'asc');
  });
}
