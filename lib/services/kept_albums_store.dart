import 'dart:convert';

import 'package:quark/models/kept_album.dart';
import 'package:quark/utils/kept_albums_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saves the albums kept on this phone (#4222), every Quark's and account's,
/// so a keep resumes after the app restarts and its album opens with no
/// network. The photos themselves live in `PhotoDiskCache`'s kept stores;
/// this holds only what was kept and the album listings.
abstract final class KeptAlbumsStore {
  /// What [load] last read or [save] last wrote, held in memory so a caller
  /// handling a failure, as `AlbumService` does offline, reads it at once
  /// rather than waiting on storage. Empty until the first of them.
  static List<KeptAlbum> loaded = const [];

  /// Every kept album, or none when nothing was saved or it cannot be read.
  static Future<List<KeptAlbum>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(KeptAlbumsConfig.prefsKey);
      loaded = raw == null
          ? const []
          : List.unmodifiable([
              for (final album in jsonDecode(raw) as List<dynamic>)
                KeptAlbum.fromJson(album as Map<String, dynamic>),
            ]);
    } on Object {
      loaded = const [];
    }
    return List.of(loaded);
  }

  /// Saves [albums] in place of what was saved before.
  static Future<void> save(List<KeptAlbum> albums) async {
    loaded = List.unmodifiable(albums);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      KeptAlbumsConfig.prefsKey,
      jsonEncode([for (final album in albums) album.toJson()]),
    );
  }

  /// The kept album [albumId] of [host] and [account] in [loaded], or null.
  static KeptAlbum? find(
    int albumId, {
    required String? host,
    required String? account,
  }) {
    for (final album in loaded) {
      if (album.albumId == albumId && album.belongsTo(host, account)) {
        return album;
      }
    }
    return null;
  }
}
