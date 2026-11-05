/// Tuning for chunked, resumable uploads (#1629).
///
/// Gathered here rather than spread through the upload manager and its
/// services because every one of these numbers is a tradeoff someone will want
/// to revisit, and the reasoning belongs next to the value rather than in the
/// commit that changed it.
abstract final class UploadConfig {
  /// Bytes sent in one `PUT` of a resumable session.
  ///
  /// A multiple of 256 KiB, which the protocol requires — the Drive API this
  /// is modelled on rejects anything else, and the contract for our own
  /// endpoint keeps the rule so the two behave alike. 8 MiB is large enough
  /// that per-request overhead disappears against the transfer and small
  /// enough that four workers hold 32 MiB between them rather than a
  /// multi-gigabyte file each.
  static const int chunkSizeBytes = 8 * 1024 * 1024;

  /// At or above this, a file goes through a session; below it, through the
  /// single multipart `POST` that has always carried uploads.
  ///
  /// Chunking a small file buys nothing and costs a session round trip plus a
  /// request per chunk. The common case — a photo, a document — must not pay
  /// for the rare one.
  static const int chunkedUploadThresholdBytes = 8 * 1024 * 1024;

  /// How many times one chunk is sent before the file is given up on.
  ///
  /// A chunk is small and cheap to repeat, and the failure it recovers from —
  /// a dropped connection on a domestic link — is usually over by the second
  /// try. More attempts than a whole-file upload gets for that reason.
  static const int maxChunkAttempts = 4;

  /// How many requests one multipart batch gets before it is given up on.
  ///
  /// Each retry carries only the files the Quark did not report as landed
  /// (#3533), so a retry never repeats a file that made it.
  static const int maxBatchAttempts = 3;

  /// Multiplied by the attempt number for the pause between chunk retries.
  ///
  /// Linear rather than exponential: the server this talks to is a small box
  /// on a home network, and it recovers in seconds or not at all.
  static const Duration chunkRetryBackoff = Duration(seconds: 1);

  /// How long a persisted session record is worth trying to resume.
  ///
  /// Shorter than the server's own session TTL so the client gives up first
  /// and starts clean, rather than resuming onto a session that was swept out
  /// from under it. A record older than this is pruned unread.
  static const Duration sessionRecordTtl = Duration(hours: 12);
}
