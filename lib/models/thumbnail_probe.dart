/// What the Quark said when asked for a file's thumbnail (#2381).
class ThumbnailProbe {
  const ThumbnailProbe({
    required this.served,
    this.clientRender = false,
    this.modTime = '',
  });

  /// The Quark answered with a thumbnail.
  final bool served;

  /// The Quark has none and cannot make one, and a client may render it and
  /// PUT it: a video or HEIC the device does not decode.
  final bool clientRender;

  /// The file's modification time as the Quark reported it, naming the
  /// version of the file a render is for. Empty unless [clientRender].
  final String modTime;
}
