import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Places the three parts of `ChatMessageContextMenu`: the quick-reaction
/// [bar] above the message, the [message] copy, and the [actions] under it.
///
/// The region they fit in is the screen less [padding], which the menu sets
/// to the safe area plus the keyboard, so neither covers a part. The message
/// starts at [anchor], the original row's rect, and moves no further than it
/// has to for all three to fit, keeping the row's width. When the message is
/// taller than the room the bar and the actions leave, it gets only that
/// room, and the copy scrolls inside it: the actions are never cut.
///
/// The bar and the actions line up with the message's text, [indent] in
/// from the row's start edge on the [textDirection] side, as far as the
/// region allows. Either may be absent.
class ChatContextMenuLayout extends MultiChildLayoutDelegate {
  /// Creates the layout for a message whose row was at [anchor].
  ChatContextMenuLayout({
    required this.anchor,
    required this.padding,
    required this.gap,
    required this.indent,
    required this.textDirection,
  });

  /// The id of the quick-reaction bar.
  static const String bar = 'bar';

  /// The id of the message copy.
  static const String message = 'message';

  /// The id of the action list.
  static const String actions = 'actions';

  /// The original row's rect, in the menu's coordinates.
  final Rect anchor;

  /// What the parts keep clear of: the safe area, the keyboard and a margin.
  final EdgeInsets padding;

  /// The space between two parts.
  final double gap;

  /// How far the message's text starts in from the row's start edge.
  final double indent;

  /// Which edge of the row is its start.
  final TextDirection textDirection;

  @override
  void performLayout(Size size) {
    final area = padding.deflateRect(Offset.zero & size);
    final loose = BoxConstraints.loose(
      Size(math.max(0, area.width), math.max(0, area.height)),
    );
    Size layout(Object id) => hasChild(id) ? layoutChild(id, loose) : Size.zero;
    final barSize = layout(bar);
    final actionsSize = layout(actions);
    final barGap = barSize.isEmpty ? 0.0 : gap;
    final actionsGap = actionsSize.isEmpty ? 0.0 : gap;

    final width = math.max(0.0, math.min(anchor.width, area.width));
    final room = math.max(
      0.0,
      area.height - barSize.height - barGap - actionsSize.height - actionsGap,
    );
    final messageSize = layoutChild(
      message,
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: room),
    );

    final total =
        barSize.height +
        barGap +
        messageSize.height +
        actionsGap +
        actionsSize.height;
    double clampTo(double value, double min, double max) =>
        value.clamp(min, math.max(min, max));
    final top = clampTo(
      anchor.top - barSize.height - barGap,
      area.top,
      area.bottom - total,
    );
    final left = clampTo(anchor.left, area.left, area.right - width);
    final ltr = textDirection == TextDirection.ltr;
    double startX(Size part) => clampTo(
      ltr ? left + indent : left + width - indent - part.width,
      area.left,
      area.right - part.width,
    );

    final messageTop = top + barSize.height + barGap;
    if (hasChild(bar)) positionChild(bar, Offset(startX(barSize), top));
    positionChild(message, Offset(left, messageTop));
    if (hasChild(actions)) {
      positionChild(
        actions,
        Offset(
          startX(actionsSize),
          messageTop + messageSize.height + actionsGap,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(ChatContextMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      padding != oldDelegate.padding ||
      gap != oldDelegate.gap ||
      indent != oldDelegate.indent ||
      textDirection != oldDelegate.textDirection;
}
