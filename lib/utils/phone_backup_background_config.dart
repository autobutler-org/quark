/// Tuning for phone backup's background runs on Android (#4165).
abstract final class PhoneBackupBackgroundConfig {
  /// A run with more files than this to go asks Android to keep it alive as a
  /// foreground `dataSync` service with a progress notification; a smaller one
  /// finishes inside the plain background window.
  static const int foregroundThreshold = 5;

  /// The method channel `MainActivity` and the background worker both answer.
  static const String channelName =
      'org.autobutler.quark/phone_backup_background';
}
