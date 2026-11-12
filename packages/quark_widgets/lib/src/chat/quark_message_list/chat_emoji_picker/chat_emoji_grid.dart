import 'package:material_ui/material_ui.dart';

import '../../../theme/quark_tokens.dart';
import '../chat_emoji_catalog.dart';

/// The scrollable emoji of a [ChatEmojiPicker], grouped by catalog section.
///
/// An empty [emoji] says "No matches" instead of an empty grid. Each emoji is
/// a 48dp button.
///
/// Key prefixes: `message_react_<messageId>_<emoji>` on each emoji.
class ChatEmojiGrid extends StatelessWidget {
  /// Creates the grid of [emoji] for message [messageId].
  const ChatEmojiGrid({
    required this.messageId,
    required this.emoji,
    required this.onPick,
    super.key,
  });

  /// The message the reaction is for, which each key carries.
  final String messageId;

  /// The emoji to draw, in catalog order. Consecutive entries that share a
  /// [ChatEmoji.group] are drawn under one heading.
  final List<ChatEmoji> emoji;

  /// Called with the emoji that was tapped.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    if (emoji.isEmpty) {
      return Center(
        child: Text(
          'No matches',
          style: TextStyle(color: tokens.mutedForeground),
        ),
      );
    }

    final slivers = <Widget>[];
    var start = 0;
    for (var i = 1; i <= emoji.length; i++) {
      if (i != emoji.length && emoji[i].group == emoji[start].group) continue;
      final group = emoji[start].group;
      final slice = emoji.sublist(start, i);
      slivers
        ..add(
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.spacingSm,
                tokens.spacingSm,
                tokens.spacingSm,
                tokens.spacingXs,
              ),
              child: Text(
                group,
                style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
              ),
            ),
          ),
        )
        ..add(
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 48,
              mainAxisExtent: 48,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = slice[index];
              return IconButton(
                key: ValueKey('message_react_${messageId}_${item.emoji}'),
                tooltip: item.name,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  fixedSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => onPick(item.emoji),
                icon: Text(item.emoji, style: const TextStyle(fontSize: 22)),
              );
            }, childCount: slice.length),
          ),
        );
      start = i;
    }

    return CustomScrollView(slivers: slivers);
  }
}
