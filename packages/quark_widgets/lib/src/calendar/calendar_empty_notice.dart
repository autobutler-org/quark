import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A calendar view's soft "nothing here" card: a headline, an optional line
/// under it, and an "Add an event" button.
///
/// It sits on a view that still shows its structure — under the month grid,
/// over the middle of the Day timeline — so it is a small card rather than a
/// screen-filling empty state. The copy is calm, never a warning (#2490): the
/// month grid says "Nothing planned this month", the Day view "Free day".
/// Headline and button wrap onto their own lines when the width or the text
/// size leaves no room for one.
///
/// Key prefixes: [buttonKey] on the button, which the caller names
/// (`calendar_month_add`, `calendar_day_add`).
///
/// ```dart
/// CalendarEmptyNotice(
///   headline: 'Nothing planned this month',
///   buttonKey: const ValueKey('calendar_month_add'),
///   onAdd: createNew,
/// );
/// ```
class CalendarEmptyNotice extends StatelessWidget {
  /// Creates the card headlined by [headline].
  const CalendarEmptyNotice({
    required this.headline,
    this.subtext,
    this.onAdd,
    this.buttonKey,
    super.key,
  });

  /// What the view lacks, in sentence case without a period.
  final String headline;

  /// A quieter line under [headline], or null for none.
  final String? subtext;

  /// Called by "Add an event". Null hides the button.
  final VoidCallback? onAdd;

  /// The key on the button, for tests and `.probe` scripts.
  final Key? buttonKey;

  /// The widest the card grows.
  static const double maxWidth = 420;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onAdd = this.onAdd;
    final subtext = this.subtext;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.card,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusLg),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacingMd,
            vertical: tokens.spacingSm,
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: tokens.spacingMd,
            runSpacing: tokens.spacingXs,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.foreground,
                    ),
                  ),
                  if (subtext != null)
                    Text(
                      subtext,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.secondaryForeground,
                      ),
                    ),
                ],
              ),
              if (onAdd != null)
                OutlinedButton.icon(
                  key: buttonKey,
                  onPressed: onAdd,
                  icon: const Icon(QuarkIcons.add_rounded, size: 18),
                  label: const Text('Add an event'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
