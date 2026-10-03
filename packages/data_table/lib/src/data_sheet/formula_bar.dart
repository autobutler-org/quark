import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide DataCell;
import 'package:flutter/services.dart';
import 'package:quark_formula/evaluation/evaluation.dart'
    show lex, parseTokens, ParsedFormula, Token, TokenKind;

import '../../data_table.dart';
import 'cell/heading/heading_cells.dart' show kResizeHandleSize;
import 'cell/heading/util.dart';
import 'data_sheet_controller.dart';

/// Palette of colors used to color-code cell references in formula editing.
/// Ordered in repeating ROYGBIV-style cycles for better visual alternation.
const _kRefPalette = [
  // Cycle 1: R O Y G B I V
  Color(0xFFD00000), // red
  Color(0xFFFF7B00), // vivid orange
  Color(0xFFAACC00), // chartreuse
  Color(0xFF2B9348), // green
  Color(0xFF4361EE), // blue
  Color(0xFF3A0CA3), // indigo
  Color(0xFF7B2CBF), // violet
  // Cycle 2: R O Y G B I V
  Color(0xFFE63946), // vermilion
  Color(0xFFBB3E03), // rust
  Color(0xFFE9D8A6), // sand
  Color(0xFF4C956C), // leaf green
  Color(0xFF4895EF), // sky blue
  Color(0xFF3F37C9), // royal blue
  Color(0xFF5A189A), // purple
  // Cycle 3: R O Y G B I V
  Color(0xFFAE2012), // brick red
  Color(0xFFCA6702), // burnt orange
  Color(0xFFEE9B00), // amber
  Color(0xFF55A630), // yellow green
  Color(0xFF4CC9F0), // light cyan
  Color(0xFF1D3557), // navy
  Color(0xFFB5179E), // magenta
  // Remaining colors in continued warm→cool passes.
  Color(0xFF9B2226), // wine red
  Color(0xFF80B918), // lime olive
  Color(0xFF70E000), // bright lime
  Color(0xFF118AB2), // cyan blue
  Color(0xFF005F73), // deep cyan
  Color(0xFF9EF01A), // neon lime
  Color(0xFF457B9D), // slate blue
  Color(0xFF006D77), // deep teal
  Color(0xFF94D2BD), // seafoam
  Color(0xFF0A9396), // cyan teal
  Color(0xFF06D6A0), // mint
];

/// A [TextEditingController] that renders cell/range reference tokens in the
/// formula bar using the same palette colors assigned to the grid borders.
///
/// Call [setTokenColors] with a map of `{refString -> Color}` whenever the
/// parse result changes; call [clearTokenColors] when editing ends.
class _FormulaTextEditingController extends TextEditingController {
  /// Maps a normalized reference string (e.g. "A1" or "A1:C3") to its color.
  Map<String, Color> _tokenColors = {};

  void setTokenColors(Map<String, Color> colors) {
    _tokenColors = colors;
    notifyListeners();
  }

  void clearTokenColors() {
    if (_tokenColors.isEmpty) return;
    _tokenColors = {};
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final formula = text;
    if (_tokenColors.isEmpty || !formula.startsWith('=')) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }

