import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/vault_cache_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/vault_cache.dart';

import '../support/fake_vault.dart';

const _password = 'correct horse battery staple';

const _github = VaultItemData(
  kind: VaultItemKind.entry,
  name: 'GitHub',
  url: 'https://github.com/login',
  username: 'grace-at-github',
  password: 'gh-secret-password',
  notes: 'recovery codes in the drawer',
);

/// The cache files in memory, by account key.
class _Disk {
  final files = <String, String>{};
  int clears = 0;
  int writes = 0;

  Future<void> write(String accountKey, String contents) async {
    writes++;
    files
      ..clear()
      ..[accountKey] = contents;
  }

  Future<void> clear() async {
    clears++;
    files.clear();
  }

  Map<String, dynamic> only() {
    expect(files, hasLength(1));
    return jsonDecode(files.values.single) as Map<String, dynamic>;
  }
}

void main() {
  late AccountCrypto crypto;
  late FakeVault server;
  late _Disk disk;
  late StreamController<FileEvent> events;
  late ValueNotifier<String?> session;
  late ({String host, String username})? account;

  setUpAll(() async => crypto = await AccountCrypto.load());

  setUp(() {
    server = FakeVault();
    disk = _Disk();
    events = StreamController<FileEvent>.broadcast();
    session = ValueNotifier('token');
    account = (host: 'https://quark.local', username: 'grace');
  });

  tearDown(() => events.close());

  VaultCacheController cacheController({VaultController? vault}) {
    final c = VaultCacheController(
      fetchKey: server.fetchKey,
      listItems: server.listItems,
      account: () async => account,
      write: disk.write,
      clear: disk.clear,
      now: () => DateTime.utc(2026, 10, 20, 12),
      enabled: true,
    );
    addTearDown(c.dispose);
    c.start(events: events.stream, session: session, vault: vault);
    return c;
  }

  /// A vault page controller over [server], set up under [_password] and
  /// unlocked.
  Future<VaultController> unlockedVault() async {
    final v = server.controller(crypto, events: events.stream);
    addTearDown(v.dispose);
    await v.load();
    await v.setUp(_password);
    expect(v.status, VaultStatus.unlocked);
    return v;
  }

  /// Lets the cache controller's queued work finish.
  Future<void> settle() => pumpEventQueue();

  String serverItemsJson() => jsonEncode([
    for (final item in server.items.values) {'id': item.id, ...item.toJson()},
  ]);

  test('start writes the items the server holds, as ciphertext', () async {
    final vault = await unlockedVault();
    await vault.save(_github);
    cacheController();
    await settle();

    final json = disk.only();
    expect(
      disk.files.keys.single,
      VaultCache.accountKey('https://quark.local', 'grace'),
    );
    expect(json['host'], 'https://quark.local');
    expect(json['username'], 'grace');
    expect(jsonEncode(json['items']), serverItemsJson());
  });

  test('nothing in the file is plaintext, a password or a key', () async {
    final vault = await unlockedVault();
    await vault.save(_github);
    cacheController();
    await settle();

    final raw = disk.files.values.single;
    for (final secret in [
      _password,
      _github.password,
      _github.username,
      _github.notes,
      'github.com',
      'GitHub',
    ]) {
      expect(raw, isNot(contains(secret)));
    }
    final json = disk.only();
    expect(json.keys.toSet(), {
      'schema',
      'host',
      'username',
      'syncedAt',
      'items',
    });
    for (final item in json['items'] as List) {
      expect((item as Map).keys.toSet(), {
        'id',
        'ciphertext',
        'nonce',
        'formatVersion',
      });
    }
    // The wrapped key and its KDF parameters stay on the Quark.
    final key = server.key!.toJson();
    for (final value in key.values.whereType<String>()) {
      expect(raw, isNot(contains(value)));
    }
  });

  test('an unlock refreshes the cache', () async {
    final vault = await unlockedVault();
    vault.lock();
    cacheController(vault: vault);
    await settle();
    expect(jsonEncode(disk.only()['items']), '[]');

    // Another device adds an item; this app learns of it on unlock.
    final other = server.controller(crypto);
    addTearDown(other.dispose);
    await other.load();
    await other.unlock(_password);
    await other.save(_github);

    await vault.unlock(_password);
    await settle();
    expect(jsonEncode(disk.only()['items']), serverItemsJson());
    expect(server.items, hasLength(1));
  });

  test('vault_changed brings in an add, an edit and a delete from another '
      'device, even while locked', () async {
    final vault = await unlockedVault();
    cacheController();
    await settle();
    expect(disk.only()['items'], isEmpty);

    final id = await vault.save(_github);
    vault.lock();
    events.add(const FileEvent(kind: 'vault_changed', path: ''));
    await settle();
    expect(jsonEncode(disk.only()['items']), serverItemsJson());

    await vault.unlock(_password);
    await vault.save(
      const VaultItemData(kind: VaultItemKind.entry, name: 'GitHub 2'),
      id: id,
    );
    events.add(const FileEvent(kind: 'resync', path: ''));
    await settle();
    expect(jsonEncode(disk.only()['items']), serverItemsJson());

    await vault.delete(id);
    events.add(const FileEvent(kind: 'vault_changed', path: ''));
    await settle();
    expect(disk.only()['items'], isEmpty);
  });

  test('other events leave the cache alone', () async {
    await unlockedVault();
    cacheController();
    await settle();
    disk.files.clear();
    events.add(const FileEvent(kind: 'file_created', path: '/a'));
    await settle();
    expect(disk.files, isEmpty);
  });

  test('signing out wipes the cache', () async {
    await unlockedVault();
    cacheController();
    await settle();
    expect(disk.files, hasLength(1));

    account = null;
    session.value = null;
    await settle();
    expect(disk.files, isEmpty);
    expect(disk.clears, greaterThan(0));
  });

  test('switching account replaces the previous account\'s cache', () async {
    await unlockedVault();
    cacheController();
    await settle();
    final before = disk.files.keys.single;

    account = (host: 'https://quark.local', username: 'ada');
    server.key = null; // ada has no vault
    server.items.clear();
    session.value = 'ada-token';
    await settle();
    expect(disk.files, isEmpty);
    expect(disk.files.containsKey(before), isFalse);
  });

  test('a session change mid-fetch never writes the old account', () async {
    await unlockedVault();
    final gate = Completer<void>();
    final c = VaultCacheController(
      fetchKey: server.fetchKey,
      listItems: () async {
        await gate.future;
        return server.listItems();
      },
      account: () async => account,
      write: disk.write,
      clear: disk.clear,
      enabled: true,
    );
    addTearDown(c.dispose);
    c.start(events: events.stream, session: session);
    await settle();

    account = null;
    session.value = null;
    gate.complete();
    await settle();
    expect(disk.writes, 0);
    expect(disk.files, isEmpty);
  });

  test('a deleted vault wipes the cache', () async {
    final vault = await unlockedVault();
    await vault.save(_github);
    cacheController();
    await settle();
    expect(disk.files, hasLength(1));

    await vault.startOver(_password);
    events.add(const FileEvent(kind: 'vault_changed', path: ''));
    await settle();
    expect(disk.files, isEmpty);
  });

  test('a failed fetch keeps the last cache for offline fills', () async {
    await unlockedVault();
    cacheController();
    await settle();
    final before = Map.of(disk.files);

    server.failKeyWith = 503;
    events.add(const FileEvent(kind: 'vault_changed', path: ''));
    await settle();
    expect(disk.files, before);
  });

  test('disabled, as on web, it neither fetches nor writes', () async {
    var fetched = false;
    final c = VaultCacheController(
      fetchKey: () async {
        fetched = true;
        return null;
      },
      listItems: server.listItems,
      account: () async => account,
      write: disk.write,
      clear: disk.clear,
      enabled: false,
    );
    addTearDown(c.dispose);
    c.start(events: events.stream, session: session);
    events.add(const FileEvent(kind: 'vault_changed', path: ''));
    await settle();
    expect(fetched, isFalse);
    expect(disk.files, isEmpty);
  });
}
