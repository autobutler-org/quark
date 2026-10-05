import 'package:flutter/widgets.dart';

import '../model/cell_range.dart';
import '../model/slide.dart';
import '../model/slide_element.dart';
import '../model/slide_size.dart';
import '../theme/slide_theme.dart';
import 'slide_background_view.dart';
import 'slide_canvas_style.dart';
import 'slide_element_label.dart';
import 'slide_element_view.dart';
import 'slide_image_source.dart';
import 'slide_text_highlight_painter.dart';

/// A slide laid out at its logical size: one logical pixel per slide unit,
/// its background and then its elements back to front, clipped to the
/// slide.
///
/// It is drawn at full size and scaled by its parent, so text wraps the
/// same way at every zoom. The device's text scale does not apply: a
/// slide's type sizes are part of its design, like an image's pixels.
///
/// An editable stage — one given [onSelect] — shows empty text boxes'
/// placeholders, draws the text box [editingId] as [editor], and draws
/// [preview], the element a drawing tool is dragging out, in front of
/// everything, hidden from screen readers and pointers.
class SlideStage extends StatelessWidget {
  /// Creates a stage for [slide].
  const SlideStage({
    super.key,
    required this.slide,
    required this.size,
    required this.style,
    required this.theme,
    required this.elementLabel,
    this.imageBuilder,
    this.selection = const {},
    this.onSelect,
    this.editingId,
    this.editor,
    this.preview,
    this.highlights = const {},
    this.cellLabel = defaultSlideTableCellLabel,
    this.selectedCells,
  });

  /// The slide to draw.
  final Slide slide;

  /// The slide's size in slide units.
  final SlideSize size;

  /// Supplies the placeholder color.
  final SlideCanvasStyle style;

  /// The theme the slide's role colors and unset text styles resolve
  /// against: the deck's, or `slideFallbackTheme`.
  final SlideTheme theme;

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

  /// An element being drawn, not yet in the slide; `null` when none is.
  final SlideElement? preview;

  /// Search highlights by text box id, at any depth.
  final Map<String, List<SlideTextHighlight>> highlights;

  /// Names a table's cells for a screen reader.
  final SlideTableCellLabel cellLabel;

  /// The table cells selected on the canvas, or `null`.
  final ({String tableId, CellRange range})? selectedCells;

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
                    theme: theme,
                    imageBuilder: imageBuilder,
                  ),
                ),
                for (final element in slide.elements)
                  SlideElementView(
                    element: element,
                    style: style,
                    theme: theme,
                    label: elementLabel(element),
                    imageBuilder: imageBuilder,
                    selected: selection.contains(element.id),
                    onSelect:
                        onSelect == null ? null : () => onSelect!(element.id),
                    elementLabel: elementLabel,
                    editingId: editingId,
                    editor: editor,
                    showPlaceholder: onSelect != null,
                    highlights: highlights,
                    cellLabel: cellLabel,
                    selectedCells: selectedCells,
                  ),
                if (preview case final preview?)
                  SlideElementView(
                    element: preview,
                    style: style,
                    theme: theme,
                    label: '',
                    excluded: true,
                  ),
              ],
            ),
          ),
        ),
      );
}
