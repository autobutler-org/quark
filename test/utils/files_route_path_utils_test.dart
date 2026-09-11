import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/files_route_path_utils.dart';

void main() {
  group('isLikelyFilePath', () {
    test('returns false for empty and folder-like paths', () {
      expect(isLikelyFilePath(''), isFalse);
      expect(isLikelyFilePath('/Documents'), isFalse);
      expect(isLikelyFilePath('/Documents/Projects/'), isFalse);
    });

    test('returns true when the final segment looks like a file', () {
      expect(isLikelyFilePath('/Documents/report.qdoc'), isTrue);
      expect(isLikelyFilePath('/Documents/archive.zip'), isTrue);
    });

    test('recognizes a deep-linked sheet at the root', () {
      // Used for display and navigation decisions, not for suppressing the
      // directory listing on a file route — that guard reads exact open-file
      // state instead, because this is a heuristic (see the case below).
      // Root-level and non-ASCII names take the same branch as any other.
      expect(isLikelyFilePath('/budget.qsheet'), isTrue);
      expect(
        isLikelyFilePath('/\u{1F3CB}\uFE0F_Strength Training.qsheet'),
        isTrue,
      );
    });

    test('cannot tell a dotted folder from a file', () {
      // Deliberate: a name heuristic, not a fact about the backend. This is
      // why the file browser never gates a network request on it — a real
      // folder called `things.qdoc` would stop listing entirely — and stats
      // the path instead.
      expect(isLikelyFilePath('/Documents/things.qdoc'), isTrue);
    });
  });

  group('filesRouteDisplayPath', () {
    test('formats empty and non-empty files paths', () {
      expect(filesRouteDisplayPath(''), '/files');
      expect(
        filesRouteDisplayPath('/Documents/report.qdoc'),
        '/files/Documents/report.qdoc',
      );
    });
  });

  group('supported editor helpers', () {
    test('recognize editor-backed file paths and types', () {
      expect(hasSupportedFilesEditorForPath('/Documents/report.qdoc'), isTrue);
      expect(
        hasSupportedFilesEditorForPath('/Documents/budget.qsheet'),
        isTrue,
      );
      expect(hasSupportedFilesEditorForPath('/Documents/photo.jpg'), isFalse);

      expect(hasSupportedFilesEditorForType('qdoc'), isTrue);
      expect(hasSupportedFilesEditorForType('qsheet'), isTrue);
      expect(hasSupportedFilesEditorForType('image'), isFalse);
    });
  });

  group('usesGenericFileViewer', () {
    test('covers the document types that had no viewer', () {
      // These reached the "No supported editor" dead end before #1184.
      expect(usesGenericFileViewer('pdf'), isTrue);
      expect(usesGenericFileViewer('docx'), isTrue);
      expect(usesGenericFileViewer('slideshow'), isTrue);
      expect(usesGenericFileViewer('epub'), isTrue);
    });

    test('covers a raw workbook opened by URL', () {
      // The file browser offers to convert a workbook before it gets here, so
      // this is the deep-link fallback: download and "Open with", not the
      // dead end an unnamed type used to reach (#1741).
      expect(usesGenericFileViewer('xlsx'), isTrue);
    });

    test('covers unclassified files', () {
      expect(usesGenericFileViewer('generic'), isTrue);
      expect(usesGenericFileViewer(''), isTrue);
      expect(usesGenericFileViewer('  '), isTrue);
      expect(usesGenericFileViewer('PDF'), isTrue, reason: 'case-insensitive');
    });

    test('leaves types that have a real viewer alone', () {
      for (final type in [
        'qdoc',
        'qsheet',
        'image',
        'video',
        'audio',
        'text',
        'archive',
        'folder',
      ]) {
        expect(usesGenericFileViewer(type), isFalse, reason: type);
      }
    });
  });

  group('opensStraightInSystemViewer', () {
    bool opens(String type, {bool isWeb = false, TargetPlatform? platform}) =>
        opensStraightInSystemViewer(
          type,
          isWeb: isWeb,
          platform: platform ?? TargetPlatform.iOS,
        );

    test('skips the "Open with" tap for a PDF on iOS', () {
      // QuickLook is the only handler, so the tap bought nothing (#1807).
      expect(opens('pdf'), isTrue);
      expect(opens(' PDF '), isTrue, reason: 'case- and space-insensitive');
    });

    test('keeps the tap where it is a real choice', () {
      expect(opens('pdf', platform: TargetPlatform.android), isFalse);
      expect(opens('pdf', isWeb: true), isFalse);
      for (final type in ['docx', 'epub', 'xlsx', 'slideshow', 'generic']) {
        expect(opens(type), isFalse, reason: type);
      }
    });
  });

  group('fileNameWithoutExtension', () {
    test('keeps every letter of the name', () {
      // Both editors save under this name. Counting the extension by hand cut
      // a letter off each save, so the sheet was written to a new file every
      // time: budget.qsheet -> budge.qsheet.
      expect(
        fileNameWithoutExtension('/files/data/budget.qsheet', '.qsheet'),
        'budget',
      );
      expect(fileNameWithoutExtension('/files/notes.qdoc', '.qdoc'), 'notes');
    });

    test('leaves a name without the extension alone', () {
      expect(fileNameWithoutExtension('/files/budget', '.qsheet'), 'budget');
      expect(
        fileNameWithoutExtension('/files/budget.csv', '.qsheet'),
        'budget.csv',
      );
    });

    test('strips only the trailing extension', () {
      expect(
        fileNameWithoutExtension('/files/q3.qsheet.qsheet', '.qsheet'),
        'q3.qsheet',
      );
      expect(fileNameWithoutExtension('/a.qsheet/b.qsheet', '.qsheet'), 'b');
    });
  });
}
