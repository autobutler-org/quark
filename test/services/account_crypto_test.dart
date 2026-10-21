import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/utils/error_text.dart';

/// Argon2id's floor, so the suite spends its time on logic rather than the
/// KDF. The shipped cost is [KdfParams.standard].
const _cheap = KdfParams(opsLimit: 1, memLimit: 8192);

const _wrong = 'wrong secret';

/// Real libsodium, built for the test host by the `sodium` package's build
/// hook. Chat's own vectors are pinned in `chat_crypto_test.dart`.
void main() {
  late AccountCrypto crypto;
  final salt = Uint8List.fromList(List.generate(16, (i) => i));

  setUpAll(() async => crypto = await AccountCrypto.load());

  // Computed outside this codebase, as chat's vectors are: Go's x/crypto
  // argon2.IDKey (3 passes, 64 MiB, 1 lane, 32 bytes) and hkdf.New(sha256,
  // master, nil, info). Vaults depend on this never changing.
  test('the vault wrap keys are pinned by fixed vectors', () {
    final password = crypto.deriveAuthKeys(
      'correct horse battery staple',
      salt,
      KdfParams.standard,
    );
    final phrase = crypto.deriveRecoveryKeys(
      'abandon-ability-able-about-above-absent',
      salt,
      KdfParams.standard,
    );
    addTearDown(password.dispose);
    addTearDown(phrase.dispose);

    expect(
      base64Encode(password.vaultWrapKey.extractBytes()),
      'v/TmPg0XmN2JiMZAMQUHkHZQ7jNwNtgxdiFD9MZRlEE=',
    );
    expect(
      base64Encode(phrase.vaultWrapKey.extractBytes()),
      'mZlMPn/Xus0XDDf+hjswgPSV8UrCzTQL+Njry/yeTAA=',
    );
  });

  test('the vault wrap key is neither the auth key nor the chat wrap key', () {
    final keys = crypto.deriveAuthKeys('one-password', salt, _cheap);
    addTearDown(keys.dispose);

    final vault = keys.vaultWrapKey.extractBytes();
    expect(vault, isNot(base64Decode(keys.authKey)));
    expect(vault, isNot(keys.wrapKey.extractBytes()));
  });

  test('a vault key is random and 32 bytes', () {
    final a = crypto.generateVaultKey();
    final b = crypto.generateVaultKey();
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    expect(a.extractBytes(), hasLength(32));
    expect(a.extractBytes(), isNot(b.extractBytes()));
  });

  group('the vault key wrap', () {
    test('opens with the password and with the phrase', () {
      final vaultKey = crypto.generateVaultKey();
      final password = crypto.deriveAuthKeys('one-password', salt, _cheap);
      final phrase = crypto.deriveRecoveryKeys('apple-bread', salt, _cheap);
      addTearDown(vaultKey.dispose);
      addTearDown(password.dispose);
      addTearDown(phrase.dispose);

      for (final keys in [password, phrase]) {
        final wrapped = crypto.wrapVaultKey(vaultKey, keys.vaultWrapKey, salt);
        expect(wrapped.salt, salt);

        // Re-derived, the way the next unlock or recovery would.
        final again = keys == password
            ? crypto.deriveAuthKeys('one-password', salt, _cheap)
            : crypto.deriveRecoveryKeys('Apple-Bread', salt, _cheap);
        addTearDown(again.dispose);
        final opened = crypto.unwrapVaultKey(
          wrapped,
          again.vaultWrapKey,
          wrongSecret: _wrong,
        );
        addTearDown(opened.dispose);
        expect(opened.extractBytes(), vaultKey.extractBytes());
      }
    });

    test('a wrong password, or the chat wrap key, does not open it', () {
      final vaultKey = crypto.generateVaultKey();
      final right = crypto.deriveAuthKeys('right-one', salt, _cheap);
      final wrong = crypto.deriveAuthKeys('wrong-one', salt, _cheap);
      addTearDown(vaultKey.dispose);
      addTearDown(right.dispose);
      addTearDown(wrong.dispose);
      final wrapped = crypto.wrapVaultKey(vaultKey, right.vaultWrapKey, salt);

      for (final key in [wrong.vaultWrapKey, right.wrapKey]) {
        expect(
          () => crypto.unwrapVaultKey(wrapped, key, wrongSecret: _wrong),
          throwsA(
            isA<MessageException>().having((e) => e.message, 'message', _wrong),
          ),
        );
      }
    });

    test('draws a fresh nonce each time', () {
      final vaultKey = crypto.generateVaultKey();
      final keys = crypto.deriveAuthKeys('one-password', salt, _cheap);
      addTearDown(vaultKey.dispose);
      addTearDown(keys.dispose);

      expect(
        crypto.wrapVaultKey(vaultKey, keys.vaultWrapKey, salt).wrapped,
        isNot(crypto.wrapVaultKey(vaultKey, keys.vaultWrapKey, salt).wrapped),
      );
    });
  });

  group('a vault item', () {
    final plaintext = Uint8List.fromList(utf8.encode('{"name":"GitHub"}'));

    test('opens with its key and the version it was sealed with', () {
      final key = crypto.generateVaultKey();
      addTearDown(key.dispose);

      final sealed = crypto.encryptVaultItem(plaintext, key, formatVersion: 1);
      expect(sealed.nonce, hasLength(24));
      expect(
        utf8.decode(sealed.ciphertext, allowMalformed: true),
        isNot(contains('GitHub')),
      );
      expect(
        crypto.decryptVaultItem(
          sealed.ciphertext,
          sealed.nonce,
          key,
          formatVersion: 1,
          wrongKey: _wrong,
        ),
        plaintext,
      );
    });

    test('another key, another version or a tampered byte does not open '
        'it', () {
      final key = crypto.generateVaultKey();
      final other = crypto.generateVaultKey();
      addTearDown(key.dispose);
      addTearDown(other.dispose);
      final sealed = crypto.encryptVaultItem(plaintext, key, formatVersion: 1);
      final tampered = Uint8List.fromList(sealed.ciphertext)..[0] ^= 1;

      final attempts = <Uint8List Function()>[
        () => crypto.decryptVaultItem(
          sealed.ciphertext,
          sealed.nonce,
          other,
          formatVersion: 1,
          wrongKey: _wrong,
        ),
        () => crypto.decryptVaultItem(
          sealed.ciphertext,
          sealed.nonce,
          key,
          formatVersion: 2,
          wrongKey: _wrong,
        ),
        () => crypto.decryptVaultItem(
          tampered,
          sealed.nonce,
          key,
          formatVersion: 1,
          wrongKey: _wrong,
        ),
        () => crypto.decryptVaultItem(
          sealed.ciphertext,
          Uint8List(3),
          key,
          formatVersion: 1,
          wrongKey: _wrong,
        ),
        () => crypto.decryptVaultItem(
          sealed.ciphertext.sublist(0, 15),
          sealed.nonce,
          key,
          formatVersion: 1,
          wrongKey: _wrong,
        ),
      ];
      for (final attempt in attempts) {
        expect(
          attempt,
          throwsA(
            isA<MessageException>().having((e) => e.message, 'message', _wrong),
          ),
        );
      }
    });

    // The item every client pins: quark-browser-extensions, ios/ and
    // android/ read the same file (#3597).
    test('opens the shared item vector', () {
      final vector =
          (jsonDecode(
                    File('test/fixtures/vault_vectors.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>)['item']
              as Map<String, dynamic>;
      final key = crypto.sodium.secureCopy(
        Uint8List.fromList((vector['key'] as List).cast<int>()),
      );
      addTearDown(key.dispose);

      final opened = crypto.decryptVaultItem(
        base64Decode(vector['ciphertext'] as String),
        base64Decode(vector['nonce'] as String),
        key,
        formatVersion: vector['formatVersion'] as int,
        wrongKey: _wrong,
      );
      expect(utf8.decode(opened), vector['plaintext']);
      expect(VaultItemData.decode(opened).name, 'GitHub');
    });

    test('does not open as a plain wrap, without the additional data', () {
      final key = crypto.generateVaultKey();
      addTearDown(key.dispose);
      final sealed = crypto.encryptVaultItem(plaintext, key, formatVersion: 1);

      expect(
        () => crypto.unwrapWithKey(
          WrappedSecret(
            wrapped: Uint8List.fromList([
              ...sealed.nonce,
              ...sealed.ciphertext,
            ]),
            salt: salt,
          ),
          key,
          wrongSecret: _wrong,
        ),
        throwsA(isA<MessageException>()),
      );
    });

    test('draws a fresh nonce each time', () {
      final key = crypto.generateVaultKey();
      addTearDown(key.dispose);

      expect(
        crypto.encryptVaultItem(plaintext, key, formatVersion: 1).nonce,
        isNot(crypto.encryptVaultItem(plaintext, key, formatVersion: 1).nonce),
      );
    });
  });

  test('randomString draws only from the pool, at the length asked', () {
    final drawn = crypto.randomString('ab', 64);
    expect(drawn, hasLength(64));
    expect(drawn, matches(RegExp(r'^[ab]+$')));
    expect(drawn, contains('a'));
    expect(drawn, contains('b'));
  });
}
