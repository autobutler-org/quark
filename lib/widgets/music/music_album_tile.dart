import 'package:flutter/material.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One [MusicAlbum] as an [AlbumGridTile], with its cover from the Quark.
class MusicAlbumTile extends StatelessWidget {
  /// Creates the card for [album].
  const MusicAlbumTile({required this.album, required this.onTap, super.key});

  /// The album to show.
  final MusicAlbum album;

  /// Called with the album's key when tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return AlbumGridTile(
      albumKey: album.albumKey,
      title: album.title.isEmpty ? 'Unknown album' : album.title,
      albumArtist: album.albumArtist,
      year: album.year > 0 ? album.year : null,
      trackCount: album.trackCount,
      coverBuilder: MusicCover.builder(
        album.coverPath,
        serial: album.coverSerial,
      ),
      onTap: onTap,
    );
  }
}
