import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// #4217: a thumbnail URL names the photo's version in `v`, so the Quark can
/// serve it as immutable, and a new version is a new URL and a new store entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stored = <String, String>{};
  final settings = AppSettings.instance;

  setUpAll(() {
    mockSecureStorage(stored);
  });

  setUp(() async {
    stored.clear();
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
    await settings.setUsername('ada');
    await settings.setSessionToken('token-a');
  });

  Uri thumbnail({String? version}) => FilesService.constructThumbnailUrl(
    '/photos/beach.jpg',
    size: 'md',
    version: version,
  );

  test('a version goes in v beside the other parameters', () {
    final url = thumbnail(version: '1700000000.1');
    expect(url.path, '/api/v0/thumbnails/photos/beach.jpg');
    expect(url.queryParameters['v'], '1700000000.1');
    expect(url.queryParameters['size'], 'md');
  });

  test('without a version the URL is unversioned, as before', () {
    expect(thumbnail().queryParameters.containsKey('v'), isFalse);
  });

  test('a rotation is a new URL and a new store entry', () {
    final before = thumbnail(version: '1700000000.0');
    final after = thumbnail(version: '1700000000.1');
    expect(after, isNot(before));
    expect(
      ThumbnailCacheManager.keyFor(after),
      isNot(ThumbnailCacheManager.keyFor(before)),
    );
  });
}
