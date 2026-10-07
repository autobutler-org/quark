import 'package:flutter/widgets.dart';

import '../model/slide.dart';
import '../model/slide_size.dart';
import 'slide_background_view.dart';
import 'slide_canvas_style.dart';
import 'slide_element_label.dart';
import 'slide_element_view.dart';
import 'slide_image_source.dart';

/// A slide laid out at its logical size: one logical pixel per slide unit,
/// its background and then its elements back to front, clipped to the
/// slide.
///
/// It is drawn at full size and scaled by its parent, so text wraps the
/// same way at every zoom. The device's text scale does not apply: a
/// slide's type sizes are part of its design, like an image's pixels.
///
/// An editable stage — one given [onSelect] — shows empty text boxes'
/// placeholders, and draws the text box [editingId] as [editor].
class SlideStage extends StatelessWidget {
  /// Creates a stage for [slide].
  const SlideStage({
    super.key,
    required this.slide,
    required this.size,
    required this.style,
    required this.elementLabel,
    this.imageBuilder,
    this.selection = const {},
    this.onSelect,
    this.editingId,
    this.editor,
  });

  /// The slide to draw.
  final Slide slide;

  /// The slide's size in slide units.
  final SlideSize size;

  /// Supplies colors and text defaults.
  final SlideCanvasStyle style;

  /// Names each element for a screen reader.
  final SlideElementLabel elementLabel;

  /// Draws images; see [SlideImageBuilder].
  final SlideImageBuilder? imageBuilder;

  /// The ids of the selected elements.
  final Set<String> selection;

  /// Selects an element by id from a screen reader, or `null` when the
  /// slide is read-only.
  final ValueChanged<String>? onSelect;

  /// The id of the text box being edited, drawn as [editor] and not as
  /// itself; `null` when nothing is.
  final String? editingId;

  /// The in-place editor of [editingId].
  final Widget? editor;

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: SlideBackgroundView(
                    background: slide.background,
                    style: style,
                    imageBuilder: imageBuilder,
                  ),
                ),
                for (final element in slide.elements)
                  SlideElementView(
                    element: element,
                    style: style,
                    label: elementLabel(element),
                    imageBuilder: imageBuilder,
                    selected: selection.contains(element.id),
                    onSelect:
                        onSelect == null ? null : () => onSelect!(element.id),
                    editor: element.id == editingId ? editor : null,
                    showPlaceholder: onSelect != null,
                  ),
              ],
            ),
          ),
        ),
      );
}
