import 'package:flutter/foundation.dart';

import '../canvas/slide_text_layout.dart';
import '../model/presentation.dart';
import 'slide_document_controller.dart';

/// A [ChangeNotifier] over a [SlideDocumentController], for Flutter UI.
///
/// It adds nothing but notification: issue commands on [controller], and
/// listeners hear about every change to the presentation and its history.
///
/// ```dart
/// final doc = SlideDocumentNotifier(QslideCodec.decode(text));
/// ListenableBuilder(
///   listenable: doc,
///   builder: (context, _) => Text('${doc.presentation.slides.length}'),
/// );
/// doc.controller.addSlide();
/// ```
class SlideDocumentNotifier extends ChangeNotifier {
  /// Creates a notifier editing [presentation]; [newId], [maxUndoDepth]
  /// and [measureText] are passed to the [SlideDocumentController].
  ///
  /// [measureText] defaults to [SlideTextLayout]'s, at the canvas's default
  /// text size, so text boxes grow to fit their text; an app that draws
  /// with a different `SlideCanvasStyle.fontSize` passes
  /// `SlideTextLayout.fromStyle(style).measure`.
  SlideDocumentNotifier(
    Presentation presentation, {
    String Function()? newId,
    int maxUndoDepth = 100,
    TextBoxMeasurer? measureText,
  }) {
    controller = SlideDocumentController(
      presentation,
      newId: newId,
      onChanged: notifyListeners,
      maxUndoDepth: maxUndoDepth,
      measureText: measureText ?? const SlideTextLayout().measure,
    );
  }

  /// The controller every command goes through.
  late final SlideDocumentController controller;

  /// The current presentation; shorthand for `controller.presentation`.
  Presentation get presentation => controller.presentation;

  @override
  void dispose() {
    controller.onChanged = null;
    super.dispose();
  }
}
