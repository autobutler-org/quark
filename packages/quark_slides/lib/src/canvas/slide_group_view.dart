import 'package:flutter/widgets.dart';

import '../model/slide_element.dart';
import '../theme/slide_theme.dart';
import 'slide_canvas_style.dart';
import 'slide_element_label.dart';
import 'slide_element_view.dart';
import 'slide_image_source.dart';

/// The inside of a [GroupElement]: its children, back to front, each a
/// [SlideElementView] at its group-local frame in a box the size of the
/// group's frame. The [SlideElementView] around it places, sizes and turns
/// the group, so the children move, scale and rotate with it.
///
/// Each child keeps its own key, `slide_element_<id>`, and reads to a
/// screen reader as [elementLabel] names it, inside the group's node. The
/// text box [editingId], when it is one of the children, is drawn as
/// [editor].
class SlideGroupView extends StatelessWidget {
  /// Creates the inside of [group].
  const SlideGroupView({
    super.key,
    required this.group,
    required this.style,
    required this.theme,
    required this.elementLabel,
    this.imageBuilder,
    this.editingId,
    this.editor,
    this.showPlaceholder = false,
    this.excluded = false,
  });

  /// The group to draw.
  final GroupElement group;

  /// Supplies the placeholder colors.
  final SlideCanvasStyle style;

  /// The theme the slide's role colors and unset text styles resolve
  /// against: the deck's, or `slideFallbackTheme`.
  final SlideTheme theme;

  /// Names each child for a screen reader.
  final SlideElementLabel elementLabel;

  /// Draws images; see [SlideImageBuilder].
  final SlideImageBuilder? imageBuilder;

  /// The id of the text box being edited, or `null`.
  final String? editingId;

  /// The in-place editor of [editingId].
  final Widget? editor;

  /// Whether an empty text box shows its placeholder.
  final bool showPlaceholder;

  /// Whether the children are left out of the semantics tree.
  final bool excluded;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final child in group.children)
            SlideElementView(
              element: child,
              style: style,
              theme: theme,
              label: elementLabel(child),
              elementLabel: elementLabel,
              imageBuilder: imageBuilder,
              editingId: editingId,
              editor: editor,
              showPlaceholder: showPlaceholder,
              excluded: excluded,
            ),
        ],
      );
}
