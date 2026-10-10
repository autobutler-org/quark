import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/thumbnail_cache_key.dart';

/// #1777: the disk cache was keyed by the thumbnail's URL, which carries the
/// session token, so signing in again threw every cached thumbnail away.
void main() {
  Uri url({
    String base = 'https://quark.local',
    String path = 'photos/beach.jpg',
    String? serial,
    String? size,
    String? token = 'token-a',
  }) => Uri.parse('$base/api/v0/thumbnails/$path').replace(
    queryParameters: {'serial': ?serial, 'size': ?size, 'token': ?token},
  );

  String key(Uri url, {String host = 'quark.local', String account = 'ada'}) =>
      thumbnailCacheKey(url, host: host, account: account);

  test('a rotated token keeps the key', () {
    expect(key(url(token: 'token-b')), key(url()));
    expect(key(url(token: null)), key(url()));
  });

  test('the token is nowhere in the key', () {
    expect(key(url(token: 'secret-token')), isNot(contains('secret-token')));
  });

  test('the address the Quark is reached on does not change the key', () {
    // The same Quark answers at home and over remote access (#1880).
    expect(key(url(base: 'https://abc.relay.example')), key(url()));
  });

  test('path, serial and size each change the key', () {
    final keys = {
      key(url()),
      key(url(path: 'photos/dunes.jpg')),
      key(url(serial: 'usb-1')),
      key(url(size: 'sm')),
      key(url(serial: 'usb-1', size: 'sm')),
    };
    expect(keys, hasLength(5));
  });

  test('another Quark or another account gets its own key', () {
    final keys = {
      key(url()),
      key(url(), host: 'other.local'),
      key(url(), account: 'grace'),
    };
    expect(keys, hasLength(3));
  });

  test('a host, account or path cannot be shifted into its neighbor', () {
    expect(
      thumbnailCacheKey(url(), host: 'a', account: 'b|c'),
      isNot(thumbnailCacheKey(url(), host: 'a|b', account: 'c')),
    );
  });
}
