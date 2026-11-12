import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';
import '../code_highlighter.dart';
import '../code_search_match.dart';

/// One line of a `QuarkCodeViewer`: its right-aligned line number in a gutter
/// of [gutterWidth], then the text, colored by [tokens] with every search hit
/// in [matches] on a tinted background and [activeMatch] on a solid one.
/// Inside a hit the syntax colors give way to plain foreground text, which
/// keeps AA contrast on the tint where they do not (#3187).
///
/// The line is as tall as its text: one row with [wrap] off, where the text
/// runs on to the right, and as many rows as it needs with [wrap] on. The
/// number is left out of a text selection, so copying code copies code.
///
/// Key prefixes: none of its own. The viewer keys each line
/// `code_viewer_line_<index>`.
///
/// ```dart
/// CodeViewerLine(
///   index: 0,
///   text: 'final answer = 42;',
///   tokens: const [CodeToken(0, 5, CodeTokenKind.keyword)],
///   gutterWidth: 48,
///   style: codeStyle,
///   strutStyle: codeStrut,
/// );
/// ```
class CodeViewerLine extends StatelessWidget {
  /// Creates line [index], showing [text].
  const CodeViewerLine({
    required this.index,
    required this.text,
    required this.tokens,
    required this.gutterWidth,
    required this.style,
    required this.strutStyle,
    this.matches = const [],
    this.activeMatch,
    this.wrap = false,
    super.key,
  });

  /// The 0-based index of the line. The gutter shows it plus one.
  final int index;

  /// The line's text, without a trailing newline.
  final String text;

  /// The colored runs of [text], ordered and not overlapping, as
  /// `highlightCodeLine` returns them.
  final List<CodeToken> tokens;

  /// The width of the gutter, the padding on both sides of the number
  /// included.
  final double gutterWidth;

  /// The monospace style the text is drawn in. Its color is the plain text
  /// color.
  final TextStyle style;

  /// The strut that gives every row the same height.
  final StrutStyle strutStyle;

  /// The search hits on this line, ordered and not overlapping. Offsets
  /// outside the line are tolerated.
  final List<CodeSearchMatch> matches;

  /// The hit the search is on, drawn stronger than the rest; null when it is
  /// not on this line.
  final CodeSearchMatch? activeMatch;

  /// Whether a line too long for the width wraps onto more rows.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final quark = QuarkTokens.of(context);
    final length = text.length;
    final spans = <TextSpan>[];
    var tokenIndex = 0;
    var matchIndex = 0;
    var position = 0;
    // Walk the line once, cutting it wherever a token or a hit starts or ends.
    while (position < length) {
      while (tokenIndex < tokens.length && tokens[tokenIndex].end <= position) {
        tokenIndex++;
      }
      while (matchIndex < matches.length &&
          matches[matchIndex].end <= position) {
        matchIndex++;
      }
      final token = tokenIndex < tokens.length ? tokens[tokenIndex] : null;
      final match = matchIndex < matches.length ? matches[matchIndex] : null;
      final inToken = token != null && token.start <= position;
      final inMatch = match != null && match.start <= position;
      var next = length;
      if (token != null) {
        next = math.min(next, inToken ? token.end : token.start);
      }
      if (match != null) {
        next = math.min(next, inMatch ? match.end : match.start);
      }
      final isActive = inMatch && match == activeMatch;
      final color = isActive
          ? quark.primaryForeground
          : inMatch
          ? quark.foreground
          : switch (inToken ? token.kind : CodeTokenKind.plain) {
              CodeTokenKind.plain => null,
              CodeTokenKind.comment => quark.mutedForeground,
              CodeTokenKind.string => quark.success,
              CodeTokenKind.number => quark.warning,
              CodeTokenKind.keyword || CodeTokenKind.key => quark.primary,
            };
      spans.add(
        TextSpan(
          text: text.substring(position, next),
          style: color == null && !inMatch
              ? null
              : TextStyle(
                  color: color,
                  backgroundColor: isActive
                      ? quark.primary
                      : inMatch
                      ? quark.primary.withValues(alpha: 0.25)
                      : null,
                ),
        ),
      );
      position = next;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutterWidth,
          child: Padding(
            padding: EdgeInsets.only(
              left: quark.spacingSm,
              right: quark.spacingMd,
            ),
            child: SelectionContainer.disabled(
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.right,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: style.copyWith(color: quark.mutedForeground),
                strutStyle: strutStyle,
              ),
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(style: style, children: spans),
            softWrap: wrap,
            overflow: TextOverflow.clip,
            strutStyle: strutStyle,
          ),
        ),
        SizedBox(width: quark.spacingMd),
      ],
    );
  }
}
