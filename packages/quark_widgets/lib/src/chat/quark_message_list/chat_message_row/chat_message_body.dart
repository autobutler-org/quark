import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../theme/quark_tokens.dart';

/// A web address found in a message: the half-open range `[start, end)` of
/// the text it covers, and the address a tap opens.
typedef ChatMessageLink = ({int start, int end, Uri uri});

/// The text of a chat message, with the web addresses in it drawn as links.
///
/// With [onOpenLink] set, each `http://`, `https://` or `www.` address in
/// [text] takes the theme's primary color and an underline, and a tap fires
/// [onOpenLink] with its [Uri]; the caller opens it. The text itself is drawn
/// exactly as written, as plain spans, so a long address still wraps and
/// nothing in a message is interpreted. With [onOpenLink] null the text is
/// plain: no link is styled that a tap could not open.
///
/// A part of `ChatMessageRow`, tested through `QuarkMessageList`. Spans carry
/// no keys, so a test or a script reaches a link by its text inside the key
/// the row puts on this widget.
class ChatMessageBody extends StatefulWidget {
  /// Creates the body [text] of a message.
  const ChatMessageBody({
    required this.text,
    this.style,
    this.onOpenLink,
    super.key,
  });

  /// The message text, drawn as written.
  final String text;

  /// The style of the text that is not a link, and the base of a link's.
  final TextStyle? style;

  /// Called with a link's address when it is tapped. Null draws [text] with
  /// no links.
  final ValueChanged<Uri>? onOpenLink;

  static final RegExp _candidate = RegExp(
    r'(?<![A-Za-z0-9.@/])(?:https?://|www\.)[^\s<>]+',
    caseSensitive: false,
  );

  /// The web addresses in [text], in order.
  ///
  /// Only `http://`, `https://` and a bare `www.` at the start of a word
  /// count; `www.` opens as `https://`. Sentence punctuation after an address
  /// is left out of it, as is a closing bracket whose opener is outside it. A
  /// candidate that does not parse to an http(s) address with a host is not a
  /// link.
  static List<ChatMessageLink> linksIn(String text) {
    final links = <ChatMessageLink>[];
    for (final match in _candidate.allMatches(text)) {
      var url = match.group(0)!;
      while (url.isNotEmpty) {
        final last = url[url.length - 1];
        final unopened =
            (last == ')' && _count(url, ')') > _count(url, '(')) ||
            (last == ']' && _count(url, ']') > _count(url, '['));
        if (!unopened && !'.,;:!?\'"'.contains(last)) break;
        url = url.substring(0, url.length - 1);
      }
      final bare = url.toLowerCase().startsWith('www.');
      final uri = Uri.tryParse(bare ? 'https://$url' : url);
      if (uri == null ||
          !(uri.isScheme('http') || uri.isScheme('https')) ||
          uri.host.isEmpty ||
          (bare && uri.host.length <= 'www.'.length)) {
        continue;
      }
      links.add((start: match.start, end: match.start + url.length, uri: uri));
    }
    return List.unmodifiable(links);
  }

  static int _count(String text, String char) => char.allMatches(text).length;

  @override
  State<ChatMessageBody> createState() => _ChatMessageBodyState();
}

class _ChatMessageBodyState extends State<ChatMessageBody> {
  List<ChatMessageLink> _links = const [];
  List<TapGestureRecognizer> _recognizers = const [];

  @override
  void initState() {
    super.initState();
    _findLinks();
  }

  @override
  void didUpdateWidget(ChatMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        (oldWidget.onOpenLink == null) != (widget.onOpenLink == null)) {
      _disposeRecognizers();
      _findLinks();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _findLinks() {
    _links = widget.onOpenLink == null
        ? const []
        : ChatMessageBody.linksIn(widget.text);
    // Each recognizer reads the callback when tapped, so a parent that hands
    // down a new closure every build does not cost a recognizer mid-tap.
    _recognizers = [
      for (final link in _links)
        TapGestureRecognizer()..onTap = () => widget.onOpenLink?.call(link.uri),
    ];
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (_links.isEmpty) return Text(text, style: widget.style);

    final primary = QuarkTokens.of(context).primary;
    final linkStyle = TextStyle(
      color: primary,
      decoration: TextDecoration.underline,
      decorationColor: primary,
    );
    final spans = <InlineSpan>[];
    var at = 0;
    for (final (index, link) in _links.indexed) {
      if (link.start > at) {
        spans.add(TextSpan(text: text.substring(at, link.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(link.start, link.end),
          style: linkStyle,
          mouseCursor: SystemMouseCursors.click,
          recognizer: _recognizers[index],
        ),
      );
      at = link.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));

    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
