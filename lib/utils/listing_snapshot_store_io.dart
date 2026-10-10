import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quark/utils/listing_snapshot_config.dart';
import 'package:quark/utils/listing_snapshot_store.dart';

/// Snapshots as JSON files, one per name, under the app's support directory:
/// `listing_cache/<name>.json` holding `{"scope": ..., "data": ...}`.
///
/// Every call is asynchronous and queued behind the one before it, so a
/// [clear] issued after a [write] always wins and nothing here can hold up a
/// frame.
class IoListingSnapshotStore implements ListingSnapshotStore {
  /// [root] is the directory the files live in; a test passes a temporary
  /// one.
  IoListingSnapshotStore({Future<Directory> Function()? root})
    : _resolveRoot = root ?? _supportDirectory;

  final Future<Directory> Function() _resolveRoot;

  /// Resolved once: the path does not move while the app runs. Null when it
  /// cannot be resolved, which leaves the store keeping nothing.
  late final Future<Directory?> _root = Future.sync(_resolveRoot)
      .then<Directory?>(
        (root) => root,
        onError: (Object e) {
          debugPrint('[listing_snapshot_store_io.dart] no directory: $e');
          return null;
        },
      );

  /// The last call queued. Every call chains onto it.
  Future<void> _tail = Future.value();

  /// The file contents last asked for under each name. The Files page puts
  /// the same listing back on every refresh, and that must not reach the
  /// disk.
  final _requested = <String, String>{};

  static Future<Directory> _supportDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/'
    '${ListingSnapshotConfig.directoryName}',
  );

  Future<File?> _file(String name) async {
    final root = await _root;
    return root == null ? null : File('${root.path}/$name.json');
  }

  Future<T> _queued<T>(Future<T> Function() call) {
    final result = _tail.then((_) => call());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<Object?> read(String name, {required String scope}) =>
      _queued(() async {
        try {
          final file = await _file(name);
          if (file == null || !await file.exists()) return null;
          try {
            if (await file.length() <= ListingSnapshotConfig.maxBytes) {
              final contents = await file.readAsString();
              final decoded = jsonDecode(contents);
              if (decoded is Map &&
                  decoded['scope'] == scope &&
                  decoded.containsKey('data')) {
                // Writing this back unchanged is not a write either.
                _requested.putIfAbsent(name, () => contents);
                return decoded['data'];
              }
            }
          } catch (e) {
            debugPrint('[listing_snapshot_store_io.dart] unreadable $name: $e');
          }
          // Too big, corrupt, or another account's: gone, not surfaced.
          await file.delete();
        } catch (e) {
          debugPrint('[listing_snapshot_store_io.dart] read $name failed: $e');
        }
        return null;
      });

  @override
  Future<void> write(String name, Object? data, {required String scope}) {
    final encoded = jsonEncode({'scope': scope, 'data': data});
    if (_requested[name] == encoded) return Future.value();
    _requested[name] = encoded;
    return _queued(() async {
      try {
        final file = await _file(name);
        if (file == null) return;
        final bytes = utf8.encode(encoded);
        if (bytes.length > ListingSnapshotConfig.maxBytes) {
          if (await file.exists()) await file.delete();
          return;
        }
        await file.parent.create(recursive: true);
        // Renamed into place, so a launch never reads half a snapshot.
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes);
        await temp.rename(file.path);
      } catch (e) {
        // Not on disk after all, so the same data must be allowed again.
        if (_requested[name] == encoded) _requested.remove(name);
        debugPrint('[listing_snapshot_store_io.dart] write $name failed: $e');
      }
    });
  }

  @override
  Future<void> clear() {
    _requested.clear();
    return _queued(() async {
      try {
        final root = await _root;
        if (root != null && await root.exists()) {
          await root.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('[listing_snapshot_store_io.dart] clear failed: $e');
      }
    });
  }
}

/// The native store.
final ListingSnapshotStore listingSnapshotStorePlatform =
    IoListingSnapshotStore();
