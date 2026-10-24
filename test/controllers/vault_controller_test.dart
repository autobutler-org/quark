import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/vault_export.dart';
import 'package:quark_widgets/quark_widgets.dart' show VaultEntryDraft;

import '../support/fake_vault.dart';

const _password = 'correct horse battery staple';

void main() {
  late AccountCrypto crypto;
  late FakeVault server;
  late StreamController<FileEvent> events;
  late ValueNotifier<String?> session;

  setUpAll(() async => crypto = await AccountCrypto.load());

  setUp(() {
    server = FakeVault();
    events = StreamController<FileEvent>.broadcast();
    session = ValueNotifier('token');
  });

  tearDown(() => events.close());

  VaultController controller({
    Duration autoLockAfter = const Duration(minutes: 15),
  }) {
    final c = server.controller(
      crypto,
      events: events.stream,
      session: session,
      autoLockAfter: autoLockAfter,
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A controller with a vault set up under [_password] and unlocked.
  Future<VaultController> unlocked() async {
    final c = controller();
    await c.load();
    await c.setUp(_password);
    expect(c.status, VaultStatus.unlocked);
    return c;
  }

  const github = VaultItemData(
    kind: VaultItemKind.entry,
    name: 'GitHub',
    url: 'https://github.com/login',
    username: 'grace',
    password: 'gh-secret-password',
  );

  test('loads to no vault, then to locked once one exists', () async {
    final c = controller();
    expect(c.status, VaultStatus.loading);

    await c.load();
    expect(c.status, VaultStatus.noVault);

    await (await unlocked()).load();
    await c.load();
    expect(c.status, VaultStatus.locked);
  });

  test('a failed load is an error, and the next one clears it', () async {
    var fail = true;
    final c = VaultController(
      loadCrypto: () async => crypto,
      fetchKey: () async =>
          fail ? throw const ApiException(500) : server.fetchKey(),
      events: events.stream,
    );
    addTearDown(c.dispose);

    await c.load();
    expect(c.status, VaultStatus.error);
    expect(c.error, isA<ApiException>());

    fail = false;
    await c.load();
    expect(c.status, VaultStatus.noVault);
  });

  group('setting up with the recovery phrase', () {
    const phrase = 'Apple-Bread-Cloud-Delta';

    test('adds a phrase wrap that opens to the same key, and sends only '
        'wraps', () async {
      final c = controller();
      await c.load();

      await c.setUp(_password, phrase: phrase);

      expect(c.status, VaultStatus.unlocked);
      final stored = server.key!;
      expect(stored.kdfParams.alg, KdfParams.phraseSplitAlgorithm);
      expect(stored.byPhrase!.salt, fakeVaultSalt);
      final byPassword = crypto.deriveAuthKeys(
        _password,
        fakeVaultSalt,
        stored.kdfParams,
      );
      // Normalized, as a recovery types it.
      final byPhrase = crypto.deriveRecoveryKeys(
        'apple-bread-cloud-delta',
        fakeVaultSalt,
        stored.kdfParams,
      );
      addTearDown(byPassword.dispose);
      addTearDown(byPhrase.dispose);
      final one = crypto.unwrapVaultKey(
        stored.byPassword,
        byPassword.vaultWrapKey,
        wrongSecret: 'x',
      );
      final two = crypto.unwrapVaultKey(
        stored.byPhrase!,
        byPhrase.vaultWrapKey,
        wrongSecret: 'x',
      );
      addTearDown(one.dispose);
      addTearDown(two.dispose);
      expect(two.extractBytes(), one.extractBytes());
      final sent = server.sent.single;
      expect(jsonDecode(sent).keys, {
        'wrappedByPassword',
        'saltPw',
        'wrappedByPhrase',
        'saltRp',
        'kdfParams',
        'password',
      });
      for (final secret in [
        _password,
        phrase,
        'apple-bread',
        base64Encode(one.extractBytes()),
        base64Encode(byPhrase.vaultWrapKey.extractBytes()),
        byPhrase.authKey,
      ]) {
        expect(sent, isNot(contains(secret)));
      }
    });

    test('a blank phrase leaves the phrase wrap out', () async {
      final c = controller();
      await c.load();

      await c.setUp(_password, phrase: '   ');

      expect(server.key!.byPhrase, isNull);
      expect(server.key!.kdfParams.alg, KdfParams.splitAlgorithm);
    });
  });

  group('folders', () {
    test('a blank name is refused and nothing is stored', () async {
      final c = await unlocked();

      await expectLater(
        c.createFolder('  '),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            Errors.nameBlank,
          ),
        ),
      );
      expect(server.items, isEmpty);
    });

    test('are made encrypted, and deleting one leaves its entries '
        'in no folder', () async {
      final c = await unlocked();

      final work = await c.createFolder('  Work ');
      expect(c.folderOptions.single.name, 'Work');
      expect(server.sent.last, isNot(contains('Work')));
      final id = await c.saveDraft(
        VaultEntryDraft(name: 'GitHub', password: 'p', folderId: work),
      );
      c.filterFolder(work);

      await c.delete(work);

      expect(c.folders, isEmpty);
      expect(c.folderId, isNull);
      expect(c.folderNameOf(c.itemById(id)!.data.folderId), '');
      expect(c.visibleEntries.single.id, id);
      expect(server.items.keys, [id]);
    });
  });

  group('setting up', () {
    test('wraps a new key under the login password, with no phrase wrap, and '
        'never sends the key', () async {
      final c = await unlocked();

      final stored = server.key!;
      expect(stored.byPhrase, isNull);
      expect(stored.byPassword.salt, fakeVaultSalt);
      expect(stored.kdfParams.alg, KdfParams.splitAlgorithm);
      final keys = crypto.deriveAuthKeys(_password, fakeVaultSalt, cheapKdf);
      addTearDown(keys.dispose);
      final opened = crypto.unwrapVaultKey(
        stored.byPassword,
        keys.vaultWrapKey,
        wrongSecret: 'x',
      );
      addTearDown(opened.dispose);
      expect(opened.extractBytes(), hasLength(32));
      expect(c.entries, isEmpty);
      for (final body in server.sent) {
        expect(body, isNot(contains(_password)));
        expect(body, isNot(contains(base64Encode(opened.extractBytes()))));
      }
    });

    test('a password the account does not sign in with is refused, and '
        'nothing is stored', () async {
      server.loginAuthKey = fakeLoginAuthKey(crypto, _password);
      final c = controller();
      await c.load();

      await c.setUp('not the login password');

      expect(c.status, VaultStatus.noVault);
      expect(
        c.formError,
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          Errors.vaultNotLoginPassword,
        ),
      );
      expect(server.key, isNull);

      // The same form then takes the right one.
      await c.setUp(_password);
      expect(c.formError, isNull);
      expect(c.status, VaultStatus.unlocked);
    });

    test('re-confirms with the login password\'s auth key, the only key '
        'sent', () async {
      final authKey = fakeLoginAuthKey(crypto, _password);
      server.loginAuthKey = authKey;
      final c = controller();
      await c.load();

      await c.setUp(_password);

      final body = jsonDecode(server.sent.single) as Map<String, dynamic>;
      expect(body['password'], authKey);
      expect(body.keys, {
        'wrappedByPassword',
        'saltPw',
        'kdfParams',
        'password',
      });
      final keys = crypto.deriveAuthKeys(_password, fakeVaultSalt, cheapKdf);
      addTearDown(keys.dispose);
      final vaultKey = crypto.unwrapVaultKey(
        server.key!.byPassword,
        keys.vaultWrapKey,
        wrongSecret: 'x',
      );
      addTearDown(vaultKey.dispose);
      for (final secret in [
        _password,
        base64Encode(vaultKey.extractBytes()),
        base64Encode(keys.vaultWrapKey.extractBytes()),
        base64Encode(keys.wrapKey.extractBytes()),
      ]) {
        expect(server.sent.single, isNot(contains(secret)));
      }
    });

    test('too many attempts carries the 429 to the form', () async {
      final c = VaultController(
        loadCrypto: () async => crypto,
        fetchKey: server.fetchKey,
        putKey: (_, _) => Future.error(const ApiException(429)),
        authSalt: () async => fakeVaultSalt,
        events: events.stream,
        kdfParams: cheapKdf,
      );
      addTearDown(c.dispose);
      await c.load();

      await c.setUp(_password);

      expect(c.status, VaultStatus.noVault);
      expect(
        Errors.message(c.formError, 'set up your vault'),
        'Too many requests. Wait a moment and try again.',
      );
    });

    test('a vault another session made first is unlocked instead', () async {
      final c = controller();
      await c.load();
      await (await unlocked()).load();

      await c.setUp(_password);

      expect(c.formError, isNull);
      expect(c.status, VaultStatus.locked);
    });
  });

  group('unlocking', () {
    test('with the wrong password says so and stays locked', () async {
      await unlocked();
      final c = controller();
      await c.load();

      await c.unlock('not the password');

      expect(c.status, VaultStatus.locked);
      expect(c.isBusy, isFalse);
      expect(
        c.formError,
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          Errors.vaultWrongPassword,
        ),
      );
    });

    test(
      'with the login password decrypts what another device saved',
      () async {
        final first = await unlocked();
        await first.save(github);
        final c = controller();
        await c.load();

        await c.unlock(_password);

        expect(c.status, VaultStatus.unlocked);
        expect(c.formError, isNull);
        expect(c.entries.single.data.password, 'gh-secret-password');
      },
    );

    test('leaves out an item that does not open, and keeps the rest', () async {
      final first = await unlocked();
      await first.save(github);
      server.items[99] = VaultCiphertext(
        id: 99,
        ciphertext: Uint8List(40),
        nonce: Uint8List(24),
      );
      final c = controller();
      await c.load();

      await c.unlock(_password);

      expect(c.entries.map((e) => e.data.name), ['GitHub']);
    });
  });

  group('items', () {
    test(
      'are stored only as ciphertext that opens to what was saved',
      () async {
        final c = await unlocked();

        final id = await c.save(github);

        final stored = server.items[id]!;
        expect(stored.formatVersion, 1);
        expect(server.sent.last, isNot(contains('GitHub')));
        expect(server.sent.last, isNot(contains('gh-secret-password')));
        expect(server.sent.last, isNot(contains('github.com')));
        expect(c.itemById(id)!.data.username, 'grace');
      },
    );

    test('edit, file in a folder, and delete', () async {
      final c = await unlocked();
      final folder = await c.save(const VaultItemData.folder('Work'));
      final id = await c.saveDraft(
        const VaultEntryDraft(name: 'GitHub', username: 'grace'),
      );

      await c.saveDraft(
        VaultEntryDraft(name: 'GitHub', username: 'ada', folderId: folder),
        id: id,
      );
      expect(c.entries.single.data.username, 'ada');
      expect(c.folderNameOf(c.entries.single.data.folderId), 'Work');
      expect(c.folders.single.data.name, 'Work');
      expect(c.draftOf(id).username, 'ada');

      await c.delete(id);
      expect(c.entries, isEmpty);
      expect(server.items.keys, [folder]);

      // A second device sees the same thing.
      final other = controller();
      await other.load();
      await other.unlock(_password);
      expect(other.folders.single.data.name, 'Work');
      expect(other.entries, isEmpty);
    });

    test('search, folder filtering and URL matching run in memory', () async {
      final c = await unlocked();
      final work = await c.save(const VaultItemData.folder('Work'));
      await c.save(github);
      await c.save(
        VaultItemData(
          kind: VaultItemKind.entry,
          name: 'Mail',
          url: 'mail.example.com',
          username: 'grace@example.com',
          folderId: work,
        ),
      );
      final sentBefore = server.sent.length;

      c.search('GIT');
      expect(c.visibleRows.map((r) => r.name), ['GitHub']);
      expect(c.visibleRows.single.subtitle, 'github.com');
      c.search('grace@');
      expect(c.visibleRows.map((r) => r.name), ['Mail']);
      c.search('');
      c.filterFolder(work);
      expect(c.visibleEntries.map((e) => e.data.name), ['Mail']);
      c.filterFolder(null);
      expect(c.visibleEntries, hasLength(2));

      expect(server.sent, hasLength(sentBefore));
    });

    test('a generated password comes from the default pool', () async {
      final c = await unlocked();

      final password = c.generate();

      expect(password, hasLength(20));
    });
  });

  group('locking', () {
    test('forgets the key and every decrypted item', () async {
      final c = await unlocked();
      await c.save(github);
      c.search('git');

      c.lock();

      expect(c.status, VaultStatus.locked);
      expect(c.entries, isEmpty);
      expect(c.query, isEmpty);
      await expectLater(
        c.save(github),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            Errors.vaultLocked,
          ),
        ),
      );
      expect(
        () => c.export(VaultExportFormat.json),
        throwsA(isA<MessageException>()),
      );
    });

    test('happens on its own once the vault sits idle', () async {
      final c = controller(autoLockAfter: const Duration(milliseconds: 50));
      await c.load();
      await c.setUp(_password);
      expect(c.status, VaultStatus.unlocked);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(c.status, VaultStatus.locked);
    });

    test('happens when the session changes', () async {
      final c = await unlocked();

      session.value = null;

      expect(c.status, VaultStatus.loading);
      expect(c.entries, isEmpty);
    });
  });

  group('vault_changed', () {
    test('reads the items another session changed', () async {
      final c = await unlocked();
      final other = controller();
      await other.load();
      await other.unlock(_password);
      await other.save(github);
      expect(c.entries, isEmpty);

      events.add(
        const FileEvent(kind: 'vault_changed', path: '', data: {'itemId': 1}),
      );
      await pumpEventQueue();

      expect(c.entries.single.data.name, 'GitHub');
    });

    test('locks a vault deleted from another session', () async {
      final c = await unlocked();
      await c.save(github);

      await server.deleteVault('');
      events.add(
        const FileEvent(kind: 'vault_changed', path: '', data: {'itemId': 0}),
      );
      await pumpEventQueue();

      expect(c.status, VaultStatus.noVault);
      expect(c.entries, isEmpty);
    });
  });

  test('starting over deletes the vault', () async {
    server.loginAuthKey = fakeLoginAuthKey(crypto, _password);
    final c = await unlocked();
    await c.save(github);

    await c.startOver(_password);

    expect(c.status, VaultStatus.noVault);
    expect(server.key, isNull);
    expect(server.items, isEmpty);
  });

  test('starting over with a password the account does not sign in with '
      'deletes nothing (#3615)', () async {
    server.loginAuthKey = fakeLoginAuthKey(crypto, _password);
    final c = await unlocked();
    await c.save(github);
    c.lock();

    await expectLater(
      c.startOver('not the login password'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          Errors.incorrectPassword,
        ),
      ),
    );

    expect(c.status, VaultStatus.locked);
    expect(server.key, isNotNull);
    expect(server.items, hasLength(1));
  });

  group('import and export', () {
    test(
      'import files folders, skips duplicates, and counts the rest',
      () async {
        final c = await unlocked();
        await c.save(github);
        const csv =
            'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
            'login_username,login_password,login_totp\n'
            'Social,,login,GitHub,,,0,https://github.com,grace,pw,\n'
            'Banking,,login,Bank,,,,https://bank.example,bob,bank-pw,\n'
            ',,login,,,,,,,,\n';

        final result = await c.import(csv);

        expect(result.imported, 1);
        expect(result.skipped, 1);
        expect(result.errors, hasLength(1));
        final bank = c.entries.firstWhere((e) => e.data.name == 'Bank');
        expect(c.folderNameOf(bank.data.folderId), 'Banking');
        expect(server.sent.join(), isNot(contains('bank-pw')));
      },
    );

    test('a JSON export reads back through the import', () async {
      final c = await unlocked();
      final work = await c.save(const VaultItemData.folder('Work'));
      await c.save(
        VaultItemData(
          kind: VaultItemKind.entry,
          name: 'GitHub',
          url: 'https://github.com',
          username: 'grace',
          password: 'pw',
          folderId: work,
        ),
      );
      final exported = c.export(VaultExportFormat.json);
      await c.startOver(_password);
      await c.setUp(_password);

      final result = await c.import(exported);

      expect(result.imported, 1);
      expect(c.entries.single.data.password, 'pw');
      expect(c.folderNameOf(c.entries.single.data.folderId), 'Work');
    });
  });
}
