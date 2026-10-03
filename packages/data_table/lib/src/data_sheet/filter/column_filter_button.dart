import 'package:flutter/material.dart' hide Icons;
import 'package:quark_icons/quark_icons.dart';

/// The funnel on a column header that opens the column's filter popover.
///
/// It shows an outlined funnel until the column is filtered, then a filled one
/// in the theme's primary color. [onPressed] receives the button's global
/// bounds, so the popover can open beside it.
///
/// The caller supplies the key, `col_filter_<col>` in `DataSheet`.
///
/// ```dart
/// ColumnFilterButton(
///   key: const ValueKey('col_filter_2'),
///   isActive: controller.filterFor(2) != null,
///   tooltip: 'Filter column C',
///   onPressed: (anchor) => openFilter(2, anchor),
/// )
/// ```
class ColumnFilterButton extends StatelessWidget {
  /// The size of the button's square tap target, in pixels.
  static const double size = 20;

  /// Whether the column has a filter hiding rows.
  final bool isActive;

  /// What the button says on hover and to screen readers.
  final String tooltip;

  /// Called with the button's global bounds when it is pressed.
  final ValueChanged<Rect> onPressed;

  /// A filter button, filled when [isActive].
  const ColumnFilterButton({
    super.key,
    required this.isActive,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: size, height: size),
      iconSize: 14,
      color: isActive ? cs.primary : cs.onSurfaceVariant,
      icon: Icon(
        isActive ? QuarkIcons.filter_active : QuarkIcons.filter_column,
      ),
      onPressed: () {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onPressed(box.localToGlobal(Offset.zero) & box.size);
      },
    );
  }
}
