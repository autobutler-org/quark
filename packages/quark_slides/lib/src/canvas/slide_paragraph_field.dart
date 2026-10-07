import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../model/text_format.dart';
import 'slide_paragraph_editing_controller.dart';
import 'slide_scaled_selection_controls.dart';
import 'slide_text_editing_controller.dart';

/// The editable text of one paragraph in the in-place editor: an
/// [EditableText] over [session]'s paragraph controller [index], with the
/// platform's tap, drag and long-press selection, touch handles and
/// context menu.
///
/// It lays its text out at exactly the width the paragraph's view does
/// (giving the caret its margin beyond it), so lines break in the same
/// places while editing. Keys the field takes over from the platform:
/// Escape calls [onDone]; Ctrl or Cmd with Z, Shift+Z or Y step through the
/// session's history, with B, I or U toggle bold, italic or underline, and
/// with A select every paragraph; the arrow keys and Delete cross into the
/// neighboring paragraph at an edge; Tab is swallowed rather than moving
/// focus between paragraphs.
class SlideParagraphField extends StatefulWidget {
  /// Creates the field of paragraph [index].
  const SlideParagraphField({
    super.key,
    required this.session,
    required this.index,
    required this.style,
    required this.textAlign,
    required this.scale,
    required this.cursorColor,
    required this.selectionColor,
    this.onDone,
  });

  /// The editing session the paragraph belongs to.
  final SlideTextEditingController session;

  /// Which paragraph of the session's draft this is.
  final int index;

  /// The paragraph's root style, for caret height and empty lines.
  final TextStyle style;

  /// The paragraph's alignment.
  final TextAlign textAlign;

  /// Screen pixels per slide unit, to size the caret and handles for the
  /// screen.
  final double scale;

  /// The caret.
  final Color cursorColor;

  /// The selection highlight.
  final Color selectionColor;

  /// Ends editing: Escape.
  final VoidCallback? onDone;

  /// The caret width on screen, in logical pixels.
  static const cursorScreenWidth = 2.0;

  @override
  State<SlideParagraphField> createState() => _SlideParagraphFieldState();
}

