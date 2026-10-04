import 'package:flutter/foundation.dart';

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
  /// Creates a notifier editing [presentation]; [newId] and [maxUndoDepth]
  /// are passed to the [SlideDocumentController].
  SlideDocumentNotifier(
    Presentation presentation, {
    String Function()? newId,
    int maxUndoDepth = 100,
  }) {
    controller = SlideDocumentController(
      presentation,
      newId: newId,
      onChanged: notifyListeners,
      maxUndoDepth: maxUndoDepth,
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
