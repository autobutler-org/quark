import 'package:material_ui/material_ui.dart';

import '../../../models/chat_quote_item.dart';
import '../../../theme/quark_tokens.dart';

/// The message a reply quotes, above the reply's body (#2426): its author
/// and one line of its text behind a bar in the primary color.
///
/// A quote with no text, one that was deleted, is waiting for its key or
/// isn't loaded, reads [unavailableText] instead, so nothing of it leaks
/// and nothing fails. A tap fires [onTap], which goes to the quoted message;
/// null leaves the quote inert. The whole quote is one 48dp-tall target.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`.
///
/// Key prefix: `message_quote_<replyId>` on the quote.
class ChatMessageQuote extends StatelessWidget {
  /// Creates the quote [quote] on reply [replyId].
  const ChatMessageQuote({
    required this.replyId,
    required this.quote,
    this.onTap,
    super.key,
  });

  /// The id of the reply the quote sits on, which its key carries.
  final String replyId;

  /// The quoted message.
  final ChatQuoteItem quote;

  /// Goes to the quoted message. Null leaves the quote inert.
  final VoidCallback? onTap;

  /// Read in place of a quoted message that can't be shown.
  static const String unavailableText = 'Original message unavailable';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final text = quote.text;
    final author = quote.authorName;
    return Semantics(
      button: onTap != null,
      label: 'Quoted message',
      child: InkWell(
        key: ValueKey('message_quote_$replyId'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Container(
            margin: EdgeInsets.only(top: tokens.spacingXs),
            padding: EdgeInsetsDirectional.only(start: tokens.spacingSm),
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: tokens.primary, width: 3),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (author != null)
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                Text(
                  text ?? unavailableText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.mutedForeground,
                    fontStyle: text == null ? FontStyle.italic : null,
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
