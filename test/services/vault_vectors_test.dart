// cspell:words EXAMPLE bücher generichash mple octocat
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_vault.dart';

/// The vector file the Swift (`ios/QuarkVaultCrypto`) and Kotlin
/// (`android/app/src/test`) vault code is tested against (#3597).
const _vectorsPath = 'test/fixtures/vault_vectors.json';

/// Set by `make generate/frontend/vault-vectors`, which rewrites the file
/// from what this Dart computes instead of comparing against it.
const _write = bool.fromEnvironment('WRITE_VAULT_VECTORS');

Uint8List _bytes(int start, int length) =>
    Uint8List.fromList(List.generate(length, (i) => start + i));

// The wrap and the item quark-browser-extensions pins
// (test/vaultCrypto.test.ts), sealed with the libsodium the app links over
// these fixed keys and nonces, so the app, the extension, iOS and Android all
// pin the same bytes.
final _salt = _bytes(0, 16);
final _vaultKey = _bytes(32, 32);
const _wrapped =
    'ZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7M45niWoOxKIqWBomnR5XGosNWUs6nlDxxGALxh6o2U//gocn6gTU3XzufauINP3w';
const _itemNonce = 'yMnKy8zNzs/Q0dLT1NXW19jZ2tvc3d7f';
const _itemCiphertext =
    'nRaocNRVSI97ErtFpUexy2+9h8kAqG70gerDdF5P675IgeOVPdkDuqzFkVmzbpFM+Jfna+dFb34+av88LMwq3ipSUGgEPW1DZlNDSrWtUBcSf5nbRpfgSq0IklWPVq5zk044OjmSJH5CzvkxVoP15Vct/TqTfh3bUj8nmM/nTbLNztgj9IsKPbhA8EuF5W18linIKjueXmvvV+yKb/KxDwgAwoBXJ+yT7rk/VeWj8V8VIlyRieyY82Bf/1r/wvconShHc+DoPSnFs/8m0W4EcRRwO9mlue1TEtqWcQy+3ZFp+SNx/Kw=';

/// What `crypto_generichash(16, "quark-vault-key-fingerprint-v1", key)` is
/// keyed with: docs/design/native-autofill-vault.md, "Detecting a stale
/// cached key".
const _fingerprintMessage = 'quark-vault-key-fingerprint-v1';

const _hostUrls = [
  'https://GitHub.com/login',
  ' https://github.com/login ',
  'example.com/login',
  'EXAMPLE.COM',
  'https://example.com:8443/x',
  'https://example.com?q=1',
  'https://example.com#top',
  'https://example.com.',
  'http://192.168.1.10:8080/admin',
  'https://grace:pw@example.com/',
  'ftp://files.example.com',
  'HTTPS://Example.com',
  'mailto:grace@example.com',
  'example.com/?next=https://evil.com',
  'https://exa%20mple.com',
  'https://ex%41mple.com',
  'http://exa mple.com',
  'https://bücher.de',
  'https://a_b.example.com',
  'https://ex%2Eample.com',
  'https://[2001:DB8::1]:8443/x',
  'https://[::1:8]',
  r'http://ex\ample.com',
  'https://grace:pw:x@example.com',
  'https://a@b@example.com',
  '//example.com/a://b',
  'https://example.com:0x1F/',
  'https://example.com: /',
  'javascript:alert(1)',
  'https://example.com:abc/',
  'https:///path',
  '1http://example.com',
  'not a url at all',
  '',
  '   ',
];

const _matchCases = [
  ('https://example.com/login', 'example.com'),
  ('https://accounts.example.com', 'example.com'),
  ('https://login.mail.example.com/x', 'mail.example.com'),
  ('https://example.com', 'accounts.example.com'),
  ('https://badexample.com', 'example.com'),
  ('https://example.com.evil.com', 'example.com'),
  ('HTTPS://EXAMPLE.COM', 'https://example.com/x'),
  ('https://example.com:8443', 'example.com:443'),
  ('http://192.168.1.10:8080', '192.168.1.10'),
  ('http://192.168.1.100', '192.168.1.10'),
  ('https://exa%20mple.com', 'exa%20mple.com'),
  ('not a url at all', 'not a url at all'),
  ('example.com', ''),
];

