/// Formats [duration] the way the media players show a position:
/// `m:ss`, or `h:mm:ss` from an hour up. A negative duration reads as `0:00`.
String formatPlaybackTime(Duration duration) {
  final clamped = duration < Duration.zero ? Duration.zero : duration;
  final hours = clamped.inHours;
  final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${clamped.inMinutes}:$seconds';
}
