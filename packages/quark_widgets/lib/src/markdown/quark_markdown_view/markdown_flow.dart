import 'package:material_ui/material_ui.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/quark_tokens.dart';
import '../quark_markdown_view.dart';
import 'markdown_block.dart';
import 'markdown_inline.dart';

const Set<String> _blockTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'ul',
  'ol',
  'li',
  'pre',
  'hr',
  'table',
  'div',
  'section',
};

/// The content of a container that mixes text and blocks: a list item, a
/// quote, an alert. Each block element in [nodes] becomes a `MarkdownBlock`,
/// and each run of inline nodes between them becomes one paragraph, stacked
/// in order.
///
/// It takes the full width it is offered, so its parent has to bound it.
///
/// Key prefixes: none of its own; see `QuarkMarkdownView`.
///
/// ```dart
/// MarkdownFlow(nodes: listItem.children ?? const [], style: bodyStyle);
/// ```
class MarkdownFlow extends StatelessWidget {
  /// Creates the stacked content of [nodes].
  const MarkdownFlow({
    required this.nodes,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The container's children, inline and block mixed.
  final List<md.Node> nodes;

  /// The body text style.
  final TextStyle style;

  /// Called with a link's raw `href` when it is tapped; null leaves links
  /// inert.
  final ValueChanged<String>? onLinkTap;

  /// Builds each image from its raw `src` and `alt`; null shows a
  /// placeholder.
  final QuarkMarkdownImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var run = <md.Node>[];
    void flush() {
      // A run of nothing but the whitespace between two blocks is not a
      // paragraph.
      if (run.any(
        (node) => node is md.Element || node.textContent.trim() != '',
      )) {
        children.add(
          MarkdownInline(
            nodes: run,
            style: style,
            onLinkTap: onLinkTap,
            imageBuilder: imageBuilder,
          ),
        );
      }
      run = [];
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        children.add(
          MarkdownBlock(
            node: node,
            style: style,
            onLinkTap: onLinkTap,
            imageBuilder: imageBuilder,
          ),
        );
      } else {
        run.add(node);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: QuarkTokens.of(context).spacingSm,
      children: children,
    );
  }
}
