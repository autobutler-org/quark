import '../model/slide_element.dart';

/// Names a slide element for a screen reader.
///
/// `SlideCanvas` takes one of these so an app can localize the labels; the
/// default is [defaultSlideElementLabel].
typedef SlideElementLabel = String Function(SlideElement element);

/// English screen reader labels: a text box reads its first line, an image
/// its alt text, a shape its kind.
///
/// ```dart
/// defaultSlideElementLabel(ImageElement(..., altText: 'A dog'));
/// // 'Image: A dog'
/// ```
String defaultSlideElementLabel(SlideElement element) => switch (element) {
      TextBox(:final plainText) when plainText.trim().isEmpty =>
        'Empty text box',
      TextBox(:final plainText) =>
        'Text box: ${plainText.trim().split('\n').first.trim()}',
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
