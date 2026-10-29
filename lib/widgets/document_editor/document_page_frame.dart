import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:quark/utils/document_markdown_shortcuts.dart';
import 'package:quark/utils/editor_shortcuts.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A `QuillEditorConfig.onKeyPressed` handler: non-null stops the event.
typedef DocumentEditorKeyHandler =
    KeyEventResult? Function(KeyEvent event, Node? node);

DefaultStyles _quillStyles(ColorScheme cs) {
  final fg = cs.onSurface;
  final muted = cs.onSurface.withValues(alpha: 0.5);
  final codeBg = cs.surfaceContainerHighest;
  final outline = cs.outline;

  // `leadingDistribution` is spelled out so every block agrees on where the
  // extra 0.7 of line height goes. A list marker is a plain `Text`, which
  // inherits `even` from the Material theme's typography, while the line
  // beside it is a `RichText` that falls back to the engine's `proportional`.
  // The two split the leading differently, which floated the marker a couple
  // of pixels above the item text's baseline (#2432).
  TextStyle base([double size = 14]) => TextStyle(
    color: fg,
    fontSize: size,
    height: 1.7,
    leadingDistribution: TextLeadingDistribution.proportional,
  );

  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(
      base(),
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    ),
    h1: DefaultTextBlockStyle(
      base(26).copyWith(fontWeight: FontWeight.w600, color: fg),
      HorizontalSpacing.zero,
      const VerticalSpacing(20, 6),
      VerticalSpacing.zero,
      null,
    ),
    h2: DefaultTextBlockStyle(
      base(20).copyWith(fontWeight: FontWeight.w600, color: fg),
      HorizontalSpacing.zero,
      const VerticalSpacing(16, 4),
      VerticalSpacing.zero,
      null,
    ),
    h3: DefaultTextBlockStyle(
      base(16).copyWith(fontWeight: FontWeight.w600, color: fg),
      HorizontalSpacing.zero,
      const VerticalSpacing(12, 4),
      VerticalSpacing.zero,
      null,
    ),
    placeHolder: DefaultTextBlockStyle(
      base().copyWith(color: muted),
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    ),
    // A block style left null here does not inherit `paragraph` — flutter_quill
    // merges its own default over it, which is 16px/1.15 in the *ambient*
    // theme's color rather than the page's. That is what made a list item
    // render bigger and in the wrong color than the body text around it
    // (#1748), so lists and their bullets get the paragraph style explicitly.
    lists: DefaultListBlockStyle(
      base(),
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
      null,
      indentWidthBuilder: _indentWidth,
    ),
    leading: DefaultTextBlockStyle(
      base(),
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    ),
    quote: DefaultTextBlockStyle(
      base().copyWith(color: muted, fontStyle: FontStyle.italic),
      const HorizontalSpacing(16, 0),
      const VerticalSpacing(6, 6),
      VerticalSpacing.zero,
      BoxDecoration(
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
    ),
    inlineCode: InlineCodeStyle(
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: fg,
        backgroundColor: codeBg,
      ),
      backgroundColor: codeBg,
      radius: const Radius.circular(4),
    ),
    code: DefaultTextBlockStyle(
      TextStyle(fontFamily: 'monospace', fontSize: 13, color: fg),
      const HorizontalSpacing(16, 16),
      const VerticalSpacing(8, 8),
      VerticalSpacing.zero,
      BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outline),
      ),
    ),
    color: fg,
  );
}

/// How far a block sits from the page's left edge.
///
/// flutter_quill reads this from `lists` for every block, not only lists. Its
/// default steps one font size per indent level, 14px here, which put a nested
/// list item barely right of its parent so it read as a sibling. This adds a
/// second font size per level, so each level steps as far as the bullet
/// gutter is wide (#2464).
HorizontalSpacing _indentWidth(
  Block block,
  BuildContext context,
  int count,
  LeadingBlockNumberPointWidth numberPointWidth,
) {
  final spacing = TextBlockUtils.defaultIndentWidthBuilder(
    block,
    context,
    count,
    numberPointWidth,
  );
  final level = block.style.attributes[Attribute.indent.key]?.value as int?;
  if (level == null) return spacing;
  final fontSize =
      QuillStyles.getStyles(context, false)?.paragraph?.style.fontSize ?? 16;
  return HorizontalSpacing(spacing.left + fontSize * level, spacing.right);
}

