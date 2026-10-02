import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'quark_bar_icon_button.dart';
import 'quark_toolbar.dart';

/// A greeting at the top of a page: a headline, an optional line under it,
/// and the few actions worth starting with.
///
/// A page that opens straight onto a listing says nothing to the person who
/// just arrived (#2022). This is the one place that says hello: with
/// [actions] it is a "start here" card for a new owner, and with a [headline]
/// alone it is a single line for someone coming back.
///
/// The card decides nothing. The caller chooses the words, which actions to
/// offer, and what a dismissal means; a null [onDismiss] renders no dismiss
/// button at all.
///
/// The actions go through a [QuarkToolbar], so three chips wrap onto a second
/// line at 360 pixels instead of overflowing. Pass `QuarkBarChip`s with
/// `keepLabel: true`: a start-here action that drops its word on a phone is
/// no longer saying where to start.
///
/// Key prefixes: `welcome_card_dismiss` for the dismiss button. The actions
/// carry their own keys.
///
/// ```dart
/// WelcomeCard(
///   headline: 'Welcome, ada',
///   message: 'Start by adding something.',
///   actions: [
///     QuarkBarChip(
///       key: const ValueKey('welcome_upload'),
///       icon: QuarkIcons.upload_rounded,
///       label: 'Upload',
///       keepLabel: true,
///       onPressed: upload,
///     ),
///   ],
///   onDismiss: dismiss,
/// );
/// ```
class WelcomeCard extends StatelessWidget {
  /// Creates a card greeting with [headline].
  const WelcomeCard({
    required this.headline,
    this.message,
    this.actions = const [],
    this.onDismiss,
    super.key,
  });

  /// The greeting itself, such as "Welcome, ada".
  final String headline;

  /// A line under the [headline], cut off after three lines. Null renders
  /// nothing.
  final String? message;

  /// The start-here controls, rendered in order under the text. Empty renders
  /// no action row.
  final List<Widget> actions;

  /// Called when the dismiss button is tapped. Null renders no dismiss button.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final message = this.message;
    final onDismiss = this.onDismiss;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokens.spacingSm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: tokens.spacingSm,
                children: [
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: tokens.cardForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (message != null)
                    Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.secondaryForeground,
                      ),
                    ),
                  if (actions.isNotEmpty) QuarkToolbar(actions: actions),
                ],
              ),
            ),
            if (onDismiss != null)
              QuarkBarIconButton(
                key: const ValueKey('welcome_card_dismiss'),
                icon: QuarkIcons.close_rounded,
                tooltip: 'Dismiss',
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}
