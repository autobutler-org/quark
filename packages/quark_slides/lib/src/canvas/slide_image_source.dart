import 'package:flutter/widgets.dart';

/// Builds the widget for a picture on a slide. The package never loads an
/// image itself: the host app resolves [SlideImageSource.source] — a path
/// or URL — however it fetches files, and a test or gallery returns a
/// placeholder.
typedef SlideImageBuilder = Widget Function(
  BuildContext context,
  SlideImageSource image,
);

/// A picture a slide asks the host app to draw: an image element's picture
/// or a background image.
///
/// The widget [SlideImageBuilder] returns is given the box the picture
/// fills, and should fit the picture to it with [fit].
class SlideImageSource {
  /// Creates a request for [source].
  const SlideImageSource(this.source, {this.fit = BoxFit.contain});

  /// The opaque reference stored in the presentation.
  final String source;

  /// How the picture fits its box.
  final BoxFit fit;

  @override
  bool operator ==(Object other) =>
      other is SlideImageSource && other.source == source && other.fit == fit;

  @override
  int get hashCode => Object.hash(source, fit);

  @override
  String toString() => 'SlideImageSource($source, ${fit.name})';
}
