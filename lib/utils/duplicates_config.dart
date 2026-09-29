/// Tuning values for the duplicates page (#1666).
class DuplicatesConfig {
  const DuplicatesConfig._();

  /// The largest perceptual-hash distance, out of 64 bits, at which a similar
  /// group whose copies are each a different format still counts as one
  /// picture saved in several formats, so the Keep-format choice applies to it.
  ///
  /// An estimate: no HEIC fixture was at hand, so it was measured on the
  /// repository's sample photos re-encoded as JPEG at the same size, which
  /// moved the hash by 0 to 2 bits at quality 80 and above, and by at most 4 at
  /// quality 40 to 60. Re-encoding at a third of the size moved it by up to 7,
  /// which is left out, since two shots taken moments apart can land that close.
  static const int samePictureMaxDistance = 4;
}
