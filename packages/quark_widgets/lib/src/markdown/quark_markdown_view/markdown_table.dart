import 'package:material_ui/material_ui.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/quark_tokens.dart';
import '../quark_markdown_view.dart';
import 'markdown_inline.dart';

/// A table of a `QuarkMarkdownView`: a bold header row, each column aligned
/// as the source asked and as wide as its content up to [maxCellWidth], in a
/// box that scrolls sideways when the table is wider than the page.
///
/// Key prefixes: none of its own; see `QuarkMarkdownView`.
///
/// ```dart
/// MarkdownTable(table: tableElement, style: bodyStyle);
/// ```
class MarkdownTable extends StatelessWidget {
  /// Creates the table for the `table` element [table].
  const MarkdownTable({
    required this.table,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The widest a cell's text runs before it wraps, in logical pixels.
  static const double maxCellWidth = 320;

  /// The box an image built by the caller gets inside a cell.
  static const Size cellImageSize = Size(160, 120);

  /// The `table` element: a `thead` and, when it has rows, a `tbody`.
  final md.Element table;

  /// The body text style. The header row is drawn in its bold.
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
    final imageBuilder = this.imageBuilder;
    final rows = [
      for (final section in table.children ?? const <md.Node>[])
        if (section is md.Element)
          ...(section.children ?? const <md.Node>[]).whereType<md.Element>(),
    ];
    final cells = [
      for (final row in rows)
        (row.children ?? const <md.Node>[]).whereType<md.Element>().toList(),
    ];
    final columns = cells.isEmpty ? 0 : cells.first.length;
    if (columns == 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: quark.border),
        children: [
          for (final row in cells)
            TableRow(
              children: [
                for (var column = 0; column < columns; column++)
                  if (column >= row.length)
                    const SizedBox.shrink()
                  else
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: quark.spacingMd,
                        vertical: quark.spacingSm,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: maxCellWidth,
                        ),
                        child: MarkdownInline(
                          nodes: row[column].children ?? const [],
                          style: row[column].tag == 'th'
                              ? style.copyWith(fontWeight: FontWeight.bold)
                              : style,
                          textAlign: switch (row[column].attributes['align']) {
                            'center' => TextAlign.center,
                            'right' => TextAlign.right,
                            _ => TextAlign.left,
                          },
                          onLinkTap: onLinkTap,
                          // ponytail: a fixed box, since a column is sized by
                          // intrinsic width and a caller's image (a
                          // LayoutBuilder, say) may have none. Size cells to
                          // the image if tables of images start to matter.
                          imageBuilder: imageBuilder == null
                              ? null
                              : (context, src, alt) => SizedBox.fromSize(
                                  size: cellImageSize,
                                  child: imageBuilder(context, src, alt),
                                ),
                        ),
                      ),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}
