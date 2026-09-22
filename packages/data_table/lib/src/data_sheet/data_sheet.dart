import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:flutter/services.dart';

import '../../data_table.dart';
import 'cell/cell.dart';
import 'cell/editable_cell.dart';
import 'cell/heading/heading_cells.dart'
    show
        ColumnHeaderCell,
        HeaderCornerCell,
        RowNumberCell,
        kDefaultColumnWidth,
        kDefaultRowHeight,
        kGutterWidth;
import 'cell/heading/util.dart';
import 'data_sheet_control_scheme.dart';
import 'data_sheet_controller.dart';
import 'formula_bar.dart';

/// A spreadsheet grid over a `DataSheetController`: scrolling, selection, inline editing, and resizable rows and
/// columns.
class DataSheet extends StatelessWidget {
  final DataTable table;

  /// Callback that is called before a cell value is changed.
  /// If it returns false, the change is rejected and the cell
  /// value remains unchanged.
  final bool Function(String, int, int)? beforeCellValueChanged;

  /// Callback that is called after a cell value is changed.
  /// The boolean parameter indicates whether the change had been
  /// accepted or rejected.
  final Function(String, int, int, bool)? afterCellValueChanged;

  /// Optional external controller. If omitted, a controller is created
  /// from the provided `table` and owned by the internal view.
  final DataSheetController? controller;

  /// Optional per-column pixel widths. If provided and no external
  /// controller is supplied, these are forwarded to the internal controller.
  final List<double>? columnWidths;

  /// Optional key binding scheme. Defaults to
  /// [DataSheetControlScheme.defaults] when `null`.
  ///
  /// Provide a customized scheme to remap or disable individual shortcuts.
  /// The scheme can be swapped at runtime by passing a new value from a
  /// parent widget.
  final DataSheetControlScheme? controlScheme;

  /// Whether to show the column-letter header row and row-number gutter.
  /// Defaults to `true`.
  final bool showHeadings;

  /// Whether to show the formula bar above the column headers.
  /// Defaults to `true`.
  final bool showFormulaBar;

  const DataSheet({
    super.key,
    required this.table,
    this.beforeCellValueChanged,
    this.afterCellValueChanged,
    this.controller,
    this.columnWidths,
    this.controlScheme,
    this.showHeadings = true,
    this.showFormulaBar = true,
  });

  DataSheet.unnamed({super.key})
      : table = DataTable([]),
        beforeCellValueChanged = null,
        afterCellValueChanged = null,
        controller = null,
        columnWidths = null,
        controlScheme = null,
        showHeadings = true,
        showFormulaBar = true;

  @override
  Widget build(BuildContext context) {
    return _DataSheetView(
      table: table,
      controller: controller,
      columnWidths: columnWidths,
      beforeCellValueChanged: beforeCellValueChanged,
      afterCellValueChanged: afterCellValueChanged,
      controlScheme: controlScheme,
      showHeadings: showHeadings,
      showFormulaBar: showFormulaBar,
    );
  }
}

class _DataSheetView extends StatefulWidget {
  final DataTable table;
  final DataSheetController? controller;
  final List<double>? columnWidths;
  final bool Function(String, int, int)? beforeCellValueChanged;
  final Function(String, int, int, bool)? afterCellValueChanged;
  final DataSheetControlScheme? controlScheme;
  final bool showHeadings;
  final bool showFormulaBar;

  const _DataSheetView({
    required this.table,
    this.controller,
    this.columnWidths,
    this.beforeCellValueChanged,
    this.afterCellValueChanged,
    this.controlScheme,
    this.showHeadings = true,
    this.showFormulaBar = true,
  });

  @override
  State<_DataSheetView> createState() => _DataSheetViewState();
}

class _DataSheetViewState extends State<_DataSheetView> {
  late final FocusNode keyboardFocus;
  late final DataSheetController controller;
  late final bool _ownsController;
  final ScrollController _horizontalScrollController = ScrollController();
  String _priorCellValue = '';
  String? _internalClipboard;

  int get activeRow => controller.selection.activeRow;
  int get activeCol => controller.selection.activeCol;
  int get highlightedRow => controller.selection.highlightedRow;
  int get highlightedCol => controller.selection.highlightedCol;

