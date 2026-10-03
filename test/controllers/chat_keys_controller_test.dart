import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Argon2id's floor; the shipped cost is [KdfParams.standard].
const _cheap = KdfParams(opsLimit: 1, memLimit: 8192);

/// A Quark that stores one account's wrapped keys, as `/chat/keys/me` and
/// `/auth/recover/keys` would.
class _FakeQuark {
  WrappedChatKeys? stored;
  int puts = 0;

  Future<WrappedChatKeys?> fetchMine({String? sessionToken}) async => stored;

  Future<void> putMine(WrappedChatKeys keys, {String? sessionToken}) async {
    puts++;
    stored = keys;
  }

  Future<WrappedChatKeys?> fetchForRecovery({
    required String username,
    required String recoveryPhrase,
  }) async => stored;

  /// What `/auth/recover` does with the keys it was sent.
  void recover(WrappedChatKeys keys) => stored = keys;
}

/// The chat identity lifecycle of #2416 on real libsodium: first sign-in,
/// later sign-in, a wrong password, recovery, a web reload and sign-out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final keystore = <String, String>{};
  late _FakeQuark quark;
  late ChatCrypto crypto;

  ChatKeysController controller({bool persist = true}) => ChatKeysController(
    loadCrypto: () async => crypto,
    fetchMine: quark.fetchMine,
    putMine: quark.putMine,
    fetchForRecovery: quark.fetchForRecovery,
    readCache: (key) async => keystore[key],
    writeCache: (key, value) async => keystore[key] = value,
    deleteCache: (key) async => keystore.remove(key),
    persist: persist,
    kdfParams: _cheap,
  );

  setUpAll(() async {
    crypto = await ChatCrypto.load();
    // AppSettings keeps session tokens in the keystore too.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });

  setUp(() async {
    keystore.clear();
    quark = _FakeQuark();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    await AppSettings.instance.setSessionToken('session');
  });

  test('a first sign-in makes, wraps and uploads an identity', () async {
    final keys = controller();

    await keys.signedIn(
      password: 'first-password',
      recoveryPhrase: 'Apple Bread Cloud',
    );

    expect(keys.isUnlocked, isTrue);
    expect(quark.puts, 1);
    final stored = quark.stored!;
    expect(stored.publicKeys.boxPublicKey, keys.identity!.box.publicKey);
    expect(stored.byPhrase, isNotNull);
    expect(keystore, hasLength(1));
  });

  test('a later sign-in unwraps the same identity', () async {
    await controller().signedIn(password: 'first-password');
    final published = quark.stored!.publicKeys.signPublicKey;

    final again = controller();
    await again.signedIn(password: 'first-password');

    expect(quark.puts, 1);
    expect(again.identity!.sign.publicKey, published);
  });

  test('a wrong password stays locked with Errors-readable text', () async {
    await controller().signedIn(password: 'first-password');
    final keys = controller();

    Object? thrown;
    try {
      await keys.unlock('not-the-password');
    } catch (e) {
      thrown = e;
    }

    expect(
      Errors.message(thrown, 'unlock your messages'),
      Errors.chatKeysWrongPassword,
    );
    expect(keys.isUnlocked, isFalse);
  });

  test('recovery re-wraps the same keypair under the new password', () async {
    final first = controller();
    await first.signedIn(
      password: 'old-password',
      recoveryPhrase: 'apple bread cloud',
    );
    final box = first.identity!.box.publicKey;
    final sign = first.identity!.sign.publicKey;

    // Typed with capitals and spaces around it, as the Quark accepts.
    final rewrapped = await controller().keysForRecovery(
      username: 'grace',
      recoveryPhrase: '  Apple Bread Cloud ',
      newPassword: 'new-password',
    );
    quark.recover(rewrapped);

    final after = controller();
    await after.signedIn(password: 'new-password');
    expect(after.identity!.box.publicKey, box);
    expect(after.identity!.sign.publicKey, sign);
    expect(
      () => controller().unlock('old-password'),
      throwsA(isA<MessageException>()),
    );
    // The phrase still opens it, for the next recovery.
    final next = await controller().keysForRecovery(
      username: 'grace',
      recoveryPhrase: 'apple bread cloud',
      newPassword: 'newer-password',
    );
    expect(next.publicKeys.boxPublicKey, box);
  });

  test('a wrong phrase fails before anything is re-wrapped', () async {
    await controller().signedIn(
      password: 'old-password',
      recoveryPhrase: 'apple bread cloud',
    );

    await expectLater(
      controller().keysForRecovery(
        username: 'grace',
        recoveryPhrase: 'wrong phrase',
        newPassword: 'new-password',
      ),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          Errors.chatKeysWrongPhrase,
        ),
      ),
    );
  });

  test('keys with no phrase wrap get a new identity at recovery', () async {
    await controller().signedIn(password: 'old-password');
    final old = quark.stored!.publicKeys.boxPublicKey;

    final fresh = await controller().keysForRecovery(
      username: 'grace',
      recoveryPhrase: 'apple bread cloud',
      newPassword: 'new-password',
    );

    expect(fresh.publicKeys.boxPublicKey, isNot(old));
    expect(fresh.byPhrase, isNotNull);
  });

  test('a web reload needs an unlock; native restores the cache', () async {
    await controller(persist: false).signedIn(password: 'pw');
    expect(keystore, isEmpty);
    await controller().signedIn(password: 'pw');

    final web = controller(persist: false);
    await web.start();
    expect(web.isUnlocked, isFalse);
    await web.unlock('pw');
    expect(web.isUnlocked, isTrue);

    final native = controller();
    await native.start();
    expect(native.isUnlocked, isTrue);
    expect(
      native.identity!.box.publicKey,
      quark.stored!.publicKeys.boxPublicKey,
    );
  });

  group('the split-key scheme (#2430)', () {
    final salt = Uint8List.fromList(List.generate(16, (i) => i));

    test(
      'a first sign-in with an auth salt wraps under the wrap key',
      () async {
        final keys = controller();
        await keys.signedIn(password: 'pw-one', authSalt: salt);

        final stored = quark.stored!;
        expect(stored.kdfParams.isSplit, isTrue);
        expect(stored.toJson()['kdfParams']['alg'], KdfParams.splitAlgorithm);
        // The auth salt is the wrap's salt, so the password alone re-derives.
        expect(stored.byPassword.salt, salt);
        // No longer Argon2id of the password used directly.
        expect(
          () => crypto.unwrap(stored.byPassword, 'pw-one', stored.kdfParams),
          throwsA(isA<MessageException>()),
        );
      },
    );

    test('a split wrap opens through the local unlock, with no salt handed '
        'in', () async {
      final first = controller();
      await first.signedIn(password: 'pw-one', authSalt: salt);
      final box = first.identity!.box.publicKey;

      final reloaded = controller(persist: false);
      await reloaded.unlock('pw-one');

      expect(reloaded.identity!.box.publicKey, box);
      expect(quark.puts, 1);
      await expectLater(
        controller(persist: false).unlock('pw-two'),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            Errors.chatKeysWrongPassword,
          ),
        ),
      );
    });

    test('a first-scheme wrap is opened and re-wrapped at sign-in', () async {
      final first = controller();
      await first.signedIn(password: 'pw-one', recoveryPhrase: 'a b c');
      final old = quark.stored!;
      expect(old.kdfParams.isSplit, isFalse);
      final box = first.identity!.box.publicKey;

      final upgraded = controller();
      await upgraded.signedIn(password: 'pw-one', authSalt: salt);

      expect(upgraded.identity!.box.publicKey, box);
      expect(quark.puts, 2);
      final stored = quark.stored!;
      expect(stored.kdfParams.isSplit, isTrue);
      expect(stored.byPassword.salt, salt);
      expect(stored.publicKeys.boxPublicKey, box);
      // The phrase wrap is carried over untouched and still opens.
      expect(stored.byPhrase!.wrapped, old.byPhrase!.wrapped);
      final recovered = await controller().keysForRecovery(
        username: 'grace',
        recoveryPhrase: 'a b c',
        newPassword: 'pw-two',
        authSalt: salt,
      );
      expect(recovered.publicKeys.boxPublicKey, box);
      expect(recovered.kdfParams.isSplit, isTrue);

      // And it is not re-wrapped again.
      await controller().signedIn(password: 'pw-one', authSalt: salt);
      expect(quark.puts, 2);
    });

    test('a wrong password re-wraps nothing', () async {
      await controller().signedIn(password: 'pw-one');

      await expectLater(
        controller().signedIn(password: 'pw-two', authSalt: salt),
        throwsA(isA<MessageException>()),
      );
      expect(quark.puts, 1);
      expect(quark.stored!.kdfParams.isSplit, isFalse);
    });

    test('with no auth salt the first scheme stays', () async {
      await controller().signedIn(password: 'pw-one');
      await controller().signedIn(password: 'pw-one');

      expect(quark.puts, 1);
      expect(quark.stored!.kdfParams.alg, KdfParams.algorithm);
    });

    test('an unknown scheme is refused, not guessed at', () {
      expect(
        () => KdfParams.fromJson({
          'alg': 'something-else',
          'opsLimit': 1,
          'memLimit': 8192,
        }),
        throwsFormatException,
      );
    });
  });

  test('signing out locks and forgets the cached identity', () async {
    final keys = controller();
    await keys.start();
    await keys.signedIn(password: 'pw');
    expect(keystore, isNotEmpty);

    await AppSettings.instance.setSessionToken(null);
    await pumpEventQueue();

    expect(keys.isUnlocked, isFalse);
    expect(keystore, isEmpty);
  });
}
