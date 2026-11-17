import 'dart:convert';
import 'dart:typed_data';

import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/photo_disk_store.dart';
import 'package:quark/services/photo_disk_store_io.dart'
    if (dart.library.js_interop) 'package:quark/services/photo_disk_store_web.dart';
import 'package:quark/utils/photo_disk_cache_config.dart';

/// The photos the viewer showed, kept on this device across restarts (#4221):
/// [previews], the smaller renditions, under the budget picked in Settings,
/// and [originals], the full files most recently opened, under
/// [PhotoDiskCacheConfig.originalsBudgetBytes].
///
/// Cached bytes are shown at once and never revalidated. A photo's bytes
/// change on the Quark only when it is rotated, which evicts them here, or
/// when its path changes, which is a new key.
///
/// iOS, Android and desktop only. On the web both stores are null and every
/// photo is fetched, leaving caching to the browser.
abstract final class PhotoDiskCache {
  /// The preview store, or null where there is none. A test swaps in its own,
  /// the way it swaps `ThumbnailCacheManager.instance`.
  static Future<PhotoDiskStore?> previews = openPhotoDiskStorePlatform(
    PhotoDiskCacheConfig.previewsStoreKey,
    budgetBytes: () => AppSettings.instance.photoPreviewCacheBytes.value,
  );

  /// The originals store, or null where there is none. A test swaps in its
  /// own.
  static Future<PhotoDiskStore?> originals = openPhotoDiskStorePlatform(
    PhotoDiskCacheConfig.originalsStoreKey,
    budgetBytes: () => PhotoDiskCacheConfig.originalsBudgetBytes,
  );

  /// The key the photo at [path] on drive [serial] is kept under: the Quark
  /// and account it was fetched for, the active ones unless [host] and
  /// [account] say otherwise, and the file. Never the session token, so
  /// signing in again finds what is already on disk.
  static String keyFor(
    String path, {
    String? serial,
    String? host,
    String? account,
  }) =>
      // Encoded as a list so no part can run into the one beside it.
      jsonEncode([
        host ?? AppSettings.instance.activeHost ?? '',
        account ?? AppSettings.instance.username ?? '',
        serial ?? '',
        path,
      ]);

  /// The original of the photo at [path] from disk, else from [download],
  /// kept for next time.
  static Future<Uint8List?> original(
    String path, {
    String? serial,
    required Future<Uint8List?> Function() download,
  }) => _fetch(originals, keyFor(path, serial: serial), download);

  /// The preview of the photo at [path] from disk, else from [download], kept
  /// for next time.
  static Future<Uint8List?> preview(
    String path, {
    String? serial,
    required Future<Uint8List?> Function() download,
  }) => _fetch(previews, keyFor(path, serial: serial), download);

  static Future<Uint8List?> _fetch(
    Future<PhotoDiskStore?> store,
    String key,
    Future<Uint8List?> Function() download,
  ) async {
    final disk = await store;
    final cached = await disk?.read(key);
    if (cached != null) return cached;
    final bytes = await download();
    if (bytes != null) await disk?.write(key, bytes);
    return bytes;
  }

  /// Forgets the photo at [path] on drive [serial], both renditions, so the
  /// next look fetches it again: its content changed on the Quark.
  static Future<void> evict(String path, {String? serial}) async {
    final key = keyFor(path, serial: serial);
    for (final store in await _stores()) {
      await store.remove(key);
    }
  }

  /// Empties both stores and the viewer's memory of the photos in them, for
  /// "Clear cached photos" in Settings.
  static Future<void> clear() async {
    PhotoBytesCache.instance.clear();
    for (final store in await _stores()) {
      await store.clear();
    }
  }

  /// Drops every photo kept for [host], only [account]'s when it is given:
  /// signing out of a Quark, or removing it, leaves none of its photos on
  /// this device.
  static Future<void> forget({required String host, String? account}) async {
    // The memory cache is keyed by path alone, so it all goes.
    PhotoBytesCache.instance.clear();
    bool belongs(String key) {
      try {
        final parts = jsonDecode(key) as List<dynamic>;
        return parts[0] == host && (account == null || parts[1] == account);
      } on FormatException {
        return false;
      }
    }

    for (final store in await _stores()) {
      await store.removeWhere(belongs);
    }
  }

  /// How many bytes both stores hold.
  static Future<int> sizeInBytes() async {
    var total = 0;
    for (final store in await _stores()) {
      total += await store.sizeInBytes();
    }
    return total;
  }

  /// Trims the preview store to its budget, after the budget was lowered.
  static Future<void> trimPreviews() async => (await previews)?.trim();

  static Future<List<PhotoDiskStore>> _stores() async => [
    ?await previews,
    ?await originals,
  ];
}
