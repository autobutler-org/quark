/// Carries a HEIC photo's EXIF over to the JPEG this device converted it to
/// (#4188), so "Download as JPEG" keeps the capture date and camera data.
///
/// The platform encoders that make the JPEG (`flutter_image_compress`, a
/// browser canvas) write pixels only. [heicExif] reads the TIFF block of the
/// HEIC's `Exif` item, and [jpegWithExif] writes it back into the JPEG as an
/// APP1 segment with the orientation reset, because the encoder has already
/// turned the pixels upright.
///
/// Both work on bytes already in memory: a HEIC is a few megabytes, and the
/// conversion needs it whole anyway. Neither throws on a malformed file.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The TIFF block (starting `II*\0` or `MM\0*`) of the `Exif` item in the
/// HEIC or HEIF [heic], or null when there is none or the file cannot be
/// read.
Uint8List? heicExif(Uint8List heic) {
  try {
    return _heicExif(ByteData.sublistView(heic), heic);
  } on RangeError {
    return null;
  } on FormatException {
    return null;
  }
}

/// [jpeg] with [tiff], a TIFF-format EXIF block, as its APP1 segment right
/// after SOI. Any EXIF APP1 it carried is dropped, and the copy's
/// Orientation is set to 1 (upright). A [tiff] too large for one segment,
/// or a [jpeg] that does not start with SOI, gives back [jpeg] unchanged.
Uint8List jpegWithExif(Uint8List jpeg, Uint8List tiff) {
  const header = 6; // "Exif\0\0"
  final segmentLength = 2 + header + tiff.length;
  if (segmentLength > 0xffff ||
      jpeg.length < 2 ||
      jpeg[0] != 0xff ||
      jpeg[1] != 0xd8) {
    return jpeg;
  }
  final exif = Uint8List.fromList(tiff);
  _setUpright(exif);
  final rest = _withoutExifSegments(jpeg);
  return Uint8List.fromList([
    0xff, 0xd8, 0xff, 0xe1, //
    segmentLength >> 8, segmentLength & 0xff,
    ..._exifHeader,
    ...exif,
    ...rest,
  ]);
}

final _exifHeader = [...ascii.encode('Exif'), 0, 0];

Uint8List? _heicExif(ByteData data, Uint8List bytes) {
  final meta = _child(data, 0, data.lengthInBytes, 'meta');
  if (meta == null) return null;
  // meta is a full box: four bytes of version and flags before its children.
  final metaStart = meta.start + 4;
  final iinf = _child(data, metaStart, meta.end, 'iinf');
  final iloc = _child(data, metaStart, meta.end, 'iloc');
  if (iinf == null || iloc == null) return null;
  final id = _exifItemId(data, iinf);
  if (id == null) return null;
  final item = _itemBytes(data, bytes, iloc, id);
  if (item == null || item.length < 4) return null;
  final offset = 4 + ByteData.sublistView(item).getUint32(0);
  if (offset + 8 > item.length) return null;
  final tiff = Uint8List.sublistView(item, offset);
  final order = ascii.decode(tiff.sublist(0, 2), allowInvalid: true);
  return order == 'II' || order == 'MM' ? Uint8List.fromList(tiff) : null;
}

/// The extent of one box's body.
typedef _Box = ({int start, int end});

/// The body of the first box of [type] among the boxes in [from]..[to].
_Box? _child(ByteData data, int from, int to, String type) {
  var at = from;
  while (at + 8 <= to) {
    var size = data.getUint32(at);
    var header = 8;
    if (size == 1) {
      size = data.getUint32(at + 8) * 0x100000000 + data.getUint32(at + 12);
      header = 16;
    } else if (size == 0) {
      size = to - at;
    }
    if (size < header || at + size > to) return null;
    if (_fourCC(data, at + 4) == type) {
      return (start: at + header, end: at + size);
    }
    at += size;
  }
  return null;
}

String _fourCC(ByteData data, int at) =>
    String.fromCharCodes([for (var i = 0; i < 4; i++) data.getUint8(at + i)]);

