import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A picture on a slide: [image] fitted to its box with [fit], a muted box
/// while it loads, and a muted box with a broken-picture glyph when it never
/// does — a file that moved, or a Quark that cannot be reached.
///
/// The slide editor builds one for every image element and background image,
/// from the presentation's path through the app's authenticated download
/// URL, so the canvas and the slide panel's thumbnails share a cached decode.
///
/// The picture is excluded from semantics: the canvas already names the
/// element ("Image") to a screen reader.
///
/// Key prefixes: `slide_image_loading` on the placeholder and
/// `slide_image_error` on the error state.
///
/// ```dart
/// SlideImage(image: NetworkImage(url), fit: BoxFit.cover);
/// ```
class SlideImage extends StatelessWidget {
  /// Draws [image] fitted with [fit].
  const SlideImage({required this.image, this.fit = BoxFit.contain, super.key});

  /// Where the picture comes from.
  final ImageProvider image;

  /// How the picture fits its box.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final muted = tokens.mutedForeground.withValues(alpha: 0.15);
    return Image(
      image: image,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          wasSynchronouslyLoaded || frame != null
          ? child
          : ColoredBox(
              key: const ValueKey('slide_image_loading'),
              color: muted,
              child: const SizedBox.expand(),
            ),
      errorBuilder: (context, error, stack) => ColoredBox(
        key: const ValueKey('slide_image_error'),
        color: muted,
        child: Center(
          // Slide units: a slide is 1920 across, so this reads at any zoom.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Icon(
              QuarkIcons.broken_image_outlined,
              size: 96,
              color: tokens.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}
