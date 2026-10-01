import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_icon_button.dart';
import '../theme/quark_tokens.dart';

/// Previous and next buttons and the name of the span on show: the lead of the
/// calendar's `QuarkAppBarBottom` row.
///
/// The caller words [title] ("September 2026", "Tue, Sep 29") and the two
/// tooltips ("Previous month", "Next week"), because only it knows which view
/// is on screen. A title too long for the row is clipped with an ellipsis.
///
/// Key prefixes: `calendar_prev` and `calendar_next` on the buttons.
///
/// ```dart
/// CalendarPeriodHeader(
///   title: 'September 2026',
///   previousTooltip: 'Previous month',
///   nextTooltip: 'Next month',
///   onPrevious: controller.previous,
///   onNext: controller.next,
/// );
/// ```
class CalendarPeriodHeader extends StatelessWidget {
  /// Creates a header titled [title].
  const CalendarPeriodHeader({
    required this.title,
    required this.onPrevious,
    required this.onNext,
    this.previousTooltip = 'Previous',
    this.nextTooltip = 'Next',
    super.key,
  });

  /// The span on show, already worded.
  final String title;

  /// Called by the previous button.
  final VoidCallback? onPrevious;

  /// Called by the next button.
  final VoidCallback? onNext;

  /// The previous button's tooltip and accessible name.
  final String previousTooltip;

  /// The next button's tooltip and accessible name.
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Row(
      spacing: tokens.spacingSm,
      children: [
        QuarkBarIconButton(
          key: const ValueKey('calendar_prev'),
          icon: QuarkIcons.chevron_left_rounded,
          tooltip: previousTooltip,
          onPressed: onPrevious,
        ),
        QuarkBarIconButton(
          key: const ValueKey('calendar_next'),
          icon: QuarkIcons.chevron_right_rounded,
          tooltip: nextTooltip,
          onPressed: onNext,
        ),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: tokens.foreground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
