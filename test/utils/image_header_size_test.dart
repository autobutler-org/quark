import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/image_header_size.dart';

List<int> u16be(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> u32be(int v) => [...u16be(v >> 16), ...u16be(v)];
List<int> u32le(int v) => [...u16le(v), ...u16le(v >> 16)];

List<int> png(int w, int h) => [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  ...u32be(13), ...'IHDR'.codeUnits, ...u32be(w), ...u32be(h),
  8, 6, 0, 0, 0, // depth, color type, ...
];

List<int> jpegSegment(int marker, List<int> body) => [
  0xFF,
  marker,
  ...u16be(body.length + 2),
  ...body,
];

/// An EXIF APP1 body whose IFD0 holds one Orientation entry.
List<int> exif(int orientation, {bool littleEndian = false}) {
  final u16 = littleEndian ? u16le : u16be;
  final u32 = littleEndian ? u32le : u32be;
  return [
    ...'Exif'.codeUnits, 0, 0,
    ...(littleEndian ? 'II'.codeUnits : 'MM'.codeUnits),
    ...u16(42), ...u32(8), // IFD0 at offset 8
    ...u16(1), // one entry
    ...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0,
    ...u32(0),
  ];
}

List<int> jpeg(int w, int h, {List<List<int>> before = const []}) => [
  0xFF, 0xD8, // SOI
  for (final segment in before) ...segment,
  ...jpegSegment(0xDB, List.filled(65, 0)), // a quantization table
  ...jpegSegment(0xC2, [8, ...u16be(h), ...u16be(w), 3]), // progressive SOF
  0xFF, 0xDA, // SOS: image data follows
];

void main() {
  group('imageHeaderSize', () {
    test('reads a PNG', () {
      expect(imageHeaderSize(png(640, 480)), (width: 640, height: 480));
    });

    test('reads a GIF', () {
      final gif = [...'GIF89a'.codeUnits, ...u16le(320), ...u16le(200), 0];
      expect(imageHeaderSize(gif), (width: 320, height: 200));
    });

    test('reads a JPEG past the segments before its frame header', () {
      final head = jpeg(
        4032,
        3024,
        before: [
          jpegSegment(0xE0, [
            0x4A, 0x46, 0x49, 0x46, // an APP0 header's identifier
            0,
            1,
            1,
            0,
            0,
            1,
            0,
            1,
            0,
            0,
          ]),
        ],
      );
      expect(imageHeaderSize(head), (width: 4032, height: 3024));
    });

    test('swaps a JPEG turned on its side by its EXIF orientation', () {
      for (final littleEndian in [false, true]) {
        for (final orientation in [5, 6, 7, 8]) {
          final head = jpeg(
            4032,
            3024,
            before: [
              jpegSegment(0xE1, exif(orientation, littleEndian: littleEndian)),
            ],
          );
          expect(imageHeaderSize(head), (
            width: 3024,
            height: 4032,
          ), reason: 'orientation $orientation, little endian $littleEndian');
        }
      }
    });

    test('keeps a JPEG the right way up under orientations 1 to 4', () {
      final head = jpeg(4032, 3024, before: [jpegSegment(0xE1, exif(3))]);
      expect(imageHeaderSize(head), (width: 4032, height: 3024));
    });

    test('reads the three kinds of WebP', () {
      List<int> riff(String chunk, List<int> body) => [
        ...'RIFF'.codeUnits,
        ...u32le(body.length + 12),
        ...'WEBP'.codeUnits,
        ...chunk.codeUnits,
        ...u32le(body.length),
        ...body,
      ];
      final lossy = riff('VP8 ', [
        0, 0, 0, // frame tag
        0x9D, 0x01, 0x2A,
        ...u16le(800), ...u16le(600),
      ]);
      // VP8L packs (width - 1) and (height - 1) into 14 bits each.
      const w = 1000, h = 750;
      final bits = (w - 1) | ((h - 1) << 14);
      final lossless = riff('VP8L', [0x2F, ...u32le(bits)]);
      final extended = riff('VP8X', [
        0,
        0,
        0,
        0,
        ...u32le(1919).take(3),
        ...u32le(1079).take(3),
      ]);

      expect(imageHeaderSize(lossy), (width: 800, height: 600));
      expect(imageHeaderSize(lossless), (width: w, height: h));
      expect(imageHeaderSize(extended), (width: 1920, height: 1080));
    });

    test('reads a BMP, bottom-up or top-down', () {
      List<int> bmp(int w, int h) => [
        ...'BM'.codeUnits,
        ...List.filled(12, 0),
        ...u32le(40),
        ...u32le(w),
        ...u32le(h & 0xFFFFFFFF),
      ];
      expect(imageHeaderSize(bmp(64, 32)), (width: 64, height: 32));
      expect(imageHeaderSize(bmp(64, -32)), (width: 64, height: 32));
    });

    test('gives up on what it cannot read', () {
      expect(imageHeaderSize(const []), isNull);
      expect(imageHeaderSize('not a picture'.codeUnits), isNull);
      // A JPEG cut off before its frame header.
      final cut = jpeg(10, 10);
      expect(imageHeaderSize(cut.sublist(0, 30)), isNull);
      // A PNG claiming no area.
      expect(imageHeaderSize(png(0, 10)), isNull);
    });

    test('reads from a Uint8List view', () {
      final bytes = Uint8List.fromList([0, 0, ...png(5, 7)]);
      expect(imageHeaderSize(Uint8List.sublistView(bytes, 2)), (
        width: 5,
        height: 7,
      ));
    });
  });

  group('ImageHeadRecorder', () {
    test(
      'keeps only the first bytes of a stream that passes through',
      () async {
        final recorder = ImageHeadRecorder(limit: 10);
        final chunks = Stream.fromIterable([
          [1, 2, 3, 4],
          [5, 6, 7, 8],
          [9, 10, 11, 12],
          [13],
        ]);
        final passed = await recorder.watch(chunks).expand((c) => c).toList();

        expect(passed, List.generate(13, (i) => i + 1));
        expect(recorder.head, List.generate(10, (i) => i + 1));
      },
    );
  });
}
