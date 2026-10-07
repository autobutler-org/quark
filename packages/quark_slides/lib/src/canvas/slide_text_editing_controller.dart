import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../controller/slide_document_controller.dart';
import '../geometry/slide_tree.dart';
import '../model/cell_format.dart';
import '../model/cell_range.dart';
import '../model/presentation.dart';
import '../model/rich_text.dart';
import '../model/slide_element.dart';
import '../model/text_format.dart';
import '../model/text_paragraph.dart';
import '../model/unset.dart';
import 'slide_paragraph_editing_controller.dart';
import 'slide_text_layout.dart';

/// Edits the text of a slide's text boxes: the in-place editor's session,
/// and the formatting commands a toolbar sends.
///
/// Give one to `SlideCanvas.textEditing` and keep it for the canvas's life
/// (the canvas makes its own when none is given). The canvas tells it which
/// document, slide and selection it shows, starts a session when the user
/// double-clicks a text box, presses Enter or F2 on one, or draws one with
/// the text tool, and ends it on Escape or a click elsewhere.
///
/// **A session** edits a draft of one box — [elementId], [draft] — or of
/// one table cell, opened with [beginCell]: then [elementId] is the
/// table's, [cell] the cell's, and [draft] the cell's text as a box the
/// size of the cell (see `TableElement.cellTextBox`). It
/// writes it to the document when it ends ([commit]) as a single undo step,
/// however much was typed and formatted; [cancel] drops it. Undo and redo
/// inside the editor step through the session's own history, which ends
/// with it. Call [commit] before anything that should see the typed text,
/// such as the document's own undo:
///
/// ```dart
/// editing.commit();
/// doc.controller.undo();
/// ```
///
/// **Formatting.** [format] and [toggle] apply a [TextFormat] to the
/// session's selection while editing — or, at a collapsed caret, to what is
/// typed next — and to every selected text box as a whole otherwise, as
/// one undo step. [selectionFormat] is what a toolbar shows: the formatting
/// the selection shares. [canFormat] says whether there is anything to
/// format. A toolbar listens to this controller to stay current:
///
/// ```dart
/// ListenableBuilder(
///   listenable: editing,
///   builder: (context, _) => IconButton(
///     isSelected: TextToggle.bold.isOn(editing.selectionFormat),
///     onPressed: editing.canFormat
///         ? () => editing.toggle(TextToggle.bold)
///         : null,
///     icon: const Icon(Icons.format_bold),
///   ),
/// );
/// ```
class SlideTextEditingController extends ChangeNotifier {
  /// Creates a controller; [fontFamilies] are the families a toolbar
  /// offers.
  SlideTextEditingController({this.fontFamilies = const []});

  /// The font families a toolbar offers, from the app; the canvas draws any
  /// family a run names.
  final List<String> fontFamilies;

  SlideDocumentController? _doc;
  String? _slideId;
  Set<String> _selection = const {};

  String? _elementId;
  ({int row, int column})? _cell;
  TextBox? _original;
  TextBox? _draft;
  TextSelection _textSelection = const TextSelection.collapsed(offset: 0);
  TextFormat? _pending;
  bool _removeIfEmpty = false;
  Presentation? _insertedInto;
  final List<(TextBox, TextSelection)> _undo = [];
  final List<(TextBox, TextSelection)> _redo = [];
  int? _typingAt;
  final List<SlideParagraphEditingController> _fields = [];
  SlideTextLayout _layout = const SlideTextLayout();
  int _focused = 0;

  /// Points the controller at the slide [slideId] of [document] with
  /// [selection] selected. `SlideCanvas` calls this as it builds; an app
  /// does not need to.
  void attach(
    SlideDocumentController document,
    String slideId,
    Set<String> selection,
  ) {
    _doc = document;
    _slideId = slideId;
    _selection = selection;
  }

  /// Whether a session is open.
  bool get isEditing => _draft != null;

  /// The id of the text box being edited — or of the table whose [cell] is
  /// — or `null`.
  String? get elementId => _elementId;

  /// The table cell being edited, its merge anchor, or `null` when the
  /// session edits a text box or none is open.
  ({int row, int column})? get cell => _cell;

