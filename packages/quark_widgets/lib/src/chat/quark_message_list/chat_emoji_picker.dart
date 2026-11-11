import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import 'chat_emoji_catalog.dart';
import 'chat_emoji_picker/chat_emoji_grid.dart';

/// Opens the full emoji picker, or [pickMore] when the caller has its own,
/// and fires [onPick] with what was chosen. Dismissing fires nothing.
void requestMoreEmoji(
  BuildContext context, {
  required String messageId,
  required ValueChanged<String> onPick,
  Future<String?> Function(BuildContext context, String messageId)? pickMore,
}) {
  unawaited(
    _request(context, messageId: messageId, onPick: onPick, pickMore: pickMore),
  );
}

Future<void> _request(
  BuildContext context, {
  required String messageId,
  required ValueChanged<String> onPick,
  required Future<String?> Function(BuildContext context, String messageId)?
  pickMore,
}) async {
  final emoji = pickMore == null
      ? await showChatEmojiPicker(context, messageId: messageId)
      : await pickMore(context, messageId);
  if (!context.mounted || emoji == null) return;
  onPick(emoji);
}

/// Shows [ChatEmojiPicker] and resolves to the emoji chosen, or null when
/// the dialog is dismissed.
Future<String?> showChatEmojiPicker(
  BuildContext context, {
  required String messageId,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => ChatEmojiPicker(
      messageId: messageId,
      onPick: (emoji) => Navigator.of(dialogContext).pop(emoji),
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );
}

/// A searchable catalog of emoji, for reacting with one the quick menu does
/// not list.
///
/// The quick six stay on [ChatReactionPicker]. This dialog is what "More
/// emoji" opens on every platform, unless a caller replaces it with
/// [requestMoreEmoji]'s `pickMore`. Search matches the Unicode name. The
/// search field takes focus when the dialog opens on macOS, Windows and
/// Linux; on a touch screen it waits for a tap, so the keyboard does not
/// cover the grid. Nothing here animates.
///
/// It does not close itself: [onPick] and [onClose] fire, and the caller
/// that pushed the dialog pops it. [showChatEmojiPicker] does that and
/// returns the emoji, or null when the dialog is dismissed without one.
///
/// Key prefixes: `message_emoji_search_<messageId>` on the search field,
/// `message_emoji_close_<messageId>` on the close button, and
/// `message_react_<messageId>_<emoji>` on each emoji.
///
/// ```dart
/// final emoji = await showChatEmojiPicker(context, messageId: id);
/// if (emoji != null) onReact(emoji);
/// ```
class ChatEmojiPicker extends StatefulWidget {
  /// Creates the picker for message [messageId].
  const ChatEmojiPicker({
    required this.messageId,
    required this.onPick,
    required this.onClose,
    super.key,
  });

  /// The message the reaction is for, which the keys carry.
  final String messageId;

  /// Called with the emoji that was tapped.
  final ValueChanged<String> onPick;

  /// Called when the close button is tapped.
  final VoidCallback onClose;

  @override
  State<ChatEmojiPicker> createState() => _ChatEmojiPickerState();
}

/// The search text is the field's own, thrown away when the dialog closes.
class _ChatEmojiPickerState extends State<ChatEmojiPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final query = _search.text.trim().toLowerCase();
    final matches = [
      for (final emoji in chatEmojiCatalog)
        if (query.isEmpty || emoji.name.contains(query)) emoji,
    ];
    final height = MediaQuery.sizeOf(context).height;
    final messageId = widget.messageId;

    return Dialog(
      insetPadding: EdgeInsets.all(tokens.spacingMd),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: height - tokens.spacingMd * 2,
        ),
        child: SizedBox(
          height: math.min(520, height - tokens.spacingLg * 2),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add reaction',
                        style: TextStyle(
                          color: tokens.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('message_emoji_close_$messageId'),
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                      icon: Icon(
                        QuarkIcons.close,
                        color: tokens.secondaryForeground,
                      ),
                    ),
                  ],
                ),
                TextField(
                  key: ValueKey('message_emoji_search_$messageId'),
                  controller: _search,
                  // On a touch screen the keyboard would rise over the grid
                  // before anyone asked to search (#4073).
                  autofocus: switch (Theme.of(context).platform) {
                    TargetPlatform.macOS ||
                    TargetPlatform.windows ||
                    TargetPlatform.linux => true,
                    TargetPlatform.android ||
                    TargetPlatform.iOS ||
                    TargetPlatform.fuchsia => false,
                  },
                  decoration: InputDecoration(
                    hintText: 'Search emoji',
                    prefixIcon: const Icon(QuarkIcons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: tokens.spacingSm),
                Expanded(
                  child: ChatEmojiGrid(
                    messageId: messageId,
                    emoji: matches,
                    onPick: widget.onPick,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
