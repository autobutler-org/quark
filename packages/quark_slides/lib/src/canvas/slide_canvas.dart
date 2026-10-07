import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../clipboard/slide_clipboard.dart';
import '../controller/slide_document_controller.dart';
import '../controller/slide_document_notifier.dart';
import '../geometry/frame_geometry.dart';
import '../geometry/slide_drawing.dart';
import '../geometry/slide_handle.dart';
import '../geometry/group_geometry.dart';
import '../geometry/slide_snapping.dart';
import '../geometry/slide_table_grip.dart';
import '../geometry/slide_tree.dart';
import '../geometry/slide_viewport.dart';
import '../model/cell_range.dart';
import '../model/element_frame.dart';
import '../model/presentation.dart';
import '../model/slide.dart';
import '../model/slide_element.dart';
import '../model/slide_size.dart';
import '../search/slide_match.dart';
import '../table/table_edits.dart';
import '../theme/slide_theme.dart';
import 'slide_canvas_interaction.dart';
import 'slide_canvas_style.dart';
import 'slide_chart_editing_controller.dart';
import 'slide_chart_painter.dart';
import 'slide_fallback_theme.dart';
import 'slide_canvas_tool.dart';
import 'slide_element_label.dart';
import 'slide_tool_controller.dart';
import 'slide_tool_label.dart';
import 'slide_image_source.dart';
import 'slide_selection_overlay.dart';
import 'slide_stage.dart';
import 'slide_table_editing_controller.dart';
import 'slide_table_view.dart';
import 'slide_text_editing_controller.dart';
import 'slide_text_editor.dart';
import 'slide_text_highlight_painter.dart';
import 'slide_text_layout.dart';

/// Shows one slide scaled to fit its box, with letterbox bars, at the presentation's
/// aspect ratio, and — unless built [SlideCanvas.readOnly] — edits it.
///
/// **Editing.** The default constructor edits the slide [slideId] of
/// [document]. Every change goes through the document's
/// [SlideDocumentController], and each gesture is one undo step:
///
/// - tap or click an element to select it; Shift, Ctrl or Cmd adds or
///   removes it instead; drag on empty slide to select by marquee;
/// - drag a selection to move it, snapping its edges and center to the
///   slide's and to other elements' (hold Alt to place freely), with guide
///   lines while it snaps;
/// - drag one of a single selection's eight handles to resize (Shift keeps
///   the aspect ratio at a corner), or its rotate handle to rotate (Shift
///   steps by 15°);
/// - the arrow keys nudge by one slide unit, ten with Shift; Delete or
///   Backspace deletes; Escape deselects; Tab and Shift+Tab select the
///   next and previous element in stacking order and then let focus move
///   on; Ctrl or Cmd with `]` or `[` brings forward or sends backward, and
///   with Shift as well, to the front or back;
/// - Ctrl or Cmd with C, X and V copy, cut and paste through [clipboard],
///   and with D duplicate in place; Ctrl or Cmd G groups the selection and
///   with Shift ungroups it (see [SlideDocumentController.groupElements]);
/// - scroll to pan a zoomed slide, Ctrl or Cmd scroll (or pinch) to zoom
///   about the pointer, middle-drag or two fingers to pan.
///
/// **Groups.** A group selects, moves, resizes and rotates as one element.
/// Double-click or double-tap it — or press Enter with it selected — to
/// enter it and select the child under the pointer (the backmost child
/// from the keyboard); its outline stays drawn faintly while you work on
/// its children, with the same gestures and keys. Escape, or a press
/// outside the group, steps back out.
///
/// **Text.** Double-click or double-tap a text box, or press Enter or F2
/// with one selected, to edit its text in place — at the canvas's scale and
/// rotation, with the platform's caret, selection, input methods and touch
/// handles (see [SlideTextEditor]). Escape or a click outside the box ends
/// editing and writes everything typed as one undo step. A screen reader's
/// tap on a selected text box edits it too, and the canvas announces
/// [editingAnnouncement] and [editingDoneAnnouncement] as editing starts
/// and stops. [textEditing] is the session a toolbar formats through; see
/// [SlideTextEditingController].
///
/// **Tables.** A table selects, moves, resizes and rotates as one element;
/// resizing scales its columns and rows. With a table selected, a press on
/// a cell selects it and a drag selects the cells between, Shift with the
/// arrow keys grows the selection, the arrow keys move it, Tab and
/// Shift+Tab step through the cells, Delete empties them, and Escape lets
/// go of the cells; a press within [SlideCanvasStyle.handleSize] of the
/// table's edge (or a quarter of the cell there, if that is less) moves it
/// instead. Double-click or double-tap a cell, or
/// press Enter or F2, to edit it in place with the text editor, where Tab
/// moves on to the next cell. The grips on its top and left edges drag the
/// lines between columns and rows. Each is one undo step. [tableEditing]
/// holds the selected cells and the table commands a toolbar sends; see
/// [SlideTableEditingController]. Each cell reads to a screen reader as
/// [cellLabel] names it.
///
/// **Charts.** A chart selects, moves, resizes and rotates as one element
/// with the ordinary handles; what is inside it is laid out as it is drawn
/// (see [SlideChartPainter]). It reads to a screen reader as a summary
/// ("Bar chart, 3 series, 4 categories; highest value 24 in Q4") with its
/// numbers as [chartDataLabel] reads them. [chartEditing] holds the
/// selected chart and the chart commands a toolbar sends; see
/// [SlideChartEditingController].
///
/// **Drawing.** [tools] holds the active [SlideCanvasTool]: text, any
/// [ShapeKind], a line or arrow, a table, a chart, or an image. With a drawing tool a click
/// places the element at its default size and a drag draws it (Shift keeps
/// a shape square or a line at 45° steps, Alt draws out from the point
/// pressed), previewing it as it goes. The insertion is one undo step; the
/// canvas selects the new element and returns to [SlideCanvasTool.select],
/// as Escape does. A text box opens for typing, and one left empty
/// disappears again. The image tool draws nothing itself: it calls
/// [onPickImage] with the box drawn, or `null` for a click, and the app
/// picks a picture and calls `SlideDocumentController.insertImage`.
/// Without a pointer, Enter on the focused canvas — or a screen reader's
/// tap, labeled by [toolLabel] — inserts at the slide's center. An image
/// is resized keeping its aspect ratio, unless Alt is held.
///
/// The caller owns [selection] and [zoom] and hears about changes through
/// [onSelectionChanged] and [onZoomChanged]; zoom is relative to fitting
/// the box, from [minZoom] to [maxZoom]. Handles are drawn
/// [SlideCanvasStyle.handleSize] across but grab within
/// [SlideCanvasStyle.handleHitSize]. The canvas draws without animation, so
/// there is no motion for reduced-motion settings to remove.
///
/// **Locked.** [interaction] limits an editing canvas without hiding it
/// from pointers: [SlideCanvasInteraction.selectOnly] keeps selection
/// (taps, marquee, Tab, Escape, groups, table cells), copying, pan, zoom and
/// every screen reader label while no gesture, key, tool or in-place editor
/// changes the document; [SlideCanvasInteraction.viewOnly] keeps only pan,
/// zoom — a drag pans — and the labels. Switching away from editing commits
/// a text edit in progress.
///
/// **Read-only.** [SlideCanvas.readOnly] draws a [Slide] with no chrome and
/// no input, for thumbnails and presenting.
///
/// **Themes.** Role colors (`SlideColor.theme`) and the unset styles of
/// text resolve against the presentation's `SlideTheme` as the slide is
/// painted — or, read-only, against [theme] — so a theme change repaints
/// the deck. Without one, the canvas uses [slideFallbackTheme]: the
/// style's slide and text colors and the ambient [ColorScheme]'s accents.
/// A placeholder text box reads to a screen reader with its role first
/// ("Title: Quarterly review"; see [defaultSlideElementLabel]).
///
/// **Clipboard.** Copied elements go to [clipboard] as versioned JSON (see
/// [SlideClipboardCodec]); a paste lands [SlideDocumentController.pasteOffset]
/// units past anything it would cover exactly, and selects what it pasted.
/// Plain text from another app pastes as a new text box. Each cut, paste,
/// duplicate, group and ungroup is one undo step.
///
/// **Find.** [highlights] — a `SlideSearch`'s matches — are painted behind
/// their text on this slide in [SlideCanvasStyle.highlightColor], and
/// [currentHighlight] in [SlideCanvasStyle.currentHighlightColor]. Each
/// time [currentHighlight] changes to a match in a text box on this slide,
/// the canvas reveals it: it enters the group holding the box, selects the
/// box (through [onSelectionChanged]) and pans a zoomed slide to center it.
/// Matches in speaker notes, or on other slides, are not drawn here.
///
/// Images are drawn by [imageBuilder]; the package never loads one. The
/// canvas needs a bounded box when editing and handles pointers itself, so
/// do not put it in a scroll view. Keys: each element is
/// `slide_element_<id>`, each handle `slide_handle_<id>` (see
/// [SlideHandle.keyName]), and while a box is edited each of its paragraphs
/// `slide_text_paragraph_<index>` (see [SlideTextEditor.keyName]); each
/// table cell `slide_table_cell_<id>_<row>_<column>` (see
/// [SlideTableView.cellKeyName]) and each table grip
/// `slide_table_column_<index>` or `slide_table_row_<index>` (see
/// [SlideTableGrip.keyName]).
///
/// ```dart
/// ListenableBuilder(
///   listenable: selection,
///   builder: (context, _) => SlideCanvas(
///     document: doc,
///     slideId: slideId,
///     selection: selection.value,
///     onSelectionChanged: (ids) => selection.value = ids,
///     imageBuilder: (context, image) =>
///         Image.network(image.source, fit: image.fit),
///   ),
/// );
/// ```
class SlideCanvas extends StatefulWidget {
  /// Creates an editing canvas for the slide [slideId] of [document].
  const SlideCanvas({
    super.key,
    required SlideDocumentNotifier this.document,
    required String this.slideId,
    this.selection = const {},
    this.onSelectionChanged,
    this.zoom = 1,
    this.onZoomChanged,
    this.imageBuilder,
    this.style,
    this.elementLabel = defaultSlideElementLabel,
    this.padding = const EdgeInsets.all(24),
    this.focusNode,
    this.autofocus = false,
    this.textEditing,
    this.tools,
    this.onPickImage,
    this.toolLabel = defaultSlideToolLabel,
    this.editingAnnouncement = 'Editing text',
    this.editingDoneAnnouncement = 'Done editing text',
    this.clipboard,
    this.highlights = const [],
    this.currentHighlight,
    this.tableEditing,
    this.cellLabel = defaultSlideTableCellLabel,
    this.interaction = SlideCanvasInteraction.editable,
    this.chartEditing,
    this.chartDataLabel = defaultSlideChartDataLabel,
  })  : slide = null,
        size = null,
        theme = null;

