import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/controllers/recovery_phrase_controller.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Argon2id's floor; the shipped cost is [KdfParams.standard].
const _cheap = KdfParams(opsLimit: 1, memLimit: 8192);

/// The account's auth salt.
final _salt = Uint8List.fromList(List.generate(16, (i) => i));

/// A Quark that stores one account's wrapped chat keys, as `/chat/keys/me`,
/// `/auth/recover/keys` and `PUT /auth/recovery-key` would.
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
    String? recoveryPhrase,
    String? recoveryKey,
  }) async => stored;
}

/// #3530: keys made without a phrase wrap get one under the account's phrase,
/// a wrong phrase or password changes nothing, and afterwards a recovery
/// keeps the chat identity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatKeysController.keysForPhrase', () {
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    late _FakeQuark quark;
    late ChatCrypto crypto;

    ChatKeysController controller() => ChatKeysController(
      loadCrypto: () async => crypto,
      fetchMine: quark.fetchMine,
      putMine: quark.putMine,
      fetchForRecovery: quark.fetchForRecovery,
      readCache: (key) async => null,
      writeCache: (key, value) async {},
      deleteCache: (key) async {},
      persist: false,
      kdfParams: _cheap,
    );

    AuthKeys phraseKeys(String phrase) {
      final keys = crypto.deriveRecoveryKeys(phrase, _salt, _cheap);
      addTearDown(keys.dispose);
      return keys;
    }

    setUpAll(() async {
      crypto = await ChatCrypto.load();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, (call) async => null);
    });

    setUp(() async {
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

    test('wraps the stored identity under the phrase without uploading it, '
        'and a recovery with that phrase then keeps it', () async {
      // An ordinary sign-in makes keys with no phrase wrap.
      await controller().signedIn(password: 'the-password', authSalt: _salt);
      final box = quark.stored!.publicKeys.boxPublicKey;
      expect(quark.stored!.byPhrase, isNull);
      final puts = quark.puts;

      final keys = phraseKeys('apple bread cloud');
      final wrapped = await controller().keysForPhrase(
        password: 'the-password',
        phraseWrapKey: keys.wrapKey,
        authSalt: _salt,
      );
      expect(quark.puts, puts, reason: 'only the checked request stores it');
      expect(wrapped!.publicKeys.boxPublicKey, box);
      expect(wrapped.byPhrase, isNotNull);
      expect(wrapped.kdfParams.alg, KdfParams.phraseSplitAlgorithm);

      // What PUT /auth/recovery-key stores once the phrase checks out.
      quark.stored = wrapped;
      final recovered = await controller().keysForRecovery(
        username: 'grace',
        recoveryPhrase: 'apple bread cloud',
        recoveryKeys: phraseKeys('apple bread cloud'),
        newPassword: 'new-password',
        authSalt: _salt,
      );
      expect(recovered.publicKeys.boxPublicKey, box);
      // The password still opens it.
      final after = controller();
      await after.unlock('the-password');
      expect(after.identity!.box.publicKey, box);
    });

    test('a wrong password throws and changes nothing', () async {
      await controller().signedIn(password: 'the-password', authSalt: _salt);
      final before = quark.stored!.toJson();
      final puts = quark.puts;

      await expectLater(
        controller().keysForPhrase(
          password: 'not-the-password',
          phraseWrapKey: phraseKeys('apple bread cloud').wrapKey,
          authSalt: _salt,
        ),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            Errors.chatKeysWrongPassword,
          ),
        ),
      );
      expect(quark.puts, puts);
      expect(quark.stored!.toJson(), before);
    });

    test(
      'an account with no keys has nothing to wrap, and gets none made',
      () async {
        final wrapped = await controller().keysForPhrase(
          password: 'the-password',
          phraseWrapKey: phraseKeys('apple bread cloud').wrapKey,
          authSalt: _salt,
        );
        expect(wrapped, isNull);
        expect(quark.stored, isNull);
        expect(quark.puts, 0);
      },
    );
  });

  group('RecoveryPhraseController', () {
    late MissingPhraseWraps missing;
    late List<(String, String)> added;
    Object? failure;
    var account = 'grace';

    RecoveryPhraseController controller() => RecoveryPhraseController(
      missing: () async => missing,
      addPhrase: ({required password, required phrase}) async {
        added.add((password, phrase));
        if (failure != null) throw failure!;
      },
      account: () => account,
    );

    setUp(() {
      missing = (chat: true, vault: true);
      added = [];
      failure = null;
      account = 'grace';
    });

    test('offers where a key has no phrase wrap, after a check', () async {
      final phrase = controller();
      expect(phrase.offerVault, isFalse);
      await phrase.check();
      expect(phrase.offerVault, isTrue);
      expect(phrase.offerChat, isTrue);

      missing = (chat: false, vault: true);
      await phrase.check();
      expect(phrase.offerChat, isFalse);
      expect(phrase.offerVault, isTrue);
    });

    test('a failed check keeps the offer as it was', () async {
      final phrase = RecoveryPhraseController(
        missing: () => Future.error(Exception('offline')),
        addPhrase: ({required password, required phrase}) async {},
        account: () => account,
      );
      await phrase.check();
      expect(phrase.offerVault, isFalse);
    });

    test('a phrase the Quark refuses keeps the offer and says why', () async {
      final phrase = controller();
      await phrase.check();
      failure = const MessageException(Errors.recoveryPhraseNotTheAccounts);

      expect(await phrase.add(password: 'pw', phrase: 'wrong words'), isFalse);

      expect(added, [('pw', 'wrong words')]);
      expect(
        Errors.message(phrase.error, 'add your recovery phrase'),
        Errors.recoveryPhraseNotTheAccounts,
      );
      expect(phrase.offerVault, isTrue);
      expect(phrase.offerChat, isTrue);
      expect(phrase.isBusy, isFalse);
      phrase.clearError();
      expect(phrase.error, isNull);
    });

    test('a phrase that is added puts both offers away', () async {
      final phrase = controller();
      await phrase.check();

      expect(await phrase.add(password: 'pw', phrase: 'right words'), isTrue);

      expect(phrase.error, isNull);
      expect(phrase.offerVault, isFalse);
      expect(phrase.offerChat, isFalse);
    });

    test('dismissing hides the offer for this account only', () async {
      final phrase = controller();
      await phrase.check();
      phrase.dismiss();
      expect(phrase.offerVault, isFalse);
      expect(phrase.offerChat, isFalse);

      account = 'ada';
      expect(phrase.offerVault, isTrue);
    });
  });
}
