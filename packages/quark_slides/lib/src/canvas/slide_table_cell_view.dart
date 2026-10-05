import 'package:flutter/widgets.dart';

import '../model/slide_element.dart';
import '../theme/slide_theme.dart';
import 'slide_canvas_style.dart';
import 'slide_table_view.dart';
import 'slide_text_box_view.dart';

/// One cell of a [TableElement] — the whole area of a merged one — placed
/// at its box in a [SlideTableView]'s `Stack`: its fill, its text inside
/// the cell padding, and a tint when [selected].
///
/// It reads to a screen reader as [label], or, while it is being edited,
/// as the [editor] drawn in place of its text.
class SlideTableCellView extends StatelessWidget {
  /// Creates the view of the cell at [row], [column] of [table].
  const SlideTableCellView({
    super.key,
    required this.table,
    required this.row,
    required this.column,
    required this.style,
    required this.theme,
    required this.label,
    this.selected = false,
    this.editor,
  });

  /// The table the cell is in.
  final TableElement table;

  /// The cell's row.
  final int row;

  /// The cell's column.
  final int column;

  /// Supplies the selection tint.
  final SlideCanvasStyle style;

  /// The theme the cell's colors and unset text styles resolve against.
  final SlideTheme theme;

  /// What a screen reader announces.
  final String label;

  /// Whether the cell is in the canvas's cell selection.
  final bool selected;

  /// The in-place editor drawn instead of the text, or `null`.
  final Widget? editor;

  @override
  Widget build(BuildContext context) {
    final box = table.cellBox(row, column);
    final fill = table.fillAt(row, column);
    final editor = this.editor;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TableElement.cellPaddingX,
        vertical: TableElement.cellPaddingY,
      ),
      child: editor ??
          SlideTextBoxView(
            box: table.cellTextBox(row, column),
            style: style,
            theme: SlideTableView.cellTheme(table, row, theme),
          ),
    );
    return Positioned(
      left: box.x,
      top: box.y,
      width: box.width,
      height: box.height,
      child: Semantics(
        container: true,
        label: editor == null ? label : null,
        selected: selected,
        excludeSemantics: editor == null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill == null ? null : Color(fill.resolve(theme)),
          ),
          child: selected
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: style.selectionColor.withValues(alpha: 0.18),
                  ),
                  position: DecorationPosition.foreground,
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}
