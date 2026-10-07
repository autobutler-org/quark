import 'package:flutter/widgets.dart';

/// Clips a slide to [fraction] of its box, for a wipe's moving edge; `null`
/// clips to the whole box.
class SlideTransitionClipper extends CustomClipper<Rect> {
  /// Clips to [fraction], in fractions of the clipped box.
  const SlideTransitionClipper(this.fraction);

  /// The part that shows, in fractions of the box, or `null` for all of it.
  final Rect? fraction;

  @override
  Rect getClip(Size size) {
    final f = fraction;
    if (f == null) return Offset.zero & size;
    return Rect.fromLTRB(
      f.left * size.width,
      f.top * size.height,
      f.right * size.width,
      f.bottom * size.height,
    );
  }

  @override
  bool shouldReclip(SlideTransitionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
