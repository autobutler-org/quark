import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/markdown_properties.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Word and character counts the Markdown viewer computes from the text it
/// already holds (#3275).
void main() {
  test('counts words and characters in the text, not the markup', () {
    final properties = markdownDocumentProperties(
      QuarkMarkdownDocument.parse('# Hello world\n\nSecond line\n'),
    );

    expect(properties.words, 4);
    expect(properties.characters, 22);
    expect(properties.countsSource, 'parsed');
    expect(properties.title, isNull);
  });

  test('a blank document counts as zero', () {
    final properties = markdownDocumentProperties(
      const QuarkMarkdownDocument.empty(),
    );

    expect(properties.words, 0);
    expect(properties.characters, 0);
    expect(properties.countsSource, 'parsed');
  });

  test('words on either side of a list and a table stay separate', () {
    final properties = markdownDocumentProperties(
      QuarkMarkdownDocument.parse(
        'Before\n\n- one\n- two\n\n| A | B |\n| --- | --- |\n| cell | |\n',
      ),
    );

    // Before, one, two, the header cells, and cell.
    expect(properties.words, 6);
  });
}