/// The page-shaped card the document is written on, and the editor inside it.
///
/// flutter_quill runs its own text input but exposes no text field to
/// semantics. With semantics on, the web engine types only into the DOM
/// element of a focused, enabled text-field node, so without one every
/// keystroke went nowhere on web (#3743). The node is a leaf, or an inner
/// focusable node takes the click and blurs the field; `value` keeps the text
/// readable to native screen readers. A read-only page leaves its lines as
/// separate nodes to read. The editor stays mounted across the read-only
/// switch.
///
/// Quill registers the focus listener that calls [TextInput.show] only from
/// [State.initState], and only when the editor is created already editable.
/// A document opens read-only, so that listener is never added.
/// [FocusNode.requestFocus] applies in a later microtask, and on a node that
/// is already focused it returns without a keyboard token. This opens the
/// connection with [EditorState.requestKeyboard] once the node is focused,
/// then changes the semantics annotation so the engine's text field updates
/// again after [TextInput.show] has stored its config. Drop both once
/// flutter_quill registers that listener when `readOnly` becomes false.
/// flutter-quill#2531 tracks the missing text-field semantics only.
class DocumentPageFrame extends StatefulWidget {
  final QuillController controller;
  final FocusNode editorFocus;
  final ScrollController scrollController;

  /// Page brightness, chosen independently of the global theme toggle (#938).
  final bool darkPage;

  /// The app's theme color, so the page wears the same palette as the chrome
  /// around it in whichever brightness [darkPage] picks.
  final QuarkThemeColor themeColor;

  /// Read-only / edit mode (#939) — drives whether a caret is drawn at all.
  final bool isReadOnly;
  final VoidCallback onTap;
  final DocumentEditorKeyHandler onKeyPressed;

  const DocumentPageFrame({
    required this.controller,
    required this.editorFocus,
    required this.scrollController,
    required this.darkPage,
    required this.themeColor,
    required this.isReadOnly,
    required this.onTap,
    required this.onKeyPressed,
    super.key,
  });

  @override
  State<DocumentPageFrame> createState() => _DocumentPageFrameState();
}

class _DocumentPageFrameState extends State<DocumentPageFrame> {
  final GlobalKey<QuillEditorState> _editorKey = GlobalKey();

  /// Bumped after each [TextInput.show]. The web engine ignores
  /// [SemanticsProperties.currentValueLength], but the framework only resends
  /// a semantics node whose annotation changed. An already-focused field would
  /// otherwise never reach `SemanticTextField.update` again, and that update
  /// is what attaches the DOM field to the config [TextInput.show] stored.
  int _semanticsGeneration = 0;
  bool _waitingForEditor = false;

  @override
  void initState() {
    super.initState();
    widget.editorFocus.addListener(_onEditorFocusChanged);
  }

