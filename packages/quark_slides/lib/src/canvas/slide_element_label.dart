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
/// text, a shape its kind.
///
/// ```dart
/// defaultSlideElementLabel(ImageElement(..., altText: 'A dog'));
/// // 'Image: A dog'
/// ```
String defaultSlideElementLabel(SlideElement element) => switch (element) {
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
      UnknownElement(:final type) => 'Unsupported $type element',
    };

String _capitalized(String s) => s[0].toUpperCase() + s.substring(1);
