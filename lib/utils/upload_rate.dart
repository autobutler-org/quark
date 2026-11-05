import 'package:quark/utils/upload_config.dart';

/// How fast an upload is moving and how long it has left, worked out from
/// two successive readings of its committed offset.
class UploadRate {
  /// Creates a reading.
  const UploadRate({this.bytesPerSecond, this.remaining, this.stalled = false});

  /// The rate between the last two readings that moved, or null before two.
  final double? bytesPerSecond;

  /// About how long is left at [bytesPerSecond], or null when unknown.
  final Duration? remaining;

  /// Whether no byte has landed for [UploadConfig.stallAfter].
  final bool stalled;
}

/// Keeps the last reading of each upload so [read] can compare against it.
///
/// Pure bookkeeping with no clock of its own: the caller passes the time, so a
/// test controls it.
class UploadRateTracker {
  final Map<String, _Sample> _samples = {};

  /// The rate for session [id], now at [offset] of [total] bytes with its
  /// last chunk landing at [updatedAt], as of [now].
  UploadRate read({
    required String id,
    required int offset,
    required int total,
    required DateTime updatedAt,
    required DateTime now,
  }) {
    final previous = _samples[id];
    var rate = previous?.rate;
    if (previous != null && offset > previous.offset) {
      final elapsed = updatedAt.difference(previous.at).inMicroseconds;
      if (elapsed > 0) {
        rate =
            (offset - previous.offset) *
            Duration.microsecondsPerSecond /
            elapsed;
      }
    }
    if (previous == null || offset != previous.offset) {
      _samples[id] = _Sample(offset: offset, at: updatedAt, rate: rate);
    }
    final left = total - offset;
    return UploadRate(
      bytesPerSecond: rate,
      remaining: rate == null || rate <= 0 || left <= 0
          ? null
          : Duration(
              microseconds: (left / rate * Duration.microsecondsPerSecond)
                  .round(),
            ),
      stalled: now.difference(updatedAt) >= UploadConfig.stallAfter,
    );
  }

  /// Forgets every session not in [ids].
  void retain(Set<String> ids) =>
      _samples.removeWhere((id, _) => !ids.contains(id));
}

class _Sample {
  const _Sample({required this.offset, required this.at, required this.rate});

  final int offset;
  final DateTime at;
  final double? rate;
}
