import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark/widgets/slides/slide_image_still.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A picture on a slide: [image] fitted to its box with [fit], a muted box
/// while it loads, and a muted box with a broken-picture glyph when it never
/// does — a file that moved, or a Quark that cannot be reached.
///
/// The slide editor builds one for every image element and background image,
/// from the presentation's path through the app's authenticated download
/// URL, so the canvas and present mode share a cached decode.
///
/// An animated GIF plays its frames in order. Where it should not move —
/// [animate] is false, as the slide panel's thumbnails set it, or the viewer
/// asked for reduced motion (Android's and the browser's flag, or iOS Reduce
/// Motion) — it stands still on its first frame through [SlideStillImage].
/// Flutter pauses a moving picture under reduced motion itself, but on the
/// web the paused stream plays on unseen, and each picture built later used
/// to land on whatever frame it had reached (#2866).
///
/// The picture is excluded from semantics: the canvas already names the
/// element ("Image") to a screen reader.
///
/// A picture the viewer may not read — its folder is not shared with them
/// (#1170), so the download answers 401 or 403 — shows a lock instead, so a
/// shared deck reads as "no access" rather than as a broken file.
///
/// Key prefixes: `slide_image_loading` on the placeholder,
/// `slide_image_no_access` on the no-access state and `slide_image_error` on
/// the error state.
///
/// ```dart
/// SlideImage(image: NetworkImage(url), fit: BoxFit.cover);
/// ```
class SlideImage extends StatefulWidget {
  /// Draws [image] fitted with [fit].
  const SlideImage({
    required this.image,
    this.fit = BoxFit.contain,
    this.animate = true,
    super.key,
  });

  /// Where the picture comes from.
  final ImageProvider image;

  /// How the picture fits its box.
  final BoxFit fit;

  /// Whether an animated picture plays; false holds its first frame, which
  /// is all a thumbnail needs and spares it a repaint every frame.
  final bool animate;

  @override
  State<SlideImage> createState() => _SlideImageState();
}

class _SlideImageState extends State<SlideImage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // iOS Reduce Motion does not reach MediaQuery, so its change is heard here.
  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final muted = tokens.mutedForeground.withValues(alpha: 0.15);
    final still =
        !widget.animate ||
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    return Image(
      image: still ? SlideStillImage(widget.image) : widget.image,
      fit: widget.fit,
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
      errorBuilder: (context, error, stack) {
        final noAccess = _isNoAccess(error);
        return ColoredBox(
          key: ValueKey(
            noAccess ? 'slide_image_no_access' : 'slide_image_error',
          ),
          color: muted,
          child: Center(
            // Slide units: a slide is 1920 across, so this reads at any zoom.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Icon(
                noAccess
                    ? QuarkIcons.lock_outline
                    : QuarkIcons.broken_image_outlined,
                size: 96,
                color: tokens.mutedForeground,
              ),
            ),
          ),
        );
      },
    );
  }

  static bool _isNoAccess(Object error) =>
      error is NetworkImageLoadException &&
      (error.statusCode == 401 || error.statusCode == 403);
}
