import '../controller/slide_document_controller.dart';
import '../format/qslide_format_exception.dart';
import '../format/slide_clipboard_codec.dart';
import '../geometry/slide_tree.dart';

/// Where `SlideCanvas` and a toolbar send copied elements and read pasted
/// ones, as text (see [SlideClipboardCodec]).
///
/// The package never touches the platform clipboard: the app supplies
/// [read] and [write], so it decides how — and whether — to reach the
/// system clipboard. Without one, the canvas uses [SlideClipboard.memory],
/// which copies and pastes inside the app only, across slides and
/// presentations.
///
/// ```dart
/// final clipboard = SlideClipboard(
///   read: () async => (await Clipboard.getData('text/plain'))?.text,
///   write: (text) => Clipboard.setData(ClipboardData(text: text)),
/// );
/// SlideCanvas(document: doc, slideId: slideId, clipboard: clipboard, ...);
///
/// // A toolbar's buttons:
/// await clipboard.copy(doc.controller, slideId, selection);
/// await clipboard.cut(doc.controller, slideId, selection);
/// final pasted = await clipboard.paste(doc.controller, slideId);
/// setState(() => selection = pasted.toSet());
/// ```
class SlideClipboard {
  /// A clipboard backed by [read] and [write].
  const SlideClipboard({required this.read, required this.write});

  /// Returns the clipboard's text, or `null` when it holds none.
  final Future<String?> Function() read;

  /// Replaces the clipboard's text with the given value.
  final Future<void> Function(String text) write;

  static String? _memoryText;

  /// An in-app clipboard shared by every canvas, used when the app passes
  /// none.
  static final SlideClipboard memory = SlideClipboard(
    read: () async => _memoryText,
    write: (text) async => _memoryText = text,
  );

  /// Writes the elements [elementIds] of the slide [slideId] to the
  /// clipboard, with their frames on the slide (see
  /// [SlideDocumentController.copyElements]). Nothing is written when
  /// [elementIds] is empty.
  Future<void> copy(
    SlideDocumentController doc,
    String slideId,
    Iterable<String> elementIds,
  ) async {
    final elements = doc.copyElements(slideId, elementIds);
    if (elements.isEmpty) return;
    await write(SlideClipboardCodec.encode(elements));
  }

  /// Copies [elementIds], then deletes them from the slide [slideId] as one
  /// undo step.
  Future<void> cut(
    SlideDocumentController doc,
    String slideId,
    Iterable<String> elementIds,
  ) async {
    final ids = elementIds.toSet();
    await copy(doc, slideId, ids);
    // The document may have moved on while the clipboard was written.
    final slide = doc.presentation.slideById(slideId);
    if (slide == null) return;
    final still = {
      for (final id in ids)
        if (slide.findElement(id) != null) id,
    };
    if (still.isNotEmpty) doc.deleteElements(slideId, still);
  }

  /// Pastes the clipboard onto the slide [slideId] as one undo step and
  /// returns the new elements' ids, for the caller to select.
  ///
  /// Copied elements paste with fresh ids, [SlideDocumentController.pasteOffset]
  /// past anything they would land on exactly (see
  /// [SlideDocumentController.pasteElements]); images keep their sources.
  /// Any other text pastes as a new text box. Nothing is pasted — and the
  /// list is empty — when the clipboard is empty or blank, holds elements
  /// from a newer version, or the slide is gone by the time it is read.
  Future<List<String>> paste(
    SlideDocumentController doc,
    String slideId,
  ) async {
    final text = await read();
    if (text == null || doc.presentation.slideById(slideId) == null) {
      return const [];
    }
    final List<String>? elements;
    try {
      final decoded = SlideClipboardCodec.decode(text);
      elements = decoded == null ? null : doc.pasteElements(slideId, decoded);
    } on QslideFormatException {
      return const [];
    }
    if (elements != null) return elements;
    final id = doc.pasteText(slideId, text);
    return id == null ? const [] : [id];
  }
}
