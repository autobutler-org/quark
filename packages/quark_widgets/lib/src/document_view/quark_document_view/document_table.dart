import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../quark_document.dart';
import '../quark_document_view.dart';
import 'document_table_cell.dart';
import 'document_table_grid.dart';
import 'document_table_grid_cell.dart';

/// A horizontally scrollable document table with row and column spans.
class DocumentTableView extends StatelessWidget {
  /// Creates a table.
  const DocumentTableView({
    required this.table,
    required this.style,
    this.onLinkTap,
    this.imageBuilder,
    super.key,
  });

  /// The table to render.
  final QuarkDocumentTable table;

  /// The document body style.
  final TextStyle style;

  /// Called with a link target when it is tapped.
  final ValueChanged<String>? onLinkTap;

  /// Builds embedded images in table cells.
  final QuarkDocumentImageBuilder? imageBuilder;

  /// The smallest width allocated to a logical column.
  static const double minColumnWidth = 112;

  @override
  Widget build(BuildContext context) {
    final rows = <List<_PlacedDocumentCell>>[];
    final remaining = <int>[];
    var columnCount = 0;
    for (final row in table.rows) {
      final occupied = [for (final value in remaining) value > 0];
      for (var column = 0; column < remaining.length; column++) {
        if (remaining[column] > 0) remaining[column]--;
      }
      final placed = <_PlacedDocumentCell>[];
      var cursor = 0;
      for (final cell in row.cells) {
        while (true) {
          while (cursor < occupied.length && occupied[cursor]) {
            cursor++;
          }
          final blocked = Iterable<int>.generate(
            cell.colSpan,
            (offset) => cursor + offset,
          ).where((column) => column < occupied.length && occupied[column]);
          if (blocked.isEmpty) break;
          cursor = blocked.first + 1;
        }
        while (remaining.length < cursor + cell.colSpan) {
          remaining.add(0);
          occupied.add(false);
        }
        placed.add(_PlacedDocumentCell(column: cursor, cell: cell));
        if (cell.rowSpan > 1) {
          for (var column = cursor; column < cursor + cell.colSpan; column++) {
            remaining[column] = math.max(remaining[column], cell.rowSpan - 1);
          }
        }
        cursor += cell.colSpan;
      }
      columnCount = math.max(columnCount, math.max(cursor, remaining.length));
      rows.add(placed);
    }
    if (columnCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final tableWidth = math.max(
          viewportWidth,
          columnCount * minColumnWidth,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: DocumentTableGrid(
              rowCount: rows.length,
              columnCount: columnCount,
              children: [
                for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
                  for (final placed in rows[rowIndex])
                    DocumentTableGridCell(
                      row: rowIndex,
                      column: placed.column,
                      rowSpan: math.min(
                        placed.cell.rowSpan,
                        rows.length - rowIndex,
                      ),
                      colSpan: placed.cell.colSpan,
                      child: DocumentTableCellView(
                        cell: placed.cell,
                        style: style,
                        onLinkTap: onLinkTap,
                        imageBuilder: imageBuilder,
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlacedDocumentCell {
  const _PlacedDocumentCell({required this.column, required this.cell});

  final int column;
  final QuarkDocumentTableCell cell;
}
