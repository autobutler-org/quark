import 'package:material_ui/material_ui.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/quark_tokens.dart';
import '../quark_markdown_view.dart';
import 'markdown_inline_spans.dart';

/// One paragraph of a `QuarkMarkdownView`: the inline [nodes] of a paragraph,
/// heading or table cell laid out as wrapping rich text.
///
/// Key prefixes: none of its own; see `QuarkMarkdownView`.
///
/// ```dart
/// MarkdownInline(nodes: paragraph.children ?? const [], style: bodyStyle);
/// ```
class MarkdownInline extends StatelessWidget {
  /// Creates the rich text of [nodes].
  const MarkdownInline({
    required this.nodes,
    required this.style,
    this.textAlign,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The inline nodes: text, emphasis, code, links, images, line breaks.
  final List<md.Node> nodes;

  /// The style of plain text. Emphasis, code and links derive theirs from it.
  final TextStyle style;

  /// How the lines are aligned; null follows the text direction.
  final TextAlign? textAlign;

  /// Called with a link's raw `href` when it is tapped; null leaves links
  /// inert.
  final ValueChanged<String>? onLinkTap;

  /// Builds each image from its raw `src` and `alt`; null shows a
  /// placeholder.
  final QuarkMarkdownImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: markdownInlineSpans(
        nodes,
        style: style,
        quark: QuarkTokens.of(context),
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      ),
    ),
    style: style,
    textAlign: textAlign,
  );
}
