/// Tuning for the on-device disk cache of viewed photos (#4221), read by
/// `PhotoDiskCache` and the Settings control that sizes it.
abstract final class PhotoDiskCacheConfig {
  /// Names the folder and index of the store holding previews: the smaller
  /// renditions the viewer shows, such as a HEIC's stored JPEG. Changing it
  /// orphans every preview already on disk.
  static const String previewsStoreKey = 'quarkPreviews';

  /// Names the folder and index of the store holding recently viewed
  /// originals. Changing it orphans every original already on disk.
  static const String originalsStoreKey = 'quarkOriginals';

  /// One MiB, the unit the budgets are written in.
  static const int _mib = 1024 * 1024;

  /// How many bytes of previews are kept before the least recently used go,
  /// until the user picks another size in Settings. A preview runs a few
  /// hundred kilobytes, so this holds a few thousand photos.
  static const int defaultPreviewBudgetBytes = 1024 * _mib;

  /// The preview budgets Settings offers.
  static const List<int> previewBudgetChoices = [
    256 * _mib,
    512 * _mib,
    1024 * _mib,
    2048 * _mib,
    4096 * _mib,
  ];

  /// How many bytes of originals are kept before the least recently used go.
  /// A phone photo runs 3 to 8 MB, so this holds the last hundred or so
  /// opened: enough for yesterday's photos to open with no network.
  static const int originalsBudgetBytes = 500 * _mib;

  /// How many entries the underlying store keeps whatever their size. The
  /// byte budget is the real bound; this is set past anything it allows so
  /// the store's own count limit never evicts first.
  static const int maxObjects = 100000;

  /// How long an entry nobody has opened stays on disk.
  static const Duration stalePeriod = Duration(days: 365);
}
