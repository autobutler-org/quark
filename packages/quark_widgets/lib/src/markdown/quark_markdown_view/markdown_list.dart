import 'package:material_ui/material_ui.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/quark_tokens.dart';
import '../quark_markdown_view.dart';
import 'markdown_flow.dart';

/// A bulleted or numbered list of a `QuarkMarkdownView`. A numbered list
/// counts from its `start` attribute; a task list item shows its glyph in
/// place of a bullet. Items hold any content, nested lists included.
///
/// Key prefixes: none of its own; see `QuarkMarkdownView`.
///
/// ```dart
/// MarkdownList(list: listElement, style: bodyStyle);
/// ```
class MarkdownList extends StatelessWidget {
  /// Creates the list for the `ul` or `ol` element [list].
  const MarkdownList({
    required this.list,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The `ul` or `ol` element.
  final md.Element list;

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
    final quark = QuarkTokens.of(context);
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = (list.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: quark.spacingXs,
      children: [
        for (final (index, item) in items.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A task item leads with its own glyph.
              if (item.attributes['class'] != 'task-list-item')
                Container(
                  constraints: BoxConstraints(minWidth: quark.spacingLg),
                  padding: EdgeInsets.only(right: quark.spacingSm),
                  alignment: Alignment.topRight,
                  child: Text(
                    ordered ? '${start + index}.' : '•',
                    style: style.copyWith(color: quark.mutedForeground),
                  ),
                ),
              Expanded(
                child: MarkdownFlow(
                  nodes: item.children ?? const [],
                  style: style,
                  onLinkTap: onLinkTap,
                  imageBuilder: imageBuilder,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
