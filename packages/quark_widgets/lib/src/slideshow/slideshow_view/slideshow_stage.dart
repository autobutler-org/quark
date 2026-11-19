import 'package:material_ui/material_ui.dart';

import '../../core/quark_loader.dart';

/// The photo a slideshow shows, whole and uncropped, cross-fading into the
/// next over [fade].
///
/// A part of `SlideshowView`, which passes a zero [fade] under reduced motion
/// so the photos change at once.
///
/// Key prefixes: `slideshow_slide_<slideId>` on the photo.
class SlideshowStage extends StatelessWidget {
  /// Creates the stage showing [image].
  const SlideshowStage({
    required this.image,
    required this.slideId,
    required this.isLoading,
    required this.error,
    required this.fade,
    super.key,
  });

  /// The photo to show, or null before the first one has loaded.
  final ImageProvider? image;

  /// The shown photo's identity, which keys it so a new one cross-fades in.
  final String? slideId;

  /// Whether the first photo is still loading, with nothing to show yet.
  final bool isLoading;

  /// Why the photo could not be shown, written by the caller, or null.
  final String? error;

  /// How long one photo takes to fade into the next.
  final Duration fade;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    final error = this.error;
    return AnimatedSwitcher(
      duration: fade,
      child: error != null
          ? Center(
              key: const ValueKey('slideshow_error'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  // White on the black stage, whatever the theme.
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : image != null
          ? SizedBox.expand(
              key: ValueKey('slideshow_slide_$slideId'),
              child: Image(
                image: image,
                // Shown whole, never cropped.
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            )
          : isLoading
          ? const Center(child: QuarkLoader())
          : const SizedBox.shrink(),
    );
  }
}
