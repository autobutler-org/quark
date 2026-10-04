import 'package:flutter/rendering.dart';

import '../geometry/frame_geometry.dart';
import '../geometry/slide_handle.dart';
import '../geometry/slide_snapping.dart';
import '../geometry/slide_viewport.dart';
import '../model/element_frame.dart';
import 'slide_canvas_style.dart';

/// Paints the editing marks over a slide, in viewport pixels: a faint
/// outline around an entered [groupFrame], an outline around each selected
/// frame, the stem up to the rotate handle, the snap
/// guides and the marquee. Hairlines stay one pixel wide at every zoom.
class SlideSelectionPainter extends CustomPainter {
  /// Creates a painter.
  const SlideSelectionPainter({
    required this.viewport,
    required this.frames,
    required this.style,
    this.showRotateStem = false,
    this.guides = const [],
    this.marquee,
    this.groupFrame,
  });

  /// Maps slide units to the viewport.
  final SlideViewport viewport;

  /// The selected elements' frames.
  final List<ElementFrame> frames;

  /// Supplies colors and the rotate handle's offset.
  final SlideCanvasStyle style;

  /// Whether to draw the stem to the rotate handle of the single frame.
  final bool showRotateStem;

  /// The snap guides to draw across the slide.
  final List<SnapGuide> guides;

  /// The marquee rectangle in slide units, while one is dragged.
  final Rect? marquee;

  /// The frame of the group whose children are being edited, or `null`.
  final ElementFrame? groupFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = style.selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (groupFrame case final group?) {
      canvas.drawPath(
        Path()
          ..addPolygon(
            [for (final c in group.corners) viewport.toView(c)],
            true,
          ),
        Paint()
          ..color = style.selectionColor.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    for (final frame in frames) {
      canvas.drawPath(
        Path()
          ..addPolygon(
            [for (final c in frame.corners) viewport.toView(c)],
            true,
          ),
        outline,
      );
    }
    if (showRotateStem && frames.length == 1) {
      final frame = frames.single;
      canvas.drawLine(
        viewport.toView(frame.handlePoint(SlideHandle.top)),
        viewport.toView(
          frame.handlePoint(
            SlideHandle.rotate,
            rotateOffset: style.rotateHandleOffset / viewport.scale,
          ),
        ),
        outline,
      );
    }
    final slide = viewport.slideRect;
    final guide = Paint()
      ..color = style.guideColor
      ..strokeWidth = 1;
    for (final g in guides) {
      final at = viewport.toView(Offset(g.position, g.position));
      switch (g.axis) {
        case SnapAxis.vertical:
          canvas.drawLine(
            Offset(at.dx, slide.top),
            Offset(at.dx, slide.bottom),
            guide,
          );
        case SnapAxis.horizontal:
          canvas.drawLine(
            Offset(slide.left, at.dy),
            Offset(slide.right, at.dy),
            guide,
          );
      }
    }
    final area = marquee;
    if (area != null) {
      final rect = Rect.fromPoints(
        viewport.toView(area.topLeft),
        viewport.toView(area.bottomRight),
      );
      canvas
        ..drawRect(
          rect,
          Paint()..color = style.selectionColor.withValues(alpha: 0.12),
        )
        ..drawRect(rect, outline..strokeWidth = 1);
    }
  }

  // A new viewport is built on every frame of a drag, so comparing would
  // only ever answer yes; the painting is a handful of lines.
  @override
  bool shouldRepaint(SlideSelectionPainter oldDelegate) => true;
}
