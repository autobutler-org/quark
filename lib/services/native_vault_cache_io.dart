/// The native vault cache's files on iOS and Android (#3596).
///
/// iOS puts them in the app group container, under
/// `Library/Application Support/vault-autofill/`, so the credential provider
/// extension can read them. Files there default to the
/// `completeUntilFirstUserAuthentication` protection class, which lets the
/// app refresh the cache from a background event after the first unlock.
/// Android puts them in `noBackupFilesDir/vault-autofill/`, which the
/// `AutofillService` reads in the app's own process and Auto Backup skips.
/// Every other platform has no autofill to share with and stores nothing.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:quark/services/vault_cache.dart';

/// The cache directory on this platform, or null for none: off iOS and
/// Android, or on an iOS build whose app group entitlement is missing.
Future<String?> defaultDirectory() async {
  if (Platform.isIOS) {
    final container = await PathProviderFoundation().getContainerPath(
      appGroupIdentifier: VaultCache.appGroup,
    );
    if (container == null) {
      debugPrint('[native_vault_cache] no ${VaultCache.appGroup} container');
      return null;
    }
    return '$container/Library/Application Support/${VaultCache.directoryName}';
  }
  if (Platform.isAndroid) {
    // path_provider has no noBackupFilesDir. Android keeps it beside
    // filesDir, which is what the application support directory is there.
    final files = await getApplicationSupportDirectory();
    return '${files.parent.path}/no_backup/${VaultCache.directoryName}';
  }
  return null;
}

/// Writes [contents] to [name] in [dir] through a temporary file and a
/// rename, so a reader never sees half a file, then deletes every other file
/// there.
Future<void> replaceOnly(String dir, String name, String contents) async {
  final directory = await Directory(dir).create(recursive: true);
  final temp = File('${directory.path}/$name.tmp');
  await temp.writeAsString(contents, flush: true);
  await temp.rename('${directory.path}/$name');
  final others = await directory
      .list()
      .where((e) => e is File && e.uri.pathSegments.last != name)
      .toList();
  for (final other in others) {
    await other.delete();
  }
}

/// Deletes [dir] and everything in it, if it is there.
Future<void> deleteDirectory(String dir) async {
  final directory = Directory(dir);
  if (await directory.exists()) await directory.delete(recursive: true);
}
