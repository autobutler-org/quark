import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/vault_biometric.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_vault.dart';

const _password = 'correct horse battery staple';
const _account = 'acct_0123456789abcdef0123456789abcdef';

/// The platform keystore, in memory: one entry per account, a biometric
/// check that passes unless told otherwise, and a record of every call.
class FakeKeystore {
  final entries = <String, ({Uint8List key, Uint8List fingerprint})>{};
  VaultBiometricSupport supported = (
    availability: VaultBiometricAvailability.available,
    kind: VaultBiometricKind.faceId,
  );

  /// The failure the next prompt ends in; null passes it.
  VaultBiometricFailure? nextPrompt;
  final prompts = <String>[];
  int deletes = 0;

  Future<VaultBiometricSupport> support() async => supported;

  Future<Uint8List?> storedFingerprint(String account) async =>
      entries[account]?.fingerprint;

  Future<void> store(
    String account,
    Uint8List key,
    Uint8List fingerprint,
    VaultBiometricPrompt prompt,
  ) async {
    _prompt(prompt);
    entries
      ..clear()
      ..[account] = (
        key: Uint8List.fromList(key),
        fingerprint: Uint8List.fromList(fingerprint),
      );
  }

  Future<VaultBiometricEntry> read(
    String account,
    VaultBiometricPrompt prompt,
  ) async {
    _prompt(prompt);
    final entry = entries[account];
    if (entry == null) {
      throw const VaultBiometricException(VaultBiometricFailure.missing);
    }
    return VaultBiometricEntry(
      key: Uint8List.fromList(entry.key),
      fingerprint: Uint8List.fromList(entry.fingerprint),
    );
  }

  Future<void> delete({String? account}) async {
    deletes++;
    account == null ? entries.clear() : entries.remove(account);
  }

  void _prompt(VaultBiometricPrompt prompt) {
    prompts.add(prompt.title);
    final failure = nextPrompt;
    nextPrompt = null;
    if (failure == null) return;
    // The OS deletes nothing itself; the app does on invalidated.
    throw VaultBiometricException(failure);
  }
}