    // Lex the formula to get token positions.
    List<Token> tokens;
    try {
      tokens = lex(formula).toList();
    } catch (_) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }

    // The lexer strips the leading '=' before tokenizing, so all token
    // offsets are relative to the formula-without-'='. Add 1 to each
    // offset when mapping back into the full formula bar text.
    final shift = formula.startsWith('=') ? 1 : 0;

    // Build a list of (start, end, color?) spans from the token stream.
    // Adjacent cellRef tokens separated only by a colon are treated as a
    // range ref and colored with the range's assigned color.
    final spans = <TextSpan>[];
    var cursor = 0;

    for (var i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      if (tok.kind == TokenKind.eof) break;
      if (tok.kind != TokenKind.cellRef) continue;

      final refStart = tok.offset + shift;
      final refValue = tok.value; // e.g. "A1" (already normalized)

      // Check if followed by colon + cellRef (range ref).
      String? rangeKey;
      int refEnd = _tokenSrcEnd(formula, refStart);

      if (i + 1 < tokens.length && tokens[i + 1].kind != TokenKind.eof) {
        // If this cellRef is immediately followed by a colon token then
        // another cellRef, it's a range reference.
        if (i + 2 < tokens.length &&
            tokens[i + 1].kind == TokenKind.colon &&
            tokens[i + 2].kind == TokenKind.cellRef) {
          final endTok = tokens[i + 2];
          rangeKey = '${tok.value}:${endTok.value}';
          refEnd = _tokenSrcEnd(formula, endTok.offset + shift);
          // Try to find the range color; fall back to first-cell color.
          final color = _tokenColors[rangeKey] ?? _tokenColors[tok.value];
          if (color != null) {
            // Emit unstyled text before this span.
            if (refStart > cursor) {
              spans.add(TextSpan(
                  text: formula.substring(cursor, refStart), style: style));
            }
            // Compute actual source end (account for '$' in original).
            final srcEnd = (refEnd <= formula.length) ? refEnd : formula.length;
            spans.add(TextSpan(
              text: formula.substring(refStart, srcEnd),
              style: (style ?? const TextStyle()).copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ));
            cursor = srcEnd;
          }
          i += 2; // skip colon + end cellRef
          continue;
        }
      }

      // Single cell ref.
      final color = _tokenColors[refValue];
      if (color != null) {
        if (refStart > cursor) {
          spans.add(TextSpan(
              text: formula.substring(cursor, refStart), style: style));
        }
        final srcEnd = (refEnd <= formula.length) ? refEnd : formula.length;
        spans.add(TextSpan(
          text: formula.substring(refStart, srcEnd),
          style: (style ?? const TextStyle()).copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ));
        cursor = srcEnd;
      }
    }

    // Remaining text after last colored span.
    if (cursor < formula.length) {
      spans.add(TextSpan(text: formula.substring(cursor), style: style));
    }

    if (spans.isEmpty) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }

    return TextSpan(children: spans);
  }

  /// Returns the index just past the end of a cell-ref lexeme starting at
  /// [from] in [source]. The lexer normalizes token values (strips `$`,
  /// uppercases), so `tok.value.length` is unreliable for source offsets;
  /// this walks the raw source instead.
  static int _tokenSrcEnd(String source, int from) {
    var j = from;
    while (j < source.length) {
      final c = source.codeUnitAt(j);
      // Allow $, A–Z, a–z, 0–9
      if (c == 36 ||
          (c >= 65 && c <= 90) ||
          (c >= 97 && c <= 122) ||
          (c >= 48 && c <= 57)) {
        j++;
      } else {
        break;
      }
    }
    return j;
  }
}

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
  late final _FormulaTextEditingController _barCtrl;
  late final FocusNode _focusNode;

  static const double _minHeight = 32.0;
  double _height = 32.0;
  bool _handleHovered = false;

  /// Raw cell value captured when the bar gains focus — used to restore on Escape.
  String _priorValue = '';

  /// Debounce timer for live reference highlighting.
  Timer? _refHighlightTimer;

  /// True while a ref-highlight update is in-flight (microtask scheduled or
  /// running). Prevents the notifyListeners triggered by setActiveRefColors
  /// from scheduling another microtask and looping forever.
  bool _highlightUpdatePending = false;

  /// Key used to measure the available width of the text field area for
  /// auto-sizing.
  final GlobalKey _fieldKey = GlobalKey();

  /// Prevents the active-cell-controller listener from overwriting the bar
  /// while the bar itself is pushing a change into that controller.
  bool _suppressActiveCellSync = false;

  DataSheetController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _barCtrl = _FormulaTextEditingController();
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // Shift+Enter → insert a newline (same as Shift+Enter in the grid cell editor).
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isShiftPressed) {
          final sel = _barCtrl.selection;
          final text = _barCtrl.text;
          final before = text.substring(0, sel.start < 0 ? 0 : sel.start);
          final after = text.substring(sel.end < 0 ? 0 : sel.end);
          final newText = '$before\n$after';
          _barCtrl.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: before.length + 1),
          );
          _onBarChanged(newText);
          return KeyEventResult.handled;
        }
        // Enter → commit the cell (same as pressing Enter in the grid cell editor).
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _commitIfActive();
          _focusNode.unfocus();
          return KeyEventResult.handled;
        }
        // Escape → cancel, restore prior value.
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEdit();
          _focusNode.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _controller.addListener(_onControllerChanged);
    _controller.activeCellEditingController
        .addListener(_onActiveCellTextChanged);
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
    _refHighlightTimer?.cancel();
    _controller.clearActiveRefColors();
    _barCtrl.clearTokenColors();
    _controller.removeListener(_onControllerChanged);
    _controller.activeCellEditingController
        .removeListener(_onActiveCellTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _barCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sync helpers
  // ---------------------------------------------------------------------------

  void _onControllerChanged() {
    // Don't overwrite the bar while the user is actively typing in it.
    if (_focusNode.hasFocus) return;
    _syncBarFromController();
  }

  void _onActiveCellTextChanged() {
    if (_suppressActiveCellSync) return;
    // Don't overwrite the bar while the user is typing in it.
    if (_focusNode.hasFocus) return;
    final newText = _controller.activeCellEditingController.text;
    if (_barCtrl.text != newText) {
      _barCtrl.text = newText;
    }
  }

  /// Reads the canonical cell value from the controller and updates the bar.
  void _syncBarFromController() {
    final sel = _controller.selection;
    final r = sel.contextRow;
    final c = sel.contextCol;
    if (r < 0 || c < 0) {
      if (_barCtrl.text.isNotEmpty) _barCtrl.clear();
      _barCtrl.clearTokenColors();
      // Defer the controller notify call so we don't call notifyListeners
      // while already inside a notifyListeners dispatch.
      _scheduleHighlightUpdate(null);
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
    _scheduleHighlightUpdate(newText);
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
        _suppressActiveCellSync = true;
        _controller.activeCellEditingController.text = value;
        _suppressActiveCellSync = false;
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
      // Lost focus — commit any pending edit.
      _commitIfActive();
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
  // Reference highlighting

  /// Schedule a ref-highlight update for [text] (or a clear when [text] is
  /// null) to run after the current ChangeNotifier dispatch completes.
  ///
  /// All calls that could trigger [setActiveRefColors] / [clearActiveRefColors]
  /// (both of which call [notifyListeners]) must go through here when they
  /// originate from a listener callback, to avoid ChangeNotifier reentrancy.
  void _scheduleHighlightUpdate(String? text) {
    if (_highlightUpdatePending) return;
    _highlightUpdatePending = true;
    Future.microtask(() {
      if (!mounted) {
        _highlightUpdatePending = false;
        return;
      }
      // Keep _highlightUpdatePending = true while the call runs so that
      // the synchronous notifyListeners fired by set/clearActiveRefColors
      // doesn't re-enter and schedule another microtask. Reset only after
      // the call tree completes.
      if (text == null) {
        _controller.clearActiveRefColors();
      } else {
        _updateRefHighlights(text);
      }
      _highlightUpdatePending = false;
    });
  }

  // ---------------------------------------------------------------------------

  /// Parse [formula] and push color assignments for every referenced cell/range
  /// into the controller so the grid can draw colored borders.
  void _updateRefHighlights(String formula) {
    if (!formula.startsWith('=')) {
      _controller.clearActiveRefColors();
      _barCtrl.clearTokenColors();
      return;
    }
    ParsedFormula? parsed;
    try {
      parsed = parseTokens(lex(formula));
    } catch (_) {
      // Incomplete formula while typing — clear highlights silently.
      _controller.clearActiveRefColors();
      _barCtrl.clearTokenColors();
      return;
    }

    final allRefs = <String>{};
    allRefs.addAll(parsed.cellRefs);
    // Expand range refs into individual cell strings for color assignment.
    for (final range in parsed.rangeRefs) {
      final colon = range.indexOf(':');
      if (colon < 0) continue;
      final start = _parseCellRef(range.substring(0, colon));
      final end = _parseCellRef(range.substring(colon + 1));
      if (start == null || end == null) continue;
      final rMin = start.$1 < end.$1 ? start.$1 : end.$1;
      final rMax = start.$1 > end.$1 ? start.$1 : end.$1;
      final cMin = start.$2 < end.$2 ? start.$2 : end.$2;
      final cMax = start.$2 > end.$2 ? start.$2 : end.$2;
      for (var r = rMin; r <= rMax; r++) {
        for (var c = cMin; c <= cMax; c++) {
          // Re-encode as "A1" style so it matches cellRefs keys.
          allRefs.add('${_colLabel(c)}${r + 1}');
        }
      }
    }

    // Assign a palette color per unique top-level reference token.
    // (Cells within a range share the same color as the range token.)
    final tokenColors = <String, Color>{};
    var paletteIdx = 0;
    // First pass: assign colors to top-level tokens (cellRefs + rangeRefs).
    for (final ref in [...parsed.cellRefs, ...parsed.rangeRefs]) {
      if (!tokenColors.containsKey(ref)) {
        tokenColors[ref] = _kRefPalette[paletteIdx % _kRefPalette.length];
        paletteIdx++;
      }
    }

    // Build the (row, col) → Color map for the grid.
    final colors = <(int, int), Color>{};
    for (final ref in parsed.cellRefs) {
      final pos = _parseCellRef(ref);
      if (pos == null) {
        continue;
      }
      if (pos.$1 < 0 ||
          pos.$1 >= _controller.rowCount ||
          pos.$2 < 0 ||
          pos.$2 >= _controller.colCount) {
        continue;
      }
      colors[pos] = tokenColors[ref]!;
    }
    for (final range in parsed.rangeRefs) {
      final colon = range.indexOf(':');
      if (colon < 0) {
        continue;
      }
      final start = _parseCellRef(range.substring(0, colon));
      final end = _parseCellRef(range.substring(colon + 1));
      if (start == null || end == null) {
        continue;
      }
      final color = tokenColors[range]!;
      final rMin = start.$1 < end.$1 ? start.$1 : end.$1;
      final rMax = start.$1 > end.$1 ? start.$1 : end.$1;
      final cMin = start.$2 < end.$2 ? start.$2 : end.$2;
      final cMax = start.$2 > end.$2 ? start.$2 : end.$2;
      for (var r = rMin; r <= rMax; r++) {
        for (var c = cMin; c <= cMax; c++) {
          if (r < 0 ||
              r >= _controller.rowCount ||
              c < 0 ||
              c >= _controller.colCount) {
            continue;
          }
          colors[(r, c)] = color;
        }
      }
    }

    _controller.setActiveRefColors(colors);
    // Push the same ref→color map to the bar controller so it can
    // color-code the reference tokens in the formula text.
    _barCtrl.setTokenColors(tokenColors);
  }

  /// Parses a cell reference like "A1" into zero-based (row, col).
  (int, int)? _parseCellRef(String ref) {
    var splitIdx = 0;
    while (splitIdx < ref.length &&
        (ref.codeUnitAt(splitIdx) >= 65 && ref.codeUnitAt(splitIdx) <= 90 ||
            ref.codeUnitAt(splitIdx) >= 97 &&
                ref.codeUnitAt(splitIdx) <= 122)) {
      splitIdx++;
    }
    if (splitIdx == 0 || splitIdx == ref.length) return null;
    final colText = ref.substring(0, splitIdx).toUpperCase();
    final rowNum = int.tryParse(ref.substring(splitIdx));
    if (rowNum == null || rowNum <= 0) return null;
    var col = 0;
    for (final ch in colText.runes) {
      col = col * 26 + (ch - 64);
    }
    return (rowNum - 1, col - 1);
  }

  /// Encodes a zero-based column index as an Excel column label (A, B, … Z, AA…).
  String _colLabel(int col) {
    var result = '';
    var c = col + 1;
    while (c > 0) {
      final rem = (c - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      c = (c - 1) ~/ 26;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Commit / cancel logic
  // ---------------------------------------------------------------------------

  /// Commit the current bar text to the active cell (same semantics as
  /// pressing Enter in the grid cell editor).
  void _commitIfActive() {
    _refHighlightTimer?.cancel();
    _controller.clearActiveRefColors();
    _barCtrl.clearTokenColors();
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
    _refHighlightTimer?.cancel();
    _controller.clearActiveRefColors();
    _barCtrl.clearTokenColors();
    final sel = _controller.selection;
    final r = sel.activeRow;
    final c = sel.activeCol;
    if (r < 0 || c < 0) return;
    // Restore the value the cell had before editing began.
    _barCtrl.text = _priorValue;
    _suppressActiveCellSync = true;
    _controller.activeCellEditingController.text = _priorValue;
    _suppressActiveCellSync = false;
    // Leave cell highlighted but not active.
    _controller.selection.goTo(r, c);
  }

  // ---------------------------------------------------------------------------
  // Bar text change
  // ---------------------------------------------------------------------------

  void _onBarChanged(String value) {
    if (!_focusNode.hasFocus) return;
    final sel = _controller.selection;
    if (!sel.hasActiveCell) return;
    // Mirror bar text into the shared active-cell controller so the cell
    // editor (if visible) stays in sync.
    _suppressActiveCellSync = true;
    _controller.activeCellEditingController.text = value;
    _suppressActiveCellSync = false;
    // Debounce reference highlighting — update ~150 ms after typing stops.
    _refHighlightTimer?.cancel();
    _refHighlightTimer = Timer(const Duration(milliseconds: 150), () {
      _updateRefHighlights(value);
    });
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

        return Stack(
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
                        child: TextField(
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
                          onChanged: _onBarChanged,
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
      },
    );
  }
}
