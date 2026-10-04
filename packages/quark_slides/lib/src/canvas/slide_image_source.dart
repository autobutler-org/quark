import 'package:flutter/widgets.dart';

import '../model/image_source.dart';

/// Builds the widget for a picture on a slide. The package never loads an
/// image itself: the host app resolves [SlideImageSource.imageSource] — a
/// Quark file path or an uploaded asset — however it fetches files, and a
/// test or gallery returns a placeholder. The picture's semantics come from
/// the element's alt text, so the builder's widget need not label itself.
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

  /// The reference stored in the presentation; see [ImageSource].
  final String source;

  /// [source] read as a Quark file or an uploaded asset.
  ImageSource get imageSource => ImageSource.parse(source);

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
