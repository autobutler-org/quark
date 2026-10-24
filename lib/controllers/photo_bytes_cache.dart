import 'dart:typed_data';

import 'package:quark/utils/image_viewer_config.dart';

/// In-memory LRU of downloaded photo bytes, keyed by relPath + serial.
///
/// Sibling to `FileBrowserCache`, which does the same job for folder listings:
/// a process-wide singleton, so a viewer opened, closed and reopened still
/// sees what the last one fetched.
///
/// Holds *encoded* bytes only. Decoded bitmaps are an order of magnitude
/// larger (a 4000x3000 photo is ~48MB of RGBA), which is why this is bounded
/// by a byte budget rather than an item count — a fixed count of full-size
/// photos is exactly the shape that OOM-kills a low-end phone (#1710).
///
/// Failures are not cached: a photo that failed to download is retried the
/// next time it is asked for, and the exception reaches the caller unchanged
/// so the viewer can still tell a 404 from a dropped request (#1708).
class PhotoBytesCache {
  PhotoBytesCache._();
  static final instance = PhotoBytesCache._();

  /// Insertion order is the LRU order — a hit reinserts at the end.
  final Map<String, Uint8List> _entries = {};

  /// Downloads in flight, so a prefetch of the next photo and the user
  /// arriving at it a moment later share one request instead of racing.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  int _heldBytes = 0;

  static String key(String relPath, String? serial) =>
      '${serial ?? ''} $relPath';

  /// The cached bytes for [cacheKey], or null. Marks the entry
  /// most-recently-used.
  Uint8List? get(String cacheKey) {
    final bytes = _entries.remove(cacheKey);
    if (bytes == null) return null;
    _entries[cacheKey] = bytes;
    return bytes;
  }

  /// Cached bytes for [cacheKey], else whatever [download] returns, retained.
  Future<Uint8List?> fetch(
    String cacheKey,
    Future<Uint8List?> Function() download,
  ) {
    final cached = get(cacheKey);
    if (cached != null) return Future.value(cached);

    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    final pending = download().then((bytes) {
      if (bytes != null) put(cacheKey, bytes);
      return bytes;
    });
    _inFlight[cacheKey] = pending;
    return pending.whenComplete(() => _inFlight.remove(cacheKey));
  }

  void put(String cacheKey, Uint8List bytes) {
    // A photo bigger than the whole budget would evict everything and then
    // itself; leave the cache as it was and let it be re-downloaded.
    if (bytes.lengthInBytes > ImageViewerConfig.photoCacheBudgetBytes) return;

    final replaced = _entries.remove(cacheKey);
    if (replaced != null) _heldBytes -= replaced.lengthInBytes;
    _entries[cacheKey] = bytes;
    _heldBytes += bytes.lengthInBytes;

    while (_heldBytes > ImageViewerConfig.photoCacheBudgetBytes &&
        _entries.length > 1) {
      final oldest = _entries.keys.first;
      _heldBytes -= _entries.remove(oldest)!.lengthInBytes;
    }
  }

  /// Drops [cacheKey], so the next look at that photo downloads it again.
  ///
  /// Rotating a photo rewrites it on the Quark, which leaves the bytes held
  /// here describing the photo as it was — the one mutation that changes a
  /// photo's content without changing its path or serial.
  void evict(String cacheKey) {
    final removed = _entries.remove(cacheKey);
    if (removed != null) _heldBytes -= removed.lengthInBytes;
  }

  void clear() {
    _entries.clear();
    _inFlight.clear();
    _heldBytes = 0;
  }
}
