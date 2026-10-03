import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide DataCell;
import 'package:flutter/services.dart';

import '../../data_table.dart';
import 'cell/heading/heading_cells.dart' show kResizeHandleSize;
import 'cell/heading/util.dart';
import 'data_sheet_controller.dart';
import 'formula/formula_autocomplete.dart';
import 'formula/formula_bar_error_note.dart';
import 'formula/formula_text_editing_controller.dart';

/// A formula bar companion for [DataSheetController].
///
/// Displays the current cell address (e.g. `A1`) in a fixed-width name box
/// on the left and the cell value in an editable text field on the right,
/// matching the layout used in Excel and Google Sheets.
///
/// Place it between [DataSheetControlBar] and [DataSheet]:
///
/// ```dart
/// Column(children: [
///   DataSheetControlBar(controller: myController),
///   DataSheetFormulaBar(controller: myController),
///   Expanded(child: DataSheet(controller: myController, table: myTable)),
/// ])
/// ```
///
/// Bidirectional sync:
/// - While the grid cell is being edited the bar mirrors every keystroke via
///   the shared [DataSheetController.activeCellEditingController].
/// - Typing in the bar pushes text back into that shared controller so the
///   active cell editor stays in sync.
/// - Pressing Enter (or losing focus) commits the value.
class DataSheetFormulaBar extends StatefulWidget {
  final DataSheetController controller;

  const DataSheetFormulaBar({super.key, required this.controller});

  @override
  State<DataSheetFormulaBar> createState() => _DataSheetFormulaBarState();
}

class _DataSheetFormulaBarState extends State<DataSheetFormulaBar> {
  final FormulaTextEditingController _barCtrl = FormulaTextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const double _minHeight = 32.0;
  double _height = 32.0;
  bool _handleHovered = false;

  /// Raw cell value captured when the bar gains focus — used to restore on Escape.
  String _priorValue = '';

  /// Key used to measure the available width of the text field area for
  /// auto-sizing.
  final GlobalKey _fieldKey = GlobalKey();

  /// True while the bar and the shared active-cell controller are being
  /// copied into each other, so neither copy echoes back.
  bool _syncing = false;

