import 'package:quark/services/native_vault_cache_stub.dart'
    if (dart.library.io) 'package:quark/services/native_vault_cache_io.dart'
    as impl;
import 'package:quark/services/vault_cache.dart';

/// Stores the [VaultCache] file where native autofill can read it (#3596):
/// the iOS app group container, or Android's `noBackupFilesDir`.
///
/// One account is cached at a time, so [write] drops every other account's
/// file and [clear] removes them all. On web and desktop there is no
/// directory and nothing is stored; the stub never calls `dart:io`.
class NativeVaultCache {
  /// Builds a cache over [directory], the cache directory's path or null
  /// for none. The default resolves the platform's; tests pass a temp one.
  NativeVaultCache({Future<String?> Function()? directory})
    : _directory = directory ?? impl.defaultDirectory;

  /// The app's cache.
  static final NativeVaultCache instance = NativeVaultCache();

  final Future<String?> Function() _directory;

  /// Replaces [accountKey]'s file with [contents], atomically, and removes
  /// every other account's.
  Future<void> write(String accountKey, String contents) async {
    final dir = await _directory();
    if (dir == null) return;
    await impl.replaceOnly(dir, VaultCache.fileName(accountKey), contents);
  }

  /// Removes every account's file.
  Future<void> clear() async {
    final dir = await _directory();
    if (dir == null) return;
    await impl.deleteDirectory(dir);
  }
}
