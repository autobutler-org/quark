import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/document_viewer_files.dart';
import 'package:quark/utils/file_kind.dart';

/// Which files the read-only document viewer claims (#3265), and where
/// "Open as Quark doc" puts its copy.
void main() {
  test('the viewer opens Word, OpenDocument and RTF documents', () {
    for (final name in ['a.docx', 'a.docm', 'a.odt', 'a.rtf', 'A.DOCX']) {
      expect(opensInDocumentViewer(name), isTrue, reason: name);
    }
    for (final name in ['a.qdoc', 'a.doc', 'a.pdf', 'a.pptx', 'docx']) {
      expect(opensInDocumentViewer(name), isFalse, reason: name);
    }
  });

  test('every extension the viewer opens is a Document in the file table', () {
    for (final extension in documentViewerExtensions) {
      expect(fileKindForName('a$extension'), FileKind.docx, reason: extension);
    }
  });

  test('the converted copy sits beside the document as a .qdoc', () {
    expect(siblingQdocPath('resume.docx'), 'resume.qdoc');
    expect(
      siblingQdocPath('papers/my cv.final.odt'),
      'papers/my cv.final.qdoc',
    );
    expect(siblingQdocPath('v1.2/notes.rtf'), 'v1.2/notes.qdoc');
  });
}
