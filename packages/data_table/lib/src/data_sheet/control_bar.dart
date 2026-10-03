import 'package:quark_icons/quark_icons.dart';
import 'package:flutter/material.dart' hide Icons;

import 'data_sheet_controller.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// A ready-made toolbar companion for [DataSheetController].
///
/// Provides grouped icon buttons for all common spreadsheet operations.
/// Place it wherever suits your layout — typically above a [DataSheet]:
///
/// ```dart
/// Column(children: [
///   DataSheetControlBar(controller: myController),
///   Expanded(child: DataSheet(controller: myController, table: myTable)),
/// ])
/// ```
///
/// The toolbar rebuilds whenever the controller changes (data or selection),
/// so buttons are automatically enabled/disabled based on current state.
///
/// Users who want a fully custom toolbar should build their own widget and
/// call methods on [DataSheetController] directly.
class DataSheetControlBar extends StatelessWidget {
  final DataSheetController controller;

  const DataSheetControlBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sel = controller.selection;
        final hasRow = sel.contextRow >= 0;
        final hasCol = sel.contextCol >= 0;
        final hasData = controller.rowCount > 0;
        // Row, column, clear and fill actions cover every selected cell.
        final range = sel.contextRange;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                // ── Structure ──────────────────────────────────────────────
                _group([
                  // Insert row before/after the selected row. With nothing
                  // selected the sheet edges are the anchor, so these still
                  // grow the sheet — there is no separate append button.
                  _btn(
                    QuarkIcons.insert_row_above,
                    hasRow ? 'Insert row before' : 'Insert row at top',
                    () => controller.insertRowAt(hasRow ? sel.contextRow : 0),
                  ),
                  _btn(
                    QuarkIcons.insert_row_below,
                    hasRow ? 'Insert row after' : 'Add row at end',
                    () => controller.insertRowAt(
                      hasRow ? sel.contextRow + 1 : controller.rowCount,
                    ),
                  ),
                  // Insert column before/after the selected column. Columns
                  // live inside rows, so an empty sheet has nowhere to put one.
                  _btn(
                    QuarkIcons.insert_column_left,
                    hasCol ? 'Insert column before' : 'Insert column at left',
                    hasData
                        ? () => controller.insertColumnAt(
                              hasCol ? sel.contextCol : 0,
                            )
                        : null,
                  ),
                  _btn(
                    QuarkIcons.insert_column_right,
                    hasCol ? 'Insert column after' : 'Add column at end',
                    hasData
                        ? () => controller.insertColumnAt(
                              hasCol ? sel.contextCol + 1 : controller.colCount,
                            )
                        : null,
                  ),
                  // Delete row / column
                  _btn(
                    QuarkIcons.delete_row,
                    'Delete row',
                    range != null
                        ? () => controller.deleteRowAt(
                              range.top,
                              count: range.rowCount,
                            )
                        : null,
                  ),
                  _btn(
                    QuarkIcons.delete_column,
                    'Delete column',
                    range != null
                        ? () => controller.deleteColumnAt(
                              range.left,
                              count: range.colCount,
                            )
                        : null,
                  ),
                  // Duplicate row / column
                  _btn(
                    QuarkIcons.duplicate_row,
                    'Duplicate row',
                    hasRow
                        ? () => controller.duplicateRow(sel.contextRow)
                        : null,
                  ),
                  _btn(
                    QuarkIcons.duplicate_column,
                    'Duplicate column',
                    hasCol
                        ? () => controller.duplicateColumn(sel.contextCol)
                        : null,
                  ),
                ]),
                const _Divider(),
                // ── Edit ───────────────────────────────────────────────────
                _group([
                  _btn(
                    QuarkIcons.undo,
                    'Undo',
                    controller.canUndo ? controller.undo : null,
                  ),
                  _btn(
                    QuarkIcons.redo,
                    'Redo',
                    controller.canRedo ? controller.redo : null,
                  ),
                  _btn(
                    QuarkIcons.clear_row,
                    'Clear row',
                    range != null
                        ? () => controller.clearRow(
                              range.top,
                              count: range.rowCount,
                            )
                        : null,
                  ),
                  _btn(
                    QuarkIcons.clear_column,
                    'Clear column',
                    range != null
                        ? () => controller.clearColumn(
                              range.left,
                              count: range.colCount,
                            )
                        : null,
                  ),
                  _btn(
                    QuarkIcons.fill_down,
                    'Fill down',
                    range != null
                        ? () => controller.fillDownRange(range)
                        : null,
                  ),
                  _btn(
                    QuarkIcons.fill_right,
                    'Fill right',
                    range != null
                        ? () => controller.fillRightRange(range)
                        : null,
                  ),
                ]),
                const _Divider(),
                // ── Data ───────────────────────────────────────────────────
                _group([
                  _btn(
                    QuarkIcons.sort,
                    'Sort…',
                    hasData
                        ? () => _showSortDialog(
                              context,
                              controller,
                              sel.contextCol >= 0 ? sel.contextCol : 0,
                            )
                        : null,
                  ),
                  _btn(
                    QuarkIcons.remove_duplicates,
                    'Remove duplicate rows',
                    hasData ? controller.removeDuplicateRows : null,
                  ),
                  _btn(
                    QuarkIcons.find_replace,
                    'Find & replace…',
                    () => _showFindReplaceDialog(context, controller),
                  ),
                  _btn(
                    QuarkIcons.go_to_cell,
                    'Go to cell…',
                    hasData
                        ? () => _showGoToCellDialog(context, controller)
                        : null,
                  ),
                ]),
                const _Divider(),
                // ── Import / Export ────────────────────────────────────────
                _group([
                  _btn(
                    QuarkIcons.export_csv,
                    'Export CSV',
                    hasData
                        ? () => _showExportCsvDialog(context, controller)
                        : null,
                  ),
                  _btn(
                    QuarkIcons.import_csv,
                    'Import CSV…',
                    () => _showImportCsvDialog(context, controller),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Private helper widgets
// ---------------------------------------------------------------------------

Widget _group(List<Widget> children) {
  return Row(mainAxisSize: MainAxisSize.min, children: children);
}

Widget _btn(IconData icon, String tooltip, VoidCallback? onPressed) {
  return Tooltip(
    message: tooltip,
    child: IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 28,
      child: VerticalDivider(width: 12, thickness: 1),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog helpers
// ---------------------------------------------------------------------------

Future<void> _showSortDialog(
  BuildContext context,
  DataSheetController controller,
  int defaultCol,
) async {
  if (controller.colCount == 0) return;
  var col = defaultCol.clamp(0, controller.colCount - 1);
  var ascending = true;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Sort by column'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: col,
              decoration: const InputDecoration(labelText: 'Column'),
              items: List.generate(
                controller.colCount,
                (i) =>
                    DropdownMenuItem(value: i, child: Text('Column ${i + 1}')),
              ),
              onChanged: (v) => setState(() => col = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: ascending,
              decoration: const InputDecoration(labelText: 'Direction'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Ascending')),
                DropdownMenuItem(value: false, child: Text('Descending')),
              ],
              onChanged: (v) => setState(() => ascending = v!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              controller.sortByColumn(col, ascending: ascending);
              Navigator.pop(context);
            },
            child: const Text('Sort'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showFindReplaceDialog(
  BuildContext context,
  DataSheetController controller,
) async {
  final findCtrl = TextEditingController();
  final replaceCtrl = TextEditingController();
  var caseSensitive = false;
  int? replacedCount;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Find & replace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: findCtrl,
              decoration: const InputDecoration(labelText: 'Find'),
              autofocus: true,
            ),
            TextField(
              controller: replaceCtrl,
              decoration: const InputDecoration(labelText: 'Replace with'),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              title: const Text('Case sensitive'),
              value: caseSensitive,
              onChanged: (v) => setState(() => caseSensitive = v!),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (replacedCount != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('$replacedCount replacement(s) made.'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              final count = controller.replaceCells(
                findCtrl.text,
                replaceCtrl.text,
                caseSensitive: caseSensitive,
              );
              setState(() => replacedCount = count);
            },
            child: const Text('Replace all'),
          ),
        ],
      ),
    ),
  );

  findCtrl.dispose();
  replaceCtrl.dispose();
}

Future<void> _showGoToCellDialog(
  BuildContext context,
  DataSheetController controller,
) async {
  final rowCtrl = TextEditingController();
  final colCtrl = TextEditingController();
  String? error;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Go to cell'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: rowCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Row (1-based)',
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: colCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Column (1-based)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final row = (int.tryParse(rowCtrl.text) ?? 0) - 1;
              final col = (int.tryParse(colCtrl.text) ?? 0) - 1;
              if (row < 0 ||
                  row >= controller.rowCount ||
                  col < 0 ||
                  col >= controller.colCount) {
                setState(
                  () => error =
                      'Row must be 1–${controller.rowCount}, column 1–${controller.colCount}.',
                );
                return;
              }
              controller.selection.goTo(row, col);
              Navigator.pop(context);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    ),
  );

  rowCtrl.dispose();
  colCtrl.dispose();
}

void _showExportCsvDialog(
  BuildContext context,
  DataSheetController controller,
) {
  final csv = controller.exportCsv();
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Export CSV'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 320),
        child: SingleChildScrollView(child: SelectableText(csv)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showImportCsvDialog(
  BuildContext context,
  DataSheetController controller,
) async {
  final pasteCtrl = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import CSV'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: TextField(
          controller: pasteCtrl,
          maxLines: 8,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste CSV data here…',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (pasteCtrl.text.isNotEmpty) {
              controller.loadFromCsv(pasteCtrl.text);
              Navigator.pop(context);
            }
          },
          child: const Text('Import'),
        ),
      ],
    ),
  );

  pasteCtrl.dispose();
}
