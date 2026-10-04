import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_stage.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One slide in the slide panel: a small [SlideStage] with its number, the
/// selected one outlined, and a menu of what can be done to it.
///
/// The menu opens from its button or a right-click on the thumbnail (#1161)
/// and offers duplicate, move earlier, move later and delete; a move that
/// would go nowhere and a delete of the last slide are shown disabled.
///
/// A thumbnail that becomes the selected one scrolls itself into view, so a
/// slide just added or duplicated is never left off the end of the panel.
///
/// Key prefixes, each followed by the slide id: `slide_thumb_` on the
/// thumbnail, `slide_menu_` on its menu button, and `slide_duplicate_`,
/// `slide_move_earlier_`, `slide_move_later_` and `slide_delete_` on the menu
/// rows.
class SlideThumbnail extends StatefulWidget {
  /// Creates the thumbnail of [slide], the [number]th in the show.
  const SlideThumbnail({
    required this.slide,
    required this.size,
    required this.number,
    required this.selected,
    required this.onSelect,
    required this.onDuplicate,
    this.onDelete,
    this.onMoveEarlier,
    this.onMoveLater,
    super.key,
  });

  /// The slide to draw.
  final Slide slide;

  /// The presentation's slide size.
  final SlideSize size;

  /// The slide's position in the show, counting from 1.
  final int number;

  /// Whether this is the slide on the canvas.
  final bool selected;

  /// Called when the thumbnail is tapped.
  final VoidCallback onSelect;

  /// Called from the menu's Duplicate row.
  final VoidCallback onDuplicate;

  /// Called from the menu's Delete row; null disables it.
  final VoidCallback? onDelete;

  /// Called from the menu's Move earlier row; null disables it.
  final VoidCallback? onMoveEarlier;

  /// Called from the menu's Move later row; null disables it.
  final VoidCallback? onMoveLater;

  @override
  State<SlideThumbnail> createState() => _SlideThumbnailState();
}

class _SlideThumbnailState extends State<SlideThumbnail> {
  @override
  void didUpdateWidget(SlideThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  @override
  void initState() {
    super.initState();
    // A new slide is built already selected.
    if (widget.selected) _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      // No glide under reduced motion: Android's and the browser's flag,
      // and iOS Reduce Motion, which does not set the first.
      duration:
          MediaQuery.disableAnimationsOf(context) ||
              WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures
                  .reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
    );
  });

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final SlideThumbnail(
      :slide,
      :size,
      :number,
      :selected,
      :onSelect,
      :onDuplicate,
      :onDelete,
      :onMoveEarlier,
      :onMoveLater,
    ) = widget;
    final id = slide.id;
    final entries = [
      QuarkMenuEntry(
        key: ValueKey('slide_duplicate_$id'),
        label: 'Duplicate',
        onSelected: onDuplicate,
      ),
      QuarkMenuEntry(
        key: ValueKey('slide_move_earlier_$id'),
        label: 'Move earlier',
        onSelected: onMoveEarlier,
      ),
      QuarkMenuEntry(
        key: ValueKey('slide_move_later_$id'),
        label: 'Move later',
        onSelected: onMoveLater,
      ),
      const QuarkMenuEntry.divider(),
      QuarkMenuEntry(
        key: ValueKey('slide_delete_$id'),
        label: 'Delete',
        destructive: true,
        onSelected: onDelete,
      ),
    ];
    return GestureDetector(
      // The menu button is the screen reader's way to the same rows.
      excludeFromSemantics: true,
      onSecondaryTapUp: (details) => showQuarkMenu(
        context,
        position: details.globalPosition,
        entries: entries,
      ),
      child: Stack(
        children: [
          Semantics(
            container: true,
            button: true,
            selected: selected,
            label: 'Slide $number',
            onTap: onSelect,
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('slide_thumb_$id'),
              onTap: onSelect,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              child: Container(
                padding: EdgeInsets.all(tokens.spacingXs),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(
                    color: selected ? tokens.primary : tokens.border,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    SlideStage(slide: slide, size: size),
                    PositionedDirectional(
                      start: tokens.spacingXs,
                      bottom: tokens.spacingXs,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.spacingXs,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? tokens.primary : tokens.card,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                        ),
                        child: Text(
                          '$number',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? tokens.primaryForeground
                                : tokens.foreground,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            // A backdrop of its own, so the glyph reads on any slide color.
            child: Material(
              color: tokens.card.withValues(alpha: 0.85),
              shape: const CircleBorder(),
              child: QuarkMenuButton(
                key: ValueKey('slide_menu_$id'),
                tooltip: 'Slide $number options',
                entries: entries,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
