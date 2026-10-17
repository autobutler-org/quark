import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/quark_tokens.dart';
import '../quark_markdown_document.dart';
import '../quark_markdown_view.dart';
import 'markdown_alert.dart';
import 'markdown_code_block.dart';
import 'markdown_flow.dart';
import 'markdown_inline.dart';
import 'markdown_list.dart';
import 'markdown_table.dart';

/// One block of a `QuarkMarkdownView`: a heading, paragraph, quote, alert,
/// list, code block, rule or table, picked by [node]'s tag.
///
/// A node that is not an element is a block of raw HTML, and is shown as the
/// text it was written as. An element with a tag this does not know (the
/// footnotes section) renders its children, so nothing in a document is
/// dropped.
///
/// Key prefixes: none of its own; see `QuarkMarkdownView`.
///
/// ```dart
/// MarkdownBlock(node: document.blocks.first, style: bodyStyle);
/// ```
class MarkdownBlock extends StatelessWidget {
  /// Creates the block for [node].
  const MarkdownBlock({
    required this.node,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The block to render.
  final md.Node node;

  /// The body text style. Headings and code derive theirs from it.
  final TextStyle style;

  /// Called with a link's raw `href` when it is tapped; null leaves links
  /// inert.
  final ValueChanged<String>? onLinkTap;

  /// Builds each image from its raw `src` and `alt`; null shows a
  /// placeholder.
  final QuarkMarkdownImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    // Raw HTML: literal source, line breaks kept.
    if (node is! md.Element) return Text(node.textContent, style: style);

    final quark = QuarkTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final children = node.children ?? const <md.Node>[];
    final heading = switch (node.tag) {
      'h1' => textTheme.headlineMedium,
      'h2' => textTheme.headlineSmall,
      'h3' => textTheme.titleLarge,
      'h4' => textTheme.titleMedium,
      'h5' || 'h6' => textTheme.titleSmall,
      _ => null,
    };
    if (markdownAlertKind(node) != null) {
      return MarkdownAlert(
        key: ValueKey(
          'markdown_alert_${node.attributes[markdownIndexAttribute]}',
        ),
        alert: node,
        style: style,
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      );
    }
    if (heading != null) {
      return Padding(
        padding: EdgeInsets.only(top: quark.spacingSm),
        child: Semantics(
          header: true,
          child: MarkdownInline(
            nodes: children,
            style: heading.copyWith(
              color: node.tag == 'h6' ? quark.mutedForeground : style.color,
              fontWeight: FontWeight.w600,
            ),
            onLinkTap: onLinkTap,
            imageBuilder: imageBuilder,
          ),
        ),
      );
    }
    return switch (node.tag) {
      'p' => MarkdownInline(
        nodes: children,
        style: style,
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      ),
      'blockquote' => DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: quark.border, width: 4)),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: quark.spacingMd),
          child: MarkdownFlow(
            nodes: children,
            style: style.copyWith(color: quark.secondaryForeground),
            onLinkTap: onLinkTap,
            imageBuilder: imageBuilder,
          ),
        ),
      ),
      'ul' || 'ol' => MarkdownList(
        list: node,
        style: style,
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      ),
      'pre' => MarkdownCodeBlock(block: node, style: style),
      'hr' => Divider(color: quark.border, height: quark.spacingLg),
      'table' => MarkdownTable(
        table: node,
        style: style,
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      ),
      _ => MarkdownFlow(
        nodes: children,
        style: style,
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      ),
    };
  }
}
