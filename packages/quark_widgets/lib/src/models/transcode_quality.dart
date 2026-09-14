/// How much of a video's size a conversion keeps.
///
/// [name] is the value the API takes, so a caller can send `quality.name`.
enum TranscodeQuality {
  /// The video's own resolution. The default.
  original(
    label: 'Original',
    description: 'Same resolution as the video. Quick when the format allows.',
  ),

  /// At most 480 lines tall, for a much smaller file.
  small(label: 'Small', description: 'Up to 480p, for a much smaller file.');

  const TranscodeQuality({required this.label, required this.description});

  /// The quality's name, shown on its chip.
  final String label;

  /// One line under the quality chips while this quality is chosen.
  final String description;
}
