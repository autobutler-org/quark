import 'package:material_ui/material_ui.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../quark_markdown_document.dart';
import '../quark_markdown_view.dart';
import 'markdown_image.dart';
import 'markdown_link.dart';

// Font names, not prose.
// cspell:ignore Consolas Menlo Roboto

/// The monospace family code is drawn in.
const String markdownMonoFamily = 'monospace';

/// The fallbacks for [markdownMonoFamily], the code viewer's own list.
const List<String> markdownMonoFallback = [
  'Menlo',
  'Consolas',
  'Roboto Mono',
  'DejaVu Sans Mono',
  'Courier New',
];

/// Turns the inline [nodes] of a paragraph into spans drawn in [style].
///
/// Text is literal: raw inline HTML arrives from the parser as text and stays
/// text. A soft line break in the source becomes a space, a hard one a new
/// line. Links, images and task glyphs are widgets inside the text, keyed
/// `markdown_link_<n>`, `markdown_image_<n>` and `markdown_task_<n>`. An
/// element with an unknown tag contributes its children.
///
/// Every span carries its whole style, since a link's text is a widget of its
/// own and inherits nothing from the paragraph around it.
List<InlineSpan> markdownInlineSpans(
  List<md.Node> nodes, {
  required TextStyle style,
  required QuarkTokens quark,
  ValueChanged<String>? onLinkTap,
  QuarkMarkdownImageBuilder? imageBuilder,
}) {
  List<InlineSpan> children(md.Element element, TextStyle childStyle) =>
      markdownInlineSpans(
        element.children ?? const [],
        style: childStyle,
        quark: quark,
        onLinkTap: onLinkTap,
        imageBuilder: imageBuilder,
      );

  final spans = <InlineSpan>[];
  for (final node in nodes) {
    if (node is! md.Element) {
      spans.add(
        TextSpan(text: node.textContent.replaceAll('\n', ' '), style: style),
      );
      continue;
    }
    final index = node.attributes[markdownIndexAttribute];
    switch (node.tag) {
      case 'br':
        spans.add(TextSpan(text: '\n', style: style));
      case 'strong':
        spans.addAll(
          children(node, style.copyWith(fontWeight: FontWeight.bold)),
        );
      case 'em':
        spans.addAll(
          children(node, style.copyWith(fontStyle: FontStyle.italic)),
        );
      case 'del':
        spans.addAll(
          children(
            node,
            style.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      case 'sup':
        final size = style.fontSize;
        spans.addAll(
          children(
            node,
            size == null ? style : style.copyWith(fontSize: size * 0.8),
          ),
        );
      case 'code':
        spans.add(
          TextSpan(
            text: node.textContent,
            style: style.copyWith(
              fontFamily: markdownMonoFamily,
              fontFamilyFallback: markdownMonoFallback,
              backgroundColor: quark.card,
            ),
          ),
        );
      case 'a':
        // A widget, not a recognizer: it can carry a key, and nothing has to
        // be disposed. Middle-aligned, since a baseline-aligned widget span
        // has no intrinsic width and a table column needs one.
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MarkdownLink(
              key: ValueKey('markdown_link_$index'),
              href: node.attributes['href'] ?? '',
              onTap: onLinkTap,
              child: Text.rich(
                TextSpan(
                  children: children(
                    node,
                    style.copyWith(
                      color: quark.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: quark.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case 'img':
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MarkdownImage(
              key: ValueKey('markdown_image_$index'),
              src: node.attributes['src'] ?? '',
              alt: node.attributes['alt'] ?? '',
              style: style,
              imageBuilder: imageBuilder,
            ),
          ),
        );
      case 'input':
        // A task list's checkbox: a glyph, never a control.
        final checked = node.attributes.containsKey('checked');
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: quark.spacingSm),
              child: Icon(
                checked
                    ? QuarkIcons.check_circle_rounded
                    : QuarkIcons.radio_button_unchecked,
                key: ValueKey('markdown_task_$index'),
                size: (style.fontSize ?? 16) * 1.2,
                color: checked ? quark.primary : quark.mutedForeground,
                semanticLabel: checked ? 'Done' : 'Not done',
              ),
            ),
          ),
        );
      default:
        spans.addAll(children(node, style));
    }
  }
  return spans;
}
