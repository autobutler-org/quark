/// When a song counts as played (#3284): 30 seconds of listening, or half of
/// a song shorter than a minute. The player posts the play once, the first
/// time the listening crosses the line; the Quark only counts.
///
/// Listening is the forward progress of the position between updates, so
/// seeking ahead to the end does not count, and a pause adds nothing.
class MusicPlayThreshold {
  /// Tracks listening to a song [duration] long; null or zero when unknown,
  /// which falls back to [fullThreshold].
  MusicPlayThreshold(Duration? duration) : threshold = thresholdFor(duration);

  /// The listening a song of a minute or more needs.
  static const fullThreshold = Duration(seconds: 30);

  /// Songs shorter than this count at half their length.
  static const shortSong = Duration(seconds: 60);

  /// The longest step between two position updates taken as listening; a
  /// longer jump is a seek.
  static const maxStep = Duration(seconds: 2);

  /// How much listening a song [duration] long needs to count.
  static Duration thresholdFor(Duration? duration) =>
      duration != null && duration > Duration.zero && duration < shortSong
      ? duration ~/ 2
      : fullThreshold;

  /// The listening this song needs.
  final Duration threshold;

  Duration _listened = Duration.zero;
  Duration? _last;
  bool _crossed = false;

  /// How much has been listened so far.
  Duration get listened => _listened;

  /// Takes the player's [position], and returns true exactly once: on the
  /// update that crosses [threshold].
  bool update(Duration position) {
    final last = _last;
    _last = position;
    if (_crossed || last == null) return false;
    final step = position - last;
    if (step > Duration.zero && step <= maxStep) _listened += step;
    if (_listened < threshold) return false;
    _crossed = true;
    return true;
  }
}
