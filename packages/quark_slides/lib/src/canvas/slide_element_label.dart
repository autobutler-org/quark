import '../model/slide_element.dart';

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
      ShapeElement(:final kind) => '${_shapeNames[kind]} shape',
      ImageElement(:final altText) when altText.isEmpty => 'Image',
      ImageElement(:final altText) => 'Image: $altText',
      LineElement(:final startCap, :final endCap)
          when startCap == LineCap.arrow || endCap == LineCap.arrow =>
        'Arrow',
      LineElement() => 'Line',
      UnknownElement(:final type) => 'Unsupported $type element',
    };

const _shapeNames = {
  ShapeKind.rectangle: 'Rectangle',
  ShapeKind.roundedRectangle: 'Rounded rectangle',
  ShapeKind.ellipse: 'Ellipse',
  ShapeKind.triangle: 'Triangle',
  ShapeKind.diamond: 'Diamond',
  ShapeKind.arrow: 'Arrow',
  ShapeKind.star: 'Star',
};
