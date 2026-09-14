import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/transcode_format.dart';

void main() {
  test('reads the formats list in order', () {
    final formats = TranscodeFormat.listFromJson({
      'formats': [
        {'format': 'mp4', 'label': 'MP4'},
        {'format': 'webm', 'label': 'WebM'},
      ],
    });

    expect(formats.map((f) => f.format), ['mp4', 'webm']);
    expect(formats.map((f) => f.label), ['MP4', 'WebM']);
  });

  test('skips entries that are not objects or name no format', () {
    final formats = TranscodeFormat.listFromJson({
      'formats': [
        'mov',
        {'label': 'Nameless'},
        {'format': 'mkv', 'label': 'MKV'},
      ],
    });

    expect(formats.map((f) => f.format), ['mkv']);
  });

  test('is empty when the list is missing', () {
    expect(TranscodeFormat.listFromJson({}), isEmpty);
  });
}