  @override
  void initState() {
    super.initState();
    keyboardFocus = FocusNode();
    if (widget.controller != null) {
      controller = widget.controller!;
      _ownsController = false;
    } else {
      controller = DataSheetController.fromTable(
        widget.table,
        columnWidths: widget.columnWidths,
      );
      _ownsController = true;
    }
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    keyboardFocus.dispose();
    _horizontalScrollController.dispose();
    controller.removeListener(_onControllerChanged);
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: keyboardFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final scheme =
            widget.controlScheme ?? DataSheetControlScheme.defaults();
        bool m(List<KeyboardShortcut> triggers) =>
            triggers.any((t) => t.matches(event));

        // While a cell is actively being edited, only intercept Escape
        // (cancel) and Enter (confirm). All other keys — including arrow
        // keys, backspace, and delete — must reach the TextField so it can
        // handle them normally.
        if (activeRow >= 0 && activeCol >= 0) {
          if (m(scheme.cancelEdit)) {
            _storeCellValue(
              _priorCellValue,
              highlightRow: activeRow,
              highlightCol: activeCol,
            );
            keyboardFocus.requestFocus();
            return KeyEventResult.handled;
          }
          if (m(scheme.confirmEdit)) {
            final r = activeRow;
            final c = activeCol;
            _storeCellValue(
              controller.activeCellEditingController.text,
              highlightRow: r,
              highlightCol: c,
            );
            keyboardFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        // Modifier shortcuts are checked first (most specific) to prevent
        // them from falling through to plain-key handlers.
        if (m(scheme.undo)) {
          controller.undo();
          return KeyEventResult.handled;
        }
        if (m(scheme.redo)) {
          controller.redo();
          return KeyEventResult.handled;
        }
        if (m(scheme.copy)) {
          _copyCell();
          return KeyEventResult.handled;
        }
        if (m(scheme.cut)) {
          _cutCell();
          return KeyEventResult.handled;
        }
        if (m(scheme.paste)) {
          _pasteCell();
          return KeyEventResult.handled;
        }
        if (m(scheme.fillDown)) {
          _fillDown();
          return KeyEventResult.handled;
        }
        if (m(scheme.fillRight)) {
          _fillRight();
          return KeyEventResult.handled;
        }
        if (m(scheme.jumpToFirst)) {
          _jumpToFirst();
          return KeyEventResult.handled;
        }
        if (m(scheme.jumpToLast)) {
          _jumpToLast();
          return KeyEventResult.handled;
        }
        if (m(scheme.insertRow)) {
          _insertRow();
          return KeyEventResult.handled;
        }
        if (m(scheme.deleteRow)) {
          _deleteRow();
          return KeyEventResult.handled;
        }
        if (m(scheme.insertColumn)) {
          _insertColumn();
          return KeyEventResult.handled;
        }
        if (m(scheme.deleteColumn)) {
          _deleteColumn();
          return KeyEventResult.handled;
        }

        // Plain / shift shortcuts.
        if (m(scheme.moveUp)) {
          _moveUp();
          return KeyEventResult.handled;
        }
        if (m(scheme.moveDown)) {
          _moveDown();
          return KeyEventResult.handled;
        }
        if (m(scheme.moveLeft)) {
          _moveLeft();
          return KeyEventResult.handled;
        }
        if (m(scheme.moveRight)) {
          _moveRight();
          return KeyEventResult.handled;
        }
        if (m(scheme.movePreviousCell)) {
          if (activeRow >= 0 && activeCol >= 0) {
            final r = activeRow;
            final c = activeCol;
            _storeCellValue(
              controller.activeCellEditingController.text,
              highlightRow: r,
              highlightCol: c,
            );
            keyboardFocus.requestFocus();
          }
          _moveLeft();
          return KeyEventResult.handled;
        }
        if (m(scheme.moveNextCell)) {
          if (activeRow >= 0 && activeCol >= 0) {
            final r = activeRow;
            final c = activeCol;
            _storeCellValue(
              controller.activeCellEditingController.text,
              highlightRow: r,
              highlightCol: c,
            );
            keyboardFocus.requestFocus();
          }
          _moveRight();
          return KeyEventResult.handled;
        }
        if (m(scheme.confirmEdit)) {
          if (highlightedRow >= 0 && highlightedCol >= 0) {
            _activateCell(
              controller.cellAt(highlightedRow, highlightedCol),
              highlightedRow,
              highlightedCol,
            );
          } else if (activeRow >= 0 && activeCol >= 0) {
            final r = activeRow;
            final c = activeCol;
            _storeCellValue(
              controller.activeCellEditingController.text,
              highlightRow: r,
              highlightCol: c,
            );
            keyboardFocus.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (m(scheme.enterEditMode)) {
          if (highlightedRow >= 0 && highlightedCol >= 0) {
            _activateCell(
              controller.cellAt(highlightedRow, highlightedCol),
              highlightedRow,
              highlightedCol,
            );
          }
          return KeyEventResult.handled;
        }
        if (m(scheme.cancelEdit)) {
          if (activeRow >= 0 && activeCol >= 0) {
            _storeCellValue(
              _priorCellValue,
              highlightRow: activeRow,
              highlightCol: activeCol,
            );
            keyboardFocus.requestFocus();
          } else {
            controller.selection.clear();
          }
          return KeyEventResult.handled;
        }
        if (m(scheme.clearCell)) {
          if (highlightedRow >= 0 && highlightedCol >= 0) {
            controller.clearCell(highlightedRow, highlightedCol);
          }
          return KeyEventResult.handled;
        }
        if (m(scheme.jumpRowStart)) {
          if (highlightedRow >= 0) {
            controller.selection.setHighlighted(highlightedRow, 0);
          }
          return KeyEventResult.handled;
        }
        if (m(scheme.jumpRowEnd)) {
          if (highlightedRow >= 0) {
            controller.selection.setHighlighted(
              highlightedRow,
              controller.colCount - 1,
            );
          }
          return KeyEventResult.handled;
        }

        // Any other key while a cell is highlighted: start editing it.
        // Skip modifier-only keypresses (Ctrl, Cmd, Shift, Alt) so that
        // pressing a modifier alone does not inadvertently activate a cell.
        final modifierKeys = {
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.controlRight,
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.metaRight,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftRight,
          LogicalKeyboardKey.alt,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.altRight,
        };
        if (modifierKeys.contains(event.logicalKey)) {
          return KeyEventResult.ignored;
        }
        if (highlightedRow >= 0 && highlightedCol >= 0) {
          _activateCell(
            controller.cellAt(highlightedRow, highlightedCol),
            highlightedRow,
            highlightedCol,
          );
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final totalW = _totalContentWidth();
              final scrollW =
                  totalW < constraints.maxWidth ? constraints.maxWidth : totalW;
              return Column(
                children: [
                  // ── Formula bar ─────────────────────────────────────
                  if (widget.showFormulaBar)
                    DataSheetFormulaBar(controller: controller),
                  // ── Scrollable grid ─────────────────────────────────
                  Expanded(
                    child: Listener(
                      // Intercept horizontal pointer scroll events and
                      // consume them via the PointerSignalResolver so the
                      // browser never sees them as back/forward navigation
                      // gestures (macOS trackpad two-finger swipe).
                      onPointerSignal: (PointerSignalEvent event) {
                        if (event is PointerScrollEvent &&
                            event.scrollDelta.dx != 0) {
                          GestureBinding.instance.pointerSignalResolver
                              .register(event, (PointerSignalEvent e) {
                            final dx = (e as PointerScrollEvent).scrollDelta.dx;
                            if (!_horizontalScrollController.hasClients) {
                              return;
                            }
                            final pos = _horizontalScrollController.position;
                            final next = (pos.pixels + dx).clamp(
                              0.0,
                              pos.maxScrollExtent,
                            );
                            _horizontalScrollController.jumpTo(next);
                          });
                        }
                      },
                      child: SingleChildScrollView(
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: scrollW,
                          child: Column(
                            children: [
                              // ── Column header row ─────────────────────
                              if (widget.showHeadings) _buildHeaderRow(),
                              // ── Data rows ─────────────────────────────
                              Expanded(
                                child: ListView.builder(
                                  itemCount: controller.rowCount,
                                  itemBuilder: (context, r) {
                                    return ValueListenableBuilder<
                                        List<DataCell>>(
                                      valueListenable: controller.rowNotifier(
                                        r,
                                      ),
                                      builder: (context, rowCells, _) =>
                                          _buildDataRow(context, r, rowCells),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layout helpers
  // ---------------------------------------------------------------------------

  double _totalContentWidth() {
    final gutterW = widget.showHeadings ? kGutterWidth : 0.0;
    return gutterW + controller.columnWidths.fold(0.0, (acc, w) => acc + w);
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        HeaderCornerCell(),
        ...List.generate(controller.colCount, (c) {
          final width = c < controller.columnWidths.length
              ? controller.columnWidths[c]
              : kDefaultColumnWidth;
          return SizedBox(
            width: width,
            child: ColumnHeaderCell(
              key: ValueKey('col_header_$c'),
              label: columnLabel(c),
              onResizeDelta: (delta) {
                final cur = c < controller.columnWidths.length
                    ? controller.columnWidths[c]
                    : kDefaultColumnWidth;
                controller.setColumnWidth(c, cur + delta);
              },
              onAutoSize: () => controller.autoSizeColumn(
                c,
                textStyle: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDataRow(BuildContext context, int r, List<DataCell> rowCells) {
    final rowHeight = r < controller.rowHeights.length
        ? controller.rowHeights[r]
        : kDefaultRowHeight;
    return Row(
      children: [
        if (widget.showHeadings)
          RowNumberCell(
            key: ValueKey('row_num_$r'),
            number: r + 1,
            height: rowHeight,
            onResizeDelta: (delta) {
              final cur = r < controller.rowHeights.length
                  ? controller.rowHeights[r]
                  : kDefaultRowHeight;
              controller.setRowHeight(r, cur + delta);
            },
            onAutoSize: () => controller.autoSizeRow(
              r,
              textStyle: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ...List.generate(rowCells.length, (c) {
          final isActiveCell = (r == activeRow && c == activeCol);
          final isHighlightedCell =
              (r == highlightedRow && c == highlightedCol);
          final colWidth = c < controller.columnWidths.length
              ? controller.columnWidths[c]
              : kDefaultColumnWidth;

          final cellChild = isActiveCell
              ? EditableCell(
                  key: ValueKey('r${r}c$c'),
                  controller: controller.activeCellEditingController,
                  onSubmitted: _storeCellValue,
                  onEditingComplete: () {
                    _storeCellValue(
                      controller.activeCellEditingController.text,
                    );
                  },
                  onTapOutside: (_) {
                    _storeCellValue(
                      controller.activeCellEditingController.text,
                      highlightRow: activeRow,
                      highlightCol: activeCol,
                    );
                    keyboardFocus.requestFocus();
                  },
                )
              : Builder(
                  builder: (context) {
                    final display = controller.displayValueAt(r, c);
                    final isError = controller.isCellError(r, c);
                    return Text(
                      display,
                      style: isError
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w500,
                            )
                          : null,
                    );
                  },
                );

          final cell = Cell(
            key: ValueKey('r${r}c$c'),
            isActive: isActiveCell,
            isHighlighted: isHighlightedCell,
            cursor: isActiveCell
                ? SystemMouseCursors.text
                : SystemMouseCursors.cell,
            height: rowHeight,
            referenceColor: controller.activeRefColors[(r, c)],
            child: cellChild,
          );

          return SizedBox(
            width: colWidth,
            child: isActiveCell
                ? cell
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (activeRow >= 0 && activeCol >= 0) {
                        _storeCellValue(
                          controller.activeCellEditingController.text,
                        );
                      } else {
                        if (highlightedRow == r && highlightedCol == c) {
                          _activateCell(rowCells[c], r, c);
                        } else {
                          controller.selection.setHighlighted(r, c);
                          keyboardFocus.requestFocus();
                        }
                      }
                    },
                    child: cell,
                  ),
          );
        }),
      ],
    );
  }

  void _storeCellValue(
    String value, {
    int highlightRow = -1,
    int highlightCol = -1,
  }) {
    final changedRow = activeRow;
    final changedCol = activeCol;
    if (changedRow < 0 || changedCol < 0) return;
    final isChangeAccepted =
        widget.beforeCellValueChanged?.call(value, changedRow, changedCol) ??
            true;
    if (isChangeAccepted) {
      controller.updateCell(changedRow, changedCol, DataCell(value));
    }
    controller.activeCellEditingController.clear();
    if (highlightRow >= 0) {
      controller.selection.goTo(highlightRow, highlightCol);
    } else {
      controller.selection.clear();
    }
    widget.afterCellValueChanged?.call(
      value,
      changedRow,
      changedCol,
      isChangeAccepted,
    );
  }

  void _activateCell(DataCell cell, int row, int col) {
    _priorCellValue = cell.value.toString();
    controller.activeCellEditingController.text = _priorCellValue;
    keyboardFocus.unfocus();
    controller.selection.setActive(row, col);
  }

  // ---------------------------------------------------------------------------
  // Shortcut action helpers
  // ---------------------------------------------------------------------------

  void _copyCell() {
    final row = controller.selection.contextRow;
    final col = controller.selection.contextCol;
    if (row < 0 || col < 0) return;
    _internalClipboard = controller.cellAt(row, col).value;
  }

  void _cutCell() {
    final row = controller.selection.contextRow;
    final col = controller.selection.contextCol;
    if (row < 0 || col < 0) return;
    _internalClipboard = controller.cellAt(row, col).value;
    controller.clearCell(row, col);
  }

  void _pasteCell() {
    final row = controller.selection.contextRow;
    final col = controller.selection.contextCol;
    if (row < 0 || col < 0) return;
    if (_internalClipboard == null) return;
    controller.updateCell(row, col, DataCell(_internalClipboard!));
  }

  void _fillDown() {
    final row = controller.selection.contextRow;
    final col = controller.selection.contextCol;
    if (row < 0 || col < 0) return;
    controller.fillDown(row, col);
  }

  void _fillRight() {
    final row = controller.selection.contextRow;
    final col = controller.selection.contextCol;
    if (row < 0 || col < 0) return;
    controller.fillRight(row, col);
  }

  void _jumpToFirst() {
    if (controller.rowCount == 0 || controller.colCount == 0) return;
    controller.selection.goTo(0, 0);
  }

  void _jumpToLast() {
    if (controller.rowCount == 0 || controller.colCount == 0) return;
    controller.selection.goTo(controller.rowCount - 1, controller.colCount - 1);
  }

  void _insertRow() {
    final row = controller.selection.contextRow;
    if (row < 0) return;
    controller.insertRowAt(row);
  }

  void _deleteRow() {
    final row = controller.selection.contextRow;
    if (row < 0) return;
    controller.deleteRowAt(row);
  }

  void _insertColumn() {
    final col = controller.selection.contextCol;
    if (col < 0) return;
    controller.insertColumnAt(col);
  }

  void _deleteColumn() {
    final col = controller.selection.contextCol;
    if (col < 0) return;
    controller.deleteColumnAt(col);
  }

  void _moveUp() {
    if (highlightedRow > 0) {
      controller.selection.setHighlighted(highlightedRow - 1, highlightedCol);
    }
  }

  void _moveDown() {
    if (highlightedRow < controller.rowCount - 1) {
      controller.selection.setHighlighted(highlightedRow + 1, highlightedCol);
    }
  }

  void _moveLeft() {
    if (highlightedCol > 0) {
      controller.selection.setHighlighted(highlightedRow, highlightedCol - 1);
    }
  }

  void _moveRight() {
    if (highlightedCol < controller.colCount - 1) {
      controller.selection.setHighlighted(highlightedRow, highlightedCol + 1);
    }
  }

  // ── Header helpers ────────────────────────────────────────────────────────
  // Column label conversion is in heading/column_label.dart (columnLabel())
  // and heading widgets are in heading/heading_cells.dart.
}
