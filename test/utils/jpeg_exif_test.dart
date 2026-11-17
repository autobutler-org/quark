import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/jpeg_exif.dart';

/// A big-endian ISO-BMFF box of [type] around [body].
List<int> _box(String type, List<int> body) => [
  ..._u32(8 + body.length),
  ...ascii.encode(type),
  ...body,
];

List<int> _u16(int v) => [(v >> 8) & 0xff, v & 0xff];
List<int> _u32(int v) => [..._u16(v >> 16), ..._u16(v & 0xffff)];

/// A little-endian TIFF block with IFD0 holding Orientation [orientation]
/// and DateTime "2024:05:06 07:08:09".
Uint8List _tiff({int orientation = 6}) {
  final date = ascii.encode('2024:05:06 07:08:09\x00'); // 20 bytes
  List<int> le16(int v) => [v & 0xff, (v >> 8) & 0xff];
  List<int> le32(int v) => [...le16(v & 0xffff), ...le16(v >> 16)];
  const ifdOffset = 8;
  const entries = 2;
  const dateOffset = ifdOffset + 2 + entries * 12 + 4;
  return Uint8List.fromList([
    ...ascii.encode('II'), ...le16(42), ...le32(ifdOffset),
    ...le16(entries),
    // Orientation, SHORT, 1, value in place.
    ...le16(0x0112), ...le16(3), ...le32(1), ...le16(orientation), 0, 0,
    // DateTime, ASCII, 20, at dateOffset.
    ...le16(0x0132), ...le16(2), ...le32(date.length), ...le32(dateOffset),
    ...le32(0),
    ...date,
  ]);
}

/// A HEIC skeleton: ftyp, a meta box whose iinf names item 2 as Exif and
/// whose iloc points it at [exifPayload] inside mdat, split in two extents
/// when [split].
Uint8List _heic(Uint8List tiff, {bool split = false}) {
  // Exif item data: a 4-byte offset to the TIFF header, here 6 bytes of
  // "Exif\0\0" in front of it.
  final payload = [..._u32(6), ...ascii.encode('Exif'), 0, 0, ...tiff];
  final ftyp = _box('ftyp', [...ascii.encode('heic'), ..._u32(0)]);
  List<int> infe(int id, String type) => _box('infe', [
    2,
    0,
    0,
    0,
    ..._u16(id),
    ..._u16(0),
    ...ascii.encode(type),
  ]);
  final iinf = _box('iinf', [
    0, 0, 0, 0, ..._u16(2), //
    ...infe(1, 'hvc1'),
    ...infe(2, 'Exif'),
  ]);
  List<int> iloc(int mdatData) {
    final half = payload.length ~/ 2;
    final extents = split
        ? [
            [mdatData, half],
            [mdatData + half, payload.length - half],
          ]
        : [
            [mdatData, payload.length],
          ];
    return _box('iloc', [
      0, 0, 0, 0, // version 0
      0x44, 0x00, // offset_size 4, length_size 4, base_offset_size 0
      ..._u16(2),
      ..._u16(1), ..._u16(0), ..._u16(1), ..._u32(mdatData), ..._u32(0),
      ..._u16(2), ..._u16(0), ..._u16(extents.length),
      for (final e in extents) ...[..._u32(e[0]), ..._u32(e[1])],
    ]);
  }

  // The iloc size does not depend on the offsets, so measure it first.
  final ilocLength = iloc(0).length;
  final metaLength = 8 + 4 + iinf.length + ilocLength;
  final mdatData = ftyp.length + metaLength + 8;
  final meta = _box('meta', [0, 0, 0, 0, ...iinf, ...iloc(mdatData)]);
  return Uint8List.fromList([...ftyp, ...meta, ..._box('mdat', payload)]);
}

/// SOI, a JFIF APP0, a stand-in scan, EOI.
final _jpeg = Uint8List.fromList([
  0xff, 0xd8, //
  0xff, 0xe0, 0x00, 0x10, ...ascii.encode('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0,
  0xff, 0xda, 0x00, 0x02, 0x11, 0x22,
  0xff, 0xd9,
]);

void main() {
  group('heicExif (#4188)', () {
    test('returns the TIFF block of the Exif item', () {
      final tiff = _tiff();
      expect(heicExif(_heic(tiff)), tiff);
    });

    test('joins an item stored in several extents', () {
      final tiff = _tiff();
      expect(heicExif(_heic(tiff, split: true)), tiff);
    });

    test('is null for a file that is not HEIC or has no Exif item', () {
      expect(heicExif(_jpeg), isNull);
      expect(heicExif(Uint8List(0)), isNull);
      final noExif = Uint8List.fromList(
        _box('ftyp', [...ascii.encode('heic'), ..._u32(0)]),
      );
      expect(heicExif(noExif), isNull);
    });

    test('is null rather than throwing on a truncated file', () {
      final heic = _heic(_tiff());
      for (var n = 0; n < heic.length; n += 7) {
        expect(
          () => heicExif(Uint8List.sublistView(heic, 0, n)),
          returnsNormally,
        );
      }
    });
  });

  group('jpegWithExif (#4188)', () {
    test('puts the EXIF in an APP1 right after SOI', () {
      final tiff = _tiff();
      final out = jpegWithExif(_jpeg, tiff);
      expect(out.sublist(0, 4), [0xff, 0xd8, 0xff, 0xe1]);
      final length = (out[4] << 8) | out[5];
      expect(length, 2 + 6 + tiff.length);
      expect(ascii.decode(out.sublist(6, 10)), 'Exif');
      // Everything after the original SOI follows unchanged.
      expect(out.sublist(4 + length), _jpeg.sublist(2));
    });

    test('resets the orientation, since the pixels are already upright', () {
      final out = jpegWithExif(_jpeg, _tiff(orientation: 6));
      final tiff = out.sublist(12);
      // IFD0's first entry is Orientation; its value sits at 8 + 2 + 8.
      expect(tiff[18] | (tiff[19] << 8), 1);
      // The date is carried as it was.
      expect(ascii.decode(tiff.sublist(38, 57)), '2024:05:06 07:08:09');
    });

    test('drops an EXIF APP1 the JPEG already carried', () {
      final once = jpegWithExif(_jpeg, _tiff());
      final twice = jpegWithExif(once, _tiff());
      expect(twice, once);
    });

    test('leaves a JPEG alone when the EXIF is too large for one segment', () {
      expect(jpegWithExif(_jpeg, Uint8List(70000)), _jpeg);
    });
  });
}
