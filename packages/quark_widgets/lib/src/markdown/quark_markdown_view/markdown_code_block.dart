import 'package:material_ui/material_ui.dart';
import 'package:markdown/markdown.dart' as md;

import '../../code/code_highlighter.dart';
import '../../code/code_language.dart';
import '../../theme/quark_tokens.dart';
import 'markdown_inline_spans.dart';

/// A fenced or indented code block of a `QuarkMarkdownView`: monospace text
/// on a tinted panel that scrolls sideways, so a long line never wraps or
/// overflows. A fence that names its language (```` ```dart ````) is colored
/// by the code viewer's highlighter.
///
/// Key prefixes: none.
///
/// ```dart
/// MarkdownCodeBlock(block: preElement, style: bodyStyle);
/// ```
class MarkdownCodeBlock extends StatelessWidget {
  /// Creates the code block for the `pre` element [block].
  const MarkdownCodeBlock({
    required this.block,
    required this.style,
    super.key,
  });

  /// The `pre` element, holding one `code` child.
  final md.Element block;

  /// The body text style, which sets the code's color and size.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final quark = QuarkTokens.of(context);
    final code = block.children?.firstOrNull;
    final fence = code is md.Element ? code.attributes['class'] ?? '' : '';
    final name = fence.startsWith('language-')
        ? fence.substring('language-'.length).toLowerCase()
        : '';
    // A fence names a language (`python`) or an extension (`py`).
    final language =
        CodeLanguage.values.asNameMap()[name] ?? codeLanguageFor('f.$name');

    final text = block.textContent;
    final lines =
        (text.endsWith('\n') ? text.substring(0, text.length - 1) : text).split(
          '\n',
        );
    final spans = <TextSpan>[];
    var state = CodeLineState.initial;
    for (final (index, line) in lines.indexed) {
      final result = highlightCodeLine(line, language, state);
      state = result.endState;
      var position = 0;
      for (final token in result.tokens) {
        if (token.start > position) {
          spans.add(TextSpan(text: line.substring(position, token.start)));
        }
        spans.add(
          TextSpan(
            text: line.substring(token.start, token.end),
            style: TextStyle(
              color: switch (token.kind) {
                CodeTokenKind.plain => null,
                CodeTokenKind.comment => quark.mutedForeground,
                CodeTokenKind.string => quark.success,
                CodeTokenKind.number => quark.warning,
                CodeTokenKind.keyword || CodeTokenKind.key => quark.primary,
              },
            ),
          ),
        );
        position = token.end;
      }
      spans.add(
        TextSpan(
          text:
              line.substring(position) + (index < lines.length - 1 ? '\n' : ''),
        ),
      );
    }

    final size = style.fontSize;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: quark.card,
        border: Border.all(color: quark.border),
        borderRadius: BorderRadius.circular(quark.radiusMd),
      ),
      // ponytail: the block is one paragraph, laid out whole. A single fence
      // of many thousands of lines wants a lazy list of lines, like the code
      // viewer's.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.all(quark.spacingMd),
        child: Text.rich(
          TextSpan(children: spans),
          softWrap: false,
          style: style.copyWith(
            fontFamily: markdownMonoFamily,
            fontFamilyFallback: markdownMonoFallback,
            fontSize: size == null ? null : size * 0.875,
          ),
        ),
      ),
    );
  }
}
