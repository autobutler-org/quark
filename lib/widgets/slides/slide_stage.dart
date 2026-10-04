import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_element_preview.dart';
import 'package:quark_slides/quark_slides.dart';

/// One slide drawn read-only at its presentation's aspect ratio, scaled to
/// whatever room it is given: the editor's center area and every thumbnail
/// in the slide panel.
///
/// This is the seam the interactive slide canvas (#1153) plugs into. Until
/// that canvas lands, the editor's center shows the slide through here; once
/// it does, this one file swaps to it and nothing that places a stage changes.
///
/// The slide is laid out in slide units — [size], 1920×1080 for a 16:9 deck —
/// and scaled down as one picture, so a thumbnail and the stage agree to the
/// pixel. Its text is the presentation's, at the sizes the presentation sets,
/// so the device's text scale does not apply inside it: scaling would push
/// text out of the boxes it was written for. [semanticLabel] stands in for
/// the picture for a screen reader.
///
/// ```dart
/// SlideStage(slide: deck.slides.first, size: deck.size, semanticLabel: 'Slide 1');
/// ```
class SlideStage extends StatelessWidget {
  /// Draws [slide] at [size]'s aspect ratio.
  const SlideStage({
    required this.slide,
    required this.size,
    this.semanticLabel,
    super.key,
  });

  /// The slide to draw.
  final Slide slide;

  /// The presentation's slide size, in slide units.
  final SlideSize size;

  /// What a screen reader announces for the slide; null leaves it unlabeled.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final background = slide.background?.color;
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: size.aspectRatio,
        child: ClipRect(
          child: ColoredBox(
            color: background == null ? Colors.white : Color(background.argb),
            child: FittedBox(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: MediaQuery.withNoTextScaling(
                  child: Stack(
                    children: [
                      for (final element in slide.elements)
                        Positioned(
                          left: element.frame.x,
                          top: element.frame.y,
                          width: element.frame.width,
                          height: element.frame.height,
                          child: Transform.rotate(
                            angle: SlideElementPreview.radians(
                              element.frame.rotation,
                            ),
                            child: SlideElementPreview(element: element),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