  DataSheetController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.activeCellEditingController
        .addListener(_onActiveCellTextChanged);
    _barCtrl.addListener(_onBarValueChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(DataSheetFormulaBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      oldWidget.controller.activeCellEditingController
          .removeListener(_onActiveCellTextChanged);
      _controller.addListener(_onControllerChanged);
      _controller.activeCellEditingController
          .addListener(_onActiveCellTextChanged);
      _syncBarFromController();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.activeCellEditingController
        .removeListener(_onActiveCellTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _barCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Enter commits and Escape cancels, as in the grid's cell editor;
  /// Shift+Enter inserts a newline. The function autocomplete inside sees
  /// these keys first while its list is open.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isShiftPressed) {
      final sel = _barCtrl.selection;
      final text = _barCtrl.text;
      final before = text.substring(0, sel.start < 0 ? 0 : sel.start);
      final after = text.substring(sel.end < 0 ? 0 : sel.end);
      _barCtrl.value = TextEditingValue(
        text: '$before\n$after',
        selection: TextSelection.collapsed(offset: before.length + 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _commitIfActive();
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelEdit();
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Sync helpers
  // ---------------------------------------------------------------------------

  void _onControllerChanged() {
    // Don't overwrite the bar while the user is actively typing in it.
    if (_focusNode.hasFocus) return;
    _syncBarFromController();
  }

  /// Copies the shared active-cell text into the bar. While the bar has
  /// focus the caret comes too, so a reference picked from the grid lands
  /// where the bar's caret was and leaves it after the reference.
  void _onActiveCellTextChanged() {
    if (_syncing) return;
    final active = _controller.activeCellEditingController.value;
    _syncing = true;
    if (!_focusNode.hasFocus) {
      if (_barCtrl.text != active.text) _barCtrl.text = active.text;
    } else if (_barCtrl.value != active) {
      _barCtrl.value = active.selection.isValid
          ? active
          : active.copyWith(
              selection: TextSelection.collapsed(offset: active.text.length),
            );
    }
    _syncing = false;
  }

  /// Copies the bar's text and caret into the shared active-cell controller
  /// while the bar is the editor, so the cell editor shows what is typed and
  /// a reference picked from the grid goes at the bar's caret.
  void _onBarValueChanged() {
    if (_syncing || !_focusNode.hasFocus) return;
    if (!_controller.selection.hasActiveCell) return;
    _syncing = true;
    _controller.activeCellEditingController.value = _barCtrl.value;
    _syncing = false;
  }

  /// Reads the canonical cell value from the controller and updates the bar.
  void _syncBarFromController() {
    final sel = _controller.selection;
    final r = sel.contextRow;
    final c = sel.contextCol;
    if (r < 0 || c < 0) {
      if (_barCtrl.text.isNotEmpty) _barCtrl.clear();
      return;
    }
    // If a cell is actively being edited in the grid, prefer the live text
    // from the shared editing controller rather than the stored cell value.
    final newText = sel.hasActiveCell
        ? _controller.activeCellEditingController.text
        : _controller.cellAt(r, c).value;
    if (_barCtrl.text != newText) {
      _barCtrl.text = newText;
    }
  }

  // ---------------------------------------------------------------------------
  // Focus handling
  // ---------------------------------------------------------------------------

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // When the bar gains focus, put the highlighted cell into edit mode so
      // that keystrokes in the bar are reflected in the grid cell.
      final sel = _controller.selection;
      if (!sel.hasActiveCell && sel.hasHighlight) {
        final r = sel.highlightedRow;
        final c = sel.highlightedCol;
        final value = _controller.cellAt(r, c).value;
        _priorValue = value;
        _syncing = true;
        _controller.activeCellEditingController.text = value;
        _syncing = false;
        _controller.selection.setActive(r, c);
        // Move cursor to end of text in the bar.
        _barCtrl.selection =
            TextSelection.collapsed(offset: _barCtrl.text.length);
      } else if (sel.hasActiveCell) {
        // Cell was already active — snapshot the current raw value for Escape.
        final r = sel.activeRow;
        final c = sel.activeCol;
        _priorValue = _controller.cellAt(r, c).value;
      }
    } else {
      // Lost focus — commit any pending edit, then show what was stored.
      _commitIfActive();
      _syncBarFromController();
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-size
  // ---------------------------------------------------------------------------

  /// Resize the bar height to tightly fit the current text content.
  void _autoSize() {
    final text = _barCtrl.text;
    if (text.isEmpty) {
      setState(() => _height = _minHeight);
      return;
    }
    // Determine available width from the rendered text field container.
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldWidth = box?.size.width ?? 200.0;
    // Overhead: 4px horizontal padding each side + 1px border = 10px per side.
    const horizontalOverhead = 20.0;
    const verticalOverhead = 12.0; // top+bottom padding inside the bar
    final textStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout(
        maxWidth:
            (fieldWidth - horizontalOverhead).clamp(1.0, double.infinity));
    final needed =
        (tp.height + verticalOverhead).clamp(_minHeight, double.infinity);
    setState(() => _height = needed);
  }

  // ---------------------------------------------------------------------------
  // Commit / cancel logic
  // ---------------------------------------------------------------------------

  /// Commit the current bar text to the active cell (same semantics as
  /// pressing Enter in the grid cell editor).
  void _commitIfActive() {
    final sel = _controller.selection;
    final r = sel.activeRow;
    final c = sel.activeCol;
    if (r < 0 || c < 0) return;
    _controller.updateCell(r, c, DataCell(_barCtrl.text));
    _controller.activeCellEditingController.clear();
    _controller.selection.goTo(r, c);
  }

  /// Cancel the current edit — restore the prior raw value and leave the cell
  /// highlighted but not active (same as pressing Escape in the grid editor).
  void _cancelEdit() {
    final sel = _controller.selection;
    final r = sel.activeRow;
    final c = sel.activeCol;
    if (r < 0 || c < 0) return;
    // Restore the value the cell had before editing began.
    _barCtrl.text = _priorValue;
    _syncing = true;
    _controller.activeCellEditingController.text = _priorValue;
    _syncing = false;
    // Leave cell highlighted but not active.
    _controller.selection.goTo(r, c);
  }

  // ---------------------------------------------------------------------------
  // Address label
  // ---------------------------------------------------------------------------

  /// The name box text: the selected range (`B2:D9`, or `B2` for one cell),
  /// or the cell being edited.
  String _cellLabel() {
    final sel = _controller.selection;
    final range = sel.range;
    if (range != null) return range.label;
    final r = sel.contextRow;
    final c = sel.contextCol;
    if (r < 0 || c < 0) return '';
    return '${columnLabel(c)}${r + 1}';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final sel = _controller.selection;
        final hasSelection = sel.contextRow >= 0 && sel.contextCol >= 0;
        final label = _cellLabel();
        final cs = Theme.of(context).colorScheme;
        final dividerColor = Theme.of(context).dividerColor;
        final error = hasSelection
            ? _controller.errorAt(sel.contextRow, sel.contextCol)
            : null;

        final bar = Stack(
          children: [
            SizedBox(
              height: _height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: dividerColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Name box ──────────────────────────────────────────
                    SizedBox(
                      width: 80,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: dividerColor),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Center(
                            // A long range like AA100:AB2000 shrinks to fit
                            // rather than clipping.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                key: const ValueKey('data_sheet_name_box'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ── fx icon ───────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          'fx',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: cs.primary,
                                  ),
                        ),
                      ),
                    ),
                    // ── Divider ───────────────────────────────────────────
                    VerticalDivider(
                        width: 1, thickness: 1, color: dividerColor),
                    // ── Value field ───────────────────────────────────────
                    Expanded(
                      key: _fieldKey,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: _onKey,
                          child: FormulaAutocomplete(
                            controller: _barCtrl,
                            child: Semantics(
                              label: 'Cell contents',
                              child: TextField(
                                key: const ValueKey('data_sheet_formula_field'),
                                controller: _barCtrl,
                                focusNode: _focusNode,
                                enabled: hasSelection,
                                maxLines: null,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Bottom-edge resize handle ──────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: kResizeHandleSize,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                onEnter: (_) => setState(() => _handleHovered = true),
                onExit: (_) => setState(() => _handleHovered = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) {
                    setState(() {
                      _height = (_height + d.delta.dy)
                          .clamp(_minHeight, double.infinity);
                    });
                  },
                  onDoubleTap: _autoSize,
                  child: Container(
                    color: _handleHovered
                        ? cs.primary.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ],
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            if (error != null)
              FormulaBarErrorNote(code: error.code, message: error.message),
          ],
        );
      },
    );
  }
}
