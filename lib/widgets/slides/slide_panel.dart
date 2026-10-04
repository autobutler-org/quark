import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_thumbnail.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide panel: every slide as a numbered thumbnail in show order, with a
/// button to add one (#1161).
///
/// It runs down the side of the editor on a wide window ([Axis.vertical]) and
/// across the top on a phone ([Axis.horizontal]). A thumbnail is dragged to a
/// new place — a long press first on a touch screen — or moved from its menu,
/// which also duplicates and deletes it; see [SlideThumbnail].
///
/// Every change is reported out by slide id; the panel holds no state.
///
/// Key prefixes: `slide_panel_add` on the add button, `slide_panel_list` on
/// the list, and [SlideThumbnail]'s on each slide.
class SlidePanel extends StatelessWidget {
  /// Creates the panel over [slides].
  const SlidePanel({
    required this.slides,
    required this.size,
    required this.selectedSlideId,
    required this.axis,
    required this.canDelete,
    required this.onSelect,
    required this.onAdd,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMove,
    super.key,
  });

  /// The slides, in show order.
  final List<Slide> slides;

  /// The presentation's slide size.
  final SlideSize size;

  /// The slide on the canvas.
  final String? selectedSlideId;

  /// Down the side, or across the top.
  final Axis axis;

  /// Whether a slide may be deleted; false while only one is left.
  final bool canDelete;

  /// Called with the id of the slide tapped.
  final ValueChanged<String> onSelect;

  /// Called when the add button is tapped.
  final VoidCallback onAdd;

  /// Called with the id of the slide to duplicate.
  final ValueChanged<String> onDuplicate;

  /// Called with the id of the slide to delete.
  final ValueChanged<String> onDelete;

  /// Called with a slide's id and the position it should end up at.
  final void Function(String slideId, int toIndex) onMove;

  /// The height of the panel across the top of a phone.
  static const double stripHeight = 104;

  /// The width of the panel down the side of a wide window.
  static const double sideWidth = 220;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final vertical = axis == Axis.vertical;
    final last = slides.length - 1;
    final add = QuarkBarIconButton(
      key: const ValueKey('slide_panel_add'),
      icon: QuarkIcons.add_rounded,
      tooltip: 'New slide',
      onPressed: onAdd,
    );
    final list = ReorderableListView.builder(
      key: const ValueKey('slide_panel_list'),
      scrollDirection: axis,
      padding: EdgeInsets.all(tokens.spacingSm),
      itemCount: slides.length,
      onReorderItem: (from, to) => onMove(slides[from].id, to),
      itemBuilder: (context, index) {
        final slide = slides[index];
        final thumbnail = SlideThumbnail(
          slide: slide,
          size: size,
          number: index + 1,
          selected: slide.id == selectedSlideId,
          onSelect: () => onSelect(slide.id),
          onDuplicate: () => onDuplicate(slide.id),
          onDelete: canDelete ? () => onDelete(slide.id) : null,
          onMoveEarlier: index > 0 ? () => onMove(slide.id, index - 1) : null,
          onMoveLater: index < last ? () => onMove(slide.id, index + 1) : null,
        );
        return Padding(
          key: ValueKey('slide_item_${slide.id}'),
          padding: vertical
              ? EdgeInsets.only(bottom: tokens.spacingSm)
              : EdgeInsetsDirectional.only(end: tokens.spacingSm),
          child: vertical
              ? thumbnail
              : SizedBox(
                  width:
                      (stripHeight - 2 * tokens.spacingSm) * size.aspectRatio,
                  child: thumbnail,
                ),
        );
      },
    );
    return ColoredBox(
      color: tokens.sidebar,
      child: vertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.all(tokens.spacingSm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Slides',
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      add,
                    ],
                  ),
                ),
                Expanded(child: list),
              ],
            )
          : Row(
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(start: tokens.spacingSm),
                  child: add,
                ),
                Expanded(child: list),
              ],
            ),
    );
  }
}
