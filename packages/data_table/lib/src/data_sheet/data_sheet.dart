import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:flutter/services.dart';

import '../../data_table.dart';
import 'cell/cell.dart';
import 'cell/editable_cell.dart';
import 'cell/formatted_cell_text.dart';
import 'cell/heading/heading_cells.dart'
    show
        ColumnHeaderCell,
        HeaderCornerCell,
        RowNumberCell,
        kDefaultColumnWidth,
        kDefaultRowHeight,
        kFrozenDividerThickness,
        kGutterWidth,
        kHeaderHeight,
        kMaxFrozenFraction,
        kMinFilterButtonColumnWidth;
import 'cell/heading/util.dart';
import 'data_sheet_clipboard.dart';
import 'data_sheet_control_scheme.dart';
import 'data_sheet_controller.dart';
import 'filter/column_filter_popover.dart';
import 'formula_bar.dart';
import 'selection_gestures.dart';
import 'view/frozen_pane_divider.dart';
import 'view/linked_scroll_controllers.dart';

/// A spreadsheet grid over a `DataSheetController`: scrolling, selection, inline editing, and resizable rows and
/// columns.
///
/// Selection is a rectangle anchored at the highlighted cell: Shift+arrows,
/// Shift+click, a mouse drag, or a long-press drag on touch grows it, and a
/// column or row header click selects that whole column or row. Range cells
/// are tinted from the theme's primary color (which `QuarkTheme` derives from
/// `QuarkTokens.primary`), and the anchor keeps the strong outline.
///
/// Drag a column header's right edge or a row number's bottom edge to resize
/// it, and double-click the edge to fit the content. A selected header's edge
/// grows a touch-sized grip, so on a phone: tap the header, then drag the
/// grip. Every resize is one undo step.
///
/// Copy, cut, paste, Delete and fill act on the whole selected range, each as
/// one undo step. Copied cells go to [clipboard] as tab-separated text, the
/// format Google Sheets and Excel use, so cells paste between them.
///
/// Each column header carries a funnel that opens the column's filter
/// popover. Rows the filters hide are left out of the grid, the rest keep
/// their row numbers, and the arrow keys step over hidden rows. A filtered
/// column's header is tinted and its funnel filled.
///
/// The controller's `frozenRows` and `frozenColumns` pin that many rows and
/// columns, with the column headers and row numbers, while the rest scrolls;
/// a divider in the theme's outline color marks the edge. Frozen panes never
/// cover more than [kMaxFrozenFraction] of the grid.
///
/// Each cell draws its `CellFormat`: bold, italic, text color, fill,
/// alignment, and its number format, which changes only the text shown.
///
/// Keys: cells are `r<row>c<col>`, column headers `col_header_<col>`, their
/// filter buttons `col_filter_<col>`, row
/// numbers `row_num_<row>`, resize handles `col_resize_<col>` and
/// `row_resize_<row>`, and the freeze dividers `frozen_rows_divider` and
/// `frozen_columns_divider`.
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

  /// Where copy and cut write and paste reads. Defaults to
  /// [DataSheetClipboard.memory], which stays inside the app; pass one backed
  /// by the system clipboard to paste to and from other apps.
  final DataSheetClipboard? clipboard;

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
    this.clipboard,
  });

  DataSheet.unnamed({super.key})
      : table = DataTable([]),
        beforeCellValueChanged = null,
        afterCellValueChanged = null,
        controller = null,
        columnWidths = null,
        controlScheme = null,
        showHeadings = true,
        showFormulaBar = true,
        clipboard = null;

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
      clipboard: clipboard,
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
  final DataSheetClipboard? clipboard;

  const _DataSheetView({
    required this.table,
    this.controller,
    this.columnWidths,
    this.beforeCellValueChanged,
    this.afterCellValueChanged,
    this.controlScheme,
    this.showHeadings = true,
    this.showFormulaBar = true,
    this.clipboard,
  });

  @override
  State<_DataSheetView> createState() => _DataSheetViewState();
}

class _DataSheetViewState extends State<_DataSheetView> {
  late final FocusNode keyboardFocus;
  late final DataSheetController controller;
  late final bool _ownsController;

