import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/document_markdown_shortcuts.dart';

// The shortcut events are dispatched by flutter_quill's key handling, which
// needs a live editor. These drive the same two loops by hand — the space one
// matches the line's first leaf against `character`, the character one matches
// the key — so the handlers themselves are under test without a widget.
void main() {
  late QuillController controller;

  setUp(() => controller = QuillController.basic());
  tearDown(() => controller.dispose());

  /// Puts [text] on the (single, empty) document line with the caret after it.
  void typed(String text) {
    controller.document.insert(0, text);
    controller.updateSelection(
      TextSelection.collapsed(offset: text.length),
      ChangeSource.local,
    );
  }

  /// The space key, as [EditorKeyboardShortcuts] dispatches it.
  bool pressSpace() {
    final line = controller.document
        .queryChild(controller.selection.baseOffset)
        .node;
    if (line is! Line || line.isEmpty) return false;
    final first = line.first;
    if (first is! QuillText) return false;
    for (final event in documentSpaceShortcuts) {
      if (event.character == first.value && event.execute(first, controller)) {
        return true;
      }
    }
    return false;
  }

  /// A printable key, as [EditorKeyboardShortcuts] dispatches it.
  bool press(String character) {
    for (final event in documentCharacterShortcuts) {
      if (event.character == character && event.execute(controller)) {
        return true;
      }
    }
    return false;
  }

  /// The attributes on the line the caret is on. Quill hangs block attributes
  /// off the line's newline, so this is where `list`, `blockquote` and friends
  /// show up.
  Map<String, dynamic> lineAttributes() {
    for (final op in controller.document.toDelta().toJson()) {
      if (op['insert'] == '\n') {
        return (op['attributes'] as Map<String, dynamic>?) ?? {};
      }
    }
    return {};
  }

  String plainText() => controller.document.toPlainText();

  group('space shortcuts', () {
    test('1. starts a numbered list', () {
      typed('1.');

      expect(pressSpace(), isTrue);
      expect(lineAttributes(), containsPair('list', 'ordered'));
      expect(plainText().trim(), isEmpty);
    });

    test('- starts a bullet list', () {
      typed('-');

      expect(pressSpace(), isTrue);
      expect(lineAttributes(), containsPair('list', 'bullet'));
    });

    for (final alias in ['*', '+']) {
      test('$alias starts a bullet list too', () {
        typed(alias);

        expect(pressSpace(), isTrue);
        expect(lineAttributes(), containsPair('list', 'bullet'));
        expect(plainText().trim(), isEmpty);
      });
    }

    test('# through ### start headings', () {
      for (final (hashes, level) in [('#', 1), ('##', 2), ('###', 3)]) {
        controller.dispose();
        controller = QuillController.basic();
        typed(hashes);

        expect(pressSpace(), isTrue, reason: hashes);
        expect(lineAttributes(), containsPair('header', level), reason: hashes);
      }
    });

    test('> starts a blockquote', () {
      typed('>');

      expect(pressSpace(), isTrue);
      expect(lineAttributes(), containsPair('blockquote', true));
      expect(plainText().trim(), isEmpty);
    });

    for (final box in ['[]', '[ ]']) {
      test('$box starts an unchecked checkbox', () {
        typed(box);

        expect(pressSpace(), isTrue);
        expect(lineAttributes(), containsPair('list', 'unchecked'));
        expect(plainText().trim(), isEmpty);
      });
    }

    test('leaves a line that only looks like a shortcut alone', () {
      typed('todo');

      expect(pressSpace(), isFalse);
      expect(lineAttributes(), isEmpty);
      expect(plainText().trim(), 'todo');
    });
  });

  group('character shortcuts', () {
    test('a third backtick opens a code block', () {
      typed('``');

      expect(press('`'), isTrue);
      expect(lineAttributes(), containsPair('code-block', true));
      expect(plainText().trim(), isEmpty);
    });

    test('the code fence does not swallow inline code', () {
      typed('`code');

      expect(press('`'), isTrue);
      expect(lineAttributes(), isNot(contains('code-block')));
      expect(plainText().trim(), 'code');
    });

    test('a backtick mid-sentence is just a backtick', () {
      typed('a fence like ``');

      expect(press('`'), isFalse);
      expect(lineAttributes(), isEmpty);
    });

    test('** wraps the word in bold', () {
      typed('say **bold*');

      expect(press('*'), isTrue);
      expect(plainText().trim(), 'say bold');
    });

    test('* on its own is left for the italic shortcut to miss', () {
      typed('say *word');

      expect(press('*'), isTrue);
      expect(plainText().trim(), 'say word');
    });

    // flutter_quill's double-character handler scans back with `i > 0`, so it
    // never looks at index 0 and comes up one delimiter short. Its
    // single-character sibling works around exactly this; the double one never
    // got the same treatment. Pinned here so the day it is fixed upstream,
    // this test says so rather than the behavior changing unnoticed.
    test('** at the very start of a document does not fire (upstream)', () {
      typed('**bold*');

      expect(press('*'), isFalse);
      expect(plainText().trim(), '**bold*');
    });
  });
}
