import 'package:quark/models/music_track.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Maps the app's music models into the value types the package's music
/// widgets render.
extension MusicTrackItems on MusicTrack {
  /// This track as a [TrackListTile] row.
  MusicTrackItem toItem() => MusicTrackItem(
    path: relPath,
    serial: serial,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
  );
}

/// Maps a search hit into the package's [MusicSearchResult].
extension MusicSearchHitResults on MusicSearchHit {
  /// This hit as a [MusicSearchResults] row, with the Quark's `<b>`
  /// highlight markers dropped: the package renders the snippet as text.
  MusicSearchResult toResult() => MusicSearchResult(
    track: track.toItem(),
    snippet: snippet.replaceAll(RegExp('</?b>'), ''),
  );
}