void main() {
  late AccountCrypto crypto;
  late FakeVault server;
  late FakeKeystore keystore;
  late ValueNotifier<String?> session;
  late StreamController<FileEvent> events;
  late int cacheClears;
  late String? account;

  setUpAll(() async => crypto = await AccountCrypto.load());

  setUp(() {
    server = FakeVault();
    keystore = FakeKeystore();
    session = ValueNotifier('token');
    events = StreamController<FileEvent>.broadcast();
    cacheClears = 0;
    account = _account;
  });

  tearDown(() => events.close());

  VaultBiometricController biometric() => VaultBiometricController(
    support: keystore.support,
    storedFingerprint: keystore.storedFingerprint,
    store: keystore.store,
    read: keystore.read,
    delete: keystore.delete,
    clearCache: () async => cacheClears++,
    account: () async => account,
  );

  /// A vault set up and unlocked, and a biometric controller following it.
  Future<(VaultController, VaultBiometricController)> started() async {
    final vault = server.controller(
      crypto,
      events: events.stream,
      session: session,
    );
    addTearDown(vault.dispose);
    await vault.load();
    await vault.setUp(_password);
    await vault.save(
      const VaultItemData(
        kind: VaultItemKind.entry,
        name: 'GitHub',
        url: 'https://github.com/login',
        username: 'grace',
        password: 'gh-secret-password',
      ),
    );
    final b = biometric();
    addTearDown(b.dispose);
    b.start(vault: vault, session: session);
    await b.refresh();
    return (vault, b);
  }

  /// Lets the queued keystore work and listeners run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('is off by default, and offers itself once the vault is open', () async {
    final (vault, b) = await started();

    expect(b.isAvailable, isTrue);
    expect(b.enabled, isFalse);
    expect(b.canUnlock, isFalse);
    expect(b.shouldOffer, isTrue);
    expect(b.settingTitle, 'Unlock with Face ID');
    expect(b.settingExplanation, contains('Anyone who can pass Face ID'));

    b.dismissOffer();
    expect(b.shouldOffer, isFalse);

    vault.lock();
    expect(keystore.entries, isEmpty);
  });

  test('names the sensor the device has', () async {
    keystore.supported = (
      availability: VaultBiometricAvailability.available,
      kind: VaultBiometricKind.biometrics,
    );
    final (_, b) = await started();
    expect(b.settingTitle, 'Unlock with fingerprint or face');
    expect(b.methodName, 'your fingerprint or face');
  });

  test('offers nothing where the device cannot keep the key', () async {
    keystore.supported = (
      availability: VaultBiometricAvailability.notEnrolled,
      kind: VaultBiometricKind.touchId,
    );
    final (_, b) = await started();

    expect(b.isAvailable, isFalse);
    expect(b.shouldOffer, isFalse);
    expect(await b.enable(), isFalse);
    expect(Errors.vaultBiometric(b.error, 'turn it on'), contains("can't"));
    expect(keystore.entries, isEmpty);
  });

  test('enable caches the open key under the active account, with its '
      'fingerprint', () async {
    final (vault, b) = await started();

    expect(await b.enable(), isTrue);
    expect(b.enabled, isTrue);
    expect(b.canUnlock, isTrue);
    expect(b.shouldOffer, isFalse);
    final entry = keystore.entries[_account]!;
    expect(entry.key, hasLength(32));
    expect(entry.fingerprint, vault.keyFingerprint);
  });

  test('a fresh controller reads that it is on from the keystore', () async {
    final (vault, b) = await started();
    await b.enable();

    final again = biometric();
    addTearDown(again.dispose);
    again.start(vault: vault, session: ValueNotifier('token'));
    await again.refresh();
    expect(again.enabled, isTrue);
  });

  test('unlocks the vault with the cached key and no password', () async {
    final (vault, b) = await started();
    await b.enable();
    vault.lock();
    expect(vault.status, VaultStatus.locked);

    expect(await b.unlock(), isTrue);
    expect(vault.status, VaultStatus.unlocked);
    expect(vault.unlockedFromCache, isTrue);
    expect(vault.entries.single.data.name, 'GitHub');
    expect(keystore.prompts.last, 'Unlock your vault');
    expect(b.error, isNull);
  });

  test('locking and the idle lock keep the cached key', () async {
    final (vault, b) = await started();
    await b.enable();

    vault.lock();
    await settle();
    expect(keystore.entries, isNotEmpty);
    expect(b.enabled, isTrue);
  });

  test('disable deletes the cached key', () async {
    final (_, b) = await started();
    await b.enable();

    await b.disable();
    expect(keystore.entries, isEmpty);
    expect(b.enabled, isFalse);
  });

  group('wipes the cached key', () {
    test('on a sign-out or a switch of account or Quark', () async {
      final (_, b) = await started();
      await b.enable();

      session.value = null;
      await settle();
      await settle();
      expect(keystore.entries, isEmpty);
      expect(b.enabled, isFalse);
    });

    test('when the vault is started over', () async {
      server.loginAuthKey = fakeLoginAuthKey(crypto, _password);
      final (vault, b) = await started();
      await b.enable();

      await vault.startOver(_password);
      await settle();
      expect(keystore.entries, isEmpty);
      expect(b.enabled, isFalse);
    });

    test('when the vault was deleted from another session', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      server.key = null;
      server.items.clear();
      await vault.load();
      await settle();
      expect(vault.status, VaultStatus.noVault);
      expect(keystore.entries, isEmpty);
    });

    test('on forgetAll, which a password change calls', () async {
      final (_, b) = await started();
      await b.enable();

      await b.forgetAll();
      expect(keystore.entries, isEmpty);
      expect(b.enabled, isFalse);
    });

    test('when a sign-out lands while the enable prompt is up', () async {
      final (vault, b) = await started();
      final gate = Completer<void>();
      final slow = VaultBiometricController(
        support: keystore.support,
        storedFingerprint: keystore.storedFingerprint,
        store: (a, k, f, p) async {
          await gate.future;
          await keystore.store(a, k, f, p);
        },
        read: keystore.read,
        delete: keystore.delete,
        clearCache: () async {},
        account: () async => account,
      );
      addTearDown(slow.dispose);
      final signedIn = ValueNotifier<String?>('token');
      slow.start(vault: vault, session: signedIn);
      await slow.refresh();
      b.dismissOffer();

      final enabling = slow.enable();
      await settle();
      signedIn.value = null;
      gate.complete();
      expect(await enabling, isFalse);
      await settle();
      expect(keystore.entries, isEmpty);
      expect(slow.enabled, isFalse);
    });
  });

  group('a stale cached key', () {
    test('is dropped, with the ciphertext cache, when its fingerprint is '
        'not the one it was stored with', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();
      final entry = keystore.entries[_account]!;
      keystore.entries[_account] = (key: entry.key, fingerprint: Uint8List(16));

      expect(await b.unlock(), isFalse);
      await settle();
      expect(vault.status, VaultStatus.locked);
      expect(vault.cachedKeyStale, isTrue);
      expect(
        Errors.vaultBiometric(b.error, 'unlock your vault'),
        Errors.vaultBiometricStale,
      );
      expect(keystore.entries, isEmpty);
      expect(cacheClears, 1);
      expect(b.enabled, isFalse);
    });

    test('is dropped when the vault was replaced and no item opens under '
        'it', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      // Another session started over and set up a new vault with an item.
      server.key = null;
      server.items.clear();
      final other = server.controller(crypto);
      addTearDown(other.dispose);
      await other.load();
      await other.setUp(_password);
      await other.save(const VaultItemData.folder('Work'));
      await vault.load();

      expect(await b.unlock(), isFalse);
      await settle();
      expect(vault.status, VaultStatus.locked);
      expect(keystore.entries, isEmpty);
      expect(cacheClears, 1);

      // The password still opens the new vault.
      await vault.unlock(_password);
      expect(vault.status, VaultStatus.unlocked);
      expect(vault.cachedKeyStale, isFalse);
    });

    test('is dropped when a reload after a biometric unlock finds nothing '
        'opens', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();
      await b.unlock();
      expect(vault.status, VaultStatus.unlocked);

      server.key = null;
      server.items.clear();
      final other = server.controller(crypto);
      addTearDown(other.dispose);
      await other.load();
      await other.setUp(_password);
      await other.save(const VaultItemData.folder('Work'));
      await vault.load();
      await settle();

      expect(vault.status, VaultStatus.locked);
      expect(keystore.entries, isEmpty);
    });

    test('is dropped after a password unlock whose key has another '
        'fingerprint', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();
      final entry = keystore.entries[_account]!;
      keystore.entries[_account] = (key: entry.key, fingerprint: Uint8List(16));

      await vault.unlock(_password);
      await settle();
      await settle();
      expect(vault.status, VaultStatus.unlocked);
      expect(keystore.entries, isEmpty);
      expect(b.enabled, isFalse);
    });

    test('is kept after a password unlock of the same vault', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      await vault.unlock(_password);
      await settle();
      expect(keystore.entries, isNotEmpty);
      expect(b.enabled, isTrue);
    });
  });

  group('a failed biometric check', () {
    test('canceled leaves the vault locked with no error and the key '
        'kept', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      keystore.nextPrompt = VaultBiometricFailure.canceled;
      expect(await b.unlock(), isFalse);
      expect(vault.status, VaultStatus.locked);
      expect(b.error, isNull);
      expect(Errors.vaultBiometric(b.error, 'unlock your vault'), isNotNull);
      expect(
        Errors.vaultBiometric(
          const VaultBiometricException(VaultBiometricFailure.canceled),
          'unlock your vault',
        ),
        isNull,
      );
      expect(keystore.entries, isNotEmpty);
    });

    test('after an enrollment change deletes the key and asks for the '
        'password', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      keystore.nextPrompt = VaultBiometricFailure.invalidated;
      expect(await b.unlock(), isFalse);
      expect(vault.status, VaultStatus.locked);
      expect(
        Errors.vaultBiometric(b.error, 'unlock your vault'),
        Errors.vaultBiometricInvalidated,
      );
      expect(keystore.entries, isEmpty);
      expect(b.enabled, isFalse);
      expect(b.canUnlock, isFalse);
    });

    test('locked out keeps the key and says to use the password', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      keystore.nextPrompt = VaultBiometricFailure.lockedOut;
      expect(await b.unlock(), isFalse);
      expect(
        Errors.vaultBiometric(b.error, 'unlock your vault'),
        Errors.vaultBiometricLockedOut,
      );
      expect(keystore.entries, isNotEmpty);
    });

    test('with the key gone turns the setting off', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();
      keystore.entries.clear();

      expect(await b.unlock(), isFalse);
      expect(
        Errors.vaultBiometric(b.error, 'unlock your vault'),
        Errors.vaultBiometricMissing,
      );
      expect(b.enabled, isFalse);
    });

    test('canceled while turning it on stores nothing', () async {
      final (_, b) = await started();

      keystore.nextPrompt = VaultBiometricFailure.canceled;
      expect(await b.enable(), isFalse);
      expect(b.error, isNull);
      expect(b.enabled, isFalse);
      expect(keystore.entries, isEmpty);
    });

    test('a key the keystore found stale is dropped with the cache', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      keystore.nextPrompt = VaultBiometricFailure.stale;
      expect(await b.unlock(), isFalse);
      expect(
        Errors.vaultBiometric(b.error, 'unlock your vault'),
        Errors.vaultBiometricStale,
      );
      expect(keystore.entries, isEmpty);
      expect(cacheClears, 1);
      expect(b.enabled, isFalse);
    });

    test('an unknown failure reads as the generic sentence', () async {
      final (vault, b) = await started();
      await b.enable();
      vault.lock();

      keystore.nextPrompt = VaultBiometricFailure.failed;
      expect(await b.unlock(), isFalse);
      expect(
        Errors.vaultBiometric(b.error, 'unlock your vault'),
        Errors.message(null, 'unlock your vault'),
      );
    });
  });

  test('never logs key material', () async {
    final logged = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = previous);

    final (vault, b) = await started();
    await b.enable();
    final key = keystore.entries[_account]!.key;
    final fingerprint = keystore.entries[_account]!.fingerprint;
    vault.lock();
    keystore.nextPrompt = VaultBiometricFailure.failed;
    await b.unlock();
    keystore.entries[_account] = (key: key, fingerprint: Uint8List(16));
    await b.unlock();
    await settle();

    final secrets = [
      base64Encode(key),
      base64Encode(fingerprint),
      key.toString(),
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ];
    for (final line in logged) {
      for (final secret in secrets) {
        expect(line, isNot(contains(secret)));
      }
    }
    expect(
      VaultBiometricEntry(key: key, fingerprint: fingerprint).toString(),
      isNot(contains(key.toString())),
    );
  });
}
