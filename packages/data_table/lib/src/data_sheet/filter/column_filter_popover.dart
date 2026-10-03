import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../cell/heading/util.dart';
import '../data_sheet_controller.dart';
import 'column_filter_panel.dart';

/// Opens the filter popover for [column] of [controller] beside [anchor], a
/// rectangle in global coordinates such as the button that opened it.
///
/// The popover lists the column's values to check and uncheck, a search over
/// them, and a condition. Apply sets the filter with
/// `DataSheetController.setColumnFilter`; tapping outside or Cancel leaves it
/// as it was. On a small screen it moves to stay inside the screen and above
/// the keyboard.
Future<void> showColumnFilterPopover({
  required BuildContext context,
  required DataSheetController controller,
  required int column,
  required Rect anchor,
}) {
  final values = controller.filterValuesFor(column);
  final label = columnLabel(column);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the filter for column $label',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, __) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: CustomSingleChildLayout(
        delegate: _PopoverLayout(anchor),
        child: Material(
          key: const ValueKey('column_filter_popover'),
          elevation: 8,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: ColumnFilterPanel(
            columnLabel: label,
            values: values,
            initial: controller.filterFor(column),
            onApply: (filter) {
              controller.setColumnFilter(column, filter);
              Navigator.of(context).pop();
            },
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  );
}

/// Places the popover under its anchor, or above it when there is no room
/// below, always at least [_margin] inside the screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  static const double _margin = 8;
  static const double _maxWidth = 320;

  final Rect anchor;

  _PopoverLayout(this.anchor);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0,
          math.min(_maxWidth, constraints.maxWidth - 2 * _margin),
        ),
        maxHeight: math.max(0, constraints.maxHeight - 2 * _margin),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double fit(double want, double extent, double child) =>
        want.clamp(_margin, math.max(_margin, extent - child - _margin));
    final below = anchor.bottom + 4;
    final top = below + childSize.height + _margin <= size.height
        ? below
        : anchor.top - 4 - childSize.height;
    return Offset(
      fit(anchor.left, size.width, childSize.width),
      fit(top, size.height, childSize.height),
    );
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
