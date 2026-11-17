import 'package:flutter/painting.dart';

import '../theme/quark_tokens.dart';

/// A mention found in a message: the half-open range `[start, end)` of the
/// text it covers, `@` included, and the member it names, spelled the way the
/// member list spells it.
typedef ChatMentionRange = ({int start, int end, String name});

/// The `@` being typed at the caret: where it sits in the text, and what
/// follows it up to the caret.
typedef ChatMentionQuery = ({int start, String query});

/// The rules of a chat `@mention` (#2623), shared by the composer and the
/// message list so both read a message the same way.
///
/// A mention is the plain text `@name`, where `name` is a channel member's
/// name, matched without regard to case. Chat is end-to-end encrypted, so
/// nothing but that text travels: it sits inside the encrypted message, and a
/// client that knows nothing of mentions shows it as it was typed. The `@`
/// has to start a word, so the `@` in an email address is not a mention, and
/// the name has to end one, so `@ann` is not found inside `@annette`. Text
/// that names no member is left alone.
///
/// `@everyone` (#4293) mentions every member, by the same rules as a name,
/// but only in [names] built by [withEveryone] for an author allowed to use
/// it. The Quark can't see the text, so each reader decides that from the
/// author's permissions; from anyone else it is plain text.
abstract final class ChatMentions {
  /// The name `@everyone` mentions every member by.
  static const String everyone = 'everyone';

  /// [names] for a message whose author may or may not ([allowed]) mention
  /// everyone: with [everyone] first when allowed, so it is offered first,
  /// and without any name spelled like it otherwise, so a member named
  /// `everyone` is no way around the permission.
  static List<String> withEveryone(
    List<String> names, {
    required bool allowed,
  }) => [
    if (allowed) everyone,
    for (final name in names)
      if (name.toLowerCase() != everyone) name,
  ];

  /// Whether a mention of [mentioned], as [mentionsIn] spells it, reaches
  /// [name]: it names them, or it is [everyone].
  static bool reaches(String mentioned, String name) =>
      mentioned == everyone || mentioned.toLowerCase() == name.toLowerCase();

  /// The most names [matching] offers by default.
  static const int suggestionLimit = 5;

  static final RegExp _word = RegExp(r'[\p{L}\p{N}_]', unicode: true);

  static bool _isWordAt(String text, int index) => _word.hasMatch(text[index]);

  /// The mentions of [names] in [text], in order.
  ///
  /// Where one member's name starts another's, the longer one wins.
  static List<ChatMentionRange> mentionsIn(
    String text,
    Iterable<String> names,
  ) {
    if (!text.contains('@')) return const [];
    // ponytail: every name is tried at every `@`. Index the names by their
    // first character if a channel's member list reaches the thousands.
    final longestFirst = names.where((name) => name.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final found = <ChatMentionRange>[];
    var at = text.indexOf('@');
    while (at >= 0) {
      var next = at + 1;
      if (at == 0 || !_isWordAt(text, at - 1)) {
        for (final name in longestFirst) {
          final end = next + name.length;
          if (end <= text.length &&
              text.substring(next, end).toLowerCase() == name.toLowerCase() &&
              (end == text.length || !_isWordAt(text, end))) {
            found.add((start: at, end: end, name: name));
            next = end;
            break;
          }
        }
      }
      at = text.indexOf('@', next);
    }
    return found;
  }

  /// Whether [text] mentions [name], one of [names], by name or as
  /// [everyone] when [names] holds it.
  static bool mentions(String text, Iterable<String> names, String name) =>
      mentionsIn(text, names).any((mention) => reaches(mention.name, name));

  /// The mention being typed in [text] with the caret at [caret], or null
  /// when the caret is not in one: there is no `@` before it, the `@` does
  /// not start a word, or there is whitespace between the two.
  static ChatMentionQuery? queryAt(String text, int caret) {
    if (caret <= 0 || caret > text.length) return null;
    final start = text.lastIndexOf('@', caret - 1);
    if (start < 0 || (start > 0 && _isWordAt(text, start - 1))) return null;
    final query = text.substring(start + 1, caret);
    return query.contains(RegExp(r'\s')) ? null : (start: start, query: query);
  }

  /// The first [limit] of [names] that start with [query], without regard to
  /// case, in the order given.
  static List<String> matching(
    Iterable<String> names,
    String query, {
    int limit = suggestionLimit,
  }) => names
      .where((name) => name.toLowerCase().startsWith(query.toLowerCase()))
      .take(limit)
      .toList();

  /// How a mention is drawn in running text: the theme's primary color on a
  /// tint of it, heavier when [isSelf] says it names the reader.
  static TextStyle styleOf(QuarkTokens tokens, {bool isSelf = false}) =>
      TextStyle(
        color: tokens.primary,
        backgroundColor: tokens.primary.withValues(alpha: isSelf ? 0.28 : 0.14),
      );
}
