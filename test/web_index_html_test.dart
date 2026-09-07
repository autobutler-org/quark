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
  test('index.html keeps the hidden text input transparent while selected', () {
    final html = File(
      'web/index.html',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    expect(
      html,
      contains(
        '.flt-text-editing::selection '
        '{ background-color: transparent; color: transparent; }',
      ),
    );
  });
}