const _itemJson = [
  (
    'every field',
    '{"kind":"entry","name":"GitHub","url":"https://github.com/login",'
        '"username":"octocat","password":"hunter2","notes":"two\\nlines",'
        '"totpSecret":"JBSWY3DPEHPK3PXP","customFields":[{"label":"pin",'
        '"value":"1234","hidden":true}],"folderId":7}',
  ),
  ('the fewest fields', '{"kind":"entry","name":"Bank"}'),
  ('a folder', '{"kind":"folder","name":"Work"}'),
  ('no kind is an entry', '{"name":"Old"}'),
  (
    'an unknown key is ignored',
    '{"kind":"entry","name":"Mail","url":"mail.example.com","passkey":"x"}',
  ),
  (
    'null reads as empty',
    '{"kind":"entry","name":null,"url":null,"folderId":null}',
  ),
  ('a custom field missing parts', '{"name":"F","customFields":[{}]}'),
  ('a folder id written as a double', '{"name":"D","folderId":3.0}'),
  ('an unknown kind', '{"kind":"passkey","name":"X"}'),
  ('a name that is not a string', '{"kind":"entry","name":5}'),
  (
    'hidden that is not a bool',
    '{"name":"H","customFields":[{"label":"a","value":"b","hidden":1}]}',
  ),
  ('custom fields that are not a list', '{"name":"L","customFields":{}}'),
  ('a folder id that is not a number', '{"name":"N","folderId":"7"}'),
  ('not an object', '[]'),
];

/// Computes every vector from the Dart implementation, then either writes
/// [_vectorsPath] (`make generate/frontend/vault-vectors`) or fails if the
/// committed file has drifted from what Dart computes. Either way each
/// vector is checked against Dart first, so a file this writes is one Dart
/// agrees with.
void main() {
  late AccountCrypto crypto;

  setUpAll(() async => crypto = await AccountCrypto.load());

  test('the vault vectors are what the Dart implementation computes', () async {
    final vectors = {
      '_comment':
          'Generated from test/services/vault_vectors_test.dart by '
          '`make generate/frontend/vault-vectors`; do not edit by hand. Read '
          'by that test, ios/QuarkVaultCrypto and android/app/src/test '
          '(#3597). Keys are byte arrays, so secret scanners do not read a test '
          'key as a leaked credential; other bytes are standard padded base64.',
      'wrap': _wrapVectors(crypto),
      'item': _itemVectors(crypto),
      'fingerprints': [
        for (final key in [_vaultKey, _bytes(0, 32)])
          {
            'key': key,
            'fingerprint': base64Encode(
              crypto.sodium.crypto.genericHash(
                message: utf8.encode(_fingerprintMessage),
                outLen: 16,
                key: crypto.sodium.secureCopy(key),
              ),
            ),
          },
      ],
      'hosts': [
        for (final url in _hostUrls)
          {'url': url, 'host': VaultItemData.hostOf(url)},
      ],
      'matches': await _matchVectors(crypto),
      'itemJson': [
        for (final (name, json) in _itemJson) _itemJsonVector(name, json),
      ],
    };

    // One byte array per line, rather than one byte per line.
    final text = '${const JsonEncoder.withIndent('  ').convert(vectors)}\n'
        .replaceAllMapped(
          RegExp(r'\[\s+(\d+(?:,\s+\d+)*)\s+\]'),
          (m) => '[${m[1]!.replaceAll(RegExp(r',\s+'), ', ')}]',
        );
    final file = File(_vectorsPath);
    if (_write) {
      file.writeAsStringSync(text);
      return;
    }
    expect(
      file.readAsStringSync(),
      text,
      reason:
          '$_vectorsPath has drifted from the Dart implementation; run '
          '`make generate/frontend/vault-vectors` if the change is meant',
    );
  });
}

