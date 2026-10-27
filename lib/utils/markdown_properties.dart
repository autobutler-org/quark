import 'package:markdown/markdown.dart' as md;
import 'package:quark_widgets/quark_widgets.dart';

/// Words and characters in [document], from the text a reader sees.
///
/// Markup is not counted: a heading's hashes and a table's separator row
/// are not words. Block boundaries stay breaks, so the last word of one
/// block and the first of the next do not join. [DocumentProperties.countsSource]
/// is `parsed`, because the count is this preview's and not a number the
/// file saved. A document with no text counts as zero words.
DocumentProperties markdownDocumentProperties(QuarkMarkdownDocument document) {
  final buffer = StringBuffer();
  var characters = 0;

  void walk(md.Node node) {
    switch (node) {
      case md.Text(:final text):
        buffer.write(text);
        characters += text.length;
      case md.Element(:final tag, :final children):
        for (final child in children ?? const <md.Node>[]) {
          walk(child);
        }
        if (_blockTags.contains(tag)) buffer.writeln();
      default:
        break;
    }
  }

  for (final block in document.blocks) {
    walk(block);
  }

  final trimmed = buffer.toString().trim();
  return DocumentProperties(
    words: trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length,
    characters: characters,
    countsSource: 'parsed',
  );
}

/// Tags that end a run of words. A list item and a table cell are among
/// them so neighboring cells do not become one word.
const _blockTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'pre',
  'td',
  'th',
  'hr',
  'div',
};
