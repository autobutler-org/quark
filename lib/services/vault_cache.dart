import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/services/app_settings.dart';

/// The ciphertext cache native autofill reads (#3596): its names and its
/// file format, from `docs/design/native-autofill-vault.md` ("Names the
/// sub-issues use" and "Decision 3").
///
/// The file holds what `GET /api/v0/vault/items` returned and nothing else:
/// each item's id, ciphertext, nonce and formatVersion, base64 as the Quark
/// sent them, beside the host and username the extension labels an account
/// with. No plaintext, no vault key, and no wrapped key or KDF parameters:
/// the extension never derives a key from the password, so they would only
/// hand a thief an offline guess at it. [NativeVaultCache] puts the file
/// where the app and its extension can both read it.
abstract final class VaultCache {
  /// The iOS app group the app and its credential provider extension share.
  static const appGroup = 'group.org.autobutler.quark';

  /// The directory the cache files sit in, inside the app group container's
  /// `Library/Application Support` on iOS and `noBackupFilesDir` on Android.
  static const directoryName = 'vault-autofill';

  /// The file format's version, which a reader checks before anything else.
  static const schema = 1;

  /// The name an account's cache file, Keychain item and Keystore entry
  /// share: `acct_` and the first 32 hex digits of
  /// `sha256(normalizedHost || 0x00 || username)`.
  ///
  /// The host is normalized as the app stores it ([normalizeHostAddress]),
  /// lowercased, without a trailing slash, so `quark.local` and
  /// `https://quark.local/` name the same account.
  static String accountKey(String host, String username) {
    var normalized = normalizeHostAddress(host).toLowerCase();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final digest = sha256.convert([
      ...utf8.encode(normalized),
      0,
      ...utf8.encode(username),
    ]);
    return 'acct_${digest.toString().substring(0, 32)}';
  }

  /// The cache file's name for [accountKey].
  static String fileName(String accountKey) => '$accountKey.json';

  /// The cache file for the account [username] on [host], holding [items]
  /// as the Quark listed them at [syncedAt].
  static String encode({
    required String host,
    required String username,
    required List<VaultCiphertext> items,
    required DateTime syncedAt,
  }) => jsonEncode({
    'schema': schema,
    'host': host,
    'username': username,
    'syncedAt': syncedAt.toUtc().toIso8601String(),
    'items': [
      for (final item in items) {'id': item.id, ...item.toJson()},
    ],
  });
}
