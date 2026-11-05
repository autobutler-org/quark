// cspell:ignore rewrap
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/account_keys.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/models/vault_key.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';

/// Argon2id's floor, so a vault test spends its time on logic.
const cheapKdf = KdfParams(opsLimit: 1, memLimit: 8192);

/// The auth salt a [FakeVault]'s controllers wrap under.
final Uint8List fakeVaultSalt = Uint8List.fromList(List.generate(16, (i) => i));

/// The auth key the app sends for [password] over [fakeVaultSalt] at
/// [params], as the Quark stores it for the account.
String fakeLoginAuthKey(
  AccountCrypto crypto,
  String password, {
  KdfParams params = cheapKdf,
}) {
  final keys = crypto.deriveAuthKeys(password, fakeVaultSalt, params);
  keys.dispose();
  return keys.authKey;
}

/// The Quark's vault routes (#3459), in memory: it stores what it is sent and
/// knows nothing else.
class FakeVault {
  /// The stored wrapped key; null for an account with no vault.
  WrappedVaultKey? key;

  /// The stored items by id.
  final items = <int, VaultCiphertext>{};
  int _nextId = 1;

  /// Every body a controller sent, as JSON, to check none is plaintext.
  final sent = <String>[];

  /// Makes `GET /vault/key` fail with this status when set.
  int? failKeyWith;

  /// `GET /vault/key`.
  Future<WrappedVaultKey?> fetchKey() async {
    if (failKeyWith case final status?) throw ApiException(status);
    return key;
  }

  /// The auth key of the account's login password, which `PUT /vault/key`
  /// re-confirms (#3461). Null takes any.
  String? loginAuthKey;

  /// `PUT /vault/key`: the body as the Quark gets it, the wraps beside the
  /// re-confirming `password`. A wrong one is a 403 and nothing is stored.
  Future<void> putKey(WrappedVaultKey k, String authKey) async {
    sent.add(jsonEncode({...k.toJson(), 'password': authKey}));
    if (loginAuthKey != null && authKey != loginAuthKey) {
      throw const ApiException(403);
    }
    if (key != null) throw const ApiException(409);
    key = k;
  }

  /// `PUT /auth/password` for a vault wrapped again under the sign-in
  /// password: the body is the wrap plus `password` and `newAuthKey`, never
  /// the vault key itself. A [loginAuthKey] that does not match is a 403 and
  /// the stored key is left as it was.
  Future<void> rewrapKey(WrappedVaultKey k, String authKey) async {
    sent.add(
      jsonEncode({
        'password': authKey,
        'newAuthKey': authKey,
        'vaultKey': k.toJson(),
      }),
    );
    if (loginAuthKey != null && authKey != loginAuthKey) {
      throw const ApiException(403);
    }
    key = k;
  }

  /// `DELETE /vault`, which re-confirms [loginAuthKey] as `PUT /vault/key`
  /// does (#3615). A wrong one is a 403 and nothing is deleted.
  Future<void> deleteVault(String authKey) async {
    if (loginAuthKey != null && authKey != loginAuthKey) {
      throw const ApiException(403);
    }
    key = null;
    items.clear();
  }

  /// `GET /vault/items`.
  Future<List<VaultCiphertext>> listItems() async => items.values.toList();

  /// `POST /vault/items`.
  Future<VaultCiphertext> createItem(VaultCiphertext item) async {
    sent.add(jsonEncode(item.toJson()));
    final stored = VaultCiphertext(
      id: _nextId++,
      ciphertext: item.ciphertext,
      nonce: item.nonce,
      formatVersion: item.formatVersion,
    );
    items[stored.id] = stored;
    return stored;
  }

  /// `PUT /vault/items/:id`.
  Future<void> updateItem(int id, VaultCiphertext item) async {
    sent.add(jsonEncode(item.toJson()));
    if (!items.containsKey(id)) throw const ApiException(404);
    items[id] = VaultCiphertext(
      id: id,
      ciphertext: item.ciphertext,
      nonce: item.nonce,
      formatVersion: item.formatVersion,
    );
  }

  /// `DELETE /vault/items/:id`.
  Future<void> deleteItem(int id) async => items.remove(id);

  /// A controller over this vault, on real libsodium ([crypto]) at
  /// [cheapKdf]. The caller disposes it.
  VaultController controller(
    AccountCrypto crypto, {
    Stream<FileEvent> events = const Stream.empty(),
    Listenable? session,
    Duration autoLockAfter = const Duration(minutes: 15),
    KdfParams kdfParams = cheapKdf,
    Future<Uint8List> Function()? authSalt,
  }) => VaultController(
    loadCrypto: () async => crypto,
    fetchKey: fetchKey,
    putKey: putKey,
    deleteVault: deleteVault,
    replaceVaultKey: rewrapKey,
    listItems: listItems,
    createItem: createItem,
    updateItem: updateItem,
    deleteItem: deleteItem,
    authSalt: authSalt ?? () async => fakeVaultSalt,
    events: events,
    session: session,
    kdfParams: kdfParams,
    autoLockAfter: autoLockAfter,
  );
}
