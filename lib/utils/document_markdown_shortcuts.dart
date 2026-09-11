/// Markdown-style typing shortcuts for the docs editor (#1854).
///
/// Typing the markdown syntax formats the block, the way Notion, Google Docs
/// and GitHub all behave: `1. ` starts a numbered list, `- ` a bullet, `# ` a
/// heading, and so on. flutter_quill ships a bundle of these but leaves it
/// switched off — `QuillEditorConfig.characterShortcutEvents` and
/// `spaceShortcutEvents` both default to `const []` — so these lists are what
/// `DocumentPageFrame` passes in.
///
/// A space shortcut fires when the line so far is exactly its `character` and
/// the space key is pressed; the space itself is swallowed. A character
/// shortcut fires on its own key and inspects the text behind the caret.
///
/// The block shortcuts, all typed at the start of an otherwise empty line:
///
/// | Type   | Get           |
/// | ------ | ------------- |
/// | `1. `  | numbered list |
/// | `- `   | bullet list   |
/// | `* `   | bullet list   |
/// | `+ `   | bullet list   |
/// | `# `   | heading 1     |
/// | `## `  | heading 2     |
/// | `### ` | heading 3     |
/// | `> `   | blockquote    |
/// | `[] `  | checkbox      |
/// | `[ ] ` | checkbox      |
/// | ```` ``` ```` | code block |
///
/// And inline: `**bold**`, `__bold__`, `*italic*`, `~strike~` and
/// `` `code` ``. Two notes on that list, both flutter_quill's:
///
/// - Strikethrough is **one** tilde, not the two markdown uses. The package
///   binds `~` as a single-character shortcut and ships no double-tilde
///   event, so `~~struck~~` formats nothing.
/// - The two-character forms (`**bold**`, `__bold__`) do not fire at the very
///   start of a document, only from the second character on.
library;

// flutter_quill marks its whole shortcut-event API `@experimental` — the types,
// the standard bundles, and the two config fields that take them. There is no
// stable alternative, so the warning is silenced for the file rather than on
// every line of it; if the API changes under us, this is the file to revisit.
// ignore_for_file: experimental_member_use

import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

// ── Custom block shortcuts ────────────────────────────────────────────────────

const _orderedList = '1.';
const _bullets = ['-', '*', '+'];
const _blockQuote = '>';
const _checkboxes = ['[]', '[ ]'];

final _headings = <(String, Attribute<int?>)>[
  ('#', Attribute.h1),
  ('##', Attribute.h2),
  ('###', Attribute.h3),
];

/// Two backticks, because the event fires on the third one before it lands.
const _codeFence = '``';

/// Drops [phrase] — the markdown syntax the user typed — and formats the line
/// it was on as [attribute].
///
/// `replaceText` with a null selection leaves the caret where it was, so the
/// cursor is moved to the line start explicitly before the format; a block
/// attribute applies to whichever line the (collapsed) selection sits on.
void _formatLineAs(
  QuillController controller,
  String phrase,
  Attribute<dynamic> attribute,
) {
  final lineStart = controller.selection.baseOffset - phrase.length;
  controller
    ..replaceText(lineStart, phrase.length, '', null)
    ..updateSelection(
      TextSelection.collapsed(offset: lineStart),
      ChangeSource.local,
    )
    ..formatSelection(attribute);
}

SpaceShortcutEvent _blockOnSpace(
  String character,
  Attribute<dynamic> attribute,
) => SpaceShortcutEvent(
  character: character,
  handler: (node, controller) {
    _formatLineAs(controller, character, attribute);
    return true;
  },
);

/// ```` ``` ```` opens a code block, on the third backtick rather than on a
/// following space — nobody types a space to close a fence.
///
/// This has to sit ahead of flutter_quill's `formatCodeCharToInlineCode`,
/// which claims the same key: returning false hands the backtick on to it, so
/// `` `code` `` still works everywhere else.
final CharacterShortcutEvent _formatFenceToCodeBlock = CharacterShortcutEvent(
  key: 'Format a triple backtick to a code block',
  character: '`',
  handler: (controller) {
    final selection = controller.selection;
    if (!selection.isCollapsed) return false;
    final line = controller.document.queryChild(selection.baseOffset).node;
    if (line is! Line || line.isEmpty) return false;
    if (line.style.attributes.containsKey(Attribute.codeBlock.key)) {
      return false;
    }
    final first = line.first;
    if (first is! QuillText || first.value != _codeFence) return false;
    // Only when the caret sits right after the fence, not elsewhere on a line
    // that happens to start with one.
    if (selection.baseOffset != line.documentOffset + _codeFence.length) {
      return false;
    }
    _formatLineAs(controller, _codeFence, Attribute.codeBlock);
    return true;
  },
);

// ── The lists the editor is configured with ───────────────────────────────────

/// Block shortcuts that fire on the space key.
///
/// flutter_quill's own `standardSpaceShorcutEvents` covers the first six of
/// these, but it is not used: its handler replaces the phrase with a line
/// break and then deletes the break again, and Quill refuses to delete a
/// document's trailing newline, so a shortcut typed on the last line leaves an
/// empty paragraph behind it. [_formatLineAs] deletes the phrase outright and
/// behaves the same wherever it is typed.
final documentSpaceShortcuts = List<SpaceShortcutEvent>.unmodifiable([
  _blockOnSpace(_orderedList, Attribute.ol),
  for (final bullet in _bullets) _blockOnSpace(bullet, Attribute.ul),
  for (final (hashes, heading) in _headings) _blockOnSpace(hashes, heading),
  for (final box in _checkboxes) _blockOnSpace(box, Attribute.unchecked),
  _blockOnSpace(_blockQuote, Attribute.blockQuote),
]);

/// Inline shortcuts, plus the code fence, that fire on their own character.
///
/// The inline ones are flutter_quill's, unchanged.
final documentCharacterShortcuts = List<CharacterShortcutEvent>.unmodifiable([
  // Ahead of the standard bundle: it binds the same backtick to inline code.
  _formatFenceToCodeBlock,
  ...standardCharactersShortcutEvents,
]);
