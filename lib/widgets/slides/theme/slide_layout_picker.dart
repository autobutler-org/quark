import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/theme/slide_preview_card.dart';
import 'package:quark/widgets/slides/theme/slide_previews.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The layout picker (#1163): each of [layouts] as a [SlidePreviewCard] of
/// its empty placeholders, drawn in the presentation's [theme], with the
/// selected slide's [currentLayoutId] marked; and, given [onReset], a
/// "Reset slide to layout" button under them.
///
/// Key prefixes: `<keyPrefix>_picker` on the picker, `<keyPrefix>_<id>` on
/// each card and `<keyPrefix>_reset` on the reset button; [keyPrefix] is
/// `slide_layout` unless the caller says otherwise.
class SlideLayoutPicker extends StatelessWidget {
  /// The picker over [layouts], [currentLayoutId] marked.
  const SlideLayoutPicker({
    required this.layouts,
    required this.currentLayoutId,
    required this.size,
    required this.onSelected,
    this.theme,
    this.onReset,
    this.keyPrefix = 'slide_layout',
    super.key,
  });

  /// The layouts offered, in order.
  final List<SlideLayout> layouts;

  /// The selected slide's layout; null marks none.
  final String? currentLayoutId;

  /// The presentation's slide size, which the previews take.
  final SlideSize size;

  /// The presentation's theme, which the previews are drawn in.
  final SlideTheme? theme;

  /// Called with the id of the layout picked; null renders the cards
  /// disabled.
  final ValueChanged<String>? onSelected;

  /// Puts the slide's placeholders back where its layout has them; null
  /// leaves the button out.
  final VoidCallback? onReset;

  /// What the picker's keys start with.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onSelected = this.onSelected;
    final onReset = this.onReset;
    return Column(
      key: ValueKey('${keyPrefix}_picker'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingSm,
      children: [
        Wrap(
          spacing: tokens.spacingXs,
          runSpacing: tokens.spacingXs,
          children: [
            for (final layout in layouts)
              SlidePreviewCard(
                key: ValueKey('${keyPrefix}_${layout.id}'),
                slide: SlidePreviews.forLayout(layout, size),
                size: size,
                theme: theme,
                label: layout.name,
                selected: layout.id == currentLayoutId,
                onPressed: onSelected == null
                    ? null
                    : () => onSelected(layout.id),
              ),
          ],
        ),
        if (onReset != null)
          TextButton.icon(
            key: ValueKey('${keyPrefix}_reset'),
            onPressed: onReset,
            icon: const Icon(QuarkIcons.reset_layout),
            label: const Text('Reset slide to layout'),
          ),
      ],
    );
  }
}
