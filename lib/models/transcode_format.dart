import 'package:flutter/foundation.dart';

/// A video format the Quark can convert to, as
/// `GET /api/v0/videos/transcode/formats` lists it.
@immutable
class TranscodeFormat {
  const TranscodeFormat({required this.format, required this.label});

  /// The value `transcodeVideo` takes: the file extension without the dot.
  final String format;

  /// Its display name, such as "MOV" or "WebM".
  final String label;

  factory TranscodeFormat.fromJson(Map<String, dynamic> json) =>
      TranscodeFormat(
        format: json['format'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );

  /// The `formats` list of the endpoint's body, skipping any entry that is not
  /// an object or names no format.
  static List<TranscodeFormat> listFromJson(Map<String, dynamic> json) =>
      (json['formats'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TranscodeFormat.fromJson)
          .where((f) => f.format.isNotEmpty)
          .toList();
}
