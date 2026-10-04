import 'package:flutter/widgets.dart';

import '../geometry/frame_geometry.dart';
import '../geometry/slide_handle.dart';
import '../geometry/slide_snapping.dart';
import '../geometry/slide_viewport.dart';
import '../model/element_frame.dart';
import 'slide_canvas_style.dart';
import 'slide_selection_handle.dart';
import 'slide_selection_painter.dart';

/// The editing chrome over a slide, sized to the whole viewport: selection
/// outlines, the faint outline of an entered group, snap guides and the
/// marquee, and — when exactly one element is selected — its eight resize
/// handles and its rotate handle.
///
/// It sits in screen space rather than in the scaled slide, so handles keep
/// their size at every zoom. Handles are keyed `slide_handle_<id>`; see
/// [SlideSelectionHandle].
class SlideSelectionOverlay extends StatelessWidget {
  /// Creates the overlay.
  const SlideSelectionOverlay({
    super.key,
    required this.viewport,
    required this.frames,
    required this.style,
    this.guides = const [],
    this.marquee,
    this.groupFrame,
  });

  /// Maps slide units to the viewport.
  final SlideViewport viewport;

  /// The selected elements' frames, back to front.
  final List<ElementFrame> frames;

  /// Supplies sizes and colors.
  final SlideCanvasStyle style;

  /// Snap guides to draw.
  final List<SnapGuide> guides;

  /// The marquee rectangle in slide units, while one is dragged.
  final Rect? marquee;

  /// The frame of the group whose children are being edited, or `null`.
  final ElementFrame? groupFrame;

  @override
  Widget build(BuildContext context) {
    final single = frames.length == 1 ? frames.single : null;
    final hit = style.handleHitSize;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: SlideSelectionPainter(
              viewport: viewport,
              frames: frames,
              style: style,
              showRotateStem: single != null,
              guides: guides,
              marquee: marquee,
              groupFrame: groupFrame,
            ),
          ),
        ),
        if (single != null)
          for (final handle in [
            ...SlideHandle.resizeHandles,
            SlideHandle.rotate
          ])
            Positioned.fromRect(
              rect: Rect.fromCenter(
                center: viewport.toView(
                  single.handlePoint(
                    handle,
                    rotateOffset: style.rotateHandleOffset / viewport.scale,
                  ),
                ),
                width: hit,
                height: hit,
              ),
              child: SlideSelectionHandle(
                handle: handle,
                style: style,
                rotation: single.rotation,
              ),
            ),
      ],
    );
  }
}
