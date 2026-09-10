import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
