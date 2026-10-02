/// Limits the chat composer applies before a message is encrypted (#2503).
abstract final class ChatConfig {
  /// The most a message's ciphertext may be, mirroring
  /// `chatutil.MaxCiphertextBytes`: past it the Quark refuses the post.
  static const int maxCiphertextBytes = 16 << 10;

  /// What encryption adds to a message: the 24-byte nonce and the 16-byte
  /// tag, as `chatutil.MinCiphertextBytes` counts them.
  static const int ciphertextOverheadBytes = 24 + 16;

  /// The longest message the composer sends, in UTF-16 code units as Dart's
  /// `String.length` counts them. A code unit is at most 3 bytes of UTF-8 (a
  /// surrogate pair is 4 bytes for 2), so anything this long or shorter fits
  /// [maxCiphertextBytes] once encrypted, and the Quark never refuses a
  /// message the composer let through.
  static const int maxMessageLength =
      (maxCiphertextBytes - ciphertextOverheadBytes) ~/ 3;
}