  /// The box being edited as it stands, typing and formatting included, or
  /// `null`.
  TextBox? get draft => _draft;

  /// The selection in the [draft], as offsets into its plain text.
  TextSelection get textSelection => _textSelection;

  /// Whether [format] would do anything: a session is open, or a text box
  /// is selected.
  bool get canFormat => isEditing || _selectedBoxes().isNotEmpty;

  /// The formatting the selection shares, as a summary [TextFormat]: the
  /// session's selected text (with what a collapsed caret would type next),
  /// or else every selected text box whole.
  TextFormat get selectionFormat {
    final draft = _draft;
    if (draft != null) {
      final format = textFormatOf(
        draft.paragraphs,
        start: _textSelection.start,
        end: _textSelection.end,
        box: draft,
      );
      return _pending == null ? format : format.merge(_pending!);
    }
    final boxes = _selectedBoxes();
    if (boxes.isEmpty) return const TextFormat();
    return boxes.map((b) => textFormatOf(b.paragraphs, box: b)).reduce(_common);
  }

  /// Applies [format] to the selection; see the class doc.
  void format(TextFormat format) {
    final draft = _draft;
    if (draft == null) {
      final doc = _doc;
      final ids = {for (final b in _selectedBoxes()) b.id};
      if (doc != null && ids.isNotEmpty) {
        doc.formatText(_slideId!, ids, format);
        notifyListeners();
      }
      return;
    }
    _remember();
    final selection = _textSelection;
    if (selection.isCollapsed && format.changesRuns) {
      _pending = (_pending ?? const TextFormat()).merge(format);
    }
    _draft = formatTextBox(
      draft,
      format,
      start: selection.start,
      end: selection.end,
    );
    _sync();
    notifyListeners();
  }

  /// Flips [toggle] for the selection: on unless all of it has it already.
  void toggle(TextToggle toggle) => format(toggle.changeFrom(selectionFormat));

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  /// Opens a session on the text box [elementId] of the attached slide,
  /// committing any session already open, with [selection] (a caret at the
  /// end by default) selected.
  ///
  /// With [removeIfEmpty] — for a box just inserted — a session that ends
  /// with the box still empty undoes the insertion too, as long as nothing
  /// else changed the document in between.
  void begin(
    String elementId, {
    TextSelection? selection,
    bool removeIfEmpty = false,
  }) {
    if (isEditing) commit();
    final element =
        _doc?.presentation.slideById(_slideId!)?.findElement(elementId);
    if (element is! TextBox) {
      throw ArgumentError.value(elementId, 'elementId', 'is not a text box');
    }
    _open(element, null, selection, removeIfEmpty);
  }

  /// Opens a session on the cell at [row], [column] of the table
  /// [tableId] on the attached slide — its merge anchor, when it is merged
  /// — committing any session already open. [commit] writes the text back
  /// with `SlideDocumentController.setCellText`, as one undo step.
  void beginCell(
    String tableId,
    int row,
    int column, {
    TextSelection? selection,
  }) {
    if (isEditing) commit();
    final element =
        _doc?.presentation.slideById(_slideId!)?.findElement(tableId);
    if (element is! TableElement) {
      throw ArgumentError.value(tableId, 'tableId', 'is not a table');
    }
    RangeError.checkValidIndex(row, element.cells, 'row');
    RangeError.checkValidIndex(column, element.columnWidths, 'column');
    final box = element.cellTextBox(row, column);
    _open(
      // A blank cell gets a line to type on.
      box.paragraphs.isEmpty
          ? box.copyWith(paragraphs: const [TextParagraph([])])
          : box,
      element.anchorOf(row, column),
      selection,
      false,
    );
  }

  void _open(
    TextBox box,
    ({int row, int column})? cell,
    TextSelection? selection,
    bool removeIfEmpty,
  ) {
    _elementId = box.id;
    _cell = cell;
    _original = box;
    _draft = box;
    final length = box.plainText.length;
    _textSelection = selection == null
        ? TextSelection.collapsed(offset: length)
        : TextSelection(
            baseOffset: selection.baseOffset.clamp(0, length),
            extentOffset: selection.extentOffset.clamp(0, length),
          );
    _removeIfEmpty = removeIfEmpty;
    _insertedInto = _doc!.presentation;
    _pending = null;
    _undo.clear();
    _redo.clear();
    _typingAt = null;
    _sync();
    notifyListeners();
  }