  /// The header strip (first) and the body (second), scrolled sideways
  /// together.
  final LinkedScrollControllers _horizontalScroll = LinkedScrollControllers();

  /// The frozen columns (first) and the body (second), scrolled up and down
  /// together.
  final LinkedScrollControllers _verticalScroll = LinkedScrollControllers();
  final GlobalKey _gridBodyKey = GlobalKey();
  String _priorCellValue = '';

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
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
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
          _clipboard.copySelection(controller);
          return KeyEventResult.handled;
        }
        if (m(scheme.cut)) {
          _clipboard.cutSelection(controller);
          return KeyEventResult.handled;
        }
        if (m(scheme.paste)) {
          _clipboard.pasteIntoSelection(controller);
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

        if (m(scheme.selectAll)) {
          _selectAll();
          return KeyEventResult.handled;
        }

        // Shift+arrow range extension, checked before the plain arrows.
        if (m(scheme.extendUp)) {
          _extendBy(-1, 0);
          return KeyEventResult.handled;
        }
        if (m(scheme.extendDown)) {
          _extendBy(1, 0);
          return KeyEventResult.handled;
        }
        if (m(scheme.extendLeft)) {
          _extendBy(0, -1);
          return KeyEventResult.handled;
        }
        if (m(scheme.extendRight)) {
          _extendBy(0, 1);
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
          final range = controller.selection.range;
          if (range != null) controller.clearRange(range);
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
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Column(
            children: [
              // ── Formula bar ─────────────────────────────────────────
              if (widget.showFormulaBar)
                DataSheetFormulaBar(controller: controller),
              // ── Grid ────────────────────────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildGrid(context, constraints.biggest),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The grid in four panes: frozen corner, frozen rows, frozen columns, and
  /// the body, which scrolls both ways and carries the frozen rows sideways
  /// and the frozen columns up and down with it.
  Widget _buildGrid(BuildContext context, Size size) {
    final fr = controller.frozenRows;
    final fc = controller.frozenColumns;
    final cols = controller.colCount;
    // Frozen rows are never hidden, so the scrolling pane gets the rest.
    final body = [
      for (final r in controller.visibleRows)
        if (r >= fr) r,
    ];
    final fullLeft = _gutterWidth + _span(0, fc, _colWidth);
    final fullTop = _headerHeight + _span(0, fr, _rowHeight);
    final (:left, :top) = _frozenExtent(size);
    final rightWidth = math.max(_span(fc, cols, _colWidth), size.width - left);

    // A frozen pane wider or taller than its share of the grid is clipped.
    Widget clipWidth(Widget child) => SizedBox(
          width: left,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: fullLeft,
              maxWidth: fullLeft,
              child: child,
            ),
          ),
        );

    Widget row(int r, {required bool frozenSide}) =>
        ValueListenableBuilder<List<DataCell>>(
          valueListenable: controller.rowNotifier(r),
          builder: (context, rowCells, _) => frozenSide
              ? _buildDataRow(context, r, rowCells, 0, fc, gutter: true)
              : _buildDataRow(context, r, rowCells, fc, cols),
        );

    return Listener(
      // Intercept horizontal pointer scroll events and consume them via the
      // PointerSignalResolver so the browser never sees them as back/forward
      // navigation gestures (macOS trackpad two-finger swipe).
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent && event.scrollDelta.dx != 0) {
          GestureBinding.instance.pointerSignalResolver.register(event, (
            PointerSignalEvent e,
          ) {
            final dx = (e as PointerScrollEvent).scrollDelta.dx;
            final body = _horizontalScroll.second;
            if (!body.hasClients) return;
            final pos = body.position;
            body.jumpTo((pos.pixels + dx).clamp(0.0, pos.maxScrollExtent));
          });
        }
      },
      child: Stack(
        children: [
          DataSheetSelectionGestures(
            enabled: activeRow < 0,
            cellAt: _cellAtGlobal,
            onRangeStart: _startRange,
            onRangeExtend: _extendRangeTo,
            child: Column(
              key: _gridBodyKey,
              children: [
                // ── Column headers and frozen rows ──────────────────
                SizedBox(
                  height: top,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: fullTop,
                      maxHeight: fullTop,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          clipWidth(
                            Column(
                              children: [
                                if (widget.showHeadings)
                                  _buildHeaderRow(0, fc, corner: true),
                                for (var r = 0; r < fr; r++)
                                  row(r, frozenSide: true),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _horizontalScroll.first,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: rightWidth,
                                child: Column(
                                  children: [
                                    if (widget.showHeadings)
                                      _buildHeaderRow(fc, cols),
                                    for (var r = 0; r < fr; r++)
                                      row(r, frozenSide: false),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Row numbers, frozen columns, and the body ───────
                Expanded(
                  child: Row(
                    children: [
                      clipWidth(
                        ListView.builder(
                          controller: _verticalScroll.first,
                          itemCount: body.length,
                          itemBuilder: (context, i) =>
                              row(body[i], frozenSide: true),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _horizontalScroll.second,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: rightWidth,
                            child: ListView.builder(
                              controller: _verticalScroll.second,
                              itemCount: body.length,
                              itemBuilder: (context, i) =>
                                  row(body[i], frozenSide: false),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (fr > 0)
            Positioned(
              key: const ValueKey('frozen_rows_divider'),
              left: 0,
              right: 0,
              top: top - kFrozenDividerThickness / 2,
              height: kFrozenDividerThickness,
              child: const FrozenPaneDivider(axis: Axis.horizontal),
            ),
          if (fc > 0)
            Positioned(
              key: const ValueKey('frozen_columns_divider'),
              top: 0,
              bottom: 0,
              left: left - kFrozenDividerThickness / 2,
              width: kFrozenDividerThickness,
              child: const FrozenPaneDivider(axis: Axis.vertical),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layout helpers
  // ---------------------------------------------------------------------------

  double _colWidth(int c) => c < controller.columnWidths.length
      ? controller.columnWidths[c]
      : kDefaultColumnWidth;

  double _rowHeight(int r) => r < controller.rowHeights.length
      ? controller.rowHeights[r]
      : kDefaultRowHeight;

  double get _gutterWidth => widget.showHeadings ? kGutterWidth : 0.0;

  double get _headerHeight => widget.showHeadings ? kHeaderHeight : 0.0;

  /// The total of [size] over indexes [from] (inclusive) to [to] (exclusive).
  double _span(int from, int to, double Function(int) size) {
    var total = 0.0;
    for (var i = from; i < to; i++) {
      total += size(i);
    }
    return total;
  }

  /// How far the frozen panes reach into a grid of [size]: the left edge of
  /// the scrolling columns and the top edge of the scrolling rows.
  ({double left, double top}) _frozenExtent(Size size) => (
        left: math.min(
          _gutterWidth + _span(0, controller.frozenColumns, _colWidth),
          size.width * kMaxFrozenFraction,
        ),
        top: math.min(
          _headerHeight + _span(0, controller.frozenRows, _rowHeight),
          size.height * kMaxFrozenFraction,
        ),
      );

  /// The cell under [global], clamped to the sheet's edges so a drag past
  /// the last row or column selects up to it. Hidden rows are skipped.
  ({int row, int col})? _cellAtGlobal(Offset global) {
    final box = _gridBodyKey.currentContext?.findRenderObject() as RenderBox?;
    final visible = controller.visibleRows;
    if (box == null || visible.isEmpty || controller.colCount == 0) {
      return null;
    }
    final local = box.globalToLocal(global);
    final (:left, :top) = _frozenExtent(box.size);
    double offset(ScrollController c) => c.hasClients ? c.offset : 0.0;

    // Before [paneEnd] a position falls among the [frozen] indexes, measured
    // from [lead]; past it, among the [scrolling] ones, shifted by [scroll].
    int indexAt(
      double pos, {
      required double paneEnd,
      required double lead,
      required List<int> frozen,
      required List<int> scrolling,
      required double scroll,
      required double Function(int) size,
    }) {
      final inFrozen = frozen.isNotEmpty && pos < paneEnd || scrolling.isEmpty;
      final indexes = inFrozen ? frozen : scrolling;
      var edge = inFrozen ? lead : paneEnd - scroll;
      for (final i in indexes) {
        edge += size(i);
        if (pos < edge) return i;
      }
      return indexes.last;
    }

    final fr = controller.frozenRows;
    final fc = controller.frozenColumns;
    return (
      row: indexAt(
        local.dy,
        paneEnd: top,
        lead: _headerHeight,
        frozen: visible.take(fr).toList(),
        scrolling: visible.skip(fr).toList(),
        scroll: offset(_verticalScroll.second),
        size: _rowHeight,
      ),
      col: indexAt(
        local.dx,
        paneEnd: left,
        lead: _gutterWidth,
        frozen: List.generate(fc, (c) => c),
        scrolling: [for (var c = fc; c < controller.colCount; c++) c],
        scroll: offset(_horizontalScroll.second),
        size: _colWidth,
      ),
    );
  }

  /// Column headers [from] (inclusive) to [to] (exclusive), led by the corner
  /// cell when [corner].
  Widget _buildHeaderRow(int from, int to, {bool corner = false}) {
    final shown = controller.visibleRows.length;
    return Row(
      children: [
        if (corner) const HeaderCornerCell(),
        for (var c = from; c < to; c++)
          SizedBox(
            width: _colWidth(c),
            child: ColumnHeaderCell(
              key: ValueKey('col_header_$c'),
              resizeHandleKey: ValueKey('col_resize_$c'),
              filterButtonKey: ValueKey('col_filter_$c'),
              label: columnLabel(c),
              isSelected: controller.selection.range?.containsCol(c) ?? false,
              isFiltered: controller.filterFor(c) != null,
              filterTooltip: controller.filterFor(c) != null
                  ? 'Column ${columnLabel(c)} is filtered: '
                      '$shown of ${controller.rowCount} rows shown'
                  : 'Filter column ${columnLabel(c)}',
              onFilter: controller.filterFor(c) != null ||
                      _colWidth(c) >= kMinFilterButtonColumnWidth
                  ? (anchor) => _openFilter(c, anchor)
                  : null,
              onSelect: () => _selectColumn(c),
              onResizeStart: controller.beginResize,
              onResizeDelta: (delta) {
                controller.setColumnWidth(c, _colWidth(c) + delta);
              },
              onAutoSize: () => controller.autoSizeColumn(
                c,
                textStyle: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }

  /// Row [r]'s cells [from] (inclusive) to [to] (exclusive), led by its row
  /// number when [gutter] and headings are shown.
  Widget _buildDataRow(
    BuildContext context,
    int r,
    List<DataCell> rowCells,
    int from,
    int to, {
    bool gutter = false,
  }) {
    final rowHeight = _rowHeight(r);
    return Row(
      children: [
        if (gutter && widget.showHeadings)
          RowNumberCell(
            key: ValueKey('row_num_$r'),
            resizeHandleKey: ValueKey('row_resize_$r'),
            number: r + 1,
            height: rowHeight,
            isSelected: controller.selection.range?.containsRow(r) ?? false,
            onSelect: () => _selectRow(r),
            onResizeStart: controller.beginResize,
            onResizeDelta: (delta) {
              controller.setRowHeight(r, rowHeight + delta);
            },
            onAutoSize: () => controller.autoSizeRow(
              r,
              textStyle: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ...List.generate(math.min(to, rowCells.length) - from, (i) {
          final c = from + i;
          final isActiveCell = (r == activeRow && c == activeCol);
          final isHighlightedCell =
              (r == highlightedRow && c == highlightedCol);
          final colWidth = _colWidth(c);
          final format = controller.formatAt(r, c);

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
              : FormattedCellText(
                  text: controller.formattedValueAt(r, c),
                  format: format,
                  isError: controller.isCellError(r, c),
                );

          final cell = Cell(
            key: ValueKey('r${r}c$c'),
            isActive: isActiveCell,
            isHighlighted: isHighlightedCell,
            isInRange: controller.selection.isInRange(r, c),
            cursor: isActiveCell
                ? SystemMouseCursors.text
                : SystemMouseCursors.cell,
            height: rowHeight,
            referenceColor: controller.activeRefColors[(r, c)],
            fillColor:
                format.fillColor == null ? null : Color(format.fillColor!),
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
                      } else if (_shiftExtends) {
                        controller.selection.extendTo(r, c);
                        keyboardFocus.requestFocus();
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

  DataSheetClipboard get _clipboard =>
      widget.clipboard ?? DataSheetClipboard.memory;

  void _fillDown() {
    final range = controller.selection.contextRange;
    if (range != null) controller.fillDownRange(range);
  }

  void _fillRight() {
    final range = controller.selection.contextRange;
    if (range != null) controller.fillRightRange(range);
  }

  void _jumpToFirst() {
    final rows = controller.visibleRows;
    if (rows.isEmpty || controller.colCount == 0) return;
    controller.selection.goTo(rows.first, 0);
  }

  void _jumpToLast() {
    final rows = controller.visibleRows;
    if (rows.isEmpty || controller.colCount == 0) return;
    controller.selection.goTo(rows.last, controller.colCount - 1);
  }

  /// Opens column [c]'s filter popover beside [anchor], committing any edit
  /// first.
  void _openFilter(int c, Rect anchor) {
    _commitEdit();
    showColumnFilterPopover(
      context: context,
      controller: controller,
      column: c,
      anchor: anchor,
    );
  }

  void _insertRow() {
    final row = controller.selection.contextRow;
    if (row < 0) return;
    controller.insertRowAt(row);
  }

  void _deleteRow() {
    final range = controller.selection.contextRange;
    if (range == null) return;
    controller.deleteRowAt(range.top, count: range.rowCount);
  }

  void _insertColumn() {
    final col = controller.selection.contextCol;
    if (col < 0) return;
    controller.insertColumnAt(col);
  }

  void _deleteColumn() {
    final range = controller.selection.contextRange;
    if (range == null) return;
    controller.deleteColumnAt(range.left, count: range.colCount);
  }

  /// True when Shift is held and there is an anchor to extend from.
  bool get _shiftExtends =>
      HardwareKeyboard.instance.isShiftPressed &&
      controller.selection.hasHighlight;

  void _startRange(int r, int c) {
    if (_shiftExtends) {
      controller.selection.extendTo(r, c);
    } else {
      controller.selection.setHighlighted(r, c);
    }
    keyboardFocus.requestFocus();
  }

  void _extendRangeTo(int r, int c) {
    final sel = controller.selection;
    if (sel.extentRow == r && sel.extentCol == c) return;
    sel.extendTo(r, c);
  }

  void _extendBy(int dRow, int dCol) {
    final sel = controller.selection;
    if (!sel.hasHighlight) return;
    sel.extendTo(
      dRow == 0
          ? sel.extentRow
          : controller.nextVisibleRow(sel.extentRow, dRow),
      (sel.extentCol + dCol).clamp(0, controller.colCount - 1),
    );
  }

  void _selectAll() {
    if (controller.rowCount == 0 || controller.colCount == 0) return;
    controller.selection.selectRange(
      0,
      0,
      controller.rowCount - 1,
      controller.colCount - 1,
    );
  }

  /// Commits any edit in progress before a header click changes selection.
  void _commitEdit() {
    if (activeRow >= 0 && activeCol >= 0) {
      _storeCellValue(controller.activeCellEditingController.text);
    }
  }

  /// Selects column [c] top to bottom; with Shift, every column from the
  /// anchor's to [c].
  void _selectColumn(int c) {
    if (controller.rowCount == 0) return;
    _commitEdit();
    final anchorCol = _shiftExtends ? highlightedCol : c;
    controller.selection.selectRange(0, anchorCol, controller.rowCount - 1, c);
    keyboardFocus.requestFocus();
  }

  /// Selects row [r] end to end; with Shift, every row from the anchor's to
  /// [r].
  void _selectRow(int r) {
    if (controller.colCount == 0) return;
    _commitEdit();
    final anchorRow = _shiftExtends ? highlightedRow : r;
    controller.selection.selectRange(anchorRow, 0, r, controller.colCount - 1);
    keyboardFocus.requestFocus();
  }

  void _moveUp() => _moveVertically(-1);

  void _moveDown() => _moveVertically(1);

  /// Moves the highlight to the next visible row in direction [step].
  void _moveVertically(int step) {
    if (highlightedRow < 0) return;
    final row = controller.nextVisibleRow(highlightedRow, step);
    if (row != highlightedRow) {
      controller.selection.setHighlighted(row, highlightedCol);
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