/// The item ID `iinf` gives the `Exif` item.
int? _exifItemId(ByteData data, _Box iinf) {
  final version = data.getUint8(iinf.start);
  var at = iinf.start + 4 + (version == 0 ? 2 : 4);
  while (at < iinf.end) {
    final infe = _child(data, at, iinf.end, 'infe');
    if (infe == null) return null;
    final infeVersion = data.getUint8(infe.start);
    if (infeVersion >= 2) {
      var p = infe.start + 4;
      final id = infeVersion == 2 ? data.getUint16(p) : data.getUint32(p);
      p += (infeVersion == 2 ? 2 : 4) + 2; // ID, then protection index
      if (_fourCC(data, p) == 'Exif') return id;
    }
    at = infe.end;
  }
  return null;
}

/// The bytes `iloc` places item [id] at, its extents joined. Only items
/// stored in the file itself (construction method 0) are read.
Uint8List? _itemBytes(ByteData data, Uint8List bytes, _Box iloc, int id) {
  var p = iloc.start;
  final version = data.getUint8(p);
  p += 4;
  final sizes = data.getUint16(p);
  p += 2;
  final offsetSize = sizes >> 12;
  final lengthSize = (sizes >> 8) & 0xf;
  final baseOffsetSize = (sizes >> 4) & 0xf;
  final indexSize = version == 0 ? 0 : sizes & 0xf;
  int read(int size) {
    final value = switch (size) {
      0 => 0,
      4 => data.getUint32(p),
      8 => data.getUint32(p) * 0x100000000 + data.getUint32(p + 4),
      _ => throw const FormatException('unsupported iloc field size'),
    };
    p += size;
    return value;
  }

  final itemCount = version < 2 ? data.getUint16(p) : data.getUint32(p);
  p += version < 2 ? 2 : 4;
  for (var i = 0; i < itemCount; i++) {
    final itemId = version < 2 ? data.getUint16(p) : data.getUint32(p);
    p += version < 2 ? 2 : 4;
    var method = 0;
    if (version > 0) {
      method = data.getUint16(p) & 0xf;
      p += 2;
    }
    p += 2; // data_reference_index
    final base = read(baseOffsetSize);
    final extentCount = data.getUint16(p);
    p += 2;
    final out = BytesBuilder(copy: false);
    for (var e = 0; e < extentCount; e++) {
      read(indexSize);
      final offset = base + read(offsetSize);
      final length = read(lengthSize);
      if (itemId == id) {
        if (offset + length > bytes.length) return null;
        out.add(Uint8List.sublistView(bytes, offset, offset + length));
      }
    }
    if (itemId == id) return method == 0 ? out.takeBytes() : null;
  }
  return null;
}

/// Sets IFD0's Orientation in the TIFF block [tiff] to 1, in place.
void _setUpright(Uint8List tiff) {
  if (tiff.length < 8) return;
  final data = ByteData.sublistView(tiff);
  final endian = tiff[0] == 0x49 ? Endian.little : Endian.big;
  final ifd = data.getUint32(4, endian);
  if (ifd + 2 > tiff.length) return;
  final count = data.getUint16(ifd, endian);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > tiff.length) return;
    if (data.getUint16(entry, endian) == 0x0112) {
      data.setUint16(entry + 8, 1, endian);
      return;
    }
  }
}

/// [jpeg] after its SOI, minus any APP1 segment that holds EXIF.
Uint8List _withoutExifSegments(Uint8List jpeg) {
  final out = BytesBuilder(copy: false);
  var at = 2;
  // Walk the marker segments up to the scan; everything from SOS on is
  // entropy-coded data and goes through untouched.
  while (at + 4 <= jpeg.length && jpeg[at] == 0xff) {
    final marker = jpeg[at + 1];
    if (marker == 0xda) break;
    final length = (jpeg[at + 2] << 8) | jpeg[at + 3];
    final end = at + 2 + length;
    if (end > jpeg.length) break;
    final isExif =
        marker == 0xe1 &&
        length >= 8 &&
        ascii.decode(jpeg.sublist(at + 4, at + 8), allowInvalid: true) ==
            'Exif';
    if (!isExif) out.add(Uint8List.sublistView(jpeg, at, end));
    at = end;
  }
  out.add(Uint8List.sublistView(jpeg, at));
  return out.takeBytes();
}
