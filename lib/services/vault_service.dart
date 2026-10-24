import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/vault_item.dart';
import 'package:quark/models/vault_key.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';

/// The signed-in account's own vault under `/api/v0/vault` (#3459): its
/// wrapped vault key and its items.
///
/// Everything here is ciphertext: `VaultController` encrypts and decrypts
/// with `AccountCrypto`, and the Quark only stores what it is sent. Recovery's
/// fetch of the wrapped key, which has no session, is
/// `AuthService.fetchRecoveryVaultKey`.
class VaultService with AuthenticatedService {
  VaultService._();

  /// The one instance, for the [AuthenticatedService] helpers.
  static final VaultService instance = VaultService._();

  /// The account's wrapped vault key, or null when it has no vault yet.
  ///
  /// [sessionToken] is for a session the app has not stored yet: a sign-in
  /// whose recovery phrase is still on screen.
  static Future<WrappedVaultKey?> fetchKey({String? sessionToken}) async {
    final response = await instance.authenticatedGet(
      _uri('/key'),
      headers: _bearer(sessionToken),
    );
    if (response.statusCode == 404) return null;
    _check(response, 'fetch the vault key');
    return WrappedVaultKey.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Stores [key] as the account's first vault key. The Quark never replaces
  /// one here: a key that already exists is a 409.
  ///
  /// [authKey], the login password's auth key, re-confirms the caller as
  /// `PUT /auth/recovery-key` does: a wrong one is a 403 and nothing is
  /// stored. It is the only key sent; [key] holds only wraps.
  static Future<void> putKey(WrappedVaultKey key, String authKey) async {
    final response = await instance.authenticatedPut(
      _uri('/key'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({...key.toJson(), 'password': authKey}),
    );
    _check(response, 'store the vault key');
  }

  /// Deletes the account's vault key and every item: starting over.
  ///
  /// [authKey], the login password's auth key, re-confirms the caller as
  /// [putKey]'s does: a wrong one is a 403 and nothing is deleted, so a
  /// session alone cannot wipe a vault (#3615).
  static Future<void> deleteVault(String authKey) async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/vault'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'password': authKey}),
    );
    _check(response, 'delete the vault');
  }

  /// Every item the account stores.
  static Future<List<VaultCiphertext>> listItems() async {
    final response = await instance.authenticatedGet(_uri('/items'));
    _check(response, 'list vault items');
    return [
      for (final item in jsonDecode(response.body) as List? ?? const [])
        VaultCiphertext.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Stores a new item and returns it with its id.
  static Future<VaultCiphertext> createItem(VaultCiphertext item) async {
    final response = await instance.authenticatedPost(
      _uri('/items'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(item.toJson()),
    );
    _check(response, 'create a vault item');
    return VaultCiphertext.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Replaces item [id]'s ciphertext.
  static Future<void> updateItem(int id, VaultCiphertext item) async {
    final response = await instance.authenticatedPut(
      _uri('/items/$id'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(item.toJson()),
    );
    _check(response, 'update vault item $id');
  }

  /// Deletes item [id].
  static Future<void> deleteItem(int id) async {
    final response = await instance.authenticatedDelete(_uri('/items/$id'));
    _check(response, 'delete vault item $id');
  }

  static Map<String, String> _bearer(String? token) =>
      token == null ? const {} : {'Authorization': 'Bearer $token'};

  static Uri _uri(String suffix) => apiBaseUri.resolve('/api/v0/vault$suffix');

  // The Quark's text for a refused vault request is not copy: every status it
  // sends has a sentence of its own in Errors.
  static void _check(http.Response response, String context) =>
      throwUnlessOk(response, context, serverText: false);
}