class _SlideParagraphFieldState extends State<SlideParagraphField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey();

  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'SlideParagraphField',
    onKeyEvent: _onKey,
  );
  late final _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _showHandles = false;

  @override
  bool get forcePressEnabled =>
      Theme.of(context).platform == TargetPlatform.iOS;

  @override
  bool get selectionEnabled => true;

  SlideParagraphEditingController get _controller =>
      widget.session.paragraphControllers[widget.index];

  bool get _shouldFocus =>
      widget.session.isEditing &&
      widget.session.focusedParagraph == widget.index;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_followFocus);
    _focusNode.addListener(_onFocusChanged);
    _followFocus();
  }

  /// Tells the session when a click, not the session, focused this field.
  void _onFocusChanged() {
    if (_focusNode.hasFocus) widget.session.focusParagraph(widget.index);
  }

  @override
  void didUpdateWidget(SlideParagraphField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_followFocus);
      widget.session.addListener(_followFocus);
    }
    _followFocus();
  }

  @override
  void dispose() {
    widget.session.removeListener(_followFocus);
    _focusNode.dispose();
    super.dispose();
  }

  /// Takes focus when the session's caret moves into this paragraph.
  void _followFocus() {
    if (!_shouldFocus || _focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shouldFocus && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  RenderEditable? get _render => editableTextKey.currentState?.renderEditable;

  bool _onLine(int offset, int lineOf) {
    final render = _render;
    if (render == null) return true;
    final a = render.getLocalRectForCaret(TextPosition(offset: offset));
    final b = render.getLocalRectForCaret(TextPosition(offset: lineOf));
    return (a.top - b.top).abs() < 0.5;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final session = widget.session;
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final i = widget.index;
    final last = session.paragraphControllers.length - 1;
    final selection = _controller.selection;
    final length = _controller.text.length;
    final caret = selection.isCollapsed ? selection.extentOffset : -1;
    final VoidCallback? action = switch (key) {
      LogicalKeyboardKey.escape => widget.onDone,
      LogicalKeyboardKey.tab => () {},
      LogicalKeyboardKey.keyZ when command =>
        keys.isShiftPressed ? session.redo : session.undo,
      LogicalKeyboardKey.keyY when command => session.redo,
      LogicalKeyboardKey.keyB when command => () =>
          session.toggle(TextToggle.bold),
      LogicalKeyboardKey.keyI when command => () =>
          session.toggle(TextToggle.italic),
      LogicalKeyboardKey.keyU when command => () =>
          session.toggle(TextToggle.underline),
      LogicalKeyboardKey.keyA when command => session.selectAll,
      LogicalKeyboardKey.arrowUp
          when !keys.isShiftPressed &&
              i > 0 &&
              caret >= 0 &&
              _onLine(caret, _controller.lead) =>
        () => session.moveToParagraph(i - 1, atEnd: true),
      LogicalKeyboardKey.arrowDown
          when !keys.isShiftPressed &&
              i < last &&
              caret >= 0 &&
              _onLine(caret, length) =>
        () => session.moveToParagraph(i + 1),
      LogicalKeyboardKey.arrowRight
          when !keys.isShiftPressed && i < last && caret == length =>
        () => session.moveToParagraph(i + 1),
      LogicalKeyboardKey.arrowLeft
          when !keys.isShiftPressed && i > 0 && caret == _controller.lead =>
        () => session.moveToParagraph(i - 1, atEnd: true),
      LogicalKeyboardKey.delete when i < last && caret == length => () =>
          session.joinNext(i),
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  TextSelectionControls _platformControls(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
        TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
        TargetPlatform.android ||
        TargetPlatform.fuchsia =>
          materialTextSelectionHandleControls,
        TargetPlatform.linux ||
        TargetPlatform.windows =>
          desktopTextSelectionHandleControls,
      };

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    final show = _gestures.shouldShowSelectionHandles &&
        cause != SelectionChangedCause.keyboard &&
        (cause == SelectionChangedCause.longPress ||
            _controller.text.isNotEmpty);
    if (show != _showHandles) setState(() => _showHandles = show);
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cursorWidth = SlideParagraphField.cursorScreenWidth / widget.scale;
    // The caret's margin, which an EditableText takes out of its width.
    final margin = 1 + cursorWidth;
    return LayoutBuilder(
      builder: (context, constraints) => OverflowBox(
        alignment: AlignmentDirectional.topStart,
        minWidth: constraints.maxWidth + margin,
        maxWidth: constraints.maxWidth + margin,
        fit: OverflowBoxFit.deferToChild,
        child: _gestures.buildGestureDetector(
          behavior: HitTestBehavior.translucent,
          child: EditableText(
            key: editableTextKey,
            controller: _controller,
            focusNode: _focusNode,
            style: widget.style,
            textAlign: widget.textAlign,
            textScaler: TextScaler.noScaling,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            cursorColor: widget.cursorColor,
            cursorWidth: cursorWidth,
            cursorOpacityAnimates: false,
            backgroundCursorColor: CupertinoColors.inactiveGray,
            selectionColor: widget.selectionColor,
            selectionControls: SlideScaledSelectionControls(
              _platformControls(platform),
              widget.scale,
            ),
            showSelectionHandles: _showHandles,
            onSelectionChanged: _onSelectionChanged,
            rendererIgnoresPointer: true,
            paintCursorAboveText: platform == TargetPlatform.iOS ||
                platform == TargetPlatform.macOS,
            contextMenuBuilder: (context, state) =>
                AdaptiveTextSelectionToolbar.editableText(
              editableTextState: state,
            ),
          ),
        ),
      ),
    );
  }
}