  /// Ends the session, writing the draft to the document as one undo step
  /// when it differs from the box it started from.
  void commit() {
    final draft = _draft;
    final original = _original;
    final doc = _doc;
    if (draft == null || original == null || doc == null) return;
    final inserted = _insertedInto;
    final removeIfEmpty = _removeIfEmpty;
    final cell = _cell;
    _end();
    final slideId = _slideId!;
    final current = doc.presentation.slideById(slideId)?.findElement(
          draft.id,
        );
    if (cell != null) return _commitCell(doc, slideId, current, cell, draft);
    if (current is! TextBox) return;
    if (removeIfEmpty &&
        draft.plainText.isEmpty &&
        identical(doc.presentation, inserted) &&
        doc.canUndo) {
      doc.undo();
      return;
    }
    doc.batch(() {
      if (!listEquals(draft.paragraphs, original.paragraphs)) {
        doc.editText(slideId, draft.id, draft.paragraphs);
      }
      if (draft.anchor != original.anchor ||
          draft.autoFit != original.autoFit) {
        doc.formatText(
          slideId,
          {draft.id},
          TextFormat(anchor: draft.anchor, autoFit: draft.autoFit),
        );
      }
    });
  }

  /// Writes a cell session's [draft] to the cell [cell] of the table
  /// [current], as one step, when the table still has that cell.
  void _commitCell(
    SlideDocumentController doc,
    String slideId,
    SlideElement? current,
    ({int row, int column}) cell,
    TextBox draft,
  ) {
    if (current is! TableElement ||
        cell.row >= current.rowCount ||
        cell.column >= current.columnCount) {
      return;
    }
    final before = current.cell(cell.row, cell.column);
    final blank = draft.plainText.isEmpty && before.plainText.isEmpty;
    doc.batch(() {
      if (!blank && !listEquals(draft.paragraphs, before.paragraphs)) {
        doc.setCellText(
            slideId, draft.id, cell.row, cell.column, draft.paragraphs);
      }
      if (draft.anchor != before.anchor) {
        doc.formatCells(
          slideId,
          draft.id,
          CellRange.single(cell.row, cell.column),
          CellFormat(text: TextFormat(anchor: draft.anchor)),
        );
      }
    });
  }

  /// Ends the session and drops the draft.
  void cancel() => _end();