  /// Creates a canvas that only draws [slide], at [size], for a thumbnail or
  /// a presentation. It sizes itself to [size]'s aspect ratio within its
  /// constraints.
  const SlideCanvas.readOnly({
    super.key,
    required Slide this.slide,
    required SlideSize this.size,
    this.imageBuilder,
    this.style,
    this.elementLabel = defaultSlideElementLabel,
    this.padding = EdgeInsets.zero,
    this.theme,
    this.cellLabel = defaultSlideTableCellLabel,
    this.chartDataLabel = defaultSlideChartDataLabel,
  })  : document = null,
        slideId = null,
        selection = const {},
        onSelectionChanged = null,
        zoom = 1,
        onZoomChanged = null,
        focusNode = null,
        autofocus = false,
        textEditing = null,
        tools = null,
        onPickImage = null,
        toolLabel = defaultSlideToolLabel,
        editingAnnouncement = '',
        editingDoneAnnouncement = '',
        clipboard = null,
        highlights = const [],
        currentHighlight = null,
        tableEditing = null,
        interaction = SlideCanvasInteraction.viewOnly,
        chartEditing = null;

  /// The smallest zoom, half the fitted size.
  static const minZoom = 0.5;

  /// The largest zoom, twice the fitted size.
  static const maxZoom = 2.0;

  /// The document being edited, or `null` when read-only.
  final SlideDocumentNotifier? document;

  /// The id of the slide being edited, or `null` when read-only.
  final String? slideId;

  /// The slide drawn when read-only.
  final Slide? slide;

  /// The slide size when read-only.
  final SlideSize? size;

  /// The presentation's theme when read-only, or `null` for none; an
  /// editing canvas takes the document's.
  final SlideTheme? theme;

  /// The ids of the selected elements. Ids not on the slide are ignored.
  final Set<String> selection;

  /// Called with the new selection whenever a gesture or key changes it.
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// The zoom, relative to fitting the box: 1 fits, 0.5 is half that.
  final double zoom;

  /// Called with a new zoom, within [minZoom] and [maxZoom], on a pinch or
  /// a Ctrl-scroll. Without it the zoom stays put.
  final ValueChanged<double>? onZoomChanged;

  /// Draws image elements and background images.
  final SlideImageBuilder? imageBuilder;

  /// Chrome colors and sizes; defaults to [SlideCanvasStyle.fromTheme].
  final SlideCanvasStyle? style;

  /// Names elements for a screen reader.
  final SlideElementLabel elementLabel;

  /// Space around the slide at zoom 1, where handles on its edge still fit.
  final EdgeInsets padding;

  /// The focus node keyboard commands arrive on; the canvas makes its own
  /// when none is given.
  final FocusNode? focusNode;

  /// Whether to take focus when first built.
  final bool autofocus;

  /// The text editing session and formatting commands; the canvas makes
  /// its own when none is given.
  final SlideTextEditingController? textEditing;

  /// The active tool, shared with a toolbar; the canvas makes its own when
  /// none is given. It hands the tool back to [SlideCanvasTool.select]
  /// after each insertion and on Escape.
  final SlideToolController? tools;

  /// Asks the app for a picture after the image tool marks where it goes:
  /// with the box drawn, in slide units, or `null` for a click or Enter,
  /// meaning the default place. The app passes it on as
  /// `insertImage(..., within: box)`.
  final ValueChanged<ElementFrame?>? onPickImage;

  /// Names a drawing tool for a screen reader, as the action that inserts
  /// at the center.
  final SlideToolLabel toolLabel;

  /// What a screen reader hears when a text box opens for editing.
  final String editingAnnouncement;

  /// What a screen reader hears when editing ends.
  final String editingDoneAnnouncement;

  /// Where copy and cut write and paste reads; [SlideClipboard.memory],
  /// inside the app only, when none is given.
  final SlideClipboard? clipboard;

  /// Search matches to highlight; those on other slides or in notes are
  /// ignored.
  final List<SlideMatch> highlights;

  /// The match a search is on, emphasized and revealed when it changes;
  /// `null` for none.
  final SlideMatch? currentHighlight;

  /// The selected table cells and the table commands; the canvas makes its
  /// own when none is given.
  final SlideTableEditingController? tableEditing;

  /// Names a table's cells for a screen reader.
  final SlideTableCellLabel cellLabel;

  /// Reads a chart's numbers to a screen reader.
  final SlideChartDataLabel chartDataLabel;

  /// What a person may do: edit, only select, or only look. A read-only
  /// canvas is [SlideCanvasInteraction.viewOnly].
  final SlideCanvasInteraction interaction;

  /// The selected chart and the chart commands; the canvas makes its own
  /// when none is given.
  final SlideChartEditingController? chartEditing;

  /// Whether the canvas only draws.
  bool get readOnly => document == null;

  @override
  State<SlideCanvas> createState() => _SlideCanvasState();
}

enum _GestureKind {
  move(edits: true),

  /// A press that only selects, on a canvas that does not edit.
  press(edits: false),
  resize(edits: true),
  rotate(edits: true),
  tableResize(edits: true),
  cells(edits: false),
  marquee(edits: false),
  draw(edits: false),
  pan(edits: false);

  const _GestureKind({required this.edits});

  final bool edits;
}

/// One pointer's drag, from pointer down to up.
class _Gesture {
  _Gesture(
    this.kind, {
    required this.pointer,
    required this.startView,
    required this.startSlide,
    this.ids = const {},
    this.handle,
    this.frame,
    this.isLine = false,
    this.isImage = false,
    this.startBounds,
    this.collapseTo,
    this.hit,
    this.startPan = Offset.zero,
    this.grip,
    this.cell,
    this.startSize = 0,
  });

  final _GestureKind kind;
  final int pointer;
  final Offset startView;
  final Offset startSlide;

  /// The elements a move drags, or the one a resize or rotate changes; for
  /// a marquee, the selection it adds to.
  final Set<String> ids;
  final SlideHandle? handle;
  final ElementFrame? frame;
  final bool isLine;
  final bool isImage;
  final Rect? startBounds;

