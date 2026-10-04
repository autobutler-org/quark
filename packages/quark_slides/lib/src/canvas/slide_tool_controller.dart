import 'package:flutter/foundation.dart';

import 'slide_canvas_tool.dart';

/// The tool an editing `SlideCanvas` draws with, shared with the toolbar
/// that picks it.
///
/// The toolbar calls [use] when a tool button is pressed and listens to
/// light the active one; the canvas listens to change what the pointer
/// does, and calls [reset] after each insertion and on Escape, which
/// returns to [SlideCanvasTool.select]. Pass the same controller to both;
/// a canvas given none makes its own.
///
/// ```dart
/// final tools = SlideToolController();
/// SlideCanvas(document: doc, slideId: slideId, tools: tools, ...);
/// ListenableBuilder(
///   listenable: tools,
///   builder: (context, _) => IconButton(
///     isSelected: tools.tool == SlideCanvasTool.line,
///     onPressed: () => tools.use(SlideCanvasTool.line),
///     icon: const Icon(Icons.horizontal_rule),
///   ),
/// );
/// ```
///
/// To insert without a pointer — from a keyboard-activated button, say —
/// call the document's `insertShape`, `insertLine`, `insertTextBox` or
/// `insertImage`, which place the element at the slide's center by default.
/// With a drawing tool active, Enter on a focused canvas does the same.
class SlideToolController extends ChangeNotifier {
  /// Creates a controller holding [initial], [SlideCanvasTool.select] by
  /// default.
  SlideToolController([SlideCanvasTool initial = SlideCanvasTool.select])
      : _tool = initial;

  SlideCanvasTool _tool;

  /// The active tool.
  SlideCanvasTool get tool => _tool;

  /// The active tool's mode.
  SlideToolMode get mode => _tool.mode;

  /// Makes [tool] the active one; notifies only when it changes.
  void use(SlideCanvasTool tool) {
    if (tool == _tool) return;
    _tool = tool;
    notifyListeners();
  }

  /// Returns to [SlideCanvasTool.select].
  void reset() => use(SlideCanvasTool.select);
}
