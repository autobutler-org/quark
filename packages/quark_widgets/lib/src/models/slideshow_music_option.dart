import 'package:flutter/foundation.dart';

/// One choice of background music for a slideshow: a music album, as the
/// slideshow's music picker lists it.
///
/// The package's own view of the choice, so the picker never imports the
/// app's music model. The app maps its albums into this and matches the
/// picked one back by [id].
@immutable
class SlideshowMusicOption {
  /// Creates a choice identified by [id].
  const SlideshowMusicOption({
    required this.id,
    required this.title,
    this.subtitle = '',
  });

  /// The stable identity the picker reports back, such as an album key.
  final String id;

  /// The name shown for the choice: the album's title.
  final String title;

  /// A second line under [title], such as the album artist. Empty hides it.
  final String subtitle;

  @override
  bool operator ==(Object other) =>
      other is SlideshowMusicOption &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(id, title, subtitle);
}
