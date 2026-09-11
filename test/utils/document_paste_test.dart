import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/document_paste.dart';

// Pasting had two ways of silently doing nothing: a read-only document, where
// QuillController.clipboardPaste returns before it reads anything, and a
// browser that will not share the clipboard over plain http. Neither said so
// (#1857).
void main() {
  test('a plain paste is left to flutter_quill', () {
    expect(
      documentPasteAction(clipboardAvailable: true, isReadOnly: false),
      DocumentPasteAction.passThrough,
    );
  });

  test('a paste into a read-only document starts editing first', () {
    expect(
      documentPasteAction(clipboardAvailable: true, isReadOnly: true),
      DocumentPasteAction.editThenPaste,
    );
  });

  test('an unreachable clipboard is reported, whatever the mode', () {
    for (final readOnly in [true, false]) {
      expect(
        documentPasteAction(clipboardAvailable: false, isReadOnly: readOnly),
        DocumentPasteAction.unavailable,
        reason: 'readOnly=$readOnly',
      );
    }
  });
}
