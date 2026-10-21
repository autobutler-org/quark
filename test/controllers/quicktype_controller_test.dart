import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/quicktype_controller.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/quicktype_identities.dart';
import 'package:quark/services/vault_biometric.dart';

import '../support/fake_vault.dart';

const _password = 'correct horse battery staple';
const _account = 'acct_0123456789abcdef0123456789abcdef';

/// iOS's credential identity store, in memory: what it holds, whether
/// Quark is the enabled provider, and every call.
class FakeIdentityStore {
  List<QuickTypeIdentity> identities = const [];
  bool providerEnabled = true;
  bool failReplace = false;
  final calls = <String>[];

  Future<bool> replace(List<QuickTypeIdentity> next) async {
    calls.add('replace');
    if (failReplace) throw Exception('store refused');
    if (!providerEnabled) return false;
    identities = next;
    return true;
  }

  Future<void> clear() async {
    calls.add('clear');
    identities = const [];
  }
}

/// #3599: which vault logins reach the QuickType store, and every event
/// that empties it.
void main() {
  late AccountCrypto crypto;
  late FakeVault server;
  late FakeIdentityStore store;
  late ValueNotifier<String?> session;
  late StreamController<FileEvent> events;
  late bool storedOptIn;
  late Map<String, ({Uint8List key, Uint8List fingerprint})> keystore;

  setUpAll(() async => crypto = await AccountCrypto.load());

  setUp(() {
    server = FakeVault();
    store = FakeIdentityStore();
    session = ValueNotifier('token');
    events = StreamController<FileEvent>.broadcast();
    storedOptIn = false;
    keystore = {};
  });

  tearDown(() => events.close());

  /// Lets queued store work and listeners run.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  VaultBiometricController biometric() => VaultBiometricController(
    support: () async => (
      availability: VaultBiometricAvailability.available,
      kind: VaultBiometricKind.faceId,
    ),
    storedFingerprint: (account) async => keystore[account]?.fingerprint,
    store: (account, key, fingerprint, _) async => keystore
      ..clear()
      ..[account] = (
        key: Uint8List.fromList(key),
        fingerprint: Uint8List.fromList(fingerprint),
      ),
    read: (account, _) async =>
        throw const VaultBiometricException(VaultBiometricFailure.missing),
    delete: ({String? account}) async => keystore.clear(),
    clearCache: () async {},
    account: () async => _account,
  );

  QuickTypeController quickType({bool supported = true}) {
    final q = QuickTypeController(
      supported: supported,
      readOptIn: () async => storedOptIn,
      writeOptIn: (on) async => storedOptIn = on,
      replace: store.replace,
      clear: store.clear,
      account: () async => _account,
    );
    addTearDown(q.dispose);
    return q;
  }

  /// An open vault with three entries, two of them fit for QuickType,
  /// biometric unlock on, and a QuickType controller following both.
  Future<(VaultController, VaultBiometricController, QuickTypeController)>
  started({bool supported = true}) async {
    final vault = server.controller(
      crypto,
      events: events.stream,
      session: session,
    );
    addTearDown(vault.dispose);
    await vault.load();
    await vault.setUp(_password);
    for (final data in const [
      VaultItemData(
        kind: VaultItemKind.entry,
        name: 'GitHub',
        url: 'https://github.com/login?next=/settings',
        username: 'grace',
        password: 'gh-secret-password',
      ),
      VaultItemData(
        kind: VaultItemKind.entry,
        name: 'Router',
        url: 'https://192.168.1.1',
        username: '',
        password: 'no-username-here',
      ),
      VaultItemData(
        kind: VaultItemKind.entry,
        name: 'Bank PIN',
        username: 'grace',
        password: 'no-site-here',
      ),
      VaultItemData(
        kind: VaultItemKind.entry,
        name: 'Mail',
        url: 'mail.example.com',
        username: 'grace@example.com',
        password: 'mail-secret',
      ),
    ]) {
      await vault.save(data);
    }
    final b = biometric();
    addTearDown(b.dispose);
    b.start(vault: vault, session: session);
    await b.refresh();
    expect(await b.enable(), isTrue);
    final q = quickType(supported: supported);
    q.start(vault: vault, biometric: b, session: session);
    await settle();
    return (vault, b, q);
  }

  test('is off by default: offered, but the store stays empty', () async {
    final (_, _, q) = await started();

    expect(q.isAvailable, isTrue);
    expect(q.enabled, isFalse);
    expect(store.identities, isEmpty);
    expect(store.calls, isNot(contains('replace')));
    // Off at startup empties whatever an earlier run left.
    expect(store.calls, ['clear']);
  });

  test(
    'says that iOS keeps site addresses and usernames unencrypted',
    () async {
      final (_, _, q) = await started();

      expect(
        q.settingExplanation,
        contains(
          'iOS stores the site address and username of each login '
          'unencrypted',
        ),
      );
      expect(q.settingExplanation, contains('after Face ID'));
      expect(
        QuickTypeController.settingTitle,
        'Show Quark logins in QuickType suggestions',
      );
    },
  );

  test('turned on, holds one identity per entry with a host and a '
      'username: the host, never the URL, and never the password', () async {
    final (vault, _, q) = await started();

    expect(await q.setEnabled(true), isTrue);
    expect(storedOptIn, isTrue);
    final github = vault.entries.firstWhere((e) => e.data.name == 'GitHub');
    final mail = vault.entries.firstWhere((e) => e.data.name == 'Mail');
    expect(store.identities, [
      (
        domain: 'github.com',
        username: 'grace',
        record: '$_account/${github.id}',
      ),
      (
        domain: 'mail.example.com',
        username: 'grace@example.com',
        record: '$_account/${mail.id}',
      ),
    ]);
    final everything = store.identities.toString();
    expect(everything, isNot(contains('secret')));
    expect(everything, isNot(contains('/login')));
  });

  test(
    'a change to the entries replaces the store; a search does not',
    () async {
      final (vault, _, q) = await started();
      await q.setEnabled(true);
      final replaces = store.calls.where((c) => c == 'replace').length;

      vault.search('git');
      await settle();
      expect(store.calls.where((c) => c == 'replace'), hasLength(replaces));

      final github = vault.entries.firstWhere((e) => e.data.name == 'GitHub');
      await vault.delete(github.id);
      await settle();
      expect(store.identities.map((i) => i.domain), ['mail.example.com']);
    },
  );

  test(
    'locking keeps the identities, and the next unlock replaces them',
    () async {
      final (vault, _, q) = await started();
      await q.setEnabled(true);

      vault.lock();
      await settle();
      expect(store.identities, hasLength(2));

      store.identities = const [];
      await vault.unlock(_password);
      await settle();
      expect(store.identities, hasLength(2));
    },
  );

  test('a stored opt-in fills the store from the open vault', () async {
    storedOptIn = true;
    final (vault, _, q) = await started();

    expect(q.enabled, isTrue);
    expect(store.identities, hasLength(2));
    vault.lock();
    await settle();
    expect(store.identities, hasLength(2));
  });

  group('empties the store and turns the setting off', () {
    test('when turned off', () async {
      final (_, _, q) = await started();
      await q.setEnabled(true);

      expect(await q.setEnabled(false), isTrue);
      expect(store.identities, isEmpty);
      expect(q.enabled, isFalse);
      expect(storedOptIn, isFalse);
    });

    test('on a sign-out or a switch of account or Quark', () async {
      final (_, _, q) = await started();
      await q.setEnabled(true);

      session.value = null;
      await settle();
      expect(store.identities, isEmpty);
      expect(q.enabled, isFalse);
      expect(storedOptIn, isFalse);
    });

    test('when biometric unlock is turned off', () async {
      final (_, b, q) = await started();
      await q.setEnabled(true);

      await b.disable();
      await settle();
      expect(store.identities, isEmpty);
      expect(q.enabled, isFalse);
      expect(q.isAvailable, isFalse);
      expect(storedOptIn, isFalse);
    });

    test('when the vault is started over', () async {
      final (vault, _, q) = await started();
      await q.setEnabled(true);

      await vault.startOver(_password);
      await settle();
      expect(vault.status, VaultStatus.noVault);
      expect(store.identities, isEmpty);
      expect(q.enabled, isFalse);
    });

    test('when the vault is deleted from another session', () async {
      final (vault, _, q) = await started();
      await q.setEnabled(true);

      server.key = null;
      await vault.load();
      await settle();
      expect(store.identities, isEmpty);
      expect(q.enabled, isFalse);
    });

    test('when a cached key turns out stale', () async {
      final (vault, _, q) = await started();
      await q.setEnabled(true);

      vault.lock();
      await vault.unlockWithCachedKey(Uint8List(32), Uint8List(16));
      await settle();
      expect(vault.cachedKeyStale, isTrue);
      expect(store.identities, isEmpty);
      expect(q.enabled, isFalse);
    });
  });

  test('a replace the store refuses empties it and says so', () async {
    final (_, _, q) = await started();
    store.failReplace = true;

    expect(await q.setEnabled(true), isFalse);
    expect(q.error, isNotNull);
    expect(store.calls.last, 'clear');
    expect(store.identities, isEmpty);
  });

  test('stores nothing while Quark is not the AutoFill provider', () async {
    store.providerEnabled = false;
    final (_, _, q) = await started();

    expect(await q.setEnabled(true), isTrue);
    expect(store.identities, isEmpty);
  });

  test('off iOS it offers nothing and never touches a store', () async {
    final (_, _, q) = await started(supported: false);

    expect(q.isAvailable, isFalse);
    expect(store.calls, isEmpty);
  });
}
