import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';

void main() {
  // Every glyph drawn from the QuarkIcons font; the rest of QuarkIcons are
  // Material aliases. Two glyphs on one codepoint would draw the same icon.
  test('each font glyph has its own codepoint in the QuarkIcons font', () {
    const glyphs = [
      QuarkIcons.insert_row_above,
      QuarkIcons.insert_row_below,
      QuarkIcons.delete_row,
      QuarkIcons.duplicate_row,
      QuarkIcons.clear_row,
      QuarkIcons.insert_column_left,
      QuarkIcons.insert_column_right,
      QuarkIcons.delete_column,
      QuarkIcons.duplicate_column,
      QuarkIcons.clear_column,
    ];
    expect(glyphs.map((icon) => icon.codePoint).toSet(), hasLength(10));
    for (final icon in glyphs) {
      expect(icon.fontFamily, 'QuarkIcons');
      expect(icon.fontPackage, 'quark_icons');
    }
  });
}
