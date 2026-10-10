import 'package:quark/utils/listing_snapshot_store_io.dart'
    if (dart.library.js_interop) 'package:quark/utils/listing_snapshot_store_web.dart'
    as platform;

/// Listings kept across launches, so a cold launch can show the last content
/// while the first request is still out (#1781).
///
/// A snapshot is JSON under a name, and belongs to the [scope] it was written
/// for: reading it under any other scope deletes it. Only what a listing
/// request returns belongs in one, never a session token, file bytes or a
/// thumbnail.
///
/// No call throws. A snapshot that cannot be read, written or parsed is a
/// slower first frame, not an error anyone needs to see.
abstract interface class ListingSnapshotStore {
  /// The data last written under [name] for [scope], or null when there is
  /// none, it was written for another scope, or it cannot be read.
  Future<Object?> read(String name, {required String scope});

  /// Keeps the JSON value [data] under [name] for [scope], in place of what
  /// was there.
  Future<void> write(String name, Object? data, {required String scope});

  /// Deletes every snapshot.
  Future<void> clear();
}

/// The store this platform keeps listing snapshots in: files on native, and
/// nothing on web, where a reload already has the browser's own cache.
ListingSnapshotStore get listingSnapshotStore =>
    platform.listingSnapshotStorePlatform;
