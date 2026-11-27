/// Tuning for the read-only document viewer (#3265).
abstract final class DocumentViewerConfig {
  /// The most bytes of a document's block stream the viewer reads. The Quark
  /// stops a stream at 16 MiB and marks it truncated, so anything past this
  /// is not that stream and is refused rather than held.
  static const int maxPreviewBytes = 17 * 1024 * 1024;
}
