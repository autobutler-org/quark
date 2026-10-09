import 'package:quark/utils/listing_snapshot_store.dart';

/// Keeps nothing: the web build has no cold launch to cover.
class NoListingSnapshotStore implements ListingSnapshotStore {
  /// A store that remembers nothing.
  const NoListingSnapshotStore();

  @override
  Future<Object?> read(String name, {required String scope}) async => null;

  @override
  Future<void> write(
    String name,
    Object? data, {
    required String scope,
  }) async {}

  @override
  Future<void> clear() async {}
}

/// The web build's store.
const ListingSnapshotStore listingSnapshotStorePlatform =
    NoListingSnapshotStore();
