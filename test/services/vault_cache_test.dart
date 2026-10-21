import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/native_vault_cache.dart';
import 'package:quark/services/vault_cache.dart';

void main() {
  group('VaultCache.accountKey', () {
    test('is the doc\'s acct_ name over the normalized host and username', () {
      // hex(sha256("https://quark.local" || 0x00 || "grace"))[0:32]
      const expected = 'acct_2b22282581c9778f494250e1b20e6bbb';
      expect(VaultCache.accountKey('https://quark.local', 'grace'), expected);
      expect(VaultCache.accountKey('quark.local', 'grace'), expected);
      expect(VaultCache.accountKey('HTTPS://Quark.Local/', 'grace'), expected);
    });

    test('differs by account and by Quark', () {
      final a = VaultCache.accountKey('https://quark.local', 'grace');
      expect(VaultCache.accountKey('https://quark.local', 'ada'), isNot(a));
      expect(VaultCache.accountKey('https://other.local', 'grace'), isNot(a));
    });
  });

  test('encode writes the server\'s ciphertext, base64 for base64', () {
    final serverJson = [
      {
        'id': 7,
        'ciphertext': base64Encode(List.generate(40, (i) => i)),
        'nonce': base64Encode(List.generate(24, (i) => 200 + i % 50)),
        'formatVersion': 1,
      },
    ];
    final items = [
      for (final item in serverJson) VaultCiphertext.fromJson(item),
    ];
    final json =
        jsonDecode(
              VaultCache.encode(
                host: 'https://quark.local',
                username: 'grace',
                items: items,
                syncedAt: DateTime.utc(2026, 10, 20, 12),
              ),
            )
            as Map<String, dynamic>;
    expect(json, {
      'schema': 1,
      'host': 'https://quark.local',
      'username': 'grace',
      'syncedAt': '2026-10-20T12:00:00.000Z',
      'items': serverJson,
    });
  });

  group('NativeVaultCache', () {
    late Directory root;
    late NativeVaultCache cache;

    setUp(() {
      root = Directory.systemTemp.createTempSync('vault_cache_test');
      cache = NativeVaultCache(
        directory: () async => '${root.path}/${VaultCache.directoryName}',
      );
    });

    tearDown(() => root.deleteSync(recursive: true));

    List<String> names() => [
      for (final f in Directory(
        '${root.path}/${VaultCache.directoryName}',
      ).listSync())
        f.uri.pathSegments.last,
    ]..sort();

    test('write puts one file per account and leaves no temp file', () async {
      await cache.write('acct_a', '{"a":1}');
      await cache.write('acct_a', '{"a":2}');
      expect(names(), ['acct_a.json']);
      expect(
        File(
          '${root.path}/${VaultCache.directoryName}/acct_a.json',
        ).readAsStringSync(),
        '{"a":2}',
      );
    });

    test('write drops every other account\'s file', () async {
      await cache.write('acct_a', '{}');
      await cache.write('acct_b', '{}');
      expect(names(), ['acct_b.json']);
    });

    test('clear removes the directory', () async {
      await cache.write('acct_a', '{}');
      await cache.clear();
      expect(
        Directory('${root.path}/${VaultCache.directoryName}').existsSync(),
        isFalse,
      );
      await cache.clear(); // nothing there is fine
    });

    test('no directory, as on web or desktop, stores nothing', () async {
      final none = NativeVaultCache(directory: () async => null);
      await none.write('acct_a', '{}');
      await none.clear();
    });

    test('the bytes written are exactly the contents given', () async {
      final bytes = Uint8List.fromList(utf8.encode('{"x":"ü"}'));
      await cache.write('acct_a', utf8.decode(bytes));
      expect(
        File(
          '${root.path}/${VaultCache.directoryName}/acct_a.json',
        ).readAsBytesSync(),
        bytes,
      );
    });
  });
}
