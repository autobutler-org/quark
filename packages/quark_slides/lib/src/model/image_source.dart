/// Where an `ImageElement`'s picture comes from: a file in the Quark or an
/// asset uploaded with the presentation.
///
/// The package never loads a picture. It stores the source as one string in
/// `.qslide` — [ref] — and hands it back to the host app's image builder,
/// which resolves it:
///
/// - [QuarkFileImage] — a path in the user's Quark files, stored as the path
///   itself (`photos/dog.jpg`). Files written before sources were typed
///   read this way.
/// - [UploadedAssetImage] — an asset the app uploaded for this
///   presentation, stored as `asset:<id>`.
///
/// ```dart
/// doc.insertImage(slideId, const QuarkFileImage('photos/dog.jpg'),
///     (width: 4032, height: 3024));
/// switch (ImageSource.parse(element.source)) {
///   QuarkFileImage(:final path) => downloadUrl(path),
///   UploadedAssetImage(:final assetId) => assetUrl(assetId),
/// }
/// ```
sealed class ImageSource {
  const ImageSource();

  /// Reads a stored reference: `asset:<id>` is an [UploadedAssetImage] and
  /// anything else a [QuarkFileImage] path.
  factory ImageSource.parse(String ref) =>
      ref.startsWith(UploadedAssetImage.prefix)
          ? UploadedAssetImage(ref.substring(UploadedAssetImage.prefix.length))
          : QuarkFileImage(ref);

  /// The string stored in `.qslide`, which [ImageSource.parse] reads back.
  String get ref;

  @override
  bool operator ==(Object other) =>
      other is ImageSource &&
      other.runtimeType == runtimeType &&
      other.ref == ref;

  @override
  int get hashCode => ref.hashCode;

  @override
  String toString() => '$runtimeType($ref)';
}

/// A picture that is a file in the user's Quark, by its [path].
class QuarkFileImage extends ImageSource {
  /// Creates a source for the Quark file at [path].
  const QuarkFileImage(this.path);

  /// The file's path, as the Quark's file API names it.
  final String path;

  @override
  String get ref => path;
}

/// A picture uploaded with the presentation, by the [assetId] the app gave
/// it.
class UploadedAssetImage extends ImageSource {
  /// Creates a source for the uploaded asset [assetId].
  const UploadedAssetImage(this.assetId);

  /// What a stored reference to an uploaded asset starts with.
  static const prefix = 'asset:';

  /// The id the app's upload returned.
  final String assetId;

  @override
  String get ref => '$prefix$assetId';
}
