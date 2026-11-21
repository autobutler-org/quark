/// Tuning for albums kept on this phone for offline viewing (#4222), read by
/// `KeptAlbumsController` and the dialog that starts a keep.
abstract final class KeptAlbumsConfig {
  /// The SharedPreferences key the kept albums are saved under.
  static const String prefsKey = 'keptAlbums';

  /// What one photo's preview is guessed to take before it is downloaded: a
  /// JPEG at most 2048 px on its long edge runs a few hundred kilobytes.
  static const int previewEstimateBytes = 400 * 1024;

  /// What one photo's original is guessed to take before it is downloaded:
  /// a phone photo runs 3 to 8 MB.
  static const int originalEstimateBytes = 5 * 1024 * 1024;

  /// How long after a change on the Quark the kept albums sync, so a burst
  /// of uploads or deletes costs one sync rather than one each.
  static const Duration syncDebounce = Duration(seconds: 2);

  /// How often a sync that left work undone, waiting for Wi-Fi or cut off by
  /// a dropped connection, tries again while the app is open.
  static const Duration retryInterval = Duration(minutes: 5);

  /// What keeping [photos] photos is guessed to take, before any is
  /// downloaded: their previews, and their originals too when [originals].
  static int estimateBytes(int photos, {required bool originals}) =>
      photos * (previewEstimateBytes + (originals ? originalEstimateBytes : 0));
}
