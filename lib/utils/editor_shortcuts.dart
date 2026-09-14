import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Tab and Shift+Tab inside a code block, for `QuillEditorConfig.onKeyPressed`.
///
/// With `enableAlwaysIndentOnTab` on (#1855), flutter_quill answers Tab with
/// `indentSelection`, which sets the `indent` block attribute even on a code
/// line — and the code-block gutter then numbers indented lines in outline
/// style (a., i., ...) as if they were nested list items. Here Tab indents the
/// code instead, the way a code editor does: a tab character at the caret, or
/// at the start of every selected code line. Shift+Tab removes one leading tab,
/// or up to two leading spaces, from the caret's line or every selected one.
///
/// Returns null outside code blocks, so Quill handles the key as usual.
KeyEventResult? codeBlockTabHandler(
  QuillController controller,
  KeyEvent event,
) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.tab) {
    return null;
  }
  final keyboard = HardwareKeyboard.instance;
  if (controller.readOnly ||
      keyboard.isAltPressed ||
      keyboard.isControlPressed ||
      keyboard.isMetaPressed) {
    return null;
  }
  final selection = controller.selection;
  final first = controller.document.queryChild(selection.start).node;
  if (first is! Line || !first.style.containsKey(Attribute.codeBlock.key)) {
    return null;
  }
  final indent = !keyboard.isShiftPressed;
  if (indent && selection.isCollapsed) {
    controller.replaceText(
      selection.start,
      0,
      '\t',
      TextSelection.collapsed(offset: selection.start + 1),
    );
    return KeyEventResult.handled;
  }

  final lines = <Line>[];
  for (
    Line? line = first;
    line != null && (line == first || line.documentOffset < selection.end);
    line = line.nextLine
  ) {
    if (line.style.containsKey(Attribute.codeBlock.key)) lines.add(line);
  }
  var base = selection.baseOffset;
  var extent = selection.extentOffset;
  // Bottom-up, so each line's offset is still valid when its turn comes.
  for (final line in lines.reversed) {
    final start = line.documentOffset;
    final text = line.toPlainText();
    final removed = indent
        ? 0
        : text.startsWith('\t')
        ? 1
        : RegExp(' {0,2}').matchAsPrefix(text)!.end;
    final inserted = indent ? 1 : 0;
    if (removed == 0 && inserted == 0) continue;
    // Silent until the selection below is valid again: a listener that sees
    // the old selection past the end of the shortened text asserts.
    controller.replaceText(
      start,
      removed,
      indent ? '\t' : '',
      null,
      // ignore: experimental_member_use
      shouldNotifyListeners: false,
    );
    int shift(int offset) =>
        offset > start ? math.max(start, offset - removed) + inserted : offset;
    base = shift(base);
    extent = shift(extent);
  }
  controller.updateSelection(
    TextSelection(baseOffset: base, extentOffset: extent),
    ChangeSource.local,
  );
  return KeyEventResult.handled;
}