  @override
  void didUpdateWidget(DocumentPageFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorFocus != widget.editorFocus) {
      oldWidget.editorFocus.removeListener(_onEditorFocusChanged);
      widget.editorFocus.addListener(_onEditorFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.editorFocus.removeListener(_onEditorFocusChanged);
    super.dispose();
  }

  /// [requestFocus] applies in a microtask. By the time this runs, [hasFocus]
  /// is already true, which is when [EditorState.requestKeyboard] shows the
  /// input instead of requesting focus again.
  void _onEditorFocusChanged() {
    if (!widget.editorFocus.hasFocus || widget.isReadOnly) return;
    _openInputConnection();
  }

  /// The web engine focused this field's DOM element.
  ///
  /// A node that is already focused must show the input itself.
  /// [FocusNode.requestFocus] would return without a keyboard token, and Quill
  /// has no listener to consume one on this path.
  void _onSemanticsFocus() {
    if (widget.isReadOnly) return;
    if (widget.editorFocus.hasFocus) {
      _openInputConnection();
      return;
    }
    widget.editorFocus.requestFocus();
  }

  void _openInputConnection() {
    final editor = _editorKey.currentState?.editableTextKey.currentState;
    if (editor == null) {
      if (_waitingForEditor) return;
      _waitingForEditor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _waitingForEditor = false;
        if (!mounted || !widget.editorFocus.hasFocus || widget.isReadOnly) {
          return;
        }
        _openInputConnection();
      });
      return;
    }
    editor.requestKeyboard();
    // Off web, show() attaches the input directly. On web the engine attaches
    // its DOM field from the next semantics update, which it sends only when
    // the annotation changed.
    if (!mounted || !kIsWeb) return;
    setState(() => _semanticsGeneration++);
  }

  @override
  Widget build(BuildContext context) {
    // When dark page mode is active, use the app's dark theme ColorScheme;
    // when light, use the app's light theme ColorScheme, both in the app's
    // theme color rather than classic's. This keeps the
    // editor page consistent with the rest of the app's design language
    // while allowing the user to choose page brightness independently of
    // the global theme toggle.
    final pageCs = widget.darkPage
        ? QuarkTheme.dark(themeColor: widget.themeColor).colorScheme
        : QuarkTheme.light(themeColor: widget.themeColor).colorScheme;
    final isReadOnly = widget.isReadOnly;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: pageCs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pageCs.outline),
        ),
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
        // The GestureDetector only ever sees taps on the page margin: the
        // editor's own recognizer wins the arena over the text itself, which
        // is why the config below reports those separately (#1853).
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.translucent,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              widget.editorFocus,
              widget.controller,
            ]),
            builder: (context, child) => Semantics(
              container: !isReadOnly,
              textField: !isReadOnly,
              multiline: isReadOnly ? null : true,
              enabled: isReadOnly ? null : true,
              focused: isReadOnly ? null : widget.editorFocus.hasFocus,
              value: isReadOnly
                  ? null
                  : widget.controller.document.toPlainText(),
              // See [_semanticsGeneration]. Omitted off web, where show() attaches
              // the input directly, and while read-only, where this is not a field.
              currentValueLength:
                  !kIsWeb || isReadOnly || _semanticsGeneration == 0
                  ? null
                  : _semanticsGeneration,
              onFocus: isReadOnly ? null : _onSemanticsFocus,
              excludeSemantics: !isReadOnly,
              child: child,
            ),
            child: QuillEditor.basic(
              key: _editorKey,
              controller: widget.controller,
              focusNode: widget.editorFocus,
              scrollController: widget.scrollController,
              config: QuillEditorConfig(
                autoFocus: false,
                expands: false,
                padding: EdgeInsets.zero,
                placeholder: 'Start writing…',
                // A caret only ever appears where typing works. Left to its
                // default, `EditableText` paints one in read-only mode too —
                // and because the field is not focused the blink timer never
                // starts, so it sits there static, reading as "ready to type"
                // when keystrokes go nowhere (#1853).
                showCursor: !isReadOnly,
                // Tab indents the current block, the way it does in every other
                // document editor. Left off — flutter_quill's default — it only
                // indents when the caret sits at the very start of an existing
                // list item, and drops a literal tab character everywhere else
                // (#1855).
                enableAlwaysIndentOnTab: true,
                // A tap on the text itself. False means "not handled here", so
                // Quill still places the caret where the user clicked — the
                // caller only learns the tap happened (#1853).
                onTapUp: (details, getPosition) {
                  widget.onTap();
                  return false;
                },
                customStyles: _quillStyles(pageCs),
                customShortcuts: editorNavigationShortcuts(),
                // Type the markdown, get the block — see
                // [documentSpaceShortcuts] for the whole table (#1854).
                // ignore: experimental_member_use
                characterShortcutEvents: documentCharacterShortcuts,
                // ignore: experimental_member_use
                spaceShortcutEvents: documentSpaceShortcuts,
                // Tab in a code block indents the code, not the block — see
                // [codeBlockTabHandler]. Everything else goes to the caller,
                // which keeps Quill's built-in search dialog from opening on top
                // of the inline find bar — see [quillFindKeyInterceptor].
                // ignore: experimental_member_use
                onKeyPressed: (event, node) =>
                    codeBlockTabHandler(widget.controller, event) ??
                    widget.onKeyPressed(event, node),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
