import 'package:flutter/foundation.dart';

/// The message a quote-reply quotes (#2426), as the reply draws it above its
/// body.
///
/// The caller looks the quoted message up in what it has already decrypted.
/// One it can't show, because it was deleted, is still waiting for its key,
/// or isn't loaded, has no [text], and the reply draws a placeholder in its
/// place.
@immutable
class ChatQuoteItem {
  /// Creates a quote of message [messageId].
  const ChatQuoteItem({required this.messageId, this.authorName, this.text});

  /// The quoted message's id, which a tap on the quote goes to.
  final String messageId;

  /// Who wrote the quoted message; null when that isn't known here.
  final String? authorName;

  /// The quoted message's text, or null when it can't be shown.
  final String? text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatQuoteItem &&
          other.messageId == messageId &&
          other.authorName == authorName &&
          other.text == text;

  @override
  int get hashCode => Object.hash(messageId, authorName, text);
}
