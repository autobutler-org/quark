import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/widgets/slides/slide_thumbnail.dart';
import 'package:quark/widgets/slides/theme/slide_new_slide_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide panel: every slide as a numbered thumbnail in show order, drawn
/// in the presentation's [theme], with a button to add one (#1161). Given
/// [layouts] and [onAddWithLayout], the button is a [SlideNewSlideButton]
/// (#1163): a tap adds a slide as before, a long press or its chevron picks
/// the new slide's layout.
///
/// It runs down the side of the editor on a wide window ([Axis.vertical]) and
/// across the top on a phone ([Axis.horizontal]). A thumbnail is dragged to a
/// new place — a long press first on a touch screen — or moved from its menu,
/// which also duplicates and deletes it; see [SlideThumbnail].
///
/// With focus in the panel — after a tap on it, or tabbing to a thumbnail —
/// the arrow keys step to the previous and next slide.
///
/// Every change is reported out by slide id; the panel holds no state but
/// its focus.
///
/// Key prefixes: `slide_panel_add` on the add button, the
/// [SlideNewSlideButton]'s, `slide_panel_list` on the list, and [SlideThumbnail]'s on each slide.
class SlidePanel extends StatefulWidget {
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
    required this.onSelectPrevious,
    required this.onSelectNext,
    this.imageBuilder,
    this.onPresent,
    this.theme,
    this.defaultTransition = SlideTransitionSpec.none,
    this.layouts = const [],
    this.onAddWithLayout,
    this.readOnly = false,
    super.key,
  });

  /// Whether the presentation is view only: adding, duplicating, deleting
  /// and reordering slides are off; selecting, presenting stay.
  final bool readOnly;

  /// The presentation's theme, which the thumbnails are drawn in.
  final SlideTheme? theme;

  /// The transition slides without their own play; a slide whose transition
  /// is not none wears a marker (#1164).
  final SlideTransitionSpec defaultTransition;

  /// The layouts a new slide can be built on.
  final List<SlideLayout> layouts;

  /// Called with the id of the layout a new slide is to be built on; null
  /// leaves the add button plain.
  final ValueChanged<String>? onAddWithLayout;

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

  /// Called on the up or left arrow key.
  final VoidCallback onSelectPrevious;

  /// Called on the down or right arrow key.
  final VoidCallback onSelectNext;

  /// Draws pictures on the thumbnails.
  final SlideImageBuilder? imageBuilder;

  /// Called with the id of the slide to present from; null leaves the menu
  /// row out.
  final ValueChanged<String>? onPresent;

  /// The height of the panel across the top of a phone.
  static const double stripHeight = 104;

  /// The width of the panel down the side of a wide window.
  static const double sideWidth = 220;

  @override
  State<SlidePanel> createState() => _SlidePanelState();
}

class _SlidePanelState extends State<SlidePanel> {
  final _focusNode = FocusNode(debugLabel: 'SlidePanel');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      widget.onSelectPrevious();
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      widget.onSelectNext();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final SlidePanel(
      :slides,
      :size,
      :selectedSlideId,
      :axis,
      :canDelete,
      :onSelect,
      :onAdd,
      :onDuplicate,
      :onDelete,
      :onMove,
      :imageBuilder,
      :onPresent,
      :theme,
      :defaultTransition,
      :layouts,
      :onAddWithLayout,
      :readOnly,
    ) = widget;
    final tokens = QuarkTokens.of(context);
    final vertical = axis == Axis.vertical;
    final last = slides.length - 1;
    final Widget add = readOnly || onAddWithLayout == null || layouts.isEmpty
        ? QuarkBarIconButton(
            key: const ValueKey('slide_panel_add'),
            icon: QuarkIcons.add_rounded,
            tooltip: 'New slide',
            onPressed: readOnly ? null : onAdd,
          )
        : SlideNewSlideButton(
            layouts: layouts,
            onAdd: onAdd,
            onAddWithLayout: onAddWithLayout,
            direction: vertical ? Axis.horizontal : Axis.vertical,
          );
    final list = ReorderableListView.builder(
      key: const ValueKey('slide_panel_list'),
      scrollDirection: axis,
      buildDefaultDragHandles: !readOnly,
      padding: EdgeInsets.all(tokens.spacingSm),
      itemCount: slides.length,
      onReorderItem: (from, to) => onMove(slides[from].id, to),
      itemBuilder: (context, index) {
        final slide = slides[index];
        final thumbnail = SlideThumbnail(
          slide: slide,
          size: size,
          theme: theme,
          transition: slide.transition ?? defaultTransition,
          number: index + 1,
          selected: slide.id == selectedSlideId,
          onSelect: () => onSelect(slide.id),
          onDuplicate: readOnly ? null : () => onDuplicate(slide.id),
          imageBuilder: imageBuilder,
          onDelete: canDelete && !readOnly ? () => onDelete(slide.id) : null,
          onMoveEarlier: index > 0 && !readOnly
              ? () => onMove(slide.id, index - 1)
              : null,
          onMoveLater: index < last && !readOnly
              ? () => onMove(slide.id, index + 1)
              : null,
          onPresent: onPresent == null ? null : () => onPresent(slide.id),
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
                      (SlidePanel.stripHeight - 2 * tokens.spacingSm) *
                      size.aspectRatio,
                  child: thumbnail,
                ),
        );
      },
    );
    final panel = ColoredBox(
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
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      // A press anywhere in the panel brings the arrow keys here, away from
      // the canvas, which takes them back the same way.
      child: Listener(
        onPointerDown: (_) => _focusNode.requestFocus(),
        child: panel,
      ),
    );
  }
}
