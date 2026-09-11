import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:quark/utils/document_markdown_shortcuts.dart';
import 'package:quark/utils/editor_shortcuts.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A `QuillEditorConfig.onKeyPressed` handler: non-null stops the event.
typedef DocumentEditorKeyHandler =
    KeyEventResult? Function(KeyEvent event, Node? node);

// ── Quill styles ──────────────────────────────────────────────────────────────

DefaultStyles _quillStyles(ColorScheme cs) {
  final fg = cs.onSurface;
  final muted = cs.onSurface.withValues(alpha: 0.5);
  final codeBg = cs.surfaceContainerHighest;
  final codeColor = cs.secondary;
  final outline = cs.outline;

  TextStyle base([double size = 14]) =>
      TextStyle(color: fg, fontSize: size, height: 1.7);

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
        color: codeColor,
        backgroundColor: codeBg,
      ),
      backgroundColor: codeBg,
      radius: const Radius.circular(4),
    ),
    code: DefaultTextBlockStyle(
      TextStyle(fontFamily: 'monospace', fontSize: 13, color: codeColor),
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

/// The page-shaped card the document is written on, and the editor inside it.
class DocumentPageFrame extends StatelessWidget {
  final QuillController controller;
  final FocusNode editorFocus;
  final ScrollController scrollController;

  /// Page brightness, chosen independently of the global theme toggle (#938).
  final bool darkPage;

  /// Read-only / edit mode (#939) — drives whether a caret is drawn at all.
  final bool isReadOnly;
  final VoidCallback onTap;
  final DocumentEditorKeyHandler onKeyPressed;

  const DocumentPageFrame({
    required this.controller,
    required this.editorFocus,
    required this.scrollController,
    required this.darkPage,
    required this.isReadOnly,
    required this.onTap,
    required this.onKeyPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // When dark page mode is active, use the app's dark theme ColorScheme;
    // when light, use the app's light theme ColorScheme. This keeps the
    // editor page consistent with the rest of the app's design language
    // while allowing the user to choose page brightness independently of
    // the global theme toggle.
    final pageCs = darkPage
        ? QuarkTheme.dark().colorScheme
        : QuarkTheme.light().colorScheme;

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
          onTap: onTap,
          behavior: HitTestBehavior.translucent,
          child: QuillEditor.basic(
            controller: controller,
            focusNode: editorFocus,
            scrollController: scrollController,
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
              // A tap on the text itself. False means "not handled here", so
              // Quill still places the caret where the user clicked — the
              // caller only learns the tap happened (#1853).
              onTapUp: (details, getPosition) {
                onTap();
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
              // Keeps Quill's built-in search dialog from opening on top of the
              // inline find bar — see [quillFindKeyInterceptor].
              // ignore: experimental_member_use
              onKeyPressed: onKeyPressed,
            ),
          ),
        ),
      ),
    );
  }
}