  bool _end() {
    if (!isEditing) return false;
    _elementId = null;
    _cell = null;
    _original = null;
    _draft = null;
    _pending = null;
    _insertedInto = null;
    _undo.clear();
    _redo.clear();
    final fields = [..._fields];
    _fields.clear();
    // The editor's fields still hold these until they rebuild without them.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final field in fields) {
        field.dispose();
      }
    });
    SchedulerBinding.instance.scheduleFrame();
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // In-session history
  // ---------------------------------------------------------------------------

  /// Whether [undo] would do anything.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether [redo] would do anything.
  bool get canRedo => _redo.isNotEmpty;

  /// Reverts the session's last edit.
  void undo() => _travel(_undo, _redo);

  /// Reapplies the session's last undone edit.
  void redo() => _travel(_redo, _undo);

  void _travel(
    List<(TextBox, TextSelection)> from,
    List<(TextBox, TextSelection)> to,
  ) {
    if (!isEditing || from.isEmpty) return;
    to.add((_draft!, _textSelection));
    final (draft, selection) = from.removeLast();
    _draft = draft;
    _textSelection = selection;
    _pending = null;
    _typingAt = null;
    _sync();
    notifyListeners();
  }

  void _remember() {
    _undo.add((_draft!, _textSelection));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    _typingAt = null;
  }

  // ---------------------------------------------------------------------------
  // The editor's fields
  // ---------------------------------------------------------------------------

  /// One controller per paragraph of the [draft], for the editor's fields.
  List<SlideParagraphEditingController> get paragraphControllers =>
      List.unmodifiable(_fields);

  /// The paragraph the caret is in, whose field should have focus.
  int get focusedParagraph => _focused;

  /// Restyles the fields with [layout] at [scale]; the editor calls this
  /// as it builds.
  void configureFields(SlideTextLayout layout, double scale) {
    _layout = layout;
    for (final field in _fields) {
      field
        ..layout = layout
        ..scale = scale;
    }
  }

  /// The box offset of the first character of each paragraph.
  List<int> get _starts {
    final starts = <int>[];
    var offset = 0;
    for (final p in _draft!.paragraphs) {
      starts.add(offset);
      offset += p.plainText.length + 1;
    }
    return starts;
  }

  int get _length => _draft!.plainText.length;

  /// Selects all the draft's text, across every paragraph.
  void selectAll() {
    if (!isEditing) return;
    _textSelection = TextSelection(baseOffset: 0, extentOffset: _length);
    _pending = null;
    _sync();
    notifyListeners();
  }

  /// Puts the caret at the start (or, with [atEnd], the end) of paragraph
  /// [index], as arrowing past a paragraph's edge does.
  void moveToParagraph(int index, {bool atEnd = false}) {
    final paragraphs = _draft?.paragraphs;
    if (paragraphs == null || index < 0 || index >= paragraphs.length) return;
    final start = _starts[index];
    _textSelection = TextSelection.collapsed(
      offset: atEnd ? start + paragraphs[index].plainText.length : start,
    );
    _pending = null;
    _typingAt = null;
    _sync();
    notifyListeners();
  }

  /// Moves the session's caret into paragraph [index] at its field's own
  /// selection, when the field took focus some other way — a click.
  void focusParagraph(int index) {
    if (!isEditing || index >= _fields.length || index == _focused) return;
    final selection = _fields[index].selection;
    _onSelectionChanged(
      index,
      selection.isValid
          ? selection
          : TextSelection.collapsed(offset: _fields[index].text.length),
    );
  }

  /// Deletes the line break after paragraph [index], joining the next
  /// paragraph to it, as the Delete key at a paragraph's end does.
  void joinNext(int index) {
    final paragraphs = _draft?.paragraphs;
    if (paragraphs == null || index + 1 >= paragraphs.length) return;
    final at = _starts[index + 1] - 1;
    _replace(at, at + 1, '', TextSelection.collapsed(offset: at));
  }

  void _replace(
    int start,
    int end,
    String inserted,
    TextSelection selection, {
    bool coalesce = false,
  }) {
    if (!(coalesce && _typingAt == start && start == end)) _remember();
    final draft = _draft!;
    final style = _pending?.applyToRun(typingStyleAt(draft.paragraphs, start));
    _draft = draft.copyWith(
      paragraphs: replaceText(
        draft.paragraphs,
        start,
        end,
        inserted,
        style: style,
      ),
    );
    _textSelection = selection;
    _pending = null;
    _typingAt = coalesce ? start + inserted.length : null;
  }

  void _onEdit(
    int index,
    int start,
    int end,
    String inserted,
    TextEditingValue value,
  ) {
    if (!isEditing || index >= _fields.length) return;
    final field = _fields[index];
    final base = _starts[index] - field.lead;
    var from = base + start;
    var to = base + end;
    // A selection across paragraphs shows in each field; replacing the
    // focused field's share of it replaces all of it.
    final selection = _textSelection;
    final paragraphEnd = base + field.text.length;
    if (!selection.isCollapsed &&
        (selection.start < base + field.lead || selection.end > paragraphEnd) &&
        from == selection.start.clamp(base + field.lead, paragraphEnd) &&
        to == selection.end.clamp(base + field.lead, paragraphEnd)) {
      from = selection.start;
      to = selection.end;
    }
    final text = inserted
        .replaceAll('\r\n', '\n')
        .replaceAll(SlideParagraphEditingController.lineBreak, '');
    final count = _draft!.paragraphs.length;
    final plainEdit = text.isNotEmpty && !text.contains('\n') && from == to;
    _replace(
      from,
      to,
      text,
      TextSelection.collapsed(offset: from + text.length),
      coalesce: plainEdit,
    );
    var composing = TextRange.empty;
    if (_draft!.paragraphs.length == count &&
        from >= base + field.lead &&
        value.selection.isValid) {
      // Same paragraphs: keep the field's own selection and composing
      // range, which an input method relies on.
      _textSelection = TextSelection(
        baseOffset: base + value.selection.baseOffset,
        extentOffset: base + value.selection.extentOffset,
      );
      composing = value.composing;
    }
    _sync(composing: composing);
    notifyListeners();
  }

  void _onSelectionChanged(int index, TextSelection selection) {
    if (!isEditing || index >= _fields.length || !selection.isValid) return;
    final field = _fields[index];
    final base = _starts[index] - field.lead;
    // The caret never sits in front of the paragraph's line-break mark.
    final next = TextSelection(
      baseOffset: base + selection.baseOffset.clamp(field.lead, 1 << 30),
      extentOffset: base + selection.extentOffset.clamp(field.lead, 1 << 30),
    );
    if (next == _textSelection && index == _focused) return;
    _textSelection = next;
    _pending = null;
    _typingAt = null;
    _sync();
    notifyListeners();
  }

  /// Rebuilds the field controllers to match the draft and its selection.
  void _sync({TextRange composing = TextRange.empty}) {
    final paragraphs = _draft!.paragraphs;
    while (_fields.length > paragraphs.length) {
      final field = _fields.removeLast();
      SchedulerBinding.instance.addPostFrameCallback((_) => field.dispose());
    }
    for (var i = _fields.length; i < paragraphs.length; i++) {
      _fields.add(
        SlideParagraphEditingController(
          paragraph: paragraphs[i],
          leadingBreak: i > 0,
          layout: _layout,
          onEdit: (start, end, inserted, value) =>
              _onEdit(i, start, end, inserted, value),
          onSelectionChanged: (selection) => _onSelectionChanged(i, selection),
        ),
      );
    }
    final starts = _starts;
    final selection = _textSelection;
    _focused = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      if (selection.extentOffset >= starts[i]) _focused = i;
    }
    for (var i = 0; i < paragraphs.length; i++) {
      final lead = i > 0 ? 1 : 0;
      final base = starts[i] - lead;
      final length = paragraphs[i].plainText.length + lead;
      int local(int offset) => (offset - base).clamp(lead, length);
      final TextSelection fieldSelection;
      if (i == _focused) {
        fieldSelection = TextSelection(
          baseOffset: local(selection.baseOffset),
          extentOffset: local(selection.extentOffset),
        );
      } else if (selection.start < starts[i] + length - lead &&
          selection.end > starts[i]) {
        fieldSelection = TextSelection(
          baseOffset: local(selection.start),
          extentOffset: local(selection.end),
        );
      } else {
        fieldSelection = TextSelection.collapsed(offset: length);
      }
      _fields[i].sync(
        paragraphs[i],
        leadingBreak: i > 0,
        selection: fieldSelection,
        composing: i == _focused ? composing : TextRange.empty,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<TextBox> _selectedBoxes() {
    final slide = _doc?.presentation.slideById(_slideId ?? '');
    if (slide == null) return const [];
    return [
      for (final e in slide.allElements)
        if (e is TextBox && _selection.contains(e.id)) e,
    ];
  }

  /// The fields [a] and [b] agree on.
  static TextFormat _common(TextFormat a, TextFormat b) {
    T? same<T>(T? x, T? y) => x == y ? x : null;
    Object? sameOrUnset(Object? x, Object? y) => x == y ? x : unset;
    return TextFormat(
      bold: same(a.bold, b.bold),
      italic: same(a.italic, b.italic),
      underline: same(a.underline, b.underline),
      strikethrough: same(a.strikethrough, b.strikethrough),
      fontSize: sameOrUnset(a.fontSize, b.fontSize),
      fontFamily: sameOrUnset(a.fontFamily, b.fontFamily),
      color: sameOrUnset(a.color, b.color),
      alignment: same(a.alignment, b.alignment),
      lineSpacing: sameOrUnset(a.lineSpacing, b.lineSpacing),
      list: same(a.list, b.list),
      anchor: same(a.anchor, b.anchor),
      autoFit: same(a.autoFit, b.autoFit),
    );
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    _fields.clear();
    super.dispose();
  }
}