  /// The element to select alone if this ends as a tap on a multi-selection.
  final String? collapseTo;

  /// The element under the pointer when it went down.
  final String? hit;
  final Offset startPan;

  /// The table grip a table resize drags.
  final SlideTableGrip? grip;

  /// The cell a cell selection started on.
  final ({int row, int column})? cell;

  /// The width or height of the column or row a table resize drags, when
  /// it started.
  final double startSize;

  bool started = false;
  Offset applied = Offset.zero;

  /// Where a draw gesture's pointer is now, in slide units.
  Offset? current;

  /// The controller holding this gesture's open batch, if it opened one.
  SlideDocumentController? batch;
  Presentation? before;
}

/// Two fingers down: the slide point under their midpoint follows it, and
/// the zoom follows their spread.
class _Pinch {
  _Pinch(this.slidePoint, this.distance, this.zoom);

  final Offset slidePoint;
  final double distance;
  final double zoom;
}

class _SlideCanvasState extends State<SlideCanvas> {
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'SlideCanvas'));

  late Set<String> _selection = widget.selection;
  Offset _pan = Offset.zero;
  SlideViewport? _viewport;
  final Map<int, Offset> _pointers = {};
  _Gesture? _gesture;
  _Pinch? _pinch;
  double _trackpadZoom = 1;
  List<SnapGuide> _guides = const [];
  Rect? _marquee;
  MouseCursor _cursor = MouseCursor.defer;
  SlideTextEditingController? _ownTextEditing;
  SlideToolController? _ownTools;
  SlideTableEditingController? _ownTableEditing;
  SlideChartEditingController? _ownChartEditing;
  bool _wasEditing = false;

  /// The element a draw gesture would insert, drawn over the slide.
  SlideElement? _preview;

  /// The group whose children are being selected, entered by a double
  /// click; `null` at the slide's top level.
  String? _entered;

  /// The last tap that did not drag: when, where in slide units, and on
  /// which element, to tell a double tap.
  (Duration, Offset, String)? _lastTap;

  SlideTextEditingController get _editing =>
      widget.textEditing ?? (_ownTextEditing ??= SlideTextEditingController());

  SlideToolController get _tools =>
      widget.tools ?? (_ownTools ??= SlideToolController());

  /// The active tool; [SlideCanvasTool.select] unless the canvas edits.
  SlideCanvasTool get _tool => _edits ? _tools.tool : SlideCanvasTool.select;

  /// Whether gestures and keys may change the document.
  bool get _edits => widget.interaction.edits;

  /// Whether gestures and keys may select.
  bool get _selects => widget.interaction.selects;

  SlideTableEditingController get _cells =>
      widget.tableEditing ??
      (_ownTableEditing ??= SlideTableEditingController());

  SlideChartEditingController get _charts =>
      widget.chartEditing ??
      (_ownChartEditing ??= SlideChartEditingController());

  SlideDocumentController get _doc => widget.document!.controller;

  SlideClipboard get _clipboard => widget.clipboard ?? SlideClipboard.memory;

  Slide? get _slide => widget.document!.presentation.slideById(widget.slideId!);

  SlideSize get _size => widget.document!.presentation.size;

  SlideCanvasStyle get _style =>
      widget.style ?? SlideCanvasStyle.fromTheme(Theme.of(context));

  /// The theme the slide is painted in: the deck's, or the fallback.
  SlideTheme get _theme =>
      (widget.readOnly ? widget.theme : widget.document!.presentation.theme) ??
      slideFallbackTheme(_style, Theme.of(context).colorScheme);

  @override
  void initState() {
    super.initState();
    if (widget.readOnly) return;
    _editing.addListener(_onEditingChanged);
    _tools.addListener(_onToolChanged);
    _cells.addListener(_onCellsChanged);
    widget.document!.addListener(_onDocumentChanged);
    _revealLater();
  }

  @override
  void didUpdateWidget(SlideCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(widget.selection, oldWidget.selection)) {
      _selection = widget.selection;
      _leaveUnlessInside(_selection);
    }
    final oldEditing = oldWidget.textEditing ?? _ownTextEditing;
    if (widget.interaction != oldWidget.interaction && !_edits) {
      // What was typed is kept; nothing more can be.
      oldEditing?.commit();
      _cancelGesture();
      if (!_selects) _cells.clear();
    }
    if (widget.slideId != oldWidget.slideId ||
        widget.document != oldWidget.document ||
        oldEditing != _editing) {
      // Written to the slide it was typed on, before the canvas moves on.
      oldEditing?.commit();
      _cancelGesture();
      _selection = widget.selection;
      _entered = null;
    }
    if (oldEditing != _editing) {
      oldEditing?.removeListener(_onEditingChanged);
      if (!widget.readOnly) _editing.addListener(_onEditingChanged);
    }
    if (widget.document != oldWidget.document) {
      oldWidget.document?.removeListener(_onDocumentChanged);
      widget.document?.addListener(_onDocumentChanged);
    }
    if (widget.currentHighlight != oldWidget.currentHighlight ||
        widget.slideId != oldWidget.slideId) {
      _revealLater();
    }
    final oldTools = oldWidget.tools ?? _ownTools;
    if (oldTools != _tools) {
      oldTools?.removeListener(_onToolChanged);
      if (!widget.readOnly) _tools.addListener(_onToolChanged);
    }
    final oldCells = oldWidget.tableEditing ?? _ownTableEditing;
    if (oldCells != _cells) {
      oldCells?.removeListener(_onCellsChanged);
      if (!widget.readOnly) _cells.addListener(_onCellsChanged);
    }
  }

  @override
  void dispose() {
    _cancelGesture();
    widget.document?.removeListener(_onDocumentChanged);
    final editing = widget.textEditing ?? _ownTextEditing;
    editing?.removeListener(_onEditingChanged);
    (widget.tools ?? _ownTools)?.removeListener(_onToolChanged);
    _ownTools?.dispose();
    (widget.tableEditing ?? _ownTableEditing)?.removeListener(_onCellsChanged);
    _ownTableEditing?.dispose();
    _ownChartEditing?.dispose();
    final own = _ownTextEditing;
    if (editing != null && editing.isEditing) {
      // Keep what was typed; the document cannot change mid-unmount.
      Future.microtask(() {
        editing.commit();
        own?.dispose();
      });
    } else {
      own?.dispose();
    }
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _onCellsChanged() {
    if (mounted) setState(() {});
  }

  /// Drops a drawing in progress when the tool changes under it.
  void _onToolChanged() {
    if (!mounted) return;
    setState(() {
      if (_gesture?.kind == _GestureKind.draw) _cancelGesture();
    });
  }

  // ---------------------------------------------------------------------------
  // Text editing
  // ---------------------------------------------------------------------------

  void _onEditingChanged() {
    final editing = _editing.isEditing;
    if (editing != _wasEditing) {
      _wasEditing = editing;
      _announce(
        editing ? widget.editingAnnouncement : widget.editingDoneAnnouncement,
      );
      if (!editing) _focusNode.requestFocus();
    }
    if (mounted) setState(() {});
  }

  void _announce(String message) {
    if (message.isEmpty) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  /// Drops the session when its box leaves the slide — undone, say.
  void _onDocumentChanged() {
    final id = _editing.elementId;
    if (id == null) return;
    final element = _slide?.findElement(id);
    final cell = _editing.cell;
    final kept = cell == null
        ? element is TextBox
        : element is TableElement &&
            cell.row < element.rowCount &&
            cell.column < element.columnCount;
    if (!kept) _editing.cancel();
  }

  /// Opens [id] for editing, with the caret under the global point
  /// [caretAt] when given and at the end otherwise.
  void _beginEditing(String id, {Offset? caretAt, bool fresh = false}) {
    _editing.attach(_doc, widget.slideId!, {id});
    _editing.begin(id, removeIfEmpty: fresh);
    if (caretAt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _placeCaret(caretAt));
    }
  }

  /// Opens the cell at [row], [column] of the table [tableId] for editing,
  /// selecting it, with the caret under the global point [caretAt] when
  /// given and at the end otherwise.
  void _beginCellEditing(
    String tableId,
    int row,
    int column, {
    Offset? caretAt,
  }) {
    _cells.select(tableId, CellRange.single(row, column));
    _editing.attach(_doc, widget.slideId!, {tableId});
    _editing.beginCell(tableId, row, column);
    if (caretAt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _placeCaret(caretAt));
    }
  }

  /// Commits the cell being edited and opens the next one in reading order
  /// — the previous one when [backward] — as Tab does in the editor. Past
  /// either end the editing ends with that cell selected.
  void _tabToCell(bool backward) {
    final id = _editing.elementId;
    final cell = _editing.cell;
    if (id == null || cell == null) return;
    _editing.commit();
    final table = _slide?.findElement(id);
    if (table is! TableElement) return;
    final next = _stepCell(table, cell, backward: backward);
    if (next == null) {
      _cells.select(id, CellRange.single(cell.row, cell.column));
      return;
    }
    _beginCellEditing(id, next.row, next.column);
  }

  /// The cell after [from] in reading order — before it when [backward] —
  /// skipping covered cells, or `null` past the end.
  static ({int row, int column})? _stepCell(
    TableElement table,
    ({int row, int column}) from, {
    required bool backward,
  }) {
    final count = table.rowCount * table.columnCount;
    var i = from.row * table.columnCount + from.column;
    while (true) {
      i += backward ? -1 : 1;
      if (i < 0 || i >= count) return null;
      final row = i ~/ table.columnCount;
      final column = i % table.columnCount;
      if (!table.isCovered(row, column)) return (row: row, column: column);
    }
  }

  /// Puts the caret at the character nearest the global point [point].
  void _placeCaret(Offset point) {
    final root = context.findRenderObject();
    if (!mounted || !_editing.isEditing || root == null) return;
    final fields = <RenderEditable>[];
    void visit(RenderObject object) {
      if (object is RenderEditable) return fields.add(object);
      object.visitChildren(visit);
    }

    root.visitChildren(visit);
    if (fields.isEmpty ||
        fields.length != _editing.paragraphControllers.length) {
      return;
    }
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < fields.length; i++) {
      final local = fields[i].globalToLocal(point);
      final distance = local.dy < 0
          ? -local.dy
          : math.max(0.0, local.dy - fields[i].size.height);
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    final position = fields[best].getPositionForPoint(point);
    _editing.paragraphControllers[best].selection =
        TextSelection.collapsed(offset: position.offset);
  }

  /// The frame on the slide of the box being edited, grown to its draft
  /// text when it grows to fit.
  ElementFrame? get _editingFrame {
    final draft = _editing.draft;
    final slide = _slide;
    if (draft == null || slide == null) return null;
    final cell = _editing.cell;
    if (cell != null) {
      final table = slide.findElement(draft.id);
      final frame = slide.frameOnSlide(draft.id);
      if (table is! TableElement || frame == null) return null;
      final box = table.cellBox(cell.row, cell.column);
      return frameInParent(
        frame,
        ElementFrame(x: box.x, y: box.y, width: box.width, height: box.height),
      );
    }
    var frame = draft.frame;
    if (draft.autoFit == TextAutoFit.grow) {
      final height = SlideTextLayout.forBox(draft, _theme).contentHeight(draft);
      if (height > frame.height) frame = frame.copyWith(height: height);
    }
    return slide.placeOnSlide(draft.id, frame);
  }

  bool _insideEditor(Offset viewPoint) {
    final frame = _editingFrame;
    final viewport = _viewport;
    if (frame == null || viewport == null) return false;
    return frame.contains(
      viewport.toSlide(viewPoint),
      tolerance: _style.handleSize / viewport.scale,
    );
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  /// The selected ids that are on [slide], at any depth, back to front;
  /// none when the canvas does not select.
  Set<String> _validSelection(Slide slide) => {
        if (_selects)
          for (final e in slide.allElements)
            if (_selection.contains(e.id)) e.id,
      };

  void _select(Set<String> ids) {
    if (!_selects) return;
    _leaveUnlessInside(ids);
    if (_cells.tableId != null && !setEquals(ids, {_cells.tableId})) {
      _cells.clear();
    }
    if (setEquals(ids, _selection)) return;
    setState(() => _selection = ids);
    widget.onSelectionChanged?.call(ids);
  }

  /// Reveals [SlideCanvas.currentHighlight] once this frame is laid out,
  /// when it is in a text box on this slide.
  void _revealLater() {
    final match = widget.currentHighlight;
    if (widget.readOnly || match == null) return;
    if (match.slideId != widget.slideId || match.elementId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.currentHighlight == match) _reveal(match);
    });
  }

  /// Enters the group holding [match]'s text box, selects the box, and
  /// pans to center it.
  void _reveal(SlideMatch match) {
    final slide = _slide;
    final id = match.elementId!;
    final frame = slide?.frameOnSlide(id);
    if (slide == null || frame == null) return;
    if (_editing.isEditing && _editing.elementId != id) _editing.commit();
    setState(() => _entered = match.groupId);
    _select({id});
    final viewport = _viewport;
    if (viewport == null) return;
    _viewTo(
      viewport.panToPlace(
        frame.rect.center,
        viewport.viewportSize.center(Offset.zero),
        widget.zoom,
      ),
      widget.zoom,
    );
  }

  /// [SlideCanvas.highlights] on [slide], by text box id.
  Map<String, List<SlideTextHighlight>> _highlightsOn(Slide slide) {
    final current = widget.currentHighlight;
    final byBox = <String, List<SlideTextHighlight>>{};
    for (final m in widget.highlights) {
      final id = m.elementId;
      if (m.slideId != slide.id || id == null) continue;
      (byBox[id] ??= []).add((
        paragraph: m.paragraph,
        start: m.start,
        end: m.end,
        current: m == current,
      ));
    }
    return byBox;
  }

  /// The entered group, when it is still a group on the slide.
  GroupElement? _enteredGroup(Slide slide) {
    final id = _entered;
    final group = id == null ? null : slide.findElement(id);
    return group is GroupElement ? group : null;
  }

  /// Steps out of the entered group unless every one of [ids] is inside it.
  void _leaveUnlessInside(Set<String> ids) {
    final entered = _entered;
    final slide = widget.readOnly ? null : _slide;
    if (entered == null) return;
    final inside = slide != null &&
        ids.isNotEmpty &&
        ids.every(
          (id) => slide.ancestorsOf(id)?.any((g) => g.id == entered) ?? false,
        );
    if (!inside) _entered = null;
  }

  /// Enters the group [groupId] and selects its child [childId].
  void _enter(String groupId, String childId) {
    setState(() => _entered = groupId);
    _select({childId});
  }

  /// The id of the front element under the slide point [point]: a child of
  /// the entered group when the point is on one, otherwise an element on
  /// the slide itself.
  String? _hitAt(Slide slide, Offset point, double tolerance) {
    final group = _enteredGroup(slide);
    if (group != null) {
      final child = _childAt(slide, group, point, tolerance);
      if (child != null) return child;
    }
    return slide.elementAt(point, tolerance: tolerance)?.id;
  }

  /// The front child of [group] under the slide point [point], or `null`.
  static String? _childAt(
    Slide slide,
    GroupElement group,
    Offset point,
    double tolerance,
  ) {
    final frame = slide.frameOnSlide(group.id)!;
    final local = frame.toLocal(point) + Offset(frame.width, frame.height) / 2;
    for (final child in group.children.reversed) {
      if (child.hitTest(local, tolerance: tolerance)) return child.id;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Pointer gestures
  // ---------------------------------------------------------------------------

  bool get _additive {
    final keys = HardwareKeyboard.instance;
    return keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_editing.isEditing) {
      // The editor's own gestures handle pointers inside the box.
      if (_insideEditor(event.localPosition)) return;
      _editing.commit();
    }
    _focusNode.requestFocus();
    final mouse = event.kind == PointerDeviceKind.mouse;
    if (mouse && event.buttons == kMiddleMouseButton) {
      setState(_cancelGesture);
      _gesture = _Gesture(
        _GestureKind.pan,
        pointer: event.pointer,
        startView: event.localPosition,
        startSlide: Offset.zero,
        startPan: _viewport?.pan ?? Offset.zero,
      );
      return;
    }
    if (mouse && event.buttons != kPrimaryMouseButton) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      setState(() => _cancelGesture(revert: true));
      _startPinch();
    } else if (_pointers.length == 1 && _pinch == null) {
      _gesture = _startGesture(event);
    }
  }

  _Gesture? _startGesture(PointerDownEvent event) {
    final viewport = _viewport;
    final slide = _slide;
    if (viewport == null || slide == null) return null;
    final point = event.localPosition;
    final slidePoint = viewport.toSlide(point);
    final selected = _validSelection(slide);
    if (!_selects) {
      // Nothing to select: a drag pans.
      return _Gesture(
        _GestureKind.pan,
        pointer: event.pointer,
        startView: point,
        startSlide: slidePoint,
        startPan: viewport.pan,
      );
    }
    final hit = _hitAt(slide, slidePoint, _style.handleSize / viewport.scale);
    _Gesture gesture(
      _GestureKind kind,
      Set<String> ids, {
      SlideHandle? handle,
      SlideElement? element,
      ElementFrame? frame,
      String? collapseTo,
    }) =>
        _Gesture(
          // A canvas that does not edit presses where it would move.
          kind == _GestureKind.move && !_edits ? _GestureKind.press : kind,
          pointer: event.pointer,
          startView: point,
          startSlide: slidePoint,
          ids: ids,
          handle: handle,
          frame: frame,
          isLine: element is LineElement,
          isImage: element is ImageElement,
          startBounds: kind == _GestureKind.move ? slide.boundsOf(ids) : null,
          collapseTo: collapseTo,
          hit: hit,
        );

    if (_tool.draws) return gesture(_GestureKind.draw, const {});
    if (selected.length == 1) {
      final element = slide.findElement(selected.single)!;
      final frame = slide.frameOnSlide(element.id)!;
      final handle = _edits ? _handleAt(frame, point, viewport) : null;
      if (handle != null) {
        return gesture(
          handle.isResize ? _GestureKind.resize : _GestureKind.rotate,
          selected,
          handle: handle,
          element: element,
          frame: frame,
        );
      }
      if (element is TableElement) {
        final table = _startTableGesture(event, element, frame, hit);
        if (table != null) return table;
      }
    }
    if (hit == null) {
      if (!_additive) _select(const {});
      return gesture(_GestureKind.marquee, _additive ? selected : const {});
    }
    if (_additive) {
      final next = {...selected};
      if (!next.remove(hit)) next.add(hit);
      _select(next);
      return next.contains(hit) ? gesture(_GestureKind.move, next) : null;
    }
    if (!selected.contains(hit)) {
      _select({hit});
      return gesture(_GestureKind.move, {hit});
    }
    return gesture(
      _GestureKind.move,
      selected,
      collapseTo: selected.length > 1 ? hit : null,
    );
  }

  /// A gesture on the selected [table], whose frame on the slide is
  /// [frame]: a column or row resize on one of its grips, or a cell
  /// selection on a cell. `null` — an ordinary move — within
  /// [SlideCanvasStyle.handleSize] of its edge, or for Ctrl, Cmd, or Shift
  /// without cells to extend.
  _Gesture? _startTableGesture(
    PointerDownEvent event,
    TableElement table,
    ElementFrame frame,
    String? hit,
  ) {
    final viewport = _viewport!;
    final point = event.localPosition;
    final slidePoint = viewport.toSlide(point);
    final reach = _style.handleHitSize / 2;
    final grips = _edits
        ? SlideTableGrip.gripsOf(table, frame)
        : const <(SlideTableGrip, Offset)>[];
    for (final (grip, at) in grips) {
      final offset = point - viewport.toView(at);
      if (offset.dx.abs() > reach || offset.dy.abs() > reach) continue;
      return _Gesture(
        _GestureKind.tableResize,
        pointer: event.pointer,
        startView: point,
        startSlide: slidePoint,
        ids: {table.id},
        frame: frame,
        grip: grip,
        startSize: grip.isColumn
            ? table.columnWidths[grip.index]
            : table.rowHeights[grip.index],
        hit: hit,
      );
    }
    final local =
        frame.toLocal(slidePoint) + Offset(frame.width, frame.height) / 2;
    // The band along the edge that moves the table: a handle wide, but
    // never more than a quarter of the cell it cuts into.
    final band = _style.handleSize / viewport.scale;
    double edge(double cell) => math.min(band, cell / 4);
    if (local.dx < edge(table.columnWidths.first) ||
        local.dy < edge(table.rowHeights.first) ||
        local.dx > frame.width - edge(table.columnWidths.last) ||
        local.dy > frame.height - edge(table.rowHeights.last)) {
      return null;
    }
    final cell = hit == table.id ? table.cellAt(local.dx, local.dy) : null;
    if (cell == null) return null;
    final keys = HardwareKeyboard.instance;
    final active = _cells.tableId == table.id ? _cells.active : null;
    final extend = keys.isShiftPressed && active != null;
    if (_additive && !extend) return null;
    final from = extend ? active : cell;
    _cells.select(
      table.id,
      CellRange.spanning(from, cell),
      active: from,
    );
    return _Gesture(
      _GestureKind.cells,
      pointer: event.pointer,
      startView: point,
      startSlide: slidePoint,
      ids: {table.id},
      cell: from,
      hit: hit,
    );
  }

  /// The handle of a single selected [frame] whose hit box holds the
  /// viewport point [point], nearest first.
  SlideHandle? _handleAt(
    ElementFrame frame,
    Offset point,
    SlideViewport viewport,
  ) {
    final reach = _style.handleHitSize / 2;
    SlideHandle? best;
    var bestDistance = double.infinity;
    for (final handle in SlideHandle.values) {
      final center = viewport.toView(
        frame.handlePoint(
          handle,
          rotateOffset: _style.rotateHandleOffset / viewport.scale,
        ),
      );
      final offset = point - center;
      if (offset.dx.abs() > reach || offset.dy.abs() > reach) continue;
      if (offset.distance < bestDistance) {
        best = handle;
        bestDistance = offset.distance;
      }
    }
    return best;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointers.containsKey(event.pointer)) {
      _pointers[event.pointer] = event.localPosition;
    }
    if (_pinch != null) return _updatePinch();
    final gesture = _gesture;
    if (gesture == null || gesture.pointer != event.pointer) return;
    if (!gesture.started) {
      final travel = (event.localPosition - gesture.startView).distance;
      if (travel < computeHitSlop(event.kind, null)) return;
      gesture.started = true;
      if (gesture.kind.edits) {
        gesture
          ..batch = _doc
          ..before = _doc.presentation;
        _doc.beginBatch();
      }
    }
    _updateGesture(gesture, event.localPosition);
  }

  void _updateGesture(_Gesture gesture, Offset point) {
    final viewport = _viewport;
    final slide = _slide;
    if (viewport == null || slide == null) return;
    final slideId = widget.slideId!;
    final slidePoint = viewport.toSlide(point);
    final travel = slidePoint - gesture.startSlide;
    final keys = HardwareKeyboard.instance;
    switch (gesture.kind) {
      case _GestureKind.move:
        final ids = gesture.ids.where((id) => slide.findElement(id) != null);
        final snap = keys.isAltPressed || gesture.startBounds == null
            ? SnapResult(travel, const [])
            : snapMove(
                moving: gesture.startBounds!,
                delta: travel,
                slide: slide,
                size: _size,
                // A grouped element's group follows it; it is no target.
                exclude: {
                  ...gesture.ids,
                  for (final id in gesture.ids)
                    ...?slide.ancestorsOf(id)?.map((g) => g.id),
                },
                threshold: _style.snapDistance / viewport.scale,
              );
        final step = snap.delta - gesture.applied;
        if (step != Offset.zero) {
          _doc.moveElements(slideId, ids, step.dx, step.dy);
        }
        gesture.applied = snap.delta;
        setState(() => _guides = snap.guides);
      case _GestureKind.resize:
        final frame = gesture.frame!.resized(
          gesture.handle!,
          travel,
          // A picture keeps its proportions unless Alt frees them.
          keepAspect:
              gesture.isImage ? !keys.isAltPressed : keys.isShiftPressed,
          minExtent: gesture.isLine ? 0 : 1,
        );
        _doc.resizeElement(
          slideId,
          gesture.ids.single,
          width: frame.width,
          height: frame.height,
          x: frame.x,
          y: frame.y,
        );
      case _GestureKind.tableResize:
        final grip = gesture.grip!;
        final along = rotateOffset(travel, -gesture.frame!.rotation);
        final size = gesture.startSize + (grip.isColumn ? along.dx : along.dy);
        final id = gesture.ids.single;
        if (slide.findElement(id) is! TableElement) return;
        grip.isColumn
            ? _doc.setTableColumnWidth(slideId, id, grip.index, size)
            : _doc.setTableRowHeight(slideId, id, grip.index, size);
      case _GestureKind.cells:
        final id = gesture.ids.single;
        final table = slide.findElement(id);
        final frame = slide.frameOnSlide(id);
        if (table is! TableElement || frame == null) return;
        final local =
            frame.toLocal(slidePoint) + Offset(frame.width, frame.height) / 2;
        final cell = table.cellAt(
          local.dx.clamp(0, frame.width),
          local.dy.clamp(0, frame.height),
        );
        if (cell == null) return;
        _cells.select(
          id,
          CellRange.spanning(gesture.cell!, cell),
          active: gesture.cell,
        );
      case _GestureKind.press:
        return;
      case _GestureKind.rotate:
        _doc.rotateElement(
          slideId,
          gesture.ids.single,
          gesture.frame!.rotationToward(slidePoint, snap: keys.isShiftPressed),
        );
      case _GestureKind.marquee:
        final area = Rect.fromPoints(gesture.startSlide, slidePoint);
        _select({...gesture.ids, ...slide.elementsInside(area)});
        setState(() => _marquee = area);
      case _GestureKind.draw:
        gesture.current = slidePoint;
        final preview = _drawn(gesture.startSlide, slidePoint);
        setState(() {
          _preview = preview is SlideElement ? preview : null;
          _marquee = preview is Rect ? preview : null;
        });
      case _GestureKind.pan:
        _viewTo(gesture.startPan + (point - gesture.startView), widget.zoom);
    }
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinch != null) {
      if (_pointers.length < 2) _pinch = null;
      return;
    }
    final gesture = _gesture;
    if (gesture == null || gesture.pointer != event.pointer) return;
    if (!gesture.started && gesture.collapseTo != null) {
      _select({gesture.collapseTo!});
    }
    setState(_cancelGesture);
    if (gesture.kind == _GestureKind.draw) {
      final end = gesture.started ? gesture.current : null;
      return _insert(at: gesture.startSlide, end: end);
    }
    // A handle that was tapped, not dragged, was a tap on its element: on a
    // phone a short box is all handle.
    if (!gesture.started &&
        (gesture.kind.edits ||
            gesture.kind == _GestureKind.cells ||
            gesture.kind == _GestureKind.press)) {
      _onTap(event, gesture.hit);
    }
  }

  /// Selects [id] for a screen reader's tap, or edits it when it is a text
  /// box selected alone already.
  void _onSemanticSelect(String id) {
    final slide = _slide;
    final edit = _edits &&
        slide != null &&
        setEquals(_validSelection(slide), {id}) &&
        slide.elementById(id) is TextBox;
    if (edit) return _beginEditing(id);
    _focusNode.requestFocus();
    _select({id});
  }

  /// Opens a text box tapped twice in a row for editing.
  void _onTap(PointerEvent event, String? hit) {
    final last = _lastTap;
    final point = event.localPosition;
    _lastTap = hit == null ? null : (event.timeStamp, point, hit);
    if (last == null || hit == null) return;
    final (time, where, id) = last;
    final isDouble = id == hit &&
        event.timeStamp - time <= kDoubleTapTimeout &&
        (point - where).distance <= kDoubleTapSlop;
    final slide = _slide;
    final viewport = _viewport;
    if (!isDouble || slide == null || viewport == null) return;
    final element = slide.findElement(hit);
    if (element is GroupElement) {
      // Into the group, onto the child under the pointer.
      final child = _childAt(
        slide,
        element,
        viewport.toSlide(point),
        _style.handleSize / viewport.scale,
      );
      if (child == null) return;
      _lastTap = null;
      return _enter(hit, child);
    }
    if (element is TableElement) {
      // Into the cell under the pointer.
      final frame = slide.frameOnSlide(hit)!;
      final local = frame.toLocal(viewport.toSlide(point)) +
          Offset(frame.width, frame.height) / 2;
      final cell = element.cellAt(local.dx, local.dy);
      if (cell == null || !_edits) return;
      _lastTap = null;
      _select({hit});
      return _beginCellEditing(
        hit,
        cell.row,
        cell.column,
        caretAt: event.position,
      );
    }
    if (element is! TextBox || !_edits) return;
    _lastTap = null;
    _select({hit});
    _beginEditing(hit, caretAt: event.position);
  }

  /// What a drag from [start] to [end] with the active tool would insert,
  /// with the held modifiers applied: the element itself for a shape or a
  /// line, the box for text or an image. `null` when it is too small to
  /// tell from a click.
  Object? _drawn(Offset start, Offset end) {
    final viewport = _viewport!;
    final keys = HardwareKeyboard.instance;
    final minimum = _style.handleHitSize / viewport.scale;
    final tool = _tool;
    if (tool.mode == SlideToolMode.line) {
      final line = drawnLine(
        start,
        end,
        snap: keys.isShiftPressed,
        fromCenter: keys.isAltPressed,
      );
      final box = line.box;
      if (math.max(box.width, box.height) < minimum) return null;
      final arrow = tool.arrow ? LineCap.arrow : LineCap.none;
      return LineElement(
        id: '',
        frame: _frameOf(box),
        flipped: line.flipped,
        startCap: line.reversed ? arrow : LineCap.none,
        endCap: line.reversed ? LineCap.none : arrow,
        stroke: _doc.shapeStyle.line,
      );
    }
    final box = drawnBox(
      start,
      end,
      square: keys.isShiftPressed,
      fromCenter: keys.isAltPressed,
    );
    if (box.width < minimum && box.height < minimum) return null;
    if (tool.mode == SlideToolMode.table) {
      return newTable(
        id: '',
        frame: _frameOf(box),
        rows: tool.rows,
        columns: tool.columns,
      );
    }
    if (tool.mode != SlideToolMode.shape) return box;
    return ShapeElement(
      id: '',
      frame: _frameOf(box),
      kind: tool.shapeKind!,
      fill: _doc.shapeStyle.fill,
      stroke: _doc.shapeStyle.stroke,
    );
  }

  static ElementFrame _frameOf(Rect box) => ElementFrame(
        x: box.left,
        y: box.top,
        width: box.width,
        height: box.height,
      );

  /// Inserts what the active tool makes, as one undo step: drawn from [at]
  /// to [end] after a drag, placed at its default size with its top-left
  /// corner at [at] after a click, or at the slide's center with neither.
  /// Then selects it and hands the tool back. A text box opens for typing;
  /// the image tool asks the app for a picture instead.
  void _insert({Offset? at, Offset? end}) {
    final slide = _slide;
    if (slide == null) return;
    final tool = _tool;
    final slideId = widget.slideId!;
    final drawn = at != null && end != null ? _drawn(at, end) : null;
    _tools.reset();
    final String id;
    switch (tool.mode) {
      case SlideToolMode.select:
        return;
      case SlideToolMode.image:
        widget.onPickImage?.call(drawn is Rect ? _frameOf(drawn) : null);
        return;
      case SlideToolMode.text:
        const width = SlideDocumentController.defaultTextBoxWidth;
        id = drawn is Rect
            ? _doc.insertTextBox(
                slideId,
                at: (x: drawn.left, y: drawn.top),
                width: drawn.width,
                height: drawn.height,
              )
            : _doc.insertTextBox(
                slideId,
                at: at != null
                    ? (x: at.dx, y: at.dy)
                    : (
                        x: (_size.width - width) / 2,
                        y: (_size.height -
                                SlideDocumentController.defaultTextBoxHeight) /
                            2,
                      ),
              );
      case SlideToolMode.chart:
        final size = _doc.defaultChartSize;
        id = _doc.insertChart(
          slideId,
          tool.chartKind!,
          frame: switch ((drawn, at)) {
            (final Rect box, _) => _frameOf(box),
            (_, final at?) => ElementFrame(
                x: at.dx,
                y: at.dy,
                width: size.width,
                height: size.height,
              ),
            _ => null,
          },
        );
      case SlideToolMode.table:
        final size = _doc.defaultTableSize(tool.rows, tool.columns);
        id = _doc.insertTable(
          slideId,
          tool.rows,
          tool.columns,
          frame: switch ((drawn, at)) {
            (final TableElement table, _) => table.frame,
            (_, final at?) => ElementFrame(
                x: at.dx,
                y: at.dy,
                width: size.width,
                height: size.height,
              ),
            _ => null,
          },
        );
      case SlideToolMode.shape || SlideToolMode.line when drawn is SlideElement:
        final element = drawn.withId(_doc.newId());
        _doc.addElement(slideId, element);
        id = element.id;
      case SlideToolMode.shape:
        const side = SlideDocumentController.defaultShapeSize;
        id = _doc.insertShape(
          slideId,
          tool.shapeKind!,
          frame: at == null
              ? null
              : ElementFrame(x: at.dx, y: at.dy, width: side, height: side),
        );
      case SlideToolMode.line:
        id = _doc.insertLine(
          slideId,
          endCap: tool.arrow ? LineCap.arrow : LineCap.none,
          frame: at == null
              ? null
              : ElementFrame(
                  x: at.dx,
                  y: at.dy,
                  width: SlideDocumentController.defaultLineLength,
                  height: 0,
                ),
        );
    }
    _select({id});
    if (tool.mode == SlideToolMode.text) _beginEditing(id, fresh: true);
  }

  /// Ends the current gesture, closing its undo step and clearing its
  /// guides; [revert] undoes what it changed instead, as a second finger
  /// turning a drag into a pinch does. The caller rebuilds.
  void _cancelGesture({bool revert = false}) {
    final gesture = _gesture;
    _gesture = null;
    _guides = const [];
    _marquee = null;
    _preview = null;
    final batch = gesture?.batch;
    if (batch == null) return;
    batch.endBatch();
    if (revert && batch.presentation != gesture!.before) batch.undo();
  }

  // ---------------------------------------------------------------------------
  // Pan and zoom
  // ---------------------------------------------------------------------------

  /// Pans to [pan] (clamped) at [zoom], reporting a zoom change.
  void _viewTo(Offset pan, double zoom) {
    final viewport = _viewport;
    if (viewport == null) return;
    final clamped = SlideViewport(
      viewportSize: viewport.viewportSize,
      slideSize: viewport.slideSize,
      zoom: zoom,
      pan: pan,
      padding: viewport.padding,
    ).pan;
    if (clamped != _pan) setState(() => _pan = clamped);
    if (zoom != widget.zoom) widget.onZoomChanged?.call(zoom);
  }

  /// [zoom] clamped to the allowed range, or the current zoom when the
  /// caller does not take zoom changes.
  double _allowedZoom(double zoom) => widget.onZoomChanged == null
      ? widget.zoom
      : zoom.clamp(SlideCanvas.minZoom, SlideCanvas.maxZoom);

  void _zoomAround(Offset focal, double zoom) {
    final viewport = _viewport;
    zoom = _allowedZoom(zoom);
    if (viewport == null || zoom == widget.zoom) return;
    _viewTo(viewport.panForZoom(zoom, focal), zoom);
  }

  void _startPinch() {
    final viewport = _viewport;
    if (viewport == null) return;
    final [a, b] = _pointers.values.take(2).toList();
    _pinch = _Pinch(
      viewport.toSlide((a + b) / 2),
      math.max(1, (a - b).distance),
      widget.zoom,
    );
  }

  void _updatePinch() {
    final pinch = _pinch!;
    final viewport = _viewport;
    if (viewport == null || _pointers.length < 2) return;
    final [a, b] = _pointers.values.take(2).toList();
    final zoom = _allowedZoom(pinch.zoom * (a - b).distance / pinch.distance);
    _viewTo(viewport.panToPlace(pinch.slidePoint, (a + b) / 2, zoom), zoom);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final keys = HardwareKeyboard.instance;
      if (event is PointerScaleEvent) {
        _zoomAround(event.localPosition, widget.zoom * event.scale);
      } else if (event is PointerScrollEvent) {
        if (keys.isControlPressed || keys.isMetaPressed) {
          final factor = math.exp(-event.scrollDelta.dy / 200);
          _zoomAround(event.localPosition, widget.zoom * factor);
          return;
        }
        var delta = event.scrollDelta;
        if (keys.isShiftPressed && delta.dx == 0) delta = Offset(delta.dy, 0);
        _viewTo(_pan - delta, widget.zoom);
      }
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) =>
      _trackpadZoom = widget.zoom;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final viewport = _viewport;
    if (viewport == null) return;
    final zoom = _allowedZoom(_trackpadZoom * event.scale);
    final pan = zoom == widget.zoom
        ? _pan
        : viewport.panForZoom(zoom, event.localPosition);
    _viewTo(pan + event.panDelta, zoom);
  }

  void _onHover(PointerHoverEvent event) {
    final viewport = _viewport;
    final slide = _slide;
    if (viewport == null || slide == null) return;
    final over = slide.elementAt(
      viewport.toSlide(event.localPosition),
      tolerance: _style.handleSize / viewport.scale,
    );
    final cursor = over == null || !_selects
        ? MouseCursor.defer
        : _edits
            ? SystemMouseCursors.move
            : SystemMouseCursors.click;
    if (cursor != _cursor) setState(() => _cursor = cursor);
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  static final _nudges = {
    LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
    LogicalKeyboardKey.arrowRight: const Offset(1, 0),
    LogicalKeyboardKey.arrowUp: const Offset(0, -1),
    LogicalKeyboardKey.arrowDown: const Offset(0, 1),
  };

  static final _forwardKeys = {
    LogicalKeyboardKey.bracketRight,
    LogicalKeyboardKey.braceRight,
  };

  static final _backwardKeys = {
    LogicalKeyboardKey.bracketLeft,
    LogicalKeyboardKey.braceLeft,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final slide = _slide;
    if (slide == null ||
        event is KeyUpEvent ||
        _gesture != null ||
        _editing.isEditing ||
        !_selects) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final selected = _validSelection(slide);
    final slideId = widget.slideId!;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final only =
        selected.length == 1 ? slide.findElement(selected.single) : null;
    if (only is TableElement && !command && !_tool.draws) {
      final handled = _onTableKey(only, key, keys.isShiftPressed);
      if (handled != null) return handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      return _cycle(slide, selected, backward: keys.isShiftPressed);
    }
    if (command && key == LogicalKeyboardKey.keyV && _edits) {
      _paste();
      return KeyEventResult.handled;
    }
    if (_tool.draws) {
      if (key == LogicalKeyboardKey.escape) {
        _tools.reset();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _insert();
        return KeyEventResult.handled;
      }
    }
    if (selected.isEmpty) return KeyEventResult.ignored;
    final single =
        selected.length == 1 ? slide.findElement(selected.single) : null;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.f2) {
      if (single is TextBox && _edits) {
        _beginEditing(single.id);
        return KeyEventResult.handled;
      }
      if (single is GroupElement && key != LogicalKeyboardKey.f2) {
        _enter(single.id, single.children.first.id);
        return KeyEventResult.handled;
      }
    }
    final copy = command && key == LogicalKeyboardKey.keyC;
    if (!_edits && key != LogicalKeyboardKey.escape && !copy) {
      return KeyEventResult.ignored;
    }
    final nudge = _nudges[key];
    final toFront = _forwardKeys.contains(key);
    if (nudge != null) {
      final step = nudge * (keys.isShiftPressed ? 10 : 1);
      _doc.moveElements(slideId, selected, step.dx, step.dy);
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _doc.deleteElements(slideId, selected);
      _select(const {});
    } else if (key == LogicalKeyboardKey.escape) {
      // Out of the group, with the group selected; out of the selection.
      final group = _enteredGroup(slide);
      if (group == null) {
        _select(const {});
      } else {
        _select({group.id});
        setState(() => _entered = slide.parentOf(group.id)?.id);
      }
    } else if (copy) {
      _clipboard.copy(_doc, slideId, selected);
    } else if (command && key == LogicalKeyboardKey.keyX) {
      _clipboard.cut(_doc, slideId, selected);
      _select(const {});
    } else if (command && key == LogicalKeyboardKey.keyD) {
      _select(_doc.duplicateElements(slideId, selected).toSet());
    } else if (command && key == LogicalKeyboardKey.keyG) {
      if (keys.isShiftPressed) {
        if (!_doc.canUngroup(slideId, selected)) return KeyEventResult.handled;
        final kept = {
          for (final id in selected)
            if (slide.findElement(id) is! GroupElement) id,
        };
        _select({...kept, ..._doc.ungroupElements(slideId, selected)});
      } else if (_doc.canGroup(slideId, selected)) {
        _select({_doc.groupElements(slideId, selected)});
      }
    } else if (command && (toFront || _backwardKeys.contains(key))) {
      final all = keys.isShiftPressed;
      _doc.arrangeElements(
        slideId,
        selected,
        toFront
            ? (all ? ZOrderMove.toFront : ZOrderMove.forward)
            : (all ? ZOrderMove.toBack : ZOrderMove.backward),
      );
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static final _cellSteps = {
    LogicalKeyboardKey.arrowLeft: (row: 0, column: -1),
    LogicalKeyboardKey.arrowRight: (row: 0, column: 1),
    LogicalKeyboardKey.arrowUp: (row: -1, column: 0),
    LogicalKeyboardKey.arrowDown: (row: 1, column: 0),
  };

  /// The keys of a selected [table]: Enter or F2 edit the keyboard's cell
  /// (the first, with none selected); with cells selected, the arrows move
  /// to the next cell — growing or shrinking the selection with [shift] —
  /// Tab steps through the cells, Delete empties them and Escape lets go.
  /// `null` for a key the table leaves to the canvas.
  KeyEventResult? _onTableKey(
    TableElement table,
    LogicalKeyboardKey key,
    bool shift,
  ) {
    final range = _cells.tableId == table.id ? _cells.range : null;
    final active = range == null ? null : _cells.active;
    final enter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.f2;
    final clear =
        key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace;
    if (!_edits && (enter || clear)) return null;
    if (enter) {
      final cell = active ?? (row: 0, column: 0);
      _beginCellEditing(table.id, cell.row, cell.column);
      return KeyEventResult.handled;
    }
    if (range == null || active == null) return null;
    final step = _cellSteps[key];
    if (key == LogicalKeyboardKey.tab) {
      final next = _stepCell(table, active, backward: shift);
      if (next == null) {
        _cells.clear();
        return KeyEventResult.ignored;
      }
      _cells.select(table.id, CellRange.single(next.row, next.column));
    } else if (step != null && shift) {
      // The corner across from the keyboard's cell moves.
      final row = active.row == range.top ? range.bottom : range.top;
      final column = active.column == range.left ? range.right : range.left;
      final extent = (
        row: (row + step.row).clamp(0, table.rowCount - 1),
        column: (column + step.column).clamp(0, table.columnCount - 1),
      );
      _cells.select(
        table.id,
        CellRange.spanning(active, extent),
        active: active,
      );
    } else if (step != null) {
      final area = table.areaOf(active.row, active.column);
      final row = switch (step.row) {
        < 0 => area.top - 1,
        > 0 => area.bottom + 1,
        _ => active.row,
      };
      final column = switch (step.column) {
        < 0 => area.left - 1,
        > 0 => area.right + 1,
        _ => active.column,
      };
      final next = table.anchorOf(
        row.clamp(0, table.rowCount - 1),
        column.clamp(0, table.columnCount - 1),
      );
      _cells.select(table.id, CellRange.single(next.row, next.column));
    } else if (clear) {
      _cells.clearText();
    } else if (key == LogicalKeyboardKey.escape) {
      _cells.clear();
    } else {
      return null;
    }
    return KeyEventResult.handled;
  }

  /// Pastes the clipboard onto the slide and selects what it pasted, when
  /// the canvas is still on that slide.
  Future<void> _paste() async {
    final slideId = widget.slideId!;
    final document = widget.document;
    final ids = await _clipboard.paste(_doc, slideId);
    if (!mounted ||
        ids.isEmpty ||
        widget.slideId != slideId ||
        widget.document != document) {
      return;
    }
    _select(ids.toSet());
  }

  /// Selects the element after (or before) the selection in stacking
  /// order. Past either end it deselects and lets focus leave the canvas.
  KeyEventResult _cycle(
    Slide slide,
    Set<String> selected, {
    required bool backward,
  }) {
    final scope = _enteredGroup(slide)?.children ?? slide.elements;
    final ids = [for (final e in scope) e.id];
    if (ids.isEmpty) return KeyEventResult.ignored;
    final int next;
    if (selected.isEmpty) {
      next = backward ? ids.length - 1 : 0;
    } else {
      next = backward
          ? ids.indexOf(selected.first) - 1
          : ids.indexOf(selected.last) + 1;
    }
    if (next < 0 || next >= ids.length) {
      _select(const {});
      return KeyEventResult.ignored;
    }
    _select({ids[next]});
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (widget.readOnly) {
      final size = widget.size!;
      return Padding(
        padding: widget.padding,
        child: Center(
          child: AspectRatio(
            aspectRatio: size.aspectRatio,
            child: FittedBox(
              child: SlideStage(
                slide: widget.slide!,
                size: size,
                style: style,
                theme: _theme,
                elementLabel: widget.elementLabel,
                imageBuilder: widget.imageBuilder,
                cellLabel: widget.cellLabel,
                chartDataLabel: widget.chartDataLabel,
              ),
            ),
          ),
        ),
      );
    }
    final Widget canvas = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: widget.document!,
        builder: (context, _) {
          final slide = _slide;
          if (slide == null) return const SizedBox.expand();
          return LayoutBuilder(
            builder: (context, constraints) {
              assert(
                constraints.hasBoundedWidth && constraints.hasBoundedHeight,
                'an editing SlideCanvas needs a bounded box',
              );
              final viewport = _viewport = SlideViewport(
                viewportSize: constraints.biggest,
                slideSize: _size,
                zoom: widget.zoom,
                pan: _pan,
                padding: widget.padding,
              );
              final selected = _validSelection(slide);
              _editing.attach(_doc, widget.slideId!, selected);
              _cells.attach(_doc, widget.slideId!);
              _charts.attach(
                _doc,
                widget.slideId!,
                selected,
                editable: _edits,
              );
              final editingId = _editing.elementId;
              final editingFrame = _editingFrame;
              final theme = _theme;
              final editingCell = _editing.cell;
              final editedTable = editingId == null || editingCell == null
                  ? null
                  : slide.findElement(editingId);
              final cellsOf = _cells.tableId;
              final cellRange = _cells.range;
              final single = selected.length == 1
                  ? slide.findElement(selected.single)
                  : null;
              final tableFrame = single is TableElement && editingId == null
                  ? slide.frameOnSlide(single.id)
                  : null;
              return MouseRegion(
                cursor: _tool.draws ? SystemMouseCursors.precise : _cursor,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerUp,
                  onPointerHover: _onHover,
                  onPointerSignal: _onPointerSignal,
                  onPointerPanZoomStart: _onPanZoomStart,
                  onPointerPanZoomUpdate: _onPanZoomUpdate,
                  child: ClipRect(
                    child: ColoredBox(
                      color: style.backdropColor,
                      child: Stack(
                        children: [
                          Positioned.fromRect(
                            rect: viewport.slideRect,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: SlideStage(
                                slide: slide,
                                size: _size,
                                style: style,
                                theme: theme,
                                elementLabel: widget.elementLabel,
                                imageBuilder: widget.imageBuilder,
                                selection: selected,
                                onSelect: _selects ? _onSemanticSelect : null,
                                editingId: editingId,
                                preview: _preview,
                                highlights: _highlightsOn(slide),
                                cellLabel: widget.cellLabel,
                                chartDataLabel: widget.chartDataLabel,
                                selectedCells:
                                    cellsOf == null || cellRange == null
                                        ? null
                                        : (tableId: cellsOf, range: cellRange),
                                editor: editingId == null
                                    ? null
                                    : SlideTextEditor(
                                        session: _editing,
                                        style: style,
                                        theme: editedTable is TableElement
                                            ? SlideTableView.cellTheme(
                                                editedTable,
                                                editingCell!.row,
                                                theme,
                                              )
                                            : theme,
                                        scale: viewport.scale,
                                        onDone: _editing.commit,
                                        onTab: editingCell == null
                                            ? null
                                            : _tabToCell,
                                      ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            // The chrome takes every hit it is over; while a
                            // box is edited its text needs them instead.
                            child: IgnorePointer(
                              ignoring: editingId != null,
                              child: SlideSelectionOverlay(
                                viewport: viewport,
                                frames: [
                                  for (final id in {
                                    ...selected,
                                    if (editingId != null) editingId,
                                  })
                                    if (id == editingId && editingFrame != null)
                                      editingFrame
                                    else if (slide.frameOnSlide(id)
                                        case final frame?)
                                      frame,
                                ],
                                groupFrame: switch (_enteredGroup(slide)) {
                                  final group? => slide.frameOnSlide(group.id),
                                  null => null,
                                },
                                style: style,
                                guides: _guides,
                                marquee: _marquee,
                                showHandles: _edits,
                                tableGrips: _edits &&
                                        single is TableElement &&
                                        tableFrame != null
                                    ? SlideTableGrip.gripsOf(single, tableFrame)
                                    : const [],
                                tableRotation: tableFrame?.rotation ?? 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    final tool = _tool;
    // A screen reader's way to insert with the active tool: tap the canvas.
    // Always wrapped, so switching tools never rebuilds the canvas anew.
    return Semantics(
      container: tool.draws,
      label: tool.draws ? widget.toolLabel(tool) : null,
      onTap: tool.draws ? _insert : null,
      child: canvas,
    );
  }
}
