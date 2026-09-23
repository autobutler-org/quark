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
      // Every request has to land before it shows, which is the problem the
      // splash is here to solve. The logo is its one request, and it is the
      // PWA icon already in the build (#2235) — no other image, no web font.
      expect('<img'.allMatches(html), hasLength(1));
      expect(html, contains('<img src="icons/Icon-192.png"'));
    });

    test('paints the Quark background before the canvas exists', () {
      final html = flattened();

      expect(html, contains('--quark-background: #070d19;'));
      expect(html, contains('@media (prefers-color-scheme: light)'));
      expect(html, contains('background-color: var(--quark-background);'));
    });

    /// #2341: the splash followed only the OS, so a user who picked Light or
    /// Dark in Settings saw the other one until Flutter painted. The choice
    /// lives in `localStorage` under shared_preferences' `flutter.` prefix,
    /// and has to be read before the splash markup is parsed.
    test('follows the saved theme before it paints', () {
      final html = flattened();
      final read = html.indexOf("localStorage.getItem(\"flutter.themeMode\")");

      expect(read, isNonNegative);
      expect(read, lessThan(html.indexOf('id="quark-splash"')));
      expect(html, contains(':root[data-theme="light"]'));
      expect(html, contains('name="theme-color"'));
    });

    test('leaves on the engine first frame, not a timer', () {
      final html = flattened();

      expect(html, contains("addEventListener(\"flutter-first-frame\""));
      expect(html, contains('splash.remove();'));
    });
  });
}
