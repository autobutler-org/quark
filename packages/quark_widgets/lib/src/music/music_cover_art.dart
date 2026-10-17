import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A square album cover supplied by the caller, or a themed disc placeholder.
///
/// The cover comes from [coverBuilder] because loading it needs the network or
/// a device API this package does not depend on. The builder is clipped to the
/// same rounded square as the placeholder.
///
/// Key: `music_cover_surface` on the surface behind either variant.
///
/// ```dart
/// MusicCoverArt(
///   semanticLabel: 'Cover for Kind of Blue',
///   coverBuilder: (context) => CachedNetworkImage(imageUrl: coverUrl),
/// );
/// ```
class MusicCoverArt extends StatelessWidget {
  /// Creates cover art, falling back to a disc when [coverBuilder] is null.
  const MusicCoverArt({
    this.coverBuilder,
    this.semanticLabel = 'Album cover',
    super.key,
  });

  /// Builds the image that fills the square. Null shows the placeholder.
  final WidgetBuilder? coverBuilder;

  /// The cover's screen-reader label.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final coverBuilder = this.coverBuilder;

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        child: DecoratedBox(
          key: const ValueKey('music_cover_surface'),
          decoration: BoxDecoration(color: tokens.sidebar),
          child: coverBuilder == null
              ? Center(
                  child: Icon(
                    QuarkIcons.disc_full,
                    color: tokens.mutedForeground,
                  ),
                )
              : Semantics(
                  image: true,
                  label: semanticLabel,
                  child: ExcludeSemantics(child: coverBuilder(context)),
                ),
        ),
      ),
    );
  }
}