Map<String, Object?> _wrapVectors(AccountCrypto crypto) {
  const password = 'correct horse battery staple';
  final keys = crypto.deriveAuthKeys(password, _salt, KdfParams.standard);
  addTearDown(keys.dispose);
  final wrapped = base64Decode(_wrapped);

  final opened = crypto.unwrapVaultKey(
    WrappedSecret(wrapped: wrapped, salt: _salt),
    keys.vaultWrapKey,
    wrongSecret: 'wrong',
  );
  addTearDown(opened.dispose);
  expect(opened.extractBytes(), _vaultKey);

  final item = Uint8List.fromList([
    ...base64Decode(_itemNonce),
    ...base64Decode(_itemCiphertext),
  ]);
  final rejections = [
    ('a wrong key', _bytes(0, 32), wrapped),
    ('a flipped byte', null, _flip(wrapped, 30)),
    ('no room for a nonce', null, _bytes(0, 24)),
    ('an item, which carries additional data', _vaultKey, item),
  ];
  final wrapKey = keys.vaultWrapKey.extractBytes();
  for (final (name, key, bytes) in rejections) {
    expect(
      () => crypto.unwrapWithKey(
        WrappedSecret(wrapped: bytes, salt: _salt),
        crypto.sodium.secureCopy(key ?? wrapKey),
        wrongSecret: 'wrong',
      ),
      throwsA(isA<MessageException>()),
      reason: name,
    );
  }

  return {
    '_source':
        'The vault wrap key test/services/account_crypto_test.dart pins, and '
        'the wrap quark-browser-extensions pins in test/vaultCrypto.test.ts. '
        'Native code checks only the unwrap: it never runs Argon2id.',
    'password': password,
    'salt': base64Encode(_salt),
    'kdfParams': {
      'opsLimit': KdfParams.standard.opsLimit,
      'memLimit': KdfParams.standard.memLimit,
    },
    'vaultWrapKey': wrapKey,
    'wrapped': _wrapped,
    'vaultKey': _vaultKey,
    'rejections': [
      for (final (name, key, bytes) in rejections)
        {'name': name, 'key': key ?? wrapKey, 'wrapped': base64Encode(bytes)},
    ],
  };
}

Map<String, Object?> _itemVectors(AccountCrypto crypto) {
  final ciphertext = base64Decode(_itemCiphertext);
  final nonce = base64Decode(_itemNonce);
  final key = crypto.sodium.secureCopy(_vaultKey);
  addTearDown(key.dispose);

  final plaintext = crypto.decryptVaultItem(
    ciphertext,
    nonce,
    key,
    formatVersion: 1,
    wrongKey: 'wrong',
  );

  final rejections = [
    ('a wrong key', _bytes(0, 32), nonce, 1, ciphertext),
    ('format version 2', _vaultKey, nonce, 2, ciphertext),
    ('a flipped byte', _vaultKey, nonce, 1, _flip(ciphertext, 0)),
    ('a 23-byte nonce', _vaultKey, nonce.sublist(0, 23), 1, ciphertext),
    ('shorter than the tag', _vaultKey, nonce, 1, ciphertext.sublist(0, 15)),
  ];
  for (final (name, k, n, version, c) in rejections) {
    expect(
      () => crypto.decryptVaultItem(
        c,
        n,
        crypto.sodium.secureCopy(k),
        formatVersion: version,
        wrongKey: 'wrong',
      ),
      throwsA(isA<MessageException>()),
      reason: name,
    );
  }

  return {
    '_source':
        'The item quark-browser-extensions pins in test/vaultCrypto.test.ts. '
        'Sealing plaintext under key and nonce gives ciphertext exactly.',
    'key': _vaultKey,
    'nonce': _itemNonce,
    'formatVersion': 1,
    'ciphertext': _itemCiphertext,
    'plaintext': utf8.decode(plaintext),
    'rejections': [
      for (final (name, k, n, version, c) in rejections)
        {
          'name': name,
          'key': k,
          'nonce': base64Encode(n),
          'formatVersion': version,
          'ciphertext': base64Encode(c),
        },
    ],
  };
}

/// Each case asks the real [VaultController.entriesForUrl] whether an entry
/// saved for the site matches the URL.
Future<List<Map<String, Object?>>> _matchVectors(AccountCrypto crypto) async {
  final c = FakeVault().controller(crypto);
  addTearDown(c.dispose);
  await c.load();
  await c.setUp('one-password');
  final out = <Map<String, Object?>>[];
  for (final (i, (url, site)) in _matchCases.indexed) {
    await c.save(
      VaultItemData(kind: VaultItemKind.entry, name: 'case $i', url: site),
    );
    out.add({
      'url': url,
      'site': site,
      'matches': c.entriesForUrl(url).any((e) => e.data.name == 'case $i'),
    });
  }
  return out;
}

Map<String, Object?> _itemJsonVector(String name, String json) {
  VaultItemData item;
  try {
    item = VaultItemData.decode(utf8.encode(json));
  } catch (_) {
    return {'name': name, 'json': json, 'error': true};
  }
  return {
    'name': name,
    'json': json,
    'item': {
      'kind': item.kind.name,
      'name': item.name,
      'url': item.url,
      'username': item.username,
      'password': item.password,
      'notes': item.notes,
      'totpSecret': item.totpSecret,
      'customFields': [for (final f in item.customFields) f.toJson()],
      'folderId': item.folderId,
    },
  };
}

Uint8List _flip(Uint8List bytes, int at) => Uint8List.fromList([
  for (final (i, b) in bytes.indexed) i == at ? b ^ 1 : b,
]);
