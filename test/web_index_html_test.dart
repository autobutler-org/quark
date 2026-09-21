import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Flutter parks a hidden `<textarea>` over the canvas to drive text input and
/// keeps it invisible with `color: transparent`. Firefox will not paint
/// selected text in a color it considers invisible: it inverts that transparent
/// to opaque white, so selecting anything in the document editor draws the
/// textarea's own copy of the text on top of the canvas — doubled, and wrapped
/// differently because the textarea falls back to another font (#1747).
///
/// Naming both selection colors stops the substitution. Only `web/index.html`
/// can say it — the element belongs to the engine, not to any widget — so this
/// guards the rule against a well-meaning cleanup.
void main() {
  String flattened() =>
      File('web/index.html').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

  test('index.html keeps the hidden text input transparent while selected', () {
    expect(
      flattened(),
      contains(
        '.flt-text-editing::selection '
        '{ background-color: transparent; color: transparent; }',
      ),
    );
  });

  /// #2019: a cold load spent seconds on a blank white viewport before the
  /// bundle started. The splash is plain markup in the document because it
  /// has to paint before any Dart has run — nothing in `lib/` can put it
  /// there, so this is where the rules live.
  group('the first-paint splash', () {
    test('is in the document, not fetched', () {
      final html = flattened();

      expect(html, contains('id="quark-splash"'));
      expect(html, contains('Starting your Quark…'));
      // An <img> or a web font would be a request that has to land before
      // anything shows, which is the problem it is here to solve.
      expect(html, isNot(contains('<img')));
    });

    test('paints the Quark background before the canvas exists', () {
      final html = flattened();

      expect(html, contains('--quark-background: #070d19;'));
      expect(html, contains('@media (prefers-color-scheme: light)'));
      expect(html, contains('background-color: var(--quark-background);'));
    });

    test('leaves on the engine first frame, not a timer', () {
      final html = flattened();

      expect(html, contains("addEventListener(\"flutter-first-frame\""));
      expect(html, contains('splash.remove();'));
    });
  });
}
