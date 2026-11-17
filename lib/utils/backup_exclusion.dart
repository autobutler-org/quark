import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's own channel to `AppDelegate`, which marks a path to stay out
/// of iCloud backup (#4221).
const backupExclusionChannel = MethodChannel(
  'org.autobutler.quark/backup_exclusion',
);

/// Keeps the directory at [path] out of the device's backups, so photos the
/// app caches never reach iCloud.
///
/// iOS only. Android keeps the app's cache directory out of Google backup on
/// its own, and other platforms have no backup to opt out of. Best effort:
/// a platform that does not answer leaves the directory as it was.
Future<void> excludeFromBackup(String path) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await backupExclusionChannel.invokeMethod<void>('exclude', {'path': path});
  } on PlatformException {
    return;
  } on MissingPluginException {
    return;
  }
}
