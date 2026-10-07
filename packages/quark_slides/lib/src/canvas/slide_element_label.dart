import '../model/slide_element.dart';
import 'slide_tool_label.dart';

/// Names a slide element for a screen reader.
///
/// `SlideCanvas` takes one of these so an app can localize the labels; the
/// default is [defaultSlideElementLabel].
typedef SlideElementLabel = String Function(SlideElement element);

/// English screen reader labels: a text box reads its text, a line per
/// non-blank paragraph (its placeholder, or "Empty text box", when it has
/// none), an image its alt
/// text, a shape its kind, a table its size ("Table, 3 rows by 4 columns";
/// its cells read on their own, see [defaultSlideTableCellLabel]), a group
/// how many elements it holds. A layout
/// placeholder announces its role first: "Title: Quarterly review", or
/// "Title placeholder: Click to add title" while it is empty.
///
/// ```dart
/// defaultSlideElementLabel(ImageElement(..., altText: 'A dog'));
/// // 'Image: A dog'
/// ```
String defaultSlideElementLabel(SlideElement element) => switch (element) {
      TextBox(slot: _?, :final textRole, :final plainText, :final placeholder)
          when plainText.trim().isEmpty =>
        [
          '${textRole.label} placeholder',
          if (placeholder.isNotEmpty) placeholder,
        ].join(': '),
      final TextBox box when box.slot != null => '${box.textRole.label}: '
          '${defaultSlideElementLabel(box.copyWith(slot: null))}',
      TextBox(:final plainText, :final placeholder)
          when plainText.trim().isEmpty =>
        placeholder.isEmpty ? 'Empty text box' : placeholder,
      TextBox(:final plainText) => [
          for (final line in plainText.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ].join('\n'),
      ShapeElement(:final kind) => '${_capitalized(shapeKindName(kind))} shape',
      ImageElement(:final altText) when altText.isEmpty => 'Image',
      ImageElement(:final altText) => 'Image: $altText',
      LineElement(:final startCap, :final endCap)
          when startCap == LineCap.arrow || endCap == LineCap.arrow =>
        'Arrow',
      LineElement() => 'Line',
      TableElement(:final rowCount, :final columnCount) =>
        'Table, ${_count(rowCount, 'row')} by ${_count(columnCount, 'column')}',
      GroupElement(:final children) => 'Group of ${children.length}',
      UnknownElement(:final type) => 'Unsupported $type element',
    };

String _count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';

String _capitalized(String s) => s[0].toUpperCase() + s.substring(1);

/// Names one cell of a table for a screen reader, from its [row] and
/// [column] counted from 0 and its [text].
///
/// `SlideCanvas` takes one of these so an app can localize the labels; the
/// default is [defaultSlideTableCellLabel].
typedef SlideTableCellLabel = String Function(int row, int column, String text);

/// English cell labels, counted from 1: "Row 2, column 3: Revenue", or
/// "Row 2, column 3: empty" for a blank cell.
String defaultSlideTableCellLabel(int row, int column, String text) {
  final shown = text.trim().replaceAll('\n', ' ');
  return 'Row ${row + 1}, column ${column + 1}: '
      '${shown.isEmpty ? 'empty' : shown}';
}