Map<ShortcutActivator, Intent> editorNavigationShortcuts({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  if (!isWeb) return const {};
  final target = platform ?? defaultTargetPlatform;
  final apple = target == TargetPlatform.macOS || target == TargetPlatform.iOS;
  return apple ? _appleShortcuts : _otherShortcuts;
}

const Map<ShortcutActivator, Intent> _appleShortcuts = {
  SingleActivator(LogicalKeyboardKey.backspace, alt: true):
      DeleteToNextWordBoundaryIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.backspace, alt: true, shift: true):
      DeleteToNextWordBoundaryIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.backspace, meta: true):
      DeleteToLineBreakIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.backspace, meta: true, shift: true):
      DeleteToLineBreakIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.delete, alt: true):
      DeleteToNextWordBoundaryIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.delete, alt: true, shift: true):
      DeleteToNextWordBoundaryIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.delete, meta: true):
      DeleteToLineBreakIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.delete, meta: true, shift: true):
      DeleteToLineBreakIntent(forward: true),

  SingleActivator(
    LogicalKeyboardKey.arrowLeft,
    alt: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowRight,
    alt: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
      ExtendSelectionToLineBreakIntent(forward: false, collapseSelection: true),
  SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
      ExtendSelectionToLineBreakIntent(forward: true, collapseSelection: true),
  SingleActivator(
    LogicalKeyboardKey.arrowLeft,
    alt: true,
    shift: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowRight,
    alt: true,
    shift: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: true,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowUp,
    alt: true,
    shift: true,
  ): ExtendSelectionToLineBreakIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown, alt: true, shift: true):
      ExtendSelectionToLineBreakIntent(forward: true, collapseSelection: false),

  SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
      ExtendSelectionToLineBreakIntent(forward: false, collapseSelection: true),
  SingleActivator(LogicalKeyboardKey.arrowRight, meta: true):
      ExtendSelectionToLineBreakIntent(forward: true, collapseSelection: true),
  SingleActivator(
    LogicalKeyboardKey.arrowUp,
    meta: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowDown,
    meta: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true, shift: true):
      ExpandSelectionToLineBreakIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.arrowRight, meta: true, shift: true):
      ExpandSelectionToLineBreakIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.arrowUp, meta: true, shift: true):
      ExpandSelectionToDocumentBoundaryIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.arrowDown, meta: true, shift: true):
      ExpandSelectionToDocumentBoundaryIntent(forward: true),

  SingleActivator(LogicalKeyboardKey.home): ScrollToDocumentBoundaryIntent(
    forward: false,
  ),
  SingleActivator(LogicalKeyboardKey.end): ScrollToDocumentBoundaryIntent(
    forward: true,
  ),
  SingleActivator(LogicalKeyboardKey.home, shift: true):
      ExpandSelectionToDocumentBoundaryIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.end, shift: true):
      ExpandSelectionToDocumentBoundaryIntent(forward: true),
};

const Map<ShortcutActivator, Intent> _otherShortcuts = {
  SingleActivator(LogicalKeyboardKey.backspace, control: true):
      DeleteToNextWordBoundaryIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.backspace, control: true, shift: true):
      DeleteToNextWordBoundaryIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.backspace, alt: true):
      DeleteToLineBreakIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.backspace, alt: true, shift: true):
      DeleteToLineBreakIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.delete, control: true):
      DeleteToNextWordBoundaryIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.delete, control: true, shift: true):
      DeleteToNextWordBoundaryIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.delete, alt: true):
      DeleteToLineBreakIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.delete, alt: true, shift: true):
      DeleteToLineBreakIntent(forward: true),

  SingleActivator(
    LogicalKeyboardKey.arrowLeft,
    control: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowRight,
    control: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowLeft,
    control: true,
    shift: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowRight,
    control: true,
    shift: true,
  ): ExtendSelectionToNextWordBoundaryIntent(
    forward: true,
    collapseSelection: false,
  ),

  SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
      ExtendSelectionToLineBreakIntent(forward: false, collapseSelection: true),
  SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
      ExtendSelectionToLineBreakIntent(forward: true, collapseSelection: true),
  SingleActivator(
    LogicalKeyboardKey.arrowUp,
    alt: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowDown,
    alt: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowLeft,
    alt: true,
    shift: true,
  ): ExtendSelectionToLineBreakIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, shift: true):
      ExtendSelectionToLineBreakIntent(forward: true, collapseSelection: false),
  SingleActivator(
    LogicalKeyboardKey.arrowUp,
    alt: true,
    shift: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.arrowDown,
    alt: true,
    shift: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: true,
    collapseSelection: false,
  ),

  SingleActivator(LogicalKeyboardKey.home): ExtendSelectionToLineBreakIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(LogicalKeyboardKey.end): ExtendSelectionToLineBreakIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.home,
    shift: true,
  ): ExtendSelectionToLineBreakIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(LogicalKeyboardKey.end, shift: true):
      ExtendSelectionToLineBreakIntent(forward: true, collapseSelection: false),
  SingleActivator(
    LogicalKeyboardKey.home,
    control: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.end,
    control: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.home,
    control: true,
    shift: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.end,
    control: true,
    shift: true,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: true,
    collapseSelection: false,
  ),
};
