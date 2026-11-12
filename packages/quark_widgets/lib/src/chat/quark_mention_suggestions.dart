import 'package:material_ui/material_ui.dart';

import '../core/quark_avatar.dart';
import '../theme/quark_tokens.dart';

/// The channel members an `@mention` being typed could name, as a short list
/// to pick one from (#2623).
///
/// Each of [names] is a row with the member's initials and `@name`; a tap
/// fires [onSelect] with the name. [highlighted] is the row the keyboard is
/// on, drawn on a tint of the primary color, so a caller that moves through
/// the list with the arrow keys shows where it is. Which names match what was
/// typed, and which is highlighted, are the caller's: `QuarkMessageComposer`
/// shows this above its field while the caret is in an `@mention`.
///
/// The list is as tall as its rows up to [maxHeight], then scrolls. With no
/// [names] it takes no space. Nothing animates.
///
/// Key prefixes: `mention_suggestions` on the list and
/// `mention_suggestion_<name>` on each row.
///
/// ```dart
/// QuarkMentionSuggestions(
///   names: const ['ada', 'adam'],
///   highlighted: 'ada',
///   onSelect: (name) => insertMention(name),
/// );
/// ```
class QuarkMentionSuggestions extends StatelessWidget {
  /// Creates the list of [names] to pick a mention from.
  const QuarkMentionSuggestions({
    required this.names,
    required this.onSelect,
    this.highlighted,
    this.maxHeight = 240,
    super.key,
  });

  /// The diameter of each row's avatar.
  static const double avatarSize = 24;

  /// The members to offer, in the order to show them.
  final List<String> names;

  /// Called with the name of the row that was tapped.
  final ValueChanged<String> onSelect;

  /// The name of the row the keyboard is on. Null, or a name not in [names],
  /// highlights nothing.
  final String? highlighted;

  /// How tall the list grows before it scrolls.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final tokens = QuarkTokens.of(context);
    return Material(
      key: const ValueKey('mention_suggestions'),
      color: tokens.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final name in names)
              InkWell(
                key: ValueKey('mention_suggestion_$name'),
                onTap: () => onSelect(name),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  color: name == highlighted
                      ? tokens.primary.withValues(alpha: 0.14)
                      : null,
                  padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
                  child: Row(
                    children: [
                      QuarkAvatar(id: name, name: name, size: avatarSize),
                      SizedBox(width: tokens.spacingSm),
                      Expanded(
                        child: Text(
                          '@$name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tokens.cardForeground),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
